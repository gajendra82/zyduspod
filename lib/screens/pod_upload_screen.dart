// COMMENTED OUT: QR extraction functionality is disabled but imports are kept for easy restoration
// To restore QR functionality: uncomment all QR-related code and remove this comment block

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File; // used only on mobile/desktop paths
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

// PDF Splitting API
const String _SPLIT_API_BASE = 'https://anujakkulkarni-splitpdffile.hf.space';

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

  final streamed = await req.send();
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

class _PODUploadScreenState extends State<PODUploadScreen> {
  bool _isLoadingLists = false;
  bool _isUploading = false;
  bool _isRefreshing = false;
  bool _isBusy = false;
  bool _isProcessingDocuments = false;
  String _currentProcessingMessage = '';

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
    _loadLists();
  }

  @override
  void dispose() {
    _stockistSearchTimer?.cancel();
    _hospitalSearchTimer?.cancel();
    _scrollController.dispose();
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
                // ListTile(
                //   leading: const Icon(Icons.camera_alt),
                //   title: const Text('Camera'),
                //   onTap: () {
                //     Navigator.pop(context);
                //     _captureFromCamera();
                //   },
                // ),
                // ListTile(
                //   leading: const Icon(Icons.photo_library),
                //   title: const Text('Gallery'),
                //   onTap: () {
                //     Navigator.pop(context);
                //     _pickFromGallery();
                //   },
                // ),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: const Text('PDF Files'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickPDFFiles();
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _captureFromCamera() async {
    if (_isBusy) return;

    setState(() {
      _isProcessingDocuments = true;
      _currentProcessingMessage = 'Capturing from camera...';
      _updateBusyState();
    });

    try {
      // Mobile-first; not supported on web.
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
          if (kIsWeb) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Camera capture is not supported on Web for this flow.',
                ),
              ),
            );
          } else {
            final original = File(local);
            await _processAndAddDocumentFile(original, isFromScanner: true);
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scanner error: $e')));
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
      _currentProcessingMessage = 'Selecting from gallery...';
      _updateBusyState();
    });

    try {
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Use "PDF Files" on Web for now.')),
        );
      } else {
        final imgs = await _imagePicker.pickMultiImage(imageQuality: 100);
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gallery error: $e')));
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
        int added = 0;
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
      _currentProcessingMessage =
          'Processing ${p.basename(originalFile.path)}...';
      _updateBusyState();
    });

    try {
      final displayNameBase = p.basenameWithoutExtension(originalFile.path);
      final extension = p.extension(originalFile.path).toLowerCase();

      if (extension == '.pdf') {
        setState(() {
          _currentProcessingMessage =
              'Splitting ${p.basename(originalFile.path)} into invoices...';
        });

        final splitParts = await _splitPdfViaApi(originalFile);

        if (!kIsWeb && splitParts.isNotEmpty) {
          setState(() {
            _currentProcessingMessage =
                'Adding ${splitParts.length} split documents...';
          });

          for (int i = 0; i < splitParts.length; i++) {
            final part = splitParts[i];
            final displayName =
                (part.invoiceNo != null && part.invoiceNo!.isNotEmpty)
                    ? 'Invoice_${part.invoiceNo}.pdf'
                    : '${displayNameBase}_part${i + 1}.pdf';

            final newDoc = DocumentInfo(
              file: part.file,
              webBytes: null,
              displayName: displayName,
              isValid: true,
              qrData: null,
              qrStatus: QRProcessingStatus.completed, // Skip QR extraction - mark as completed
              originalRawFile: originalFile, // Store reference to original raw file
            );

            setState(() {
              _capturedDocuments.add(newDoc);
            });
          }
        } else {
          final newDoc = DocumentInfo(
            file: originalFile,
            webBytes: null,
            displayName: '${displayNameBase}.pdf',
            isValid: true,
            qrData: null,
            qrStatus: QRProcessingStatus.completed,
          );

          setState(() {
            _capturedDocuments.add(newDoc);
          });
        }
      } else {
        setState(() {
          _currentProcessingMessage =
              'Adding ${p.basename(originalFile.path)}...';
        });

        final newDoc = DocumentInfo(
          file: originalFile,
          webBytes: null,
          displayName: p.basename(originalFile.path),
          isValid: true,
          qrData: null,
          qrStatus: QRProcessingStatus.completed,
        );

        setState(() {
          _capturedDocuments.add(newDoc);
        });
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
      _currentProcessingMessage = 'Processing $displayName...';
      _updateBusyState();
    });

    try {
      final isPdf = p.extension(displayName).toLowerCase() == '.pdf';

      if (isPdf) {
        // Server-side split on Web via bytes
        final parts = await _splitPdfViaApiBytes(bytes, filename: displayName);
        if (parts.isNotEmpty) {
          setState(() {
            _currentProcessingMessage =
                'Adding ${parts.length} split documents...';
          });
          for (int i = 0; i < parts.length; i++) {
            final part = parts[i];
            final name =
                (part.invoiceNo != null && part.invoiceNo!.isNotEmpty)
                    ? 'Invoice_${part.invoiceNo}.pdf'
                    : '${p.basenameWithoutExtension(displayName)}_part${i + 1}.pdf';

            final newDoc = DocumentInfo(
              file: null,
              webBytes: part.bytes,
              displayName: name,
              isValid: true,
              qrData: null,
              qrStatus: QRProcessingStatus.completed,
            );

            setState(() {
              _capturedDocuments.add(newDoc);
            });
          }
        } else {
          final newDoc = DocumentInfo(
            file: null,
            webBytes: bytes,
            displayName: displayName,
            isValid: true,
            qrData: null,
            qrStatus: QRProcessingStatus.completed,
          );
          setState(() {
            _capturedDocuments.add(newDoc);
          });
        }
      } else {
        // Non-PDF (rare for this button), just add as-is (you may choose to convert later)
        final newDoc = DocumentInfo(
          file: null,
          webBytes: bytes,
          displayName: displayName,
          isValid: true,
          qrData: null,
          qrStatus: QRProcessingStatus.completed,
        );
        setState(() {
          _capturedDocuments.add(newDoc);
        });
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

    final validDocs = _capturedDocuments.where((d) => d.isValid).toList();
    if (validDocs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid documents to upload')),
      );
      return;
    }

    if (_selectedStockist == null || _selectedChemist == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select Stockist & Hospital for POD.')),
      );
      return;
    }

    final stockistIdStr = _selectedStockist!.id.trim();
    final hospitalIdStr = _selectedChemist!.id.trim();

    if (stockistIdStr.isEmpty || hospitalIdStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stockist or Hospital ID is empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final stockistId = int.tryParse(stockistIdStr);
    final hospitalId = int.tryParse(hospitalIdStr);

    if (stockistId == null || stockistId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid stockist ID: "$stockistIdStr"'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (hospitalId == null || hospitalId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid hospital ID: "$hospitalIdStr"'),
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sending data to server...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final uri = Uri.parse(Multi_Api_POD_UPLOAD_URL);
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
      // Collect unique original raw files
      final Set<String> rawFilePaths = {};
      for (final d in validDocs) {
        if (d.originalRawFile != null && await d.originalRawFile!.exists()) {
          rawFilePaths.add(d.originalRawFile!.path);
        }
      }
      
      // Attach each unique raw file with key 'raw_file'
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

      final phpStyleJson = _buildPhpStyleJson(validDocs);
      req.fields['file_einvoice_sequence'] = phpStyleJson;
      req.fields['doc_type'] = 'POD';
      req.fields['document_count'] = validDocs.length.toString();
      req.fields['multi_page'] = (validDocs.length > 1).toString();
      req.fields['ocr_enhanced'] = 'true';
      req.fields['dpi'] = '300';

      if (_selectedStockist != null) {
        final stockistId = int.parse(_selectedStockist!.id.trim());
        req.fields['stockist_id'] = stockistId.toString();
        req.fields['stockistId'] = stockistId.toString();
      }
      if (_selectedChemist != null) {
        final hospitalId = int.parse(_selectedChemist!.id.trim());
        req.fields['hospital_id'] = hospitalId.toString();
        req.fields['hospitalId'] = hospitalId.toString();
      }

      final resp = await req.send();
      final responseBody = await resp.stream.bytesToString();

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
      } else if (resp.statusCode == 202) {
        try {
          final responseData = jsonDecode(responseBody);

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder:
                    (context) => UploadStatusScreen(
                      uploadData: responseData,
                      totalFiles: validDocs.length,
                    ),
              ),
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
      } else {
        debugPrint(
          'POD upload failed: ${resp.statusCode} ${responseBody.isNotEmpty ? "- $responseBody" : ""}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'POD upload failed: ${resp.statusCode} ${responseBody.isNotEmpty ? "- $responseBody" : ""}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
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
    final validDocCount = _capturedDocuments.where((d) => d.isValid).length;
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
                  _buildSectionCard(
                    icon: Icons.local_hospital,
                    title: 'Hospital',
                    subtitle: 'Select Hospital',
                    child: _customAutocomplete(
                      key: _chemistKey,
                      options: _allChemists,
                      selected: _selectedChemist,
                      label: 'Search Hospital',
                      onSelected:
                          (opt) => setState(() => _selectedChemist = opt),
                      onClear: () {
                        setState(() {
                          _selectedChemist = null;
                          _chemistKey = UniqueKey();
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Hospital selection cleared'),
                            duration: Duration(seconds: 1),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      },
                      isStockist: false,
                    ),
                  ),
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
                  if (_capturedDocuments.isNotEmpty)
                    _buildSectionCard(
                      icon: Icons.collections,
                      title:
                          'Uploaded Documents (${_capturedDocuments.length} total, $validDocCount valid)',
                      subtitle:
                          'Tap to preview, swipe to remove. Documents ready for upload.',
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
                                  'Valid',
                                  validDocCount,
                                  Colors.green,
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
                          const SizedBox(height: 12),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _capturedDocuments.length,
                            separatorBuilder:
                                (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final doc = _capturedDocuments[index];
                              return _buildDocumentCard(doc, index);
                            },
                          ),
                        ],
                      ),
                    ),
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
                            : 'Upload $validDocCount POD Documents',
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

    Color borderColor = doc.isValid ? Colors.green : Colors.red;
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
                ),
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
    if (doc.file != null && !kIsWeb) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfPreviewScreen(pdfFile: doc.file!),
        ),
      );
    } else if (doc.webBytes != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => PdfPreviewBytesScreen(
                pdfBytes: doc.webBytes!,
                title: doc.displayName,
              ),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No previewable content.')));
    }
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

  DocumentInfo({
    required this.file,
    required this.webBytes,
    required this.displayName,
    required this.isValid,
    this.qrData,
    this.qrStatus = QRProcessingStatus.notStarted,
    this.errorMessage,
    this.originalRawFile,
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
