import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zyduspod/GstInvoiceScanner.dart';
import 'package:zyduspod/Models/_SplitOut.dart';
import 'package:zyduspod/Models/pod.dart';
import 'package:zyduspod/config.dart';
import 'package:zyduspod/services/PythonQRService.dart';
import 'package:zyduspod/widgets/EInvoiceQRExtractor.dart';
import 'package:zyduspod/widgets/PdfPreviewScreen.dart';

/// ===================== IMAGE COMPRESSION / ENHANCE (Isolate Workers) =====================

Map<String, dynamic> _enhanceImageForOCRWorker(Map<String, dynamic> args) {
  final Uint8List imgBytes = args['imageBytes'] as Uint8List;
  try {
    img.Image? image = img.decodeImage(imgBytes);
    if (image == null) return {'success': false, 'bytes': imgBytes};

    const int minWidth = 1200;
    const int minHeight = 1600;
    if (image.width < minWidth || image.height < minHeight) {
      final scale = math.max(minWidth / image.width, minHeight / image.height);
      image = img.copyResize(
        image,
        width: (image.width * scale).round(),
        height: (image.height * scale).round(),
        interpolation: img.Interpolation.cubic,
      );
    }

    image = img.grayscale(image);
    image = img.adjustColor(image, contrast: 1.2, brightness: 1.1, gamma: 0.9);
    image = img.convolution(
      image,
      filter: [-1, -1, -1, -1, 9, -1, -1, -1, -1],
      div: 1,
    );
    image = img.gaussianBlur(image, radius: 1);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final px = image.getPixel(x, y);
        final g = img.getLuminance(px).round();
        image.setPixel(
          x,
          y,
          g > 140 ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0),
        );
      }
    }

    final out = img.encodePng(image, level: 1);
    return {
      'success': true,
      'bytes': Uint8List.fromList(out),
      'width': image.width,
      'height': image.height,
    };
  } catch (e) {
    return {'success': false, 'bytes': imgBytes, 'error': e.toString()};
  }
}

// Put near other imports
// already have: import 'package:http_parser/http_parser.dart';
const String _SPLIT_API_BASE = 'https://anujakkulkarni-splitpdffile.hf.space';

Future<List<SplitOut>> _splitPdfViaApi(File pdfFile) async {
  try {
    final uri = Uri.parse('$_SPLIT_API_BASE/split-invoices');

    final req =
        http.MultipartRequest('POST', uri)
          ..files.add(
            await http.MultipartFile.fromPath(
              'file',
              pdfFile.path,
              filename: p.basename(pdfFile.path),
              contentType: MediaType('application', 'pdf'),
            ),
          )
          ..fields['include_pdf'] = 'true'
          ..fields['initial_dpi'] = '300';

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      debugPrint('[SPLIT] HTTP ${resp.statusCode}: ${resp.body}');
      throw Exception('Split API error ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map || decoded['parts'] is! List) {
      debugPrint('[SPLIT] Unexpected response: ${resp.body}');
      return <SplitOut>[];
    }

    final parts = decoded['parts'] as List;
    final tmp = await getTemporaryDirectory();
    final out = <SplitOut>[];

    for (int i = 0; i < parts.length; i++) {
      final e = parts[i];
      if (e is! Map) continue;

      final String? b64 = e['pdf_base64'] as String?;
      if (b64 == null || b64.isEmpty) continue;

      Uint8List? bytes;
      try {
        bytes = Uint8List.fromList(base64.decode(base64.normalize(b64)));
      } catch (err) {
        debugPrint('[SPLIT] base64 decode failed: $err');
        continue;
      }

      final invoiceNo = (e['invoice_no'] as String?)?.trim();
      final List<int>? pages =
          (e['pages'] is List)
              ? (e['pages'] as List).whereType<int>().toList()
              : null;
      final int? sizeBytes =
          (e['size_bytes'] is int) ? e['size_bytes'] as int : null;

      // Prefer invoice number in file name if available
      final baseName =
          invoiceNo?.isNotEmpty == true
              ? 'invoice_${invoiceNo!.replaceAll(RegExp(r"[^A-Za-z0-9_-]"), "_")}'
              : 'split_part_${i + 1}';
      final outPath =
          '${tmp.path}/$baseName${DateTime.now().millisecondsSinceEpoch}.pdf';

      final f = File(outPath);
      await f.writeAsBytes(bytes, flush: true);

      out.add(
        SplitOut(
          file: f,
          invoiceNo: invoiceNo,
          pages: pages,
          sizeBytes: sizeBytes,
        ),
      );
    }

    debugPrint('[SPLIT] Created ${out.length} split PDFs.');
    return out;
  } catch (e, st) {
    debugPrint('[SPLIT] Exception: $e');
    debugPrint('$st');
    return <SplitOut>[]; // soft-fail; caller can fallback to original
  }
}

List<Uint8List> _extractBase64PdfBytes(dynamic decoded) {
  List<Uint8List> out = [];

  Uint8List? _tryDecode(dynamic v) {
    try {
      if (v is String && v.isNotEmpty) {
        final norm = base64.normalize(v);
        return Uint8List.fromList(base64.decode(norm));
      }
    } catch (_) {}
    return null;
  }

  if (decoded is Map<String, dynamic>) {
    // files: [{ filename, content_base64 }]
    if (decoded['files'] is List) {
      for (final e in (decoded['files'] as List)) {
        if (e is Map && (e['content_base64'] is String)) {
          final b = _tryDecode(e['content_base64']);
          if (b != null) out.add(b);
        } else if (e is Map && (e['content'] is String)) {
          final b = _tryDecode(e['content']);
          if (b != null) out.add(b);
        }
      }
    }
    // parts: [{ filename, content }]
    if (decoded['parts'] is List) {
      for (final e in (decoded['parts'] as List)) {
        if (e is Map && (e['content'] is String)) {
          final b = _tryDecode(e['content']);
          if (b != null) out.add(b);
        }
      }
    }
    // pdfs: ["base64", ...]
    if (decoded['pdfs'] is List) {
      for (final s in (decoded['pdfs'] as List)) {
        final b = _tryDecode(s);
        if (b != null) out.add(b);
      }
    }
    // data: ["base64", ...]
    if (decoded['data'] is List) {
      for (final s in (decoded['data'] as List)) {
        final b = _tryDecode(s);
        if (b != null) out.add(b);
      }
    }
  } else if (decoded is List) {
    for (final s in decoded) {
      final b = _tryDecode(s);
      if (b != null) out.add(b);
    }
  }

  return out;
}

/// ===================== DATA MODEL =====================

enum DocumentType { image, pdf }

class DocumentInfo {
  final File file;
  final bool isValid;
  final String? errorMessage;
  final DocumentType type;
  final String displayName;
  final Map<String, dynamic>? qrData;

  DocumentInfo({
    required this.file,
    required this.isValid,
    this.errorMessage,
    required this.type,
    required this.displayName,
    this.qrData,
  });

  DocumentInfo copyWith({
    File? file,
    bool? isValid,
    String? errorMessage,
    DocumentType? type,
    String? displayName,
    Map<String, dynamic>? qrData,
  }) {
    return DocumentInfo(
      file: file ?? this.file,
      isValid: isValid ?? this.isValid,
      errorMessage: errorMessage ?? this.errorMessage,
      type: type ?? this.type,
      displayName: displayName ?? this.displayName,
      qrData: qrData ?? this.qrData,
    );
  }
}

/// ===================== SCREEN =====================

class DocumentUploadScreen extends StatefulWidget {
  final String? initialDocType;
  const DocumentUploadScreen({super.key, this.initialDocType});
  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  // State flags
  bool _isUploading = false;
  bool _isLoadingLists = false;
  bool _isProcessingImage = false;
  bool _isRefreshing = false;
  final bool _debugEinvoice = true;
  bool _isCancelled = false;
  int? _currentProcessingIndex;

