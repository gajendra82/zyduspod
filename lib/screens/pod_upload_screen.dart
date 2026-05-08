// COMMENTED OUT: QR extraction functionality is disabled but imports are kept for easy restoration
// To restore QR functionality: uncomment all QR-related code and remove this comment block

import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show File, SocketException; // used only on mobile/desktop paths
import 'dart:math' as math; // COMMENTED OUT: Used for QR processing
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'package:zyduspod/config.dart';
import 'package:zyduspod/GstInvoiceScanner.dart'; // COMMENTED OUT: Used for QR processing
import 'package:zyduspod/Models/_SplitOut.dart';
import 'package:zyduspod/services/PythonQRService.dart'; // COMMENTED OUT: Used for QR processing
import 'package:zyduspod/widgets/EInvoiceQRExtractor.dart'; // COMMENTED OUT: Used for QR processing
import 'package:zyduspod/widgets/PdfPreviewScreen.dart'; // existing File-based preview
import 'package:zyduspod/widgets/modern_ui_components.dart';
import 'package:zyduspod/screens/upload_status_screen.dart';
import 'package:zyduspod/routes.dart';
import 'package:zyduspod/utils/web_camera_helper.dart'
    if (dart.library.io) 'package:zyduspod/utils/web_camera_helper_stub.dart';

// PDF Splitting API
const String _SPLIT_API_BASE = 'https://anujakkulkarni-splitpdffile.hf.space';

// PDF Quality Check API
const String _QUALITY_CHECK_API =
    'https://harshadsalunkhe1212-checkpdfquality.hf.space/check-file';

/// Build MultipartFile from bytes (works on Web & mobile)
Future<http.MultipartFile> _multipartFromBytes({
  required String fieldName,
  required String filename,
  required List<int> bytes,
  MediaType? contentType,
}) async {
  return http.MultipartFile.fromBytes(
    fieldName,
    bytes,
    filename: filename,
    contentType: contentType,
  );
}

/// Build MultipartFile from File (mobile/desktop only)
Future<http.MultipartFile> _multipartFromFile({
  required String fieldName,
  required File file,
  MediaType? contentType,
}) async {
  final filename = p.basename(file.path);
  final bytes = await file.readAsBytes();
  return _multipartFromBytes(
    fieldName: fieldName,
    filename: filename,
    bytes: bytes,
    contentType: contentType,
  );
}

Future<List<SplitOut>> _splitPdfViaApi(File pdfFile) async {
  // On Web we handle splitting using bytes in a separate function
  if (kIsWeb) return <SplitOut>[];

  try {
    final uri = Uri.parse('$_SPLIT_API_BASE/split-invoices');

    final req =
        http.MultipartRequest('POST', uri)
          ..files.add(
            await _multipartFromFile(
              fieldName: 'file',
              file: pdfFile,
              contentType: MediaType('application', 'pdf'),
            ),
          )
          ..fields['include_pdf'] = 'true'
          ..fields['initial_dpi'] = '300';

    final streamed = await req.send().timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        throw TimeoutException('PDF split request timed out after 90 seconds');
      },
    );
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

      final fileName =
          'split_${i + 1}_${p.basenameWithoutExtension(pdfFile.path)}.pdf';
      final file = File(p.join(tmp.path, fileName));
      await file.writeAsBytes(bytes);

      final invoiceNo = e['invoice_no'] as String?;
      final pagesDynamic = e['pages'] as List<dynamic>?;
      final pages = pagesDynamic?.map((p) => p as int).toList();
      final sizeBytes = bytes.length;

      out.add(
        SplitOut(
          file: file,
          invoiceNo: invoiceNo,
          pages: pages,
          sizeBytes: sizeBytes,
        ),
      );
    }

    return out;
  } catch (e) {
    debugPrint('[SPLIT] Error: $e');
    return <SplitOut>[];
  }
}

/// In-memory split part for Web
class _SplitMem {
  final Uint8List bytes;
  final String? invoiceNo;
  final List<int>? pages;
  _SplitMem({required this.bytes, this.invoiceNo, this.pages});
}

/// Check file quality before processing (mobile/desktop)
Future<Map<String, dynamic>> _checkFileQuality(File file) async {
  try {
    final uri = Uri.parse(_QUALITY_CHECK_API);
    final req = http.MultipartRequest('POST', uri)
      ..files.add(
        await _multipartFromFile(
          fieldName: 'file',
          file: file,
          contentType: MediaType('application', 'pdf'),
        ),
      );

    final streamed = await req.send().timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw TimeoutException(
          'Quality check request timed out after 60 seconds',
        );
      },
    );
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      debugPrint('[QUALITY] HTTP ${resp.statusCode}: ${resp.body}');
      return {
        'is_good_for_extraction': true, // Allow processing if check fails
        'ocr_confidence': 0.0,
        'message': 'Quality check failed, proceeding anyway',
      };
    }

    final decoded = jsonDecode(resp.body);
    debugPrint('[QUALITY] Response: ${resp.body}');

    return {
      'is_good_for_extraction': decoded['is_good_for_extraction'] ?? false,
      'ocr_confidence': decoded['ocr_confidence']?.toDouble() ?? 0.0,
      'message': decoded['message'] ?? 'Quality check completed',
    };
  } catch (e) {
    debugPrint('[QUALITY] Error: $e');
    return {
      'is_good_for_extraction': true, // Allow processing if check fails
      'ocr_confidence': 0.0,
      'message': 'Quality check error, proceeding anyway',
    };
  }
}

/// Check file quality before processing (web - bytes)
Future<Map<String, dynamic>> _checkFileQualityBytes(
  Uint8List pdfBytes, {
  String filename = 'upload.pdf',
}) async {
  try {
    final uri = Uri.parse(_QUALITY_CHECK_API);
    final req = http.MultipartRequest('POST', uri)
      ..files.add(
        await _multipartFromBytes(
          fieldName: 'file',
          filename: filename,
          bytes: pdfBytes,
          contentType: MediaType('application', 'pdf'),
        ),
      );

    final streamed = await req.send().timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw TimeoutException(
          'Quality check request timed out after 60 seconds',
        );
      },
    );
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      debugPrint('[QUALITY] HTTP ${resp.statusCode}: ${resp.body}');
      return {
        'is_good_for_extraction': true,
        'ocr_confidence': 0.0,
        'message': 'Quality check failed, proceeding anyway',
      };
    }

    final decoded = jsonDecode(resp.body);
    debugPrint('[QUALITY] Response: ${resp.body}');

    return {
      'is_good_for_extraction': decoded['is_good_for_extraction'] ?? false,
      'ocr_confidence': decoded['ocr_confidence']?.toDouble() ?? 0.0,
      'message': decoded['message'] ?? 'Quality check completed',
    };
  } catch (e) {
    debugPrint('[QUALITY] Error: $e');
    return {
      'is_good_for_extraction': true,
      'ocr_confidence': 0.0,
      'message': 'Quality check error, proceeding anyway',
    };
  }
}