  // Processing counter and unified busy flag
  int _processingCount = 0;
  bool _isBusy = false;
  void _incProcessing() {
    if (!mounted) return;
    setState(() {
      _processingCount++;
      _updateBusyState();
    });
  }

  void _decProcessing() {
    if (!mounted) return;
    setState(() {
      if (_processingCount > 0) _processingCount--;
      _updateBusyState();
    });
  }

  void _updateBusyState() {
    _isBusy =
        _isUploading ||
        _isLoadingLists ||
        _isProcessingImage ||
        _processingCount > 0 ||
        _isRefreshing;
    debugPrint('isBusy: $_isBusy');
  }

  // Method to manually reset all processing flags
  void resetAllProcessingFlags() {
    if (mounted) {
      setState(() {
        _isProcessingImage = false;
        _processingCount = 0;
        _currentProcessingIndex = null;
        _qrQueueRunning = false;
        _isCancelled = false;
        _updateBusyState();
      });
      debugPrint('[QR] All processing flags reset - isBusy: $_isBusy');
    }
  }

  // Simple sequential queue for QR extraction (prevents parallel heavy work)
  final List<_QrQueueItem> _qrQueue = [];
  bool _qrQueueRunning = false;

  void _enqueueExtraction(DocumentInfo docInfo, int index) {
    _qrQueue.add(_QrQueueItem(docInfo, index));
    if (!_qrQueueRunning) {
      _processQrQueue();
    }
  }

  Future<void> _processQrQueue() async {
    _qrQueueRunning = true;
    while (_qrQueue.isNotEmpty && mounted) {
      final item = _qrQueue.removeAt(0);

      // Reset cancellation for new item
      _isCancelled = false;

      await _autoExtractQRFromDocument(item.doc, item.index);

      // Small yield to UI
      await Future.delayed(const Duration(milliseconds: 30));

      // If cancelled, clear remaining queue
      if (_isCancelled && _qrQueue.isNotEmpty) {
        if (_debugEinvoice) {
          debugPrint(
            '[QR] Clearing ${_qrQueue.length} items from queue due to cancellation',
          );
        }
        // Don't clear - let user decide per document
        // _qrQueue.clear();
      }
    }

    // Reset all processing flags when queue is complete
    if (mounted) {
      setState(() {
        _qrQueueRunning = false;
        _isProcessingImage = false;
        _processingCount = 0;
        _currentProcessingIndex = null;
        _updateBusyState();
      });
    }
  }

  // Selected doc type
  String? _selectedDocType = 'POD';

  // Selection data
  List<_SelectItem> _allStockists = [];
  List<_SelectItem> _allChemists = [];
  List<_SelectItem> _allPods = [];
  List<Pod> _pods = [];
  _SelectItem? _selectedStockist;
  _SelectItem? _selectedChemist;
  _SelectItem? _selectedPod;

  // Documents
  List<DocumentInfo> _capturedDocuments = [];
  Map<String, dynamic>? _einvoiceData;

  // Keys for Autocomplete
  Key _stockistKey = UniqueKey();
  Key _chemistKey = UniqueKey();
  Key _podKey = UniqueKey();

  // Debouncing variables for search
  Timer? _stockistSearchTimer;
  Timer? _hospitalSearchTimer;
  bool _isSearchingStockists = false;
  bool _isSearchingHospitals = false;