/// Server-side splitting for Web (bytes -> parts as bytes)
Future<List<_SplitMem>> _splitPdfViaApiBytes(
  Uint8List pdfBytes, {
  String filename = 'upload.pdf',
}) async {
  final uri = Uri.parse('$_SPLIT_API_BASE/split-invoices');

  final req =
      http.MultipartRequest('POST', uri)
        ..files.add(
          await _multipartFromBytes(
            fieldName: 'file',
            filename: filename,
            bytes: pdfBytes,
            contentType: MediaType('application', 'pdf'),
          ),
        )
        ..fields['include_pdf'] = 'true'
        ..fields['initial_dpi'] = '300';

  final streamed = await req.send().timeout(
    const Duration(seconds: 90),
    onTimeout: () {
      throw TimeoutException('PDF split request timed out after 90 seconds');
    },
  );
  final resp = await http.Response.fromStream(streamed);

  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    debugPrint('[SPLIT] (web) HTTP ${resp.statusCode}: ${resp.body}');
    throw Exception('Split API error ${resp.statusCode}');
  }

  final decoded = jsonDecode(resp.body);
  if (decoded is! Map || decoded['parts'] is! List) {
    debugPrint('[SPLIT] (web) Unexpected response: ${resp.body}');
    return <_SplitMem>[];
  }

  final parts = decoded['parts'] as List;
  final out = <_SplitMem>[];

  for (final e in parts) {
    if (e is! Map) continue;
    final String? b64 = e['pdf_base64'] as String?;
    if (b64 == null || b64.isEmpty) continue;

    try {
      final bytes = Uint8List.fromList(base64.decode(base64.normalize(b64)));
      final invoiceNo = e['invoice_no'] as String?;
      final pagesDynamic = e['pages'] as List<dynamic>?;
      final pages = pagesDynamic?.map((p) => p as int).toList();
      out.add(_SplitMem(bytes: bytes, invoiceNo: invoiceNo, pages: pages));
    } catch (err) {
      debugPrint('[SPLIT] (web) base64 decode failed: $err');
      continue;
    }
  }

  return out;
}

class PODUploadScreen extends StatefulWidget {
  const PODUploadScreen({super.key});

  @override
  State<PODUploadScreen> createState() => _PODUploadScreenState();
}