  final ImagePicker _imagePicker = ImagePicker();
  static const int maxDocuments = 25;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedDocType = widget.initialDocType ?? 'POD';
    _loadLists();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _stockistSearchTimer?.cancel();
    _hospitalSearchTimer?.cancel();
    super.dispose();
  }

  // Auto-scroll helpers
  void _scheduleScrollToBottom({bool instant = false}) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position.maxScrollExtent;
      if (instant) {
        _scrollController.jumpTo(pos);
      } else {
        _scrollController.animateTo(
          pos,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _openInvoiceDetails(Map<String, dynamic> data) async {
    final podId = _selectedPod?.id ?? '0';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceResultScreen(invoiceData: data, podId: podId),
      ),
    );
  }

  /// ===================== REFRESH FUNCTIONALITY =====================

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _updateBusyState();
    });

    try {
      // Clear current selections and data
      setState(() {
        _selectedStockist = null;
        _selectedChemist = null;
        _selectedPod = null;
        _einvoiceData = null;
        _stockistKey = UniqueKey();
        _chemistKey = UniqueKey();
        _podKey = UniqueKey();
      });

      // Reload all lists
      await _loadLists();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Page refreshed successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _updateBusyState();
        });
      }
    }
  }

  /// ===================== NORMALIZATION HELPERS =====================

  bool _isPodDoc() => (_selectedDocType ?? '').toUpperCase() == 'POD';

  bool _isEinvoiceDoc() {
    final raw = (_selectedDocType ?? '').trim().toUpperCase();
    final normalized = raw.replaceAll('-', '').replaceAll('_', '');
    return normalized == 'EINVOICE';
  }

  void _autoMarkEinvoiceSelectedForEinvoiceFlow() {
    if (_isEinvoiceDoc()) return;
  }

  /// ===================== LIST LOADING =====================

  Future<void> _loadLists() async {
    setState(() {
      _isLoadingLists = true;
      _updateBusyState();
    });
    try {
      final results = await Future.wait([
        _fetchSelectItems(API_STOCKISTS_URL),
        _fetchSelectItems(API_HOSPITALS_URL),
        _fetchPods(API_PODS_URL),
      ]);
      if (!mounted) return;
      setState(() {
        _allStockists = results[0] as List<_SelectItem>;
        _allChemists = results[1] as List<_SelectItem>;
        _pods = results[2] as List<Pod>;
        _allPods =
            _pods
                .map(
                  (p) => _SelectItem(
                    id: p.id.toString(),
                    label: _formatPodLabel(p),
                  ),
                )
                .toList();
      });
    } catch (e) {
      print('Failed to load lists: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load lists: $e')));
    } finally {
      if (mounted)
        setState(() {
          _isLoadingLists = false;
          _updateBusyState();
        });
    }
  }

  Future<List<_SelectItem>> _fetchSelectItems(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    final resp = await http.get(
      Uri.parse(url),
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
    );
    print('select items Response: ${resp.body}');
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.body}');
    }
    final decoded = _safeDecode(resp.bodyBytes);
    final rawList = _unwrapToList(decoded);
    return rawList
        .map((e) => _SelectItem.fromDynamic(e))
        .where((e) => e != null)
        .cast<_SelectItem>()
        .toList();
  }

  dynamic _safeDecode(Uint8List bytes) {
    try {
      return jsonDecode(String.fromCharCodes(bytes));
    } catch (_) {
      return [];
    }
  }

  Future<List<Pod>> _fetchPods(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    final resp = await http.get(
      Uri.parse(url),
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final decoded = _safeDecode(resp.bodyBytes);
    final list =
        decoded is Map && decoded['data'] is List
            ? (decoded['data'] as List)
            : (decoded is List ? decoded : <dynamic>[]);
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => Pod.fromJson(m))
        .toList();
  }

  // Search methods with debouncing
  Future<List<_SelectItem>> _searchStockists(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    
    // Always hit the API, even for empty search to get default list
    final searchParam = query.trim().isEmpty ? '' : '?search=${query.trim()}';
    final uri = Uri.parse('$API_STOCKISTS_URL$searchParam');
    
    final resp = await http.get(
      uri,
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
    );
    
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    
    final decoded = _safeDecode(resp.bodyBytes);
    final rawList = decoded is Map && decoded['data'] is List
        ? (decoded['data'] as List)
        : (decoded is List ? decoded : <dynamic>[]);
    
    return rawList
        .map((e) => _SelectItem.fromDynamic(e))
        .where((e) => e != null)
        .cast<_SelectItem>()
        .toList();
  }

  Future<List<_SelectItem>> _searchHospitals(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    
    // Always hit the API, even for empty search to get default list
    final searchParam = query.trim().isEmpty ? '' : '?search=${query.trim()}';
    final uri = Uri.parse('$API_HOSPITALS_URL$searchParam');
    
    final resp = await http.get(
      uri,
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
    );
    
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    
    final decoded = _safeDecode(resp.bodyBytes);
    final rawList = decoded is Map && decoded['data'] is List
        ? (decoded['data'] as List)
        : (decoded is List ? decoded : <dynamic>[]);
    
    return rawList
        .map((e) => _SelectItem.fromDynamic(e))
        .where((e) => e != null)
        .cast<_SelectItem>()
        .toList();
  }

  String _formatPodLabel(Pod pod) {
    String fmtDate(String iso) {
      try {
        final dt = DateTime.parse(iso);
        return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      } catch (_) {
        return iso;
      }
    }

    final podDt = pod.podDate.isNotEmpty ? fmtDate(pod.podDate) : '-';
    final invDt = pod.invoiceDate.isNotEmpty ? fmtDate(pod.invoiceDate) : '-';
    return 'POD ${pod.podNumber} | INV ${pod.invoiceNumber} | $podDt | $invDt';
  }

  List<dynamic> _unwrapToList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final k in ['data', 'items', 'results']) {
        final v = decoded[k];
        if (v is List) return v;
      }
    }
    return [];
  }

  /// ===================== QR / EINVOICE DECODING =====================

  Map<String, dynamic> _decodeGstQrFlexible(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    try {
      if (raw.contains('.')) {
        final parts = raw.split('.');
        if (parts.length >= 2) {
          final payload = base64Url.normalize(parts[1]);
          final decoded = utf8.decode(base64Url.decode(payload));
          final parsed = jsonDecode(decoded);
          if (parsed is Map<String, dynamic>) return parsed;
        }
      }
    } catch (_) {}
    try {
      final norm = base64.normalize(raw);
      final dec = utf8.decode(base64.decode(norm));
      final parsed = jsonDecode(dec);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    return {'raw': raw};
  }

  Map<String, dynamic>? _normalizeEinvoiceForDoc(DocumentInfo doc) {
    if (doc.qrData == null) return null;
    final q = doc.qrData!;
    final hasCore =
        q.containsKey('DocNo') ||
        q.containsKey('Irn') ||
        q.containsKey('TotInvVal');
    if (hasCore) return q;

    final candidates = <Map<String, dynamic>>[q];
    final raws = <String>[];

    for (final key in ['raw', 'data']) {
      final v = q[key];
      if (v is String && v.trim().isNotEmpty) raws.add(v);
    }
    for (final r in raws) {
      candidates.add(_decodeGstQrFlexible(r));
    }

    Map<String, dynamic>? best;
    int bestScore = -1;
    for (final c in candidates) {
      int score = 0;
      if (c.containsKey('DocNo')) score += 3;
      if (c.containsKey('DocDt')) score += 2;
      if (c.containsKey('Irn')) score += 4;
      if (c.containsKey('TotInvVal')) score += 3;
      if (c.containsKey('SellerGstin')) score += 1;
      if (c.containsKey('BuyerGstin')) score += 1;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best ?? q;
  }

  Future<void> _ensureQrForDocument(DocumentInfo doc, int overallIndex) async {
    if (doc.type != DocumentType.pdf) return;
    if (doc.qrData != null) return;

    if (_debugEinvoice) {
      debugPrint('[QR] Pre-upload check: ${doc.file.path}');
    }

    try {
      Map<String, dynamic>? qrMap;

      // Try with Hugging Face API first with timeout
      try {
        qrMap = await PythonQRService.extractQRFromPDF(
          doc.file,
          maxPages: 3,
          dpi: 400,
        ).timeout(
          const Duration(seconds: 90),
          onTimeout: () {
            if (_debugEinvoice) {
              debugPrint('[QR] HF API timeout for ${doc.displayName}');
            }
            return null;
          },
        );
      } catch (e) {
        if (_debugEinvoice) {
          debugPrint('[QR] HF API error for ${doc.displayName}: $e');
        }
        qrMap = null;
      }

      if (qrMap == null) {
        try {
          qrMap = await EInvoiceQRExtractor.extractQRFromPDF(
            doc.file,
            dpi: 600,
            maxPages: 2,
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              if (_debugEinvoice) {
                debugPrint(
                  '[QR] Flutter extraction timeout for ${doc.displayName}',
                );
              }
              return null;
            },
          );
        } catch (e) {
          if (_debugEinvoice) {
            debugPrint(
              '[QR] Flutter extraction error for ${doc.displayName}: $e',
            );
          }
          qrMap = null;
        }
      }

      if (qrMap != null) {
        final normalized = _decodeGstQrFlexible(
          jsonEncode(qrMap['raw'] ?? qrMap),
        );
        final merged = {...qrMap, ...normalized};
        final updated = doc.copyWith(qrData: merged);

        final idxInCaptured = _capturedDocuments.indexWhere(
          (d) => d.file.path == doc.file.path,
        );
        if (idxInCaptured >= 0 && mounted) {
          setState(() {
            _capturedDocuments[idxInCaptured] = updated;
          });
        }
        _einvoiceData ??= merged;

        if (_isEinvoiceDoc()) _autoMarkEinvoiceSelectedForEinvoiceFlow();

        if (_debugEinvoice) {
          debugPrint('[QR] ✓ Pre-upload extraction: ${doc.displayName}');
        }
      }
    } catch (e) {
      if (_debugEinvoice) {
        debugPrint('[QR] Pre-upload extraction error: ${doc.displayName}: $e');
      }
    }
  }

  /// ===================== DOC ANALYZE / ENHANCE / CONVERT =====================

  Future<DocumentInfo> _analyzeDocument(File file) async {
    try {
      if (!await file.exists()) {
        return DocumentInfo(
          file: file,
          isValid: false,
          errorMessage: 'File not found',
          type: DocumentType.image,
          displayName: p.basename(file.path),
        );
      }
      final ext = p.extension(file.path).toLowerCase();
      final name = p.basename(file.path);
      final size = await file.length();
      if (size < 100 || size > 50 * 1024 * 1024) {
        return DocumentInfo(
          file: file,
          isValid: false,
          errorMessage:
              'Invalid file size: ${(size / 1024 / 1024).toStringAsFixed(1)}MB',
          type: ext == '.pdf' ? DocumentType.pdf : DocumentType.image,
          displayName: name,
        );
      }
      if (ext == '.pdf') {
        return DocumentInfo(
          file: file,
          isValid: true,
          type: DocumentType.pdf,
          displayName: name,
        );
      }
      if (['.jpg', '.jpeg', '.png', '.webp', '.bmp'].contains(ext)) {
        final bytes = await file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          return DocumentInfo(
            file: file,
            isValid: false,
            errorMessage: 'Cannot decode image',
            type: DocumentType.image,
            displayName: name,
          );
        }
        if (decoded.width < 50 || decoded.height < 50) {
          return DocumentInfo(
            file: file,
            isValid: false,
            errorMessage: 'Image too small: ${decoded.width}x${decoded.height}',
            type: DocumentType.image,
            displayName: name,
          );
        }
        return DocumentInfo(
          file: file,
          isValid: true,
          type: DocumentType.image,
          displayName: '$name (${decoded.width}x${decoded.height})',
        );
      }
      return DocumentInfo(
        file: file,
        isValid: false,
        errorMessage: 'Unsupported format $ext',
        type: DocumentType.image,
        displayName: name,
      );
    } catch (e) {
      return DocumentInfo(
        file: file,
        isValid: false,
        errorMessage: 'Analysis error: $e',
        type: DocumentType.image,
        displayName: p.basename(file.path),
      );
    }
  }

  Future<File?> _enhanceImageForOCR(File original) async {
    try {
      final bytes = await original.readAsBytes();
      final res = await compute(_enhanceImageForOCRWorker, {
        'imageBytes': bytes,
      });
      if (res['success'] == true) {
        final tmp = await getTemporaryDirectory();
        final out = File(
          '${tmp.path}/enh_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await out.writeAsBytes(res['bytes'] as Uint8List);
        return out;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<File> _convertSingleImageToPDF(File imgFile) async {
    try {
      final data = await imgFile.readAsBytes();
      final doc = pw.Document();
      final mem = pw.MemoryImage(data);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Center(child: pw.Image(mem, fit: pw.BoxFit.contain)),
        ),
      );
      final bytes = await doc.save();
      final tmp = await getTemporaryDirectory();
      final outPath =
          '${tmp.path}/img_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outFile = File(outPath);
      await outFile.writeAsBytes(bytes);
      return outFile;
    } catch (_) {
      return imgFile;
    }
  }

  /// ===================== SCAN / PICK =====================

  Future<void> _takePhotoWithScanner() async {
    try {
      setState(() {
        _isProcessingImage = true;
        _updateBusyState();
      });
      final scanned = await FlutterDocScanner().getScanDocuments(page: 1);
      if (scanned != null && scanned is Map) {
        String? filePath =
            scanned['pdfUri']?.toString() ??
            scanned['imageUri']?.toString() ??
            scanned['documentUri']?.toString();
        if (filePath != null && filePath.isNotEmpty) {
          final local = filePath.replaceFirst('file://', '');
          final original = File(local);
          if (await original.exists()) {
            await _processAndAddDocument(original, isFromScanner: true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Scanned file not found.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scanner error: $e')));
    } finally {
      if (mounted)
        setState(() {
          _isProcessingImage = false;
          _updateBusyState();
        });
    }
  }

  Future<void> _pickImagesFromGallery() async {
    try {
      setState(() {
        _isProcessingImage = true;
        _updateBusyState();
      });
      final remaining = maxDocuments - _capturedDocuments.length;
      if (remaining <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Maximum $maxDocuments documents reached'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final imgs = await _imagePicker.pickMultiImage(
        imageQuality: 100,
        limit: remaining,
      );
      if (imgs.isNotEmpty) {
        for (int i = 0; i < imgs.length; i++) {
          await _processAndAddDocument(
            File(imgs[i].path),
            isFromScanner: false,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Processing image ${i + 1}/${imgs.length}'),
                duration: const Duration(milliseconds: 400),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gallery error: $e')));
    } finally {
      if (mounted)
        setState(() {
          _isProcessingImage = false;
          _updateBusyState();
        });
    }
  }

  Future<void> _pickPdfsFromFiles() async {
    try {
      setState(() {
        _isProcessingImage = true;
        _updateBusyState();
      });
      final remaining = maxDocuments - _capturedDocuments.length;
      if (remaining <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maximum documents reached'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        int added = 0;
        for (final f in result.files.take(remaining)) {
          if (f.path == null) continue;
          await _processAndAddDocument(File(f.path!), isFromScanner: true);
          added++;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added PDF $added/${result.files.length}'),
                duration: const Duration(milliseconds: 400),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Pick PDF error: $e')));
    } finally {
      if (mounted)
        setState(() {
          _isProcessingImage = false;
          _updateBusyState();
        });
    }
  }

  Future<void> _processAndAddDocument(
    File originalFile, {
    required bool isFromScanner,
  }) async {
    try {
      final info = await _analyzeDocument(originalFile);
      if (!info.isValid) {
        if (mounted) setState(() => _capturedDocuments.add(info));
        _scheduleScrollToBottom();
        return;
      }

      final List<File> finalPdfFiles = [];
      final List<String?> finalDisplayNames = [];
      final String displayNameBase = p.basenameWithoutExtension(
        info.displayName,
      );

      if (info.type == DocumentType.image) {
        final enhanced =
            isFromScanner ? null : await _enhanceImageForOCR(originalFile);
        final converted = await _convertSingleImageToPDF(
          enhanced ?? originalFile,
        );
        finalPdfFiles.add(converted);
        finalDisplayNames.add('$displayNameBase.pdf');
      } else {
        // ========= NEW: Split first =========
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Splitting ${info.displayName} into invoices...'),
            duration: const Duration(seconds: 3),
          ),
        );

        final splitParts = await _splitPdfViaApi(originalFile);

        if (splitParts.isNotEmpty) {
          for (int i = 0; i < splitParts.length; i++) {
            final part = splitParts[i];
            finalPdfFiles.add(part.file);
            // Prefer invoice number in display if available
            final disp =
                (part.invoiceNo != null && part.invoiceNo!.isNotEmpty)
                    ? 'Invoice_${part.invoiceNo}.pdf'
                    : '${displayNameBase}_part${i + 1}.pdf';
            finalDisplayNames.add(disp);
          }
        } else {
          // Fallback to original single PDF
          finalPdfFiles.add(originalFile);
          finalDisplayNames.add('$displayNameBase.pdf');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No splits returned. Using original ${info.displayName}.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      // Persist each final PDF into temp (copy) and enqueue QR
      final tmp = await getTemporaryDirectory();
      for (int i = 0; i < finalPdfFiles.length; i++) {
        final f = finalPdfFiles[i];
        final savedPath =
            '${tmp.path}/doc_${DateTime.now().millisecondsSinceEpoch}_${_capturedDocuments.length}_$i.pdf';
        final saved = await f.copy(savedPath);

        final dispName = finalDisplayNames[i] ?? '${displayNameBase}.pdf';

        if (!mounted) return;
        final newDoc = DocumentInfo(
          file: saved,
          isValid: true,
          type: DocumentType.pdf,
          displayName: dispName,
        );

        setState(() {
          _capturedDocuments.add(newDoc);
        });

        if (_isPodDoc() || _isEinvoiceDoc()) {
          final idx = _capturedDocuments.length - 1;
          _enqueueExtraction(newDoc, idx); // ← your existing QR pipeline
        }
      }

      _scheduleScrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capturedDocuments.add(
          DocumentInfo(
            file: originalFile,
            isValid: false,
            errorMessage: 'Processing error: $e',
            type: DocumentType.image,
            displayName: p.basename(originalFile.path),
          ),
        );
      });
      _scheduleScrollToBottom();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() {
        _updateBusyState();
      });
    }
  }

  /// Run QR extraction on main isolate (plugins often can't run in background isolates)
  /// with a timeout and a processing counter. Shows a SnackBar if no QR is found.
  /// ===================== QR EXTRACTION WITH ZOOM/CROP =====================

  /// ===================== QR EXTRACTION WITH PROGRESSIVE DPI ZOOM =====================

  /// ===================== QR EXTRACTION WITH PROGRESSIVE DPI ZOOM =====================

  Future<void> _autoExtractQRFromDocument(
    DocumentInfo docInfo,
    int index,
  ) async {
    // Basic guards
    if (!docInfo.isValid || docInfo.type != DocumentType.pdf) return;
    if (index < 0 || index >= _capturedDocuments.length) return;
    if (_capturedDocuments[index].qrData != null) return;

    _incProcessing();
    _isCancelled = false;
    _currentProcessingIndex = index;

    try {
      // Single, simple progress message
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Extracting QR (single API call)...',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            duration: Duration(seconds: 60),
            backgroundColor: Colors.blue,
          ),
        );
      }

      // Single API attempt — no DPI retries, no local fallback
      Map<String, dynamic>? qrMap;
      try {
        qrMap = await PythonQRService.extractQRFromPDF(
          docInfo.file,
          maxPages: 5,
        );
      } catch (e, st) {
        if (_debugEinvoice) {
          debugPrint('[QR] API call threw: $e');
          debugPrint('$st');
        }
        qrMap = null;
      } finally {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
      }

      if (qrMap == null) {
        if (mounted && !_isCancelled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No QR found in ${docInfo.displayName}.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
        if (_debugEinvoice) {
          debugPrint(
            '[QR] ❌ No QR from single API attempt for ${docInfo.displayName}',
          );
        }
        return;
      }

      // Merge/normalize like before
      final normalized = _decodeGstQrFlexible(
        jsonEncode(qrMap['raw'] ?? qrMap),
      );
      final merged = {...qrMap, ...normalized};

      if (!mounted) return;
      setState(() {
        _capturedDocuments[index] = docInfo.copyWith(qrData: merged);
        _einvoiceData ??= merged;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '✅ QR extracted via API',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e, st) {
      if (_debugEinvoice) {
        debugPrint('[QR] Unexpected error during extraction: $e');
        debugPrint('$st');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Something went wrong during QR extraction',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      _currentProcessingIndex = null;
      _decProcessing();
    }
  }

  /// Extract QR with focus on common QR regions (top-right, bottom-right)
  Future<Map<String, dynamic>?> _extractQRWithRegionFocus(File pdfFile) async {
    try {
      // This would require modifying EInvoiceQRExtractor to support region extraction
      // For now, we'll try with very high DPI on specific regions
      // You'll need to add this capability to EInvoiceQRExtractor.dart

      // Placeholder: Try extracting with focus on top-right quadrant
      // Most e-invoices have QR in top-right corner
      return await EInvoiceQRExtractor.extractQRFromPDF(
        pdfFile,
        dpi: 800,
        maxPages: 3,
      );
    } catch (e) {
      if (_debugEinvoice) {
        debugPrint('[QR] Region-based extraction error: $e');
      }
      return null;
    }
  }

  /// ===================== PERMISSIONS =====================

  /// ===================== JSON BUILDER (Laravel PHP-style) =====================

  String _buildPhpStyleFileEinvoiceJson(List<DocumentInfo> docs) {
    final List<Map<String, dynamic>> entries = [];
    for (final d in docs) {
      final currentDoc = _capturedDocuments.firstWhere(
        (x) => x.file.path == d.file.path,
        orElse: () => d,
      );
      final filename = p.basename(currentDoc.file.path);
      final einvoiceMap =
          _normalizeEinvoiceForDoc(currentDoc) ?? <String, dynamic>{};

      entries.add({
        'file': {'Illuminate\\Http\\UploadedFile': filename},
        'einvoice': jsonEncode(einvoiceMap),
      });
    }
    return jsonEncode(entries);
  }

  /// ===================== UPLOAD (Combined for POD, Per-file for others) =====================

  MediaType _inferContentType(File file) {
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.pdf') return MediaType('application', 'pdf');
    if (ext == '.png') return MediaType('image', 'png');
    if (ext == '.heic' || ext == '.heif') return MediaType('image', 'heic');
    return MediaType('image', 'jpeg');
  }

  Future<void> _uploadCaptured() async {
    if (_isUploading) return;
    if (_capturedDocuments.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No documents to upload')));
      return;
    }

    // Add overall timeout for the entire upload process
    try {
      await _performUpload().timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          throw TimeoutException('Upload process timed out after 10 minutes');
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _updateBusyState();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _performUpload() async {
    final validDocs = _capturedDocuments.where((d) => d.isValid).toList();
    if (validDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid documents to upload.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate selections by type
    if (_isPodDoc()) {
      if (_selectedStockist == null || _selectedChemist == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select Stockist & Hospital for POD.')),
        );
        return;
      }
    } else if (_isEinvoiceDoc()) {
      if (_selectedPod == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select POD to upload E-Invoice.')),
        );
        return;
      }
    } else {
      if (_selectedPod == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select POD to upload document.')),
        );
        return;
      }
    }

    setState(() {
      _isUploading = true;
      _updateBusyState();
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');

    try {
      if (_isPodDoc()) {
        // Show progress for QR processing
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Processing QR codes...'),
              duration: Duration(seconds: 2),
            ),
          );
        }

        // for (int i = 0; i < validDocs.length; i++) {
        //   if (!mounted) return;
        //   await _ensureQrForDocument(validDocs[i], i);
        // }

        // Reset QR processing states but keep upload state active
        if (mounted) {
          setState(() {
            _isProcessingImage = false;
            _processingCount = 0;
            _updateBusyState();
          });
        }

        // Show upload progress message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Uploading documents to server...'),
              duration: Duration(seconds: 2),
            ),
          );
        }

        final uri = Uri.parse(Multi_Api_POD_UPLOAD_URL);
        final req = http.MultipartRequest('POST', uri);

        // Attach files
        for (final d in validDocs) {
          final filename = p.basename(d.file.path);
          req.files.add(
            await http.MultipartFile.fromPath(
              'files[]',
              d.file.path,
              filename: filename,
              contentType: _inferContentType(d.file),
            ),
          );
        }

        // JSON array pairing each file (by filename) to its einvoice JSON string
        final phpStyleJson = _buildPhpStyleFileEinvoiceJson(validDocs);
        req.fields['file_einvoice_sequence'] = phpStyleJson;

        // Meta and selections
        req.fields['doc_type'] = _selectedDocType ?? 'POD';
        req.fields['document_count'] = validDocs.length.toString();
        req.fields['multi_page'] = (validDocs.length > 1).toString();
        req.fields['ocr_enhanced'] = 'true';
        req.fields['processed_for_ocr'] = 'true';
        req.fields['document_quality'] = 'high';
        req.fields['dpi'] = '300';

        if (_selectedStockist != null) {
          req.fields['stockist_id'] = _selectedStockist!.id;
          req.fields['stockistId'] = _selectedStockist!.id;
        }
        if (_selectedChemist != null) {
          req.fields['hospital_id'] = _selectedChemist!.id;
          req.fields['hospitalId'] = _selectedChemist!.id;
        }
        if (_selectedPod != null) {
          req.fields['pod_id'] = _selectedPod!.id;
        }

        if (token != null) req.headers['Authorization'] = 'Bearer $token';

        // Show final upload progress
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sending data to server...'),
              duration: Duration(seconds: 1),
            ),
          );
        }

        final streamed = await req.send();
        final resp = await http.Response.fromStream(streamed);

        if (!mounted) return;

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Uploaded ${validDocs.length} POD document(s) in a single request.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          // Clear uploaded docs
          final uploadedPaths = validDocs.map((d) => d.file.path).toSet();
          setState(() {
            _capturedDocuments.removeWhere(
              (d) => uploadedPaths.contains(d.file.path),
            );
            if (_capturedDocuments.every((d) => d.qrData == null)) {
              _einvoiceData = null;
            }
          });
          for (final pth in uploadedPaths) {
            try {
              final f = File(pth);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          }
        } else {
          debugPrint(
            'POD upload failed: ${resp.statusCode} ${resp.body.isNotEmpty ? "- ${resp.body}" : ""}',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'POD upload failed: ${resp.statusCode} ${resp.body.isNotEmpty ? "- ${resp.body}" : ""}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        // E-INVOICE or other types: per-file uploads
        final successes = <int>[];
        final failures = <int>[];
        print('Uploading ${validDocs.length} documents');
        for (int i = 0; i < validDocs.length; i++) {
          if (!mounted) return;
          final doc = validDocs[i];
          print('Uploading document: ${doc.qrData}');
          if (_isEinvoiceDoc()) {
            print('Ensuring QR for document: ${doc.qrData}');
            await _ensureQrForDocument(doc, i);
          }

          final currentDoc = _capturedDocuments.firstWhere(
            (d) => d.file.path == doc.file.path,
            orElse: () => doc,
          );
          final perDocInvoice =
              _isEinvoiceDoc() ? _normalizeEinvoiceForDoc(currentDoc) : null;

          final uri = Uri.parse(API_DOC_UPLOAD_URL);
          final request = http.MultipartRequest('POST', uri);

          request.files.add(
            await http.MultipartFile.fromPath(
              'file',
              currentDoc.file.path,
              filename: p.basename(currentDoc.file.path),
              contentType: _inferContentType(currentDoc.file),
            ),
          );

          request.fields['document_count'] = '1';
          request.fields['multi_page'] = 'false';
          request.fields['ocr_enhanced'] = 'true';
          request.fields['processed_for_ocr'] = 'true';
          request.fields['document_quality'] = 'high';
          request.fields['dpi'] = '300';
          request.fields['doc_type'] = _selectedDocType ?? '';

          if (_selectedStockist != null) {
            request.fields['stockist_id'] = _selectedStockist!.id;
            request.fields['stockistId'] = _selectedStockist!.id;
          }
          if (_selectedChemist != null) {
            request.fields['hospital_id'] = _selectedChemist!.id;
            request.fields['hospitalId'] = _selectedChemist!.id;
          }
          if (_selectedPod != null) {
            request.fields['pod_id'] = _selectedPod!.id;
          }

          if (perDocInvoice != null) {
            request.fields['einvoice'] = jsonEncode(perDocInvoice);
          }

          if (token != null) {
            request.headers['Authorization'] = 'Bearer $token';
          }

          // Show upload progress for each document
          if (mounted && i == 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sending documents to server...'),
                duration: Duration(seconds: 1),
              ),
            );
          }

          final streamed = await request.send();
          final resp = await http.Response.fromStream(streamed);
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            successes.add(i);
          } else {
            failures.add(i);
            if (_debugEinvoice) {
              debugPrint(
                '[UPLOAD FAIL] ${currentDoc.displayName} -> ${resp.statusCode} ${resp.body}',
              );
            }
          }
        }

        // Reset QR processing states but keep upload state active
        if (mounted) {
          setState(() {
            _isProcessingImage = false;
            _processingCount = 0;
            _updateBusyState();
          });
        }

        // Show upload progress message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Uploading documents to server...'),
              duration: Duration(seconds: 2),
            ),
          );
        }

        if (!mounted) return;

        if (successes.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Uploaded ${successes.length} document(s) successfully.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
        if (failures.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ ${failures.length} document(s) failed.'),
              backgroundColor: Colors.orange,
            ),
          );
        }

        if (successes.isNotEmpty) {
          final uploadedPaths =
              successes.map((i) => validDocs[i].file.path).toSet();
          setState(() {
            _capturedDocuments.removeWhere(
              (d) => uploadedPaths.contains(d.file.path),
            );
            if (_capturedDocuments.every((d) => d.qrData == null)) {
              _einvoiceData = null;
            }
          });
          for (final pth in uploadedPaths) {
            try {
              final f = File(pth);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _updateBusyState();
        });
        debugPrint('[UPLOAD] Upload process completed - isBusy: $_isBusy');
      }
    }
  }

  /// ===================== QR PROCESSING =====================

  Future<void> _processAllQRCodes() async {
    if (_capturedDocuments.isEmpty) return;

    final validDocs =
        _capturedDocuments
            .where((d) => d.isValid && d.type == DocumentType.pdf)
            .toList();
    if (validDocs.isEmpty) return;

    setState(() {
      _isProcessingImage = true;
      _processingCount = validDocs.length;
    });

    try {
      for (int i = 0; i < validDocs.length; i++) {
        if (!mounted) return;
        await _ensureQrForDocument(validDocs[i], i);
        _decProcessing();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingImage = false;
          _updateBusyState();
          _processingCount = 0;
        });
      }
    }
  }

  /// ===================== UI HELPERS =====================

  void _removeDocument(int index) {
    setState(() {
      try {
        _capturedDocuments[index].file.delete();
      } catch (_) {}
      _capturedDocuments.removeAt(index);
      if (_capturedDocuments.every((d) => d.qrData == null)) {
        _einvoiceData = null;
      }
    });
  }

  void _clearAllDocuments() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Clear All Documents'),
            content: Text('Remove all ${_capturedDocuments.length} documents?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    for (final d in _capturedDocuments) {
                      try {
                        d.file.delete();
                      } catch (_) {}
                    }
                    _capturedDocuments.clear();
                    _einvoiceData = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All documents cleared'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                },
                child: const Text('Clear All'),
              ),
            ],
          ),
    );
  }

  Future<void> _showDocumentSourceDialog() async {
    showDialog(
      context: context,
      builder: (_) {
        final remaining = maxDocuments - _capturedDocuments.length;
        return AlertDialog(
          title: const Text('Select Document Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.document_scanner),
                title: const Text('Document Scanner'),
                onTap: () {
                  Navigator.pop(context);
                  _takePhotoWithScanner();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery (Images)'),
                subtitle: Text(
                  remaining > 0
                      ? 'Select up to $remaining images'
                      : 'Limit reached',
                ),
                enabled: remaining > 0,
                onTap:
                    remaining > 0
                        ? () {
                          Navigator.pop(context);
                          _pickImagesFromGallery();
                        }
                        : null,
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Pick PDF File(s)'),
                subtitle: Text(
                  remaining > 0
                      ? 'Select up to $remaining PDFs'
                      : 'Limit reached',
                ),
                enabled: remaining > 0,
                onTap:
                    remaining > 0
                        ? () {
                          Navigator.pop(context);
                          _pickPdfsFromFiles();
                        }
                        : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String k, dynamic v) {
    final val = (v == null || v.toString().isEmpty) ? '-' : v.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$k:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(val)),
        ],
      ),
    );
  }

  /// ===================== UI BUILD =====================

  @override
  Widget build(BuildContext context) {
    final validDocCount = _capturedDocuments.where((d) => d.isValid).length;
    final docsWithQR = _capturedDocuments.where((d) => d.qrData != null).length;
    final showTopLoader =
        _isLoadingLists || _isProcessingImage || _processingCount > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Document'),
        actions: [
          // IconButton(onPressed: (){}, icon: Icon(Icons.person)),
          if (_capturedDocuments.isNotEmpty) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Chip(
                  label: Text('$validDocCount/$maxDocuments'),
                  backgroundColor:
                      _capturedDocuments.length >= maxDocuments
                          ? Colors.orange.shade100
                          : Colors.green.shade100,
                  labelStyle: TextStyle(
                    color:
                        _capturedDocuments.length >= maxDocuments
                            ? Colors.orange.shade800
                            : Colors.green.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (docsWithQR > 0)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Chip(
                    avatar: const Icon(Icons.qr_code, size: 16),
                    label: Text('$docsWithQR'),
                    backgroundColor: Colors.green.shade100,
                    labelStyle: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Clear All',
              onPressed: _isBusy ? null : _clearAllDocuments,
              icon: const Icon(Icons.clear_all),
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: Colors.teal,
        backgroundColor: Colors.white,
        strokeWidth: 2.5,
        displacement: 40.0,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal.withOpacity(0.05), Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (showTopLoader || _isRefreshing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          Text(
                            _isRefreshing
                                ? 'Refreshing page...'
                                : (_processingCount > 0 || _isProcessingImage)
                                ? 'Processing documents...'
                                : 'Loading lists...',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  _buildSectionCard(
                    icon: Icons.description,
                    title: 'Document Type',
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'POD', label: Text('POD')),
                        ButtonSegment(value: 'GRN', label: Text('GRN')),
                        ButtonSegment(
                          value: 'E-INVOICE',
                          label: Text('E-Invoice'),
                        ),
                      ],
                      selected: {_selectedDocType ?? 'POD'},
                      onSelectionChanged:
                          _isBusy
                              ? null
                              : (value) {
                                setState(() {
                                  _selectedDocType = value.first;
                                  _selectedStockist = null;
                                  _selectedChemist = null;
                                  _selectedPod = null;
                                  _einvoiceData = null;
                                  _stockistKey = UniqueKey();
                                  _chemistKey = UniqueKey();
                                  _podKey = UniqueKey();
                                });
                              },
                    ),
                  ),
                  if (_isPodDoc()) ...[
                    _buildSectionCard(
                      icon: Icons.store_mall_directory,
                      title: 'Stockist',
                      subtitle: 'Select Stockist',
                      child: _debouncedAutocomplete(
                        key: _stockistKey,
                        initialOptions: _allStockists,
                        selected: _selectedStockist,
                        label: 'Search Stockist',
                        onSelected:
                            (opt) => setState(() => _selectedStockist = opt),
                        onClear: () => setState(() => _selectedStockist = null),
                        searchFunction: _searchStockists,
                        isSearching: _isSearchingStockists,
                      ),
                    ),
                    _buildSectionCard(
                      icon: Icons.local_hospital,
                      title: 'Hospital',
                      subtitle: 'Select Hospital',
                      child: _debouncedAutocomplete(
                        key: _chemistKey,
                        initialOptions: _allChemists,
                        selected: _selectedChemist,
                        label: 'Search Hospital',
                        onSelected:
                            (opt) => setState(() => _selectedChemist = opt),
                        onClear: () => setState(() => _selectedChemist = null),
                        searchFunction: _searchHospitals,
                        isSearching: _isSearchingHospitals,
                      ),
                    ),
                  ],
                  if (!_isPodDoc())
                    _buildSectionCard(
                      icon: Icons.receipt_long,
                      title: 'POD Link',
                      subtitle: 'Select POD (recommended for E-Invoice / GRN)',
                      child: _customAutocomplete(
                        key: _podKey,
                        options: _allPods,
                        selected: _selectedPod,
                        label: 'Search POD',
                        onSelected: (opt) => setState(() => _selectedPod = opt),
                        onClear: () => setState(() => _selectedPod = null),
                      ),
                    ),
                  _buildSectionCard(
                    icon: Icons.add_a_photo,
                    title: 'Add Documents',
                    subtitle:
                        'Images converted to PDF. POD & E-INVOICE types auto-extract QR.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isBusy ? null : _showDocumentSourceDialog,
                          icon:
                              _isBusy
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Icon(Icons.add),
                          label: Text(
                            _isBusy ? 'Processing...' : 'Add Documents',
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Process QR Codes button
                        // if (_capturedDocuments.any((d) => d.isValid && d.type == DocumentType.pdf && d.qrData == null))
                        //   OutlinedButton.icon(
                        //     onPressed: _isBusy ? null : _processAllQRCodes,
                        //     icon: _isBusy
                        //         ? const SizedBox(
                        //             width: 18,
                        //             height: 18,
                        //             child: CircularProgressIndicator(
                        //               strokeWidth: 2,
                        //               color: Colors.blue,
                        //             ),
                        //           )
                        //         : const Icon(Icons.qr_code_scanner),
                        //     label: Text(
                        //       _isBusy ? 'Processing QR...' : 'Process QR Codes',
                        //     ),
                        //     style: OutlinedButton.styleFrom(
                        //       foregroundColor: Colors.blue,
                        //       side: const BorderSide(color: Colors.blue),
                        //     ),
                        //   ),
                        // const SizedBox(height: 8),
                        if (!_isPodDoc())
                          OutlinedButton.icon(
                            onPressed:
                                _isBusy
                                    ? null
                                    : () async {
                                      final res = await Navigator.push<
                                        Map<String, dynamic>
                                      >(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) => GstQrApp(
                                                podId: _selectedPod?.id ?? '0',
                                              ),
                                        ),
                                      );
                                      if (res != null) {
                                        setState(() => _einvoiceData = res);
                                        _autoMarkEinvoiceSelectedForEinvoiceFlow();
                                        await _openInvoiceDetails(res);
                                      }
                                    },
                            icon: const Icon(Icons.qr_code_scanner),
                            label: Text(
                              _einvoiceData != null
                                  ? 'Manual Scan (Done)'
                                  : 'Manual Scan (Camera)',
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_isEinvoiceDoc() && _einvoiceData != null)
                    _buildSectionCard(
                      icon: Icons.qr_code,
                      title: 'Primary E-Invoice',
                      subtitle: 'Auto/manual. Each PDF may have its own.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kv('Invoice No', _einvoiceData?['DocNo']),
                          _kv('Invoice Date', _einvoiceData?['DocDt']),
                          _kv('IRN', _einvoiceData?['Irn']),
                          _kv('Total Value', _einvoiceData?['TotInvVal']),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed:
                                      () => _openInvoiceDetails(_einvoiceData!),
                                  icon: const Icon(Icons.info),
                                  label: const Text('Details'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade600,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed:
                                    () => setState(() => _einvoiceData = null),
                                icon: const Icon(Icons.clear),
                                label: const Text('Clear'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (_capturedDocuments.isNotEmpty)
                    _buildSectionCard(
                      icon: Icons.collections,
                      title:
                          'Documents ($validDocCount valid / ${_capturedDocuments.length} total)',
                      subtitle:
                          'Green border = QR extracted (POD & E-INVOICE). Tap to preview. Tap QR badge to view.',
                      child: Column(
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                _capturedDocuments.asMap().entries.map((e) {
                                  final i = e.key;
                                  final d = e.value;
                                  return _buildDocumentThumbnail(d, i);
                                }).toList(),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed:
                                (_isUploading ||
                                        validDocCount == 0 ||
                                        _processingCount > 0 ||
                                        _isProcessingImage)
                                    ? null
                                    : _uploadCaptured,
                            icon:
                                _isUploading
                                    ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                    : const Icon(Icons.cloud_upload),
                            label: Text(
                              _isUploading
                                  ? 'Uploading...'
                                  : _processingCount > 0 || _isProcessingImage
                                  ? 'Processing QR Codes...'
                                  : validDocCount > 0
                                  ? 'Upload $validDocCount Document(s)'
                                  : 'No Valid Documents',
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_isUploading && _capturedDocuments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ===================== REUSABLE UI COMPONENTS =====================

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _customAutocomplete({
    Key? key,
    required List<_SelectItem> options,
    required _SelectItem? selected,
    required String label,
    required Function(_SelectItem) onSelected,
    required VoidCallback onClear,
  }) {
    return Autocomplete<_SelectItem>(
      key: key,
      displayStringForOption: (o) => o.label,
      optionsBuilder: (TextEditingValue tv) {
        final text = tv.text.toLowerCase();
        if (text.isEmpty) return options.take(50);
        return options.where(
          (o) =>
              o.label.toLowerCase().contains(text) ||
              o.id.toLowerCase().contains(text),
        );
      },
      fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
        if (selected != null && controller.text.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (controller.text.isEmpty) {
              controller.text = selected.label;
              controller.selection = TextSelection.fromPosition(
                TextPosition(offset: controller.text.length),
              );
            }
          });
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onTapOutside: (_) => FocusScope.of(ctx).unfocus(),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.grey.shade50,
            suffixIcon:
                controller.text.isEmpty
                    ? null
                    : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        controller.clear();
                        onClear();
                      },
                    ),
          ),
        );
      },
      optionsViewBuilder: (ctx, onSelectedOpt, iterable) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: iterable.length,
                itemBuilder: (_, i) {
                  final opt = iterable.elementAt(i);
                  return ListTile(
                    dense: true,
                    title: Text(opt.label),
                    onTap: () => onSelectedOpt(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: onSelected,
    );
  }

  // Debounced autocomplete for stockist and hospital search
  Widget _debouncedAutocomplete({
    Key? key,
    required List<_SelectItem> initialOptions,
    required _SelectItem? selected,
    required String label,
    required Function(_SelectItem) onSelected,
    required VoidCallback onClear,
    required Future<List<_SelectItem>> Function(String) searchFunction,
    required bool isSearching,
  }) {
    return Autocomplete<_SelectItem>(
      key: key,
      displayStringForOption: (o) => o.label,
      optionsBuilder: (TextEditingValue tv) async {
        final text = tv.text.trim();
        
        // Cancel any existing timer
        if (label.contains('Stockist')) {
          _stockistSearchTimer?.cancel();
        } else if (label.contains('Hospital')) {
          _hospitalSearchTimer?.cancel();
        }
        
        // If text is empty, return initial options
        if (text.isEmpty) {
          return initialOptions.take(50);
        }
        
        // Create a completer for the debounced result
        final completer = Completer<Iterable<_SelectItem>>();
        
        // Set up debounced timer
        final timer = Timer(const Duration(milliseconds: 500), () async {
          // Set loading state only when we actually start the API call
          if (mounted) {
            setState(() {
              if (label.contains('Stockist')) {
                _isSearchingStockists = true;
              } else if (label.contains('Hospital')) {
                _isSearchingHospitals = true;
              }
            });
          }
          
          try {
            final searchResults = await searchFunction(text);
            if (mounted) {
              setState(() {
                if (label.contains('Stockist')) {
                  _isSearchingStockists = false;
                } else if (label.contains('Hospital')) {
                  _isSearchingHospitals = false;
                }
              });
            }
            completer.complete(searchResults);
          } catch (e) {
            print('Search error: $e');
            if (mounted) {
              setState(() {
                if (label.contains('Stockist')) {
                  _isSearchingStockists = false;
                } else if (label.contains('Hospital')) {
                  _isSearchingHospitals = false;
                }
              });
            }
            // Fallback to local filtering if API fails
            final fallbackResults = initialOptions.where(
              (o) =>
                  o.label.toLowerCase().contains(text.toLowerCase()) ||
                  o.id.toLowerCase().contains(text.toLowerCase()),
            );
            completer.complete(fallbackResults);
          }
        });
        
        // Store the timer
        if (label.contains('Stockist')) {
          _stockistSearchTimer = timer;
        } else if (label.contains('Hospital')) {
          _hospitalSearchTimer = timer;
        }
        
        // Return initial filtered results immediately for better UX
        final initialFiltered = initialOptions.where(
          (o) =>
              o.label.toLowerCase().contains(text.toLowerCase()) ||
              o.id.toLowerCase().contains(text.toLowerCase()),
        ).take(20);
        
        // If we have good initial results, return them immediately
        if (initialFiltered.isNotEmpty) {
          return initialFiltered;
        }
        
        // Otherwise, wait for the debounced search results
        return completer.future;
      },
      fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
        if (selected != null && controller.text.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (controller.text.isEmpty) {
              controller.text = selected.label;
              controller.selection = TextSelection.fromPosition(
                TextPosition(offset: controller.text.length),
              );
            }
          });
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onTapOutside: (_) => FocusScope.of(ctx).unfocus(),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: isSearching 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.grey.shade50,
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      controller.clear();
                      onClear();
                    },
                  ),
          ),
        );
      },
      optionsViewBuilder: (ctx, onSelectedOpt, iterable) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: iterable.length,
                      itemBuilder: (_, i) {
                        final opt = iterable.elementAt(i);
                        return ListTile(
                          dense: true,
                          title: Text(opt.label),
                          onTap: () => onSelectedOpt(opt),
                        );
                      },
                    ),
            ),
          ),
        );
      },
      onSelected: onSelected,
    );
  }

  Widget _buildDocumentThumbnail(DocumentInfo docInfo, int index) {
    final hasQR = docInfo.qrData != null;
    final width = (MediaQuery.of(context).size.width - 64) / 3;

    return SizedBox(
      width: width,
      height: 132,
      child: Stack(
        children: [
          // Main thumbnail container
          GestureDetector(
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PdfPreviewScreen(pdfFile: docInfo.file),
                  ),
                ),
            child: Container(
              decoration: BoxDecoration(
                color: hasQR ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color:
                      hasQR
                          ? Colors.green.shade400
                          : (docInfo.isValid
                              ? Colors.grey.shade300
                              : Colors.red.shade300),
                  width: hasQR ? 2 : (docInfo.isValid ? 1 : 2),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.picture_as_pdf,
                    size: 34,
                    color:
                        hasQR
                            ? Colors.green.shade600
                            : (docInfo.isValid
                                ? Colors.red.shade600
                                : Colors.red.shade400),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PDF',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color:
                          hasQR ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                  if (hasQR)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.qr_code, size: 14),
                          const SizedBox(width: 2),
                          Text(
                            'QR',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      p.basenameWithoutExtension(docInfo.displayName),
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Remove button (top-right)
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: _isBusy ? null : () => _removeDocument(index),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: _isBusy ? Colors.grey : Colors.red.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),

          // Index badge (bottom-left)
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: docInfo.isValid ? Colors.black54 : Colors.red.shade600,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                docInfo.isValid ? '${index + 1}' : 'ERR',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // AUTO-EXTRACT BUTTON (top-left) - Blue (when no QR)
          if (docInfo.isValid &&
              docInfo.type == DocumentType.pdf &&
              !hasQR &&
              (_isPodDoc() || _isEinvoiceDoc()))
            Positioned(
              top: 4,
              left: 4,
              child: GestureDetector(
                onTap:
                    _isBusy ? null : () => _enqueueExtraction(docInfo, index),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _isBusy ? Colors.grey : Colors.blue.shade600,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.auto_awesome, color: Colors.white, size: 11),
                      SizedBox(width: 3),
                      Text(
                        'Auto',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // MANUAL SCAN BUTTON (bottom-right) - Orange (when no QR)
          if (docInfo.isValid &&
              docInfo.type == DocumentType.pdf &&
              !hasQR &&
              (_isPodDoc() || _isEinvoiceDoc()))
            Positioned(
              bottom: 4,
              right: 4,
              child: GestureDetector(
                onTap:
                    _isBusy
                        ? null
                        : () async {
                          final res =
                              await Navigator.push<Map<String, dynamic>>(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => GstQrApp(
                                        podId: _selectedPod?.id ?? '0',
                                      ),
                                ),
                              );
                          if (res != null && mounted) {
                            setState(() {
                              _capturedDocuments[index] = docInfo.copyWith(
                                qrData: res,
                              );
                              _einvoiceData ??= res;
                            });

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Manual QR scan successful'),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _isBusy ? Colors.grey : Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 11,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Scan',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // VIEW QR BUTTON (top-left) - Green (when QR exists)
          if (hasQR)
            Positioned(
              top: 4,
              left: 4,
              child: GestureDetector(
                onTap: () => _openInvoiceDetails(docInfo.qrData!),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade700,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.visibility, color: Colors.white, size: 11),
                      SizedBox(width: 3),
                      Text(
                        'View',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QrQueueItem {
  final DocumentInfo doc;
  final int index;
  _QrQueueItem(this.doc, this.index);
}

/// ===================== QR REGION ENUM =====================

enum QrRegion { topRight, bottomRight, topLeft, bottomLeft, center }

/// ===================== AUTOCOMPLETE SUPPORT =====================

class _SelectItem {
  final String id;
  final String label;
  _SelectItem({required this.id, required this.label});

  static _SelectItem? fromDynamic(dynamic value) {
    if (value == null) return null;
    if (value is String) return _SelectItem(id: value, label: value);
    if (value is Map) {
      final id = _pickString(value, const [
        'id',
        'ID',
        'stockistId',
        'chemistId',
        'code',
        'Code',
      ]);
      final label = _pickString(value, const [
        'name',
        'Name',
        'displayName',
        'DisplayName',
        'title',
        'Title',
        'label',
        'Label',
      ]);
      if (id != null && label != null) return _SelectItem(id: id, label: label);
      if (id != null) return _SelectItem(id: id, label: id);
      if (label != null) return _SelectItem(id: label, label: label);
    }
    return null;
  }

  static String? _pickString(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is num) return v.toString();
    }
    return null;
  }
}