class _PODUploadScreenState extends State<PODUploadScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoadingLists = false;
  bool _isUploading = false;
  bool _isRefreshing = false;
  bool _isBusy = false;
  bool _isProcessingDocuments = false;
  String _currentProcessingMessage = '';

  // Tab controller for quality tabs
  late TabController _tabController;

  List<_SelectItem> _allStockists = [];
  List<_SelectItem> _allChemists = [];
  _SelectItem? _selectedStockist;

  Timer? _stockistSearchTimer;
  Timer? _hospitalSearchTimer;
  bool _isSearchingStockists = false;
  bool _isSearchingHospitals = false;
  _SelectItem? _selectedChemist;

  List<DocumentInfo> _capturedDocuments = [];

  Key _stockistKey = UniqueKey();
  Key _chemistKey = UniqueKey();

  final ImagePicker _imagePicker = ImagePicker();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _loadLists();
  }

  // Helper method to get good quality count
  int get _goodQualityCount =>
      _capturedDocuments
          .where((d) => d.isValid && (d.isGoodForExtraction ?? true))
          .length;

  // Helper method to get bad quality count
  int get _badQualityCount =>
      _capturedDocuments
          .where((d) => d.isValid && (d.isGoodForExtraction == false))
          .length;

  @override
  void dispose() {
    _stockistSearchTimer?.cancel();
    _hospitalSearchTimer?.cancel();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _updateBusyState() {
    setState(() {
      _isBusy =
          _isUploading ||
          _isLoadingLists ||
          _isRefreshing ||
          _isProcessingDocuments;
    });
  }

  Future<void> _onRefresh() async {
    if (_isBusy) return;

    setState(() {
      _isRefreshing = true;
      _updateBusyState();
    });

    try {
      setState(() {
        _selectedStockist = null;
        _selectedChemist = null;
        _stockistKey = UniqueKey();
        _chemistKey = UniqueKey();
      });

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

  Future<void> _loadLists() async {
    if (_isLoadingLists) return;

    setState(() {
      _isLoadingLists = true;
      _updateBusyState();
    });

    try {
      final results = await Future.wait([
        _fetchSelectItems(API_STOCKISTS_URL),
        _fetchSelectItems(API_HOSPITALS_URL),
      ]);

      if (!mounted) return;
      setState(() {
        _allStockists = results[0];
        _allChemists = results[1];
      });
    } catch (e) {
      debugPrint('Failed to load lists: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load lists: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLists = false;
          _updateBusyState();
        });
      }
    }
  }

  Future<List<_SelectItem>> _searchStockists(String query) async {
    if (query.length < 3) {
      return _allStockists.take(50).toList();
    }

    setState(() {
      _isSearchingStockists = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final searchUrl = '${API_STOCKISTS_URL}?search=$query';

      final resp = await http.get(
        Uri.parse(searchUrl),
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final decoded = _safeDecode(resp.bodyBytes);
      final rawList = _unwrapToList(decoded);

      final items =
          rawList
              .map((e) => _SelectItem.fromDynamic(e))
              .where((e) => e != null)
              .cast<_SelectItem>()
              .toList();

      return items;
    } catch (e) {
      debugPrint('Stockist search error: $e');
      return _allStockists
          .where(
            (item) => item.label.toLowerCase().contains(query.toLowerCase()),
          )
          .take(50)
          .toList();
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingStockists = false;
        });
      }
    }
  }

  Future<List<_SelectItem>> _searchHospitals(String query) async {
    if (query.length < 3) {
      return _allChemists.take(50).toList();
    }

    setState(() {
      _isSearchingHospitals = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final searchUrl = '${API_HOSPITALS_URL}?search=$query';

      final resp = await http.get(
        Uri.parse(searchUrl),
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final decoded = _safeDecode(resp.bodyBytes);
      final rawList = _unwrapToList(decoded);

      final items =
          rawList
              .map((e) => _SelectItem.fromDynamic(e))
              .where((e) => e != null)
              .cast<_SelectItem>()
              .toList();

      return items;
    } catch (e) {
      debugPrint('Hospital search error: $e');
      return _allChemists
          .where(
            (item) => item.label.toLowerCase().contains(query.toLowerCase()),
          )
          .take(50)
          .toList();
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingHospitals = false;
        });
      }
    }
  }

  Future<List<_SelectItem>> _fetchSelectItems(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    final resp = await http.get(
      Uri.parse(url),
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
    );
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.body}');
    }
    final decoded = _safeDecode(resp.bodyBytes);
    final rawList = _unwrapToList(decoded);

    final items =
        rawList
            .map((e) => _SelectItem.fromDynamic(e))
            .where((e) => e != null)
            .cast<_SelectItem>()
            .toList();

    return items;
  }

  dynamic _safeDecode(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      try {
        return jsonDecode(String.fromCharCodes(bytes));
      } catch (_) {
        return null;
      }
    }
  }

  List<dynamic> _unwrapToList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      if (decoded.containsKey('data') && decoded['data'] is List) {
        return decoded['data'];
      }
      if (decoded.containsKey('items') && decoded['items'] is List) {
        return decoded['items'];
      }
    }
    return [];
  }

  /// ===================== DOCUMENT PROCESSING =====================

  Future<void> _showDocumentSourceDialog() async {
    if (_isBusy) return;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Documents'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // PDF Files option - FIRST
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: const Text('PDF Files'),
                  subtitle: const Text('Select PDF files'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickPDFFiles();
                  },
                ),

                // Gallery option - SECOND
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Gallery'),
                  subtitle: const Text('Select images from gallery'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickFromGallery();
                  },
                ),

                // Camera option - THIRD
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Camera'),
                  subtitle: Text(
                    kIsWeb
                        ? 'Capture photo (requires camera access)'
                        : 'Scan documents with camera',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _captureFromCamera();
                  },
                ),
              ],
            ),
          ),
    );
  }

  // Add this import at the top

  Future<void> _captureFromCamera() async {
    if (_isBusy) return;

    setState(() {
      _isProcessingDocuments = true;
      _currentProcessingMessage = 'Opening camera...';
      _updateBusyState();
    });

    try {
      if (kIsWeb) {
        // Use web camera helper
        final bytes = await WebCameraHelper().captureFromCamera();

        if (bytes != null && bytes.isNotEmpty) {
          setState(() {
            _currentProcessingMessage = 'Processing captured image...';
          });

          await _processAndAddDocumentBytes(
            bytes,
            displayName: 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Image captured successfully'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Camera capture cancelled'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        // Mobile: use document scanner
        final scanned = await FlutterDocScanner().getScanDocuments(page: 1);
        List<String> result = [];
        if (scanned != null && scanned is Map) {
          String? filePath =
              scanned['pdfUri']?.toString() ??
              scanned['imageUri']?.toString() ??
              scanned['documentUri']?.toString();
          if (filePath != null) {
            result = [filePath];
          }
        }
        if (result.isNotEmpty) {
          for (final filePath in result) {
            final local = filePath.replaceFirst('file://', '');
            final original = File(local);
            await _processAndAddDocumentFile(original, isFromScanner: true);
          }
        }
      }
    } catch (e) {
      if (!mounted) return;

      String errorMessage = 'Camera error: $e';
      Color bgColor = Colors.red;

      // Provide specific error messages
      if (e.toString().contains('HTTPS')) {
        errorMessage =
            '⚠️ Camera requires HTTPS.  Please access the site securely.';
      } else if (e.toString().contains('NotAllowedError') ||
          e.toString().contains('Permission denied')) {
        errorMessage =
            '⚠️ Camera permission denied. Please allow camera access in browser settings.';
        bgColor = Colors.orange;
      } else if (e.toString().contains('NotFoundError')) {
        errorMessage = '⚠️ No camera found on this device. ';
      } else if (e.toString().contains('NotReadableError')) {
        errorMessage =
            '⚠️ Camera is already in use by another app.  Please close other camera apps.';
      } else if (e.toString().contains('OverconstrainedError')) {
        errorMessage =
            '⚠️ Camera constraints not supported.  Try a different device.';
      } else if (e.toString().contains('TypeError')) {
        errorMessage =
            '⚠️ Browser doesn\'t support camera access.  Please update your browser.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: bgColor,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingDocuments = false;
          _currentProcessingMessage = '';
          _updateBusyState();
        });
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isBusy) return;

    setState(() {
      _isProcessingDocuments = true;
      _currentProcessingMessage = 'Opening gallery...';
      _updateBusyState();
    });

    try {
      if (kIsWeb) {
        // Use web gallery helper
        final images = await WebCameraHelper().pickFromGallery();

        if (images.isNotEmpty) {
          for (int i = 0; i < images.length; i++) {
            setState(() {
              _currentProcessingMessage =
                  'Processing image ${i + 1}/${images.length}...';
            });

            await _processAndAddDocumentBytes(
              images[i].bytes,
              displayName: images[i].filename,
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Processing ${i + 1}/${images.length}'),
                  duration: const Duration(milliseconds: 400),
                ),
              );
            }
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ ${images.length} image(s) selected'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Gallery selection cancelled'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        // Mobile: use image picker
        final imgs = await _imagePicker.pickMultiImage(imageQuality: 100);

        if (imgs.isNotEmpty) {
          for (int i = 0; i < imgs.length; i++) {
            await _processAndAddDocumentFile(
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
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gallery error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingDocuments = false;
          _currentProcessingMessage = '';
          _updateBusyState();
        });
      }
    }
  }

  Future<void> _pickPDFFiles() async {
    if (_isBusy) return;

    setState(() {
      _isProcessingDocuments = true;
      _currentProcessingMessage = 'Selecting PDF files...';
      _updateBusyState();
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
        withData: true, // IMPORTANT for Web
      );

      if (result != null && result.files.isNotEmpty) {
        for (final f in result.files) {
          if (kIsWeb) {
            if (f.bytes == null) continue;
            await _processAndAddDocumentBytes(
              f.bytes!,
              displayName: f.name.isNotEmpty ? f.name : 'document.pdf',
            );
          } else {
            if (f.path == null) continue;
            await _processAndAddDocumentFile(
              File(f.path!),
              isFromScanner: true,
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
      if (mounted) {
        setState(() {
          _isProcessingDocuments = false;
          _currentProcessingMessage = '';
          _updateBusyState();
        });
      }
    }
  }

  Future<void> _processAndAddDocumentFile(
    File originalFile, {
    required bool isFromScanner,
  }) async {
    setState(() {
      _isProcessingDocuments = true;
      _currentProcessingMessage = 'Processing file...';
      _updateBusyState();
    });

    try {
      final displayNameBase = p.basenameWithoutExtension(originalFile.path);
      final extension = p.extension(originalFile.path).toLowerCase();

      if (extension == '.pdf') {
        setState(() {
          _currentProcessingMessage =
              'Adding ${p.basename(originalFile.path)}...';
        });

        // ✅ UPDATED: Add PDF directly - backend will handle splitting
        final newDoc = DocumentInfo(
          file: originalFile,
          webBytes: null,
          displayName: p.basename(originalFile.path),
          isValid: true,
          qrData: null,
          qrStatus: QRProcessingStatus.completed,
          originalRawFile: null, // Not needed - backend handles everything
          isGoodForExtraction: true,
          ocrConfidence: 100.0,
          qualityMessage: 'PDF - Backend will process',
        );

        setState(() {
          _capturedDocuments.add(newDoc);
        });
      } else {
        // Unsupported file format
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unsupported file format: $extension'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      _scheduleScrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() {
        _isProcessingDocuments = false;
        _currentProcessingMessage = '';
        _updateBusyState();
      });
    }
  }

  Future<void> _processAndAddDocumentBytes(
    Uint8List bytes, {
    required String displayName,
  }) async {
    setState(() {
      _isProcessingDocuments = true;
      _currentProcessingMessage = 'Processing file...';
      _updateBusyState();
    });

    try {
      final extension = p.extension(displayName).toLowerCase();
      final isPdf = extension == '.pdf';
      final isImage = [
        '.jpg',
        '.jpeg',
        '.png',
        '.gif',
        '.bmp',
        '.webp',
      ].contains(extension);

      // CREATE A COPY of bytes to prevent reference issues
      final bytesCopy = Uint8List.fromList(bytes);

      if (isImage) {
        // Add image directly
        final newDoc = DocumentInfo(
          file: null,
          webBytes: bytesCopy,
          displayName: displayName,
          isValid: true,
          qrData: null,
          qrStatus: QRProcessingStatus.completed,
          isGoodForExtraction: true,
          ocrConfidence: 100.0,
          qualityMessage: 'Image file',
        );

        setState(() {
          _capturedDocuments.add(newDoc);
        });

        _scheduleScrollToBottom();
        return;
      }

      if (!isPdf) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unsupported file format: $extension'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // PDF - process and split
      // ✅ UPDATED: PDF - add directly without frontend splitting
      // Backend will handle splitting automatically
      setState(() {
        _currentProcessingMessage = 'Adding ${displayName}...';
      });

      final newDoc = DocumentInfo(
        file: null,
        webBytes: bytesCopy,
        displayName: displayName,
        isValid: true,
        qrData: null,
        qrStatus: QRProcessingStatus.completed,
        isGoodForExtraction: true,
        ocrConfidence: 100.0,
        qualityMessage: 'PDF - Backend will process',
      );

      setState(() {
        _capturedDocuments.add(newDoc);
      });

      _scheduleScrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() {
        _isProcessingDocuments = false;
        _currentProcessingMessage = '';
        _updateBusyState();
      });
    }
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// ===================== UPLOAD =====================

  Future<void> _uploadCaptured() async {
    if (_isBusy) return;

    // Filter to only good quality files that are valid
    final validDocs =
        _capturedDocuments
            .where((d) => d.isValid && (d.isGoodForExtraction ?? true))
            .toList();
    if (validDocs.isEmpty) {
      final badQualityCount =
          _capturedDocuments
              .where((d) => d.isValid && (d.isGoodForExtraction == false))
              .length;
      if (badQualityCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No good quality documents to upload. $badQualityCount file(s) have low quality. Please reupload with better quality.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid documents to upload')),
        );
      }
      return;
    }

    if (_selectedStockist == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select Stockist for POD.')));
      return;
    }

    final stockistIdStr = _selectedStockist!.id.trim();

    if (stockistIdStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stockist is empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final stockistId = int.tryParse(stockistIdStr);

    if (stockistId == null || stockistId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid Stockist ID: "$stockistIdStr"'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await _performUpload(validDocs);
  }

  Future<void> _performUpload(List<DocumentInfo> validDocs) async {
    setState(() {
      _isUploading = true;
      _updateBusyState();
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final stockistIdStr = _selectedStockist!.id.trim();

      const int maxRetries = 4;

      // Compute the upload timeout from the actual payload — `req.send()`
      // covers TCP connect + TLS + ALL multipart bytes + first response
      // byte, so a flat 45s timed out on slow links the moment the user
      // queued more than a few PDFs. Formula:
      //   base 60s + 20s per file + 1s per 50 KB total, capped at 12 min.
      int totalBytesEstimate = 0;
      for (final d in validDocs) {
        try {
          if (d.file != null) {
            totalBytesEstimate += await d.file!.length();
          } else if (d.webBytes != null) {
            totalBytesEstimate += d.webBytes!.length;
          }
        } catch (_) {
          // best-effort; missing size doesn't break the timeout calc
        }
      }
      final int dynamicSendSeconds = (60
              + (validDocs.length * 20)
              + (totalBytesEstimate / 50000).ceil())
          .clamp(120, 12 * 60);
      final Duration connectTimeout = Duration(seconds: dynamicSendSeconds);
      const Duration responseTimeout = Duration(minutes: 5);
      debugPrint(
        '[UPLOAD] Computed send timeout: ${connectTimeout.inSeconds}s '
        '(files: ${validDocs.length}, ~${(totalBytesEstimate / 1024).toStringAsFixed(0)} KB)',
      );

      final uri = Uri.parse(Multi_Api_POD_UPLOAD_URL);

      // Validate URL
      if (!uri.isAbsolute) {
        throw Exception(
          'Invalid API URL: $Multi_Api_POD_UPLOAD_URL\n'
          'URL must be absolute (start with http/https)',
        );
      }

      debugPrint('[UPLOAD] API Endpoint: $Multi_Api_POD_UPLOAD_URL');

      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          debugPrint(
            '[UPLOAD] Attempt ${attempt + 1}/$maxRetries: sending ${validDocs.length} file(s)',
          );

          final req = http.MultipartRequest('POST', uri);

          // Attach files
          for (final d in validDocs) {
            if (d.file != null) {
              // Mobile/desktop: use file path
              final filename = p.basename(d.file!.path);
              final contentType = _inferContentTypeFile(d.file!);
              req.files.add(
                await http.MultipartFile.fromPath(
                  'files[]',
                  d.file!.path,
                  filename: filename,
                  contentType: contentType,
                ),
              );
            } else if (d.webBytes != null) {
              // Web: use bytes
              final filename = d.displayName;
              final contentType = _inferContentTypeByName(filename);
              req.files.add(
                await _multipartFromBytes(
                  fieldName: 'files[]',
                  filename: filename,
                  bytes: d.webBytes!,
                  contentType: contentType,
                ),
              );
            }
          }

          // Attach original raw files if documents were split
          final Set<String> rawFilePaths = {};
          for (final d in validDocs) {
            if (d.originalRawFile != null &&
                await d.originalRawFile!.exists()) {
              rawFilePaths.add(d.originalRawFile!.path);
            }
          }
          for (final rawFilePath in rawFilePaths) {
            final rawFile = File(rawFilePath);
            final filename = p.basename(rawFile.path);
            final contentType = _inferContentTypeFile(rawFile);
            req.files.add(
              await http.MultipartFile.fromPath(
                'raw_file',
                rawFile.path,
                filename: filename,
                contentType: contentType,
              ),
            );
            debugPrint('[UPLOAD] Attached original raw file: $filename');
          }

          if (token != null) {
            req.headers['Authorization'] = 'Bearer $token';
          }

          // Force fresh connection to reduce stale keep-alive socket aborts.
          req.headers['Connection'] = 'close';

          final phpStyleJson = _buildPhpStyleJson(validDocs);
          req.fields['file_einvoice_sequence'] = phpStyleJson;
          req.fields['doc_type'] = 'POD';
          req.fields['document_count'] = validDocs.length.toString();
          req.fields['multi_page'] = (validDocs.length > 1).toString();
          req.fields['ocr_enhanced'] = 'true';
          req.fields['dpi'] = '300';
          req.fields['stockist_id'] = stockistIdStr;
          req.fields['stockistId'] = stockistIdStr;

          debugPrint('[UPLOAD] ======================');
          debugPrint('[UPLOAD] Request ready to send:');
          debugPrint('[UPLOAD]   Files: ${req.files.length}');
          debugPrint('[UPLOAD]   Fields: ${req.fields.keys.join(", ")}');
          debugPrint(
            '[UPLOAD]   Has auth token: ${token != null && token.isNotEmpty}',
          );
          debugPrint('[UPLOAD] ======================');

          // Long-running upload: keep the user informed while the bytes
          // travel. Without this the screen looks frozen on slow links.
          ScaffoldMessengerState? messenger;
          if (mounted) {
            messenger = ScaffoldMessenger.of(context);
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Uploading ${validDocs.length} POD(s)… '
                        'attempt ${attempt + 1}/$maxRetries',
                      ),
                    ),
                  ],
                ),
                duration: connectTimeout, // visible for the whole window
              ),
            );
          }

          final resp = await req.send().timeout(connectTimeout);
          final responseBody = await resp.stream.bytesToString().timeout(
            responseTimeout,
          );

          if (messenger != null) {
            messenger.hideCurrentSnackBar();
          }

          debugPrint('[UPLOAD] Response Status: ${resp.statusCode}');
          debugPrint('[UPLOAD] Response Headers: ${resp.headers}');
          debugPrint(
            '[UPLOAD] Response Body (first 500 chars): ${responseBody.substring(0, math.min(500, responseBody.length))}',
          );

          // Check if response is HTML (error page) instead of JSON
          if (responseBody.trim().startsWith('<') ||
              responseBody.trim().startsWith('<!')) {
            String errorMsg =
                'Server returned an error page. This may indicate:\n'
                '• CORS issues\n'
                '• Server error or service unavailable\n'
                '• Network redirect';

            if (responseBody.contains('error')) {
              final regex = RegExp(
                r'<[^>]*>([^<]*error[^<]*)<[^>]*>',
                caseSensitive: false,
              );
              final match = regex.firstMatch(responseBody);
              if (match != null) {
                errorMsg = match.group(1)?.trim() ?? errorMsg;
              }
            }

            debugPrint('[UPLOAD] HTML Error Response detected');

            // HTML errors from 5xx are retryable
            if (_isRetryableUploadStatus(resp.statusCode) &&
                attempt < maxRetries - 1) {
              final wait = _uploadRetryDelay(attempt);
              debugPrint('[UPLOAD] Retrying after HTML error response...');
              await Future.delayed(wait);
              continue;
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Upload failed: $errorMsg\n\nPlease check your internet connection.',
                  ),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
            return;
          }

          if (resp.statusCode == 201) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '✅ Uploaded ${validDocs.length} POD document(s) successfully. Data generated.',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            }

            setState(() {
              _capturedDocuments.clear();
            });

            if (mounted) {
              Navigator.pop(context);
            }
            return;
          }

          if (resp.statusCode == 202) {
            try {
              final responseData = jsonDecode(responseBody);

              if (mounted) {
                Navigator.pushReplacementNamed(
                  context,
                  AppRoutes.uploadStatus,
                  arguments: {
                    'uploadData': responseData,
                    'totalFiles': validDocs.length,
                  },
                );
              }
            } catch (e) {
              debugPrint('Error parsing 202 response: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✅ Uploaded ${validDocs.length} POD document(s). Background processing initiated.',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
              setState(() {
                _capturedDocuments.clear();
              });
              if (mounted) {
                Navigator.pop(context);
              }
            }
            return;
          }

          if (_isRetryableUploadStatus(resp.statusCode) &&
              attempt < maxRetries - 1) {
            final wait = _uploadRetryDelay(attempt);
            debugPrint(
              '[UPLOAD] Retryable HTTP ${resp.statusCode}. Retrying in ${wait.inSeconds}s',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Server is busy (HTTP ${resp.statusCode}). Retrying ${attempt + 2}/$maxRetries...',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            await Future.delayed(wait);
            continue;
          }

          // Non-retryable HTTP error — parse and surface the message
          String errorMessage = 'Unknown error';
          try {
            final errorData = jsonDecode(responseBody);
            errorMessage =
                errorData['error'] ??
                errorData['message'] ??
                errorData['detail'] ??
                'Server error (${resp.statusCode})';
          } catch (_) {
            errorMessage =
                responseBody.isNotEmpty
                    ? responseBody.length > 200
                        ? '${responseBody.substring(0, 200)}...'
                        : responseBody
                    : 'Server error (${resp.statusCode})';
          }

          debugPrint('POD upload failed: ${resp.statusCode} - $errorMessage');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('POD upload failed: $errorMessage'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        } catch (e) {
          final canRetry =
              _isRetryableUploadError(e) && attempt < maxRetries - 1;
          debugPrint('[UPLOAD] Attempt ${attempt + 1} error: $e');

          if (canRetry) {
            final wait = _uploadRetryDelay(attempt);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Network issue while uploading. Retrying ${attempt + 2}/$maxRetries...',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            await Future.delayed(wait);
            continue;
          }

          rethrow;
        }
      }
    } catch (e) {
      debugPrint('Upload error: $e');

      String errorMsg = 'Upload failed: $e';

      if (e is TimeoutException) {
        errorMsg =
            'Upload timed out. Server did not respond in time.\n\n'
            'Please check:\n'
            '• Your internet connection\n'
            '• The server is running\n'
            '• Try uploading again with smaller files';
      } else if (e.toString().contains('Connection reset') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('connection abort')) {
        errorMsg =
            'Connection failed.\n\n'
            'Please check:\n'
            '• Your internet connection\n'
            '• The API server is accessible\n'
            '• Try again in a moment';
      } else if (e.toString().contains('CORS') ||
          e.toString().contains('No element at index')) {
        errorMsg =
            'Server connection issue detected.\n\n'
            'This may be a CORS or network configuration issue.\n'
            'Please contact support.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _updateBusyState();
        });
      }
    }
  }

  Duration _uploadRetryDelay(int attempt) {
    // Longer, exponential-ish backoff so a real network glitch has time to
    // clear before the next retry: 4s, 8s, 16s, 30s.
    const ladder = [4, 8, 16, 30];
    final idx = attempt.clamp(0, ladder.length - 1);
    return Duration(seconds: ladder[idx]);
  }

  bool _isRetryableUploadStatus(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  bool _isRetryableUploadError(Object error) {
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;

    if (error is http.ClientException) {
      final message = error.message.toLowerCase();
      return message.contains('socketexception') ||
          message.contains('connection abort') ||
          message.contains('connection reset') ||
          message.contains('timed out') ||
          message.contains('connection closed');
    }

    return false;
  }

  MediaType _inferContentTypeByName(String filename, {File? fallbackFromFile}) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.pdf':
        return MediaType('application', 'pdf');
      case '.jpg':
      case '.jpeg':
        return MediaType('image', 'jpeg');
      case '.png':
        return MediaType('image', 'png');
      default:
        if (fallbackFromFile != null)
          return _inferContentTypeFile(fallbackFromFile);
        return MediaType('application', 'octet-stream');
    }
  }

  MediaType _inferContentTypeFile(File file) {
    final ext = p.extension(file.path).toLowerCase();
    switch (ext) {
      case '.pdf':
        return MediaType('application', 'pdf');
      case '.jpg':
      case '.jpeg':
        return MediaType('image', 'jpeg');
      case '.png':
        return MediaType('image', 'png');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  String _buildPhpStyleJson(List<DocumentInfo> docs) {
    final entries = <Map<String, dynamic>>[];
    for (int i = 0; i < docs.length; i++) {
      final doc = docs[i];
      final name = doc.displayName;
      entries.add({
        'index': i,
        'filename': name,
        'qr_data': doc.qrData,
        'is_valid': doc.isValid,
      });
    }
    return jsonEncode(entries);
  }

  void _clearAllDocuments() {
    if (_isBusy) return;
    setState(() {
      _capturedDocuments.clear();
    });
  }

  void _showClearAllDialog() {
    if (_isBusy) return;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear All Documents'),
            content: Text(
              'Are you sure you want to remove all ${_capturedDocuments.length} documents?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _clearAllDocuments();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All documents cleared'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                },
                child: const Text(
                  'Clear All',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  /// ===================== UI BUILD =====================

  @override
  Widget build(BuildContext context) {
    // final validDocCount = _capturedDocuments.where((d) => d.isValid).length; // Not used anymore
    final showTopLoader = _isLoadingLists || _isProcessingDocuments;

    return Scaffold(
      appBar: ModernUIComponents.buildModernAppBar(
        title: 'POD Upload',
        subtitle: 'Upload Proof of Delivery documents',
        icon: Icons.description,
        color: const Color(0xFF00A0A8),
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
                                : _isProcessingDocuments
                                ? _currentProcessingMessage
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
                    icon: Icons.store_mall_directory,
                    title: 'Stockist',
                    subtitle: 'Select Stockist',
                    child: _customAutocomplete(
                      key: _stockistKey,
                      options: _allStockists,
                      selected: _selectedStockist,
                      label: 'Search Stockist',
                      onSelected:
                          (opt) => setState(() => _selectedStockist = opt),
                      onClear: () {
                        setState(() {
                          _selectedStockist = null;
                          _stockistKey = UniqueKey();
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Stockist selection cleared'),
                            duration: Duration(seconds: 1),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      },
                      isStockist: true,
                    ),
                  ),

                  // _buildSectionCard(
                  //   icon: Icons.local_hospital,
                  //   title: 'Hospital',
                  //   subtitle: 'Select Hospital',
                  //   child: _customAutocomplete(
                  //     key: _chemistKey,
                  //     options: _allChemists,
                  //     selected: _selectedChemist,
                  //     label: 'Search Hospital',
                  //     onSelected:
                  //         (opt) => setState(() => _selectedChemist = opt),
                  //     onClear: () {
                  //       setState(() {
                  //         _selectedChemist = null;
                  //         _chemistKey = UniqueKey();
                  //       });
                  //       ScaffoldMessenger.of(context).showSnackBar(
                  //         const SnackBar(
                  //           content: Text('Hospital selection cleared'),
                  //           duration: Duration(seconds: 1),
                  //           backgroundColor: Colors.orange,
                  //         ),
                  //       );
                  //     },
                  //     isStockist: false,
                  //   ),
                  // ),
                  _buildSectionCard(
                    icon: Icons.add_a_photo,
                    title: 'Add Documents',
                    subtitle:
                        'Images converted to PDF. POD documents ready for upload.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isBusy ? null : _showDocumentSourceDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Documents'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00A0A8),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_capturedDocuments.isNotEmpty) ...[
                    _buildSectionCard(
                      icon: Icons.collections,
                      title: 'Documents',
                      subtitle: 'View files by quality',
                      child: Column(
                        children: [
                          // Tab Bar
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              tabs: [
                                Tab(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.check_circle, size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        'All Documents (${_capturedDocuments.where((d) => d.isValid).length})',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Tab Bar View
                          SizedBox(
                            height: 400, // Fixed height for tab content
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                Builder(
                                  builder: (context) {
                                    final allDocs =
                                        _capturedDocuments
                                            .where((d) => d.isValid)
                                            .toList();

                                    if (allDocs.isEmpty) {
                                      return Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.folder_open,
                                              size: 64,
                                              color: Colors.grey.shade400,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'No documents yet',
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: Colors.grey.shade600,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }

                                    return ListView.separated(
                                      itemCount: allDocs.length,
                                      separatorBuilder:
                                          (context, index) =>
                                              const SizedBox(height: 8),
                                      itemBuilder: (context, index) {
                                        final docIndex = _capturedDocuments
                                            .indexOf(allDocs[index]);
                                        return _buildDocumentCard(
                                          allDocs[index],
                                          docIndex,
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Summary and Clear All
                    _buildSectionCard(
                      icon: Icons.info,
                      title: 'Summary',
                      subtitle: 'Total documents: ${_capturedDocuments.length}',
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatItem(
                                  'Total',
                                  _capturedDocuments.length,
                                  Colors.blue,
                                ),
                                _buildStatItem(
                                  'Good Quality',
                                  _goodQualityCount,
                                  Colors.green,
                                ),
                                _buildStatItem(
                                  'Low Quality',
                                  _badQualityCount,
                                  Colors.red,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isBusy ? null : _showClearAllDialog,
                              icon: const Icon(Icons.clear_all, size: 18),
                              label: const Text('Clear All Documents'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade600,
                                side: BorderSide(color: Colors.red.shade300),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isBusy ? null : _uploadCaptured,
                      icon:
                          _isBusy
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                              : const Icon(Icons.cloud_upload),
                      label: Text(
                        _isBusy
                            ? (_isUploading
                                ? 'Uploading...'
                                : _isProcessingDocuments
                                ? 'Processing Documents...'
                                : 'Loading...')
                            : 'Upload $_goodQualityCount POD Documents',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isBusy ? Colors.grey : const Color(0xFF00A0A8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF00A0A8), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
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
    required bool isStockist,
  }) {
    return Autocomplete<_SelectItem>(
      key: key,
      displayStringForOption: (o) => o.label,
      optionsBuilder: (TextEditingValue tv) async {
        final text = tv.text.trim();

        if (text.isEmpty) {
          return options.take(50);
        }
        if (text.length < 3) {
          return options
              .where((o) => o.label.toLowerCase().contains(text.toLowerCase()))
              .take(50);
        }

        if (isStockist) {
          _stockistSearchTimer?.cancel();
        } else {
          _hospitalSearchTimer?.cancel();
        }

        // Return current options while waiting
        return options
            .where((o) => o.label.toLowerCase().contains(text.toLowerCase()))
            .take(50);
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            hintText: selected?.label ?? 'Type to search...',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isStockist && _isSearchingStockists)
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (!isStockist && _isSearchingHospitals)
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (selected != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: onClear,
                    tooltip: 'Clear selection',
                    color: Colors.red.shade600,
                  ),
              ],
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF00A0A8)),
            ),
          ),
          onFieldSubmitted: (value) => onFieldSubmitted(),
          readOnly: selected != null,
          onChanged: (value) async {
            if (value.length >= 3) {
              if (isStockist) {
                _stockistSearchTimer?.cancel();
                _stockistSearchTimer = Timer(
                  const Duration(milliseconds: 300),
                  () async {
                    final results = await _searchStockists(value);
                    if (mounted) {
                      setState(() {
                        _allStockists = results;
                      });
                    }
                  },
                );
              } else {
                _hospitalSearchTimer?.cancel();
                _hospitalSearchTimer = Timer(
                  const Duration(milliseconds: 300),
                  () async {
                    final results = await _searchHospitals(value);
                    if (mounted) {
                      setState(() {
                        _allChemists = results;
                      });
                    }
                  },
                );
              }
            }
          },
        );
      },
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildDocumentCard(DocumentInfo doc, int index) {
    final fileSize = _getDocSizeString(doc);

    // Use quality-based colors: green for good quality, red for bad quality
    final isGoodQuality = doc.isGoodForExtraction ?? true;
    Color borderColor =
        doc.isValid ? (isGoodQuality ? Colors.green : Colors.red) : Colors.grey;
    double borderWidth = 2;

    return Dismissible(
      key: Key('doc_$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete, color: Colors.red, size: 24),
      ),
      confirmDismiss: (direction) async {
        return await _showRemoveDialog(doc.displayName);
      },
      onDismissed: (direction) {
        _removeDocument(index);
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderColor, width: borderWidth),
        ),
        child: InkWell(
          onTap: () => _previewDocument(doc),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.description, color: borderColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        doc.displayName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _removeDocument(index),
                      icon: const Icon(Icons.close, size: 18),
                      color: Colors.red.shade600,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Size: $fileSize',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (doc.isGoodForExtraction != null) ...[
                      Icon(
                        doc.isGoodForExtraction == false
                            ? Icons.error
                            : Icons.check_circle,
                        size: 14,
                        color:
                            doc.isGoodForExtraction == false
                                ? Colors.red
                                : Colors.green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        doc.isGoodForExtraction == false
                            ? 'Low Quality (${doc.ocrConfidence?.toStringAsFixed(1) ?? "N/A"}%)'
                            : 'Good Quality',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              doc.isGoodForExtraction == false
                                  ? Colors.red
                                  : Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else ...[
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: doc.isValid ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        doc.isValid ? 'Valid' : 'Invalid',
                        style: TextStyle(
                          fontSize: 12,
                          color: doc.isValid ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
                if (doc.qualityMessage != null &&
                    doc.isGoodForExtraction == false) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            doc.qualityMessage!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getDocSizeString(DocumentInfo doc) {
    try {
      int bytes = 0;
      if (doc.webBytes != null) {
        bytes = doc.webBytes!.lengthInBytes;
      } else if (doc.file != null) {
        bytes = doc.file!.lengthSync();
      }
      if (bytes == 0) return 'Unknown';
      if (bytes < 1024) return '${bytes}B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } catch (_) {
      return 'Unknown';
    }
  }

  Future<bool> _showRemoveDialog(String fileName) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Remove Document'),
                content: Text('Are you sure you want to remove "$fileName"?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'Remove',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
        ) ??
        false;
  }

  void _previewDocument(DocumentInfo doc) {
    final extension = p.extension(doc.displayName).toLowerCase();
    final isPdf = extension == '.pdf';
    final isImage = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
    ].contains(extension);

    if (isImage) {
      // Preview image
      if (doc.webBytes != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => Scaffold(
                  appBar: AppBar(
                    title: Text(doc.displayName),
                    backgroundColor: const Color(0xFF00A0A8),
                  ),
                  body: InteractiveViewer(
                    child: Center(child: Image.memory(doc.webBytes!)),
                  ),
                ),
          ),
        );
      } else if (doc.file != null && !kIsWeb) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => Scaffold(
                  appBar: AppBar(
                    title: Text(doc.displayName),
                    backgroundColor: const Color(0xFF00A0A8),
                  ),
                  body: InteractiveViewer(
                    child: Center(child: Image.file(doc.file!)),
                  ),
                ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No image data available for preview')),
        );
      }
      return;
    }

    if (isPdf) {
      // Preview PDF
      if (doc.file != null && !kIsWeb) {
        Navigator.pushNamed(
          context,
          AppRoutes.pdfPreview,
          arguments: {'pdfFile': doc.file!},
        );
      } else if (doc.webBytes != null) {
        Navigator.pushNamed(
          context,
          AppRoutes.pdfPreview,
          arguments: {'pdfBytes': doc.webBytes!, 'title': doc.displayName},
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No PDF data available for preview')),
        );
      }
      return;
    }

    // Unsupported format
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Unsupported file format: $extension'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _removeDocument(int index) {
    if (_isBusy) return;

    setState(() {
      _capturedDocuments.removeAt(index);
    });
  }
}

/// ===================== DATA MODELS =====================

enum QRProcessingStatus { notStarted, processing, completed, failed }

class DocumentInfo {
  final File? file; // mobile/desktop
  final Uint8List? webBytes; // web
  final String displayName;
  final bool isValid;
  final Map<String, dynamic>? qrData;
  final QRProcessingStatus qrStatus;
  final String? errorMessage;
  final File? originalRawFile; // Original file if this was split from a PDF
  final bool? isGoodForExtraction; // Quality check result
  final double? ocrConfidence; // OCR confidence percentage
  final String? qualityMessage; // Quality check message

  DocumentInfo({
    required this.file,
    required this.webBytes,
    required this.displayName,
    required this.isValid,
    this.qrData,
    this.qrStatus = QRProcessingStatus.notStarted,
    this.errorMessage,
    this.originalRawFile,
    this.isGoodForExtraction,
    this.ocrConfidence,
    this.qualityMessage,
  });

  DocumentInfo copyWith({
    File? file,
    Uint8List? webBytes,
    String? displayName,
    bool? isValid,
    Map<String, dynamic>? qrData,
    QRProcessingStatus? qrStatus,
    String? errorMessage,
    File? originalRawFile,
    bool? isGoodForExtraction,
    double? ocrConfidence,
    String? qualityMessage,
  }) {
    return DocumentInfo(
      file: file ?? this.file,
      webBytes: webBytes ?? this.webBytes,
      displayName: displayName ?? this.displayName,
      isValid: isValid ?? this.isValid,
      qrData: qrData ?? this.qrData,
      qrStatus: qrStatus ?? this.qrStatus,
      errorMessage: errorMessage ?? this.errorMessage,
      originalRawFile: originalRawFile ?? this.originalRawFile,
      isGoodForExtraction: isGoodForExtraction ?? this.isGoodForExtraction,
      ocrConfidence: ocrConfidence ?? this.ocrConfidence,
      qualityMessage: qualityMessage ?? this.qualityMessage,
    );
  }
}

class _SelectItem {
  final String id;
  final String label;
  _SelectItem({required this.id, required this.label});

  static _SelectItem? fromDynamic(dynamic value) {
    if (value == null) return null;
    if (value is String) return _SelectItem(id: value, label: value);
    if (value is Map) {
      final id = _pickId(value, const [
        'id',
        'ID',
        'stockistId',
        'hospitalId',
        'podId',
      ]);
      final label = _pickString(value, const [
        'name',
        'Name',
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
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  static String? _pickId(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
      if (v is int) return v.toString();
    }
    return null;
  }
}

/// ===================== PDF PREVIEW (BYTES) =====================
/// Uses Syncfusion PDF Viewer which supports Web and memory bytes.
class PdfPreviewBytesScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final String title;

  const PdfPreviewBytesScreen({
    super.key,
    required this.pdfBytes,
    this.title = 'Preview',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ModernUIComponents.buildModernAppBar(
        title: title,
        subtitle: 'PDF preview',
        icon: Icons.picture_as_pdf,
        color: const Color(0xFF00A0A8),
      ),
      body: SfPdfViewer.memory(pdfBytes),
    );
  }
}
