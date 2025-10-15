// COMMENTED OUT: QR extraction functionality is disabled but imports are kept for easy restoration
// To restore QR functionality: uncomment all QR-related code and remove this comment block

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math; // COMMENTED OUT: Used for QR processing
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zyduspod/config.dart';
import 'package:zyduspod/GstInvoiceScanner.dart'; // COMMENTED OUT: Used for QR processing
import 'package:zyduspod/Models/_SplitOut.dart';
import 'package:zyduspod/services/PythonQRService.dart'; // COMMENTED OUT: Used for QR processing
import 'package:zyduspod/widgets/EInvoiceQRExtractor.dart'; // COMMENTED OUT: Used for QR processing
import 'package:zyduspod/widgets/PdfPreviewScreen.dart';
import 'package:zyduspod/widgets/modern_ui_components.dart';
import 'package:zyduspod/screens/upload_status_screen.dart';

// PDF Splitting API
const String _SPLIT_API_BASE = 'https://anujakkulkarni-splitpdffile.hf.space';

Future<List<SplitOut>> _splitPdfViaApi(File pdfFile) async {
  try {
    final uri = Uri.parse('$_SPLIT_API_BASE/split-invoices');

    final req = http.MultipartRequest('POST', uri)
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

      final fileName = 'split_${i + 1}_${p.basenameWithoutExtension(pdfFile.path)}.pdf';
      final file = File(p.join(tmp.path, fileName));
      await file.writeAsBytes(bytes);

      final invoiceNo = e['invoice_no'] as String?;
      final pages = e['pages'] as List<int>?;
      final sizeBytes = bytes.length;

      out.add(SplitOut(
        file: file,
        invoiceNo: invoiceNo,
        pages: pages,
        sizeBytes: sizeBytes,
      ));
    }

    return out;
  } catch (e) {
    debugPrint('[SPLIT] Error: $e');
    return <SplitOut>[];
  }
}

class PODUploadScreen extends StatefulWidget {
  const PODUploadScreen({super.key});

  @override
  State<PODUploadScreen> createState() => _PODUploadScreenState();
}

class _PODUploadScreenState extends State<PODUploadScreen> {
  // Loading states
  bool _isLoadingLists = false;
  // bool _isProcessingImage = false; // COMMENTED OUT: QR processing disabled
  bool _isUploading = false;
  bool _isRefreshing = false;
  // int _processingCount = 0; // COMMENTED OUT: QR processing disabled
  bool _isBusy = false;
  bool _isProcessingDocuments = false; // NEW: For document processing and splitting
  String _currentProcessingMessage = ''; // NEW: Current processing message

  // Selection data
  List<_SelectItem> _allStockists = [];
  List<_SelectItem> _allChemists = [];
  _SelectItem? _selectedStockist;
  
  // Search functionality
  Timer? _stockistSearchTimer;
  Timer? _hospitalSearchTimer;
  bool _isSearchingStockists = false;
  bool _isSearchingHospitals = false;
  _SelectItem? _selectedChemist;

  // Documents
  List<DocumentInfo> _capturedDocuments = [];

  // Keys for Autocomplete
  Key _stockistKey = UniqueKey();
  Key _chemistKey = UniqueKey();

  final ImagePicker _imagePicker = ImagePicker();
  final ScrollController _scrollController = ScrollController();
  final int maxDocuments = 25;

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
      // COMMENTED OUT: QR processing disabled - _isProcessingImage and _processingCount removed
      _isBusy = _isUploading || _isLoadingLists || _isRefreshing || _isProcessingDocuments;
      // Original: _isBusy = _isUploading || _isLoadingLists || _isProcessingImage || _processingCount > 0 || _isRefreshing;
    });
  }

  Future<void> _onRefresh() async {
    if (_isBusy) return;
    
    setState(() {
      _isRefreshing = true;
      _updateBusyState();
    });

    try {
      // Clear current selections
      setState(() {
        _selectedStockist = null;
        _selectedChemist = null;
        _stockistKey = UniqueKey();
        _chemistKey = UniqueKey();
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
      print('Failed to load lists: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load lists: $e')),
      );
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
      
      debugPrint('=== Stockist Search Results for "$query" ===');
      debugPrint('Found ${rawList.length} items');
      debugPrint('=============================');
      
      final items = rawList
          .map((e) => _SelectItem.fromDynamic(e))
          .where((e) => e != null)
          .cast<_SelectItem>()
          .toList();
      
      return items;
    } catch (e) {
      debugPrint('Stockist search error: $e');
      return _allStockists.where((item) => 
        item.label.toLowerCase().contains(query.toLowerCase())
      ).take(50).toList();
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
      
      debugPrint('=== Hospital Search Results for "$query" ===');
      debugPrint('Found ${rawList.length} items');
      debugPrint('=============================');
      
      final items = rawList
          .map((e) => _SelectItem.fromDynamic(e))
          .where((e) => e != null)
          .cast<_SelectItem>()
          .toList();
      
      return items;
    } catch (e) {
      debugPrint('Hospital search error: $e');
      return _allChemists.where((item) => 
        item.label.toLowerCase().contains(query.toLowerCase())
      ).take(50).toList();
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
    
    // Debug the API response
    debugPrint('=== API Response for $url ===');
    debugPrint('Raw response: ${resp.body}');
    debugPrint('Decoded: $decoded');
    debugPrint('Raw list length: ${rawList.length}');
    if (rawList.isNotEmpty) {
      debugPrint('First item: ${rawList.first}');
    }
    debugPrint('=============================');
    
    final items = rawList
        .map((e) => _SelectItem.fromDynamic(e))
        .where((e) => e != null)
        .cast<_SelectItem>()
        .toList();
    
    debugPrint('Parsed items length: ${items.length}');
    if (items.isNotEmpty) {
      debugPrint('First parsed item: id=${items.first.id}, label=${items.first.label}');
    }
    
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
      builder: (context) => AlertDialog(
        title: const Text('Add Documents'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _captureFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickFromGallery();
              },
            ),
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

      final scanned = await FlutterDocScanner().getScanDocuments(page: 1);
      List<String> result = [];
      if (scanned != null && scanned is Map) {
        String? filePath = scanned['pdfUri']?.toString() ?? 
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scanner error: $e')),
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
      _currentProcessingMessage = 'Selecting from gallery...';
      _updateBusyState();
    });
    
    try {
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gallery error: $e')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pick PDF error: $e')),
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

  Future<void> _processAndAddDocument(File originalFile, {required bool isFromScanner}) async {
    setState(() {
      _isProcessingDocuments = true;
      _currentProcessingMessage = 'Processing ${p.basename(originalFile.path)}...';
      _updateBusyState();
    });

    try {
      final displayNameBase = p.basenameWithoutExtension(originalFile.path);
      final extension = p.extension(originalFile.path).toLowerCase();
      
      // Check if it's a PDF file for splitting
      if (extension == '.pdf') {
        // Update processing message for splitting
        setState(() {
          _currentProcessingMessage = 'Splitting ${p.basename(originalFile.path)} into invoices...';
        });

        final splitParts = await _splitPdfViaApi(originalFile);

        if (splitParts.isNotEmpty) {
          // Update processing message for adding split parts
          setState(() {
            _currentProcessingMessage = 'Adding ${splitParts.length} split documents...';
          });

          for (int i = 0; i < splitParts.length; i++) {
            final part = splitParts[i];
            final displayName = (part.invoiceNo != null && part.invoiceNo!.isNotEmpty)
                ? 'Invoice_${part.invoiceNo}.pdf'
                : '${displayNameBase}_part${i + 1}.pdf';
            
            final newDoc = DocumentInfo(
              file: part.file,
              displayName: displayName,
              isValid: true,
              qrData: null,
              qrStatus: QRProcessingStatus.completed, // Skip QR extraction - mark as completed
            );
            
            setState(() {
              _capturedDocuments.add(newDoc);
            });
            
            // COMMENTED OUT: QR extraction disabled - directly proceed to upload ready state
            // Original: _enqueueExtraction(newDoc, idx); // This would trigger QR processing
          }
        } else {
          // Fallback to original single PDF
          final newDoc = DocumentInfo(
            file: originalFile,
            displayName: '${displayNameBase}.pdf',
            isValid: true,
            qrData: null,
            qrStatus: QRProcessingStatus.completed, // Skip QR extraction - mark as completed
          );
          
          setState(() {
            _capturedDocuments.add(newDoc);
          });
          
          // COMMENTED OUT: QR extraction disabled - directly proceed to upload ready state
          // Original: _enqueueExtraction(newDoc, idx); // This would trigger QR processing
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('No splits returned. Using original ${p.basename(originalFile.path)}.'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        // For non-PDF files, process directly
        setState(() {
          _currentProcessingMessage = 'Adding ${p.basename(originalFile.path)}...';
        });

        final newDoc = DocumentInfo(
          file: originalFile,
          displayName: p.basename(originalFile.path),
          isValid: true,
          qrData: null,
          qrStatus: QRProcessingStatus.completed, // Skip QR extraction - mark as completed
        );
        
        setState(() {
          _capturedDocuments.add(newDoc);
        });
        
        // COMMENTED OUT: QR extraction disabled - directly proceed to upload ready state
        // Original: _enqueueExtraction(newDoc, idx); // This would trigger QR processing
      }
      
      _scheduleScrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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

  /// ===================== QR EXTRACTION (COMMENTED OUT) =====================
  // COMMENTED OUT: QR extraction disabled - can be restored by uncommenting

  /*
  void _enqueueExtraction(DocumentInfo doc, int index) {
    _incProcessing();
    _autoExtractQRFromDocument(doc, index);
  }

  void _incProcessing() {
    setState(() {
      _processingCount++;
      _updateBusyState();
    });
  }

  void _decProcessing() {
    setState(() {
      _processingCount = math.max(0, _processingCount - 1);
      _updateBusyState();
    });
  }

  Future<void> _autoExtractQRFromDocument(DocumentInfo doc, int index) async {
    try {
      // Update status to processing
      if (mounted) {
        setState(() {
          if (index < _capturedDocuments.length) {
            _capturedDocuments[index] = doc.copyWith(
              qrStatus: QRProcessingStatus.processing,
            );
          }
        });
      }
      
      final qrMap = await _ensureQrForDocument(doc);
      if (!mounted) return;
      
      setState(() {
        if (index < _capturedDocuments.length) {
          _capturedDocuments[index] = doc.copyWith(
            qrData: qrMap,
            qrStatus: qrMap != null ? QRProcessingStatus.completed : QRProcessingStatus.failed,
            errorMessage: qrMap == null ? 'No QR code found' : null,
          );
        }
      });
    } catch (e) {
      print('QR extraction failed for ${doc.displayName}: $e');
      if (mounted) {
        setState(() {
          if (index < _capturedDocuments.length) {
            _capturedDocuments[index] = doc.copyWith(
              qrStatus: QRProcessingStatus.failed,
              errorMessage: e.toString(),
            );
          }
        });
      }
    } finally {
      _decProcessing();
      setState(() {
        _isProcessingImage = false;
        _updateBusyState();
      });
    }
  }

  Future<Map<String, dynamic>?> _ensureQrForDocument(DocumentInfo doc) async {
    try {
      // Try Hugging Face API first
      final qrMap = await PythonQRService.extractQRFromPDF(doc.file);
      if (qrMap != null) {
        return qrMap;
      }
      
      // Fallback to Flutter QR extraction
      final qrData = await EInvoiceQRExtractor.extractQRFromPDF(doc.file);
      if (qrData != null) {
        return qrData;
      }
      
      return null;
    } catch (e) {
      print('QR extraction error: $e');
      return null;
    }
  }
  */

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

    // Validate selections
    if (_selectedStockist == null || _selectedChemist == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select Stockist & Hospital for POD.')),
      );
      return;
    }

    // Validate that both IDs are valid integers
    final stockistIdStr = _selectedStockist!.id.trim();
    final hospitalIdStr = _selectedChemist!.id.trim();
    
    if (stockistIdStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stockist ID is empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (hospitalIdStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hospital ID is empty'),
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
      // COMMENTED OUT: QR processing disabled - directly proceed to upload
      // Original: Show progress for QR processing, then await _processAllQRCodes(validDocs);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Uploading documents to server...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

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
        final filename = p.basename(d.file.path);
        final contentType = _inferContentType(d.file);
        req.files.add(
          await http.MultipartFile.fromPath(
            'files[]',
            d.file.path,
            filename: filename,
            contentType: contentType,
          ),
        );
      }

      // Add headers
      if (token != null) {
        req.headers['Authorization'] = 'Bearer $token';
      }

      // Add form fields
      final phpStyleJson = _buildPhpStyleJson(validDocs);
      req.fields['file_einvoice_sequence'] = phpStyleJson;
      req.fields['doc_type'] = 'POD';
      req.fields['document_count'] = validDocs.length.toString();
      req.fields['multi_page'] = (validDocs.length > 1).toString();
      req.fields['ocr_enhanced'] = 'true';
      req.fields['dpi'] = '300';
      
      // Debug all fields being sent
      debugPrint('=== Upload Fields ===');
      req.fields.forEach((key, value) {
        debugPrint('$key: $value (${value.runtimeType})');
      });
      debugPrint('===================');
      debugPrint('stockist: ${_selectedStockist?.id} (${_selectedStockist?.id.runtimeType})');
      debugPrint('hospital: ${_selectedChemist?.id} (${_selectedChemist?.id.runtimeType})');
      if (_selectedStockist != null) {
        // Use the already validated and trimmed ID
        final stockistId = int.parse(_selectedStockist!.id.trim());
        req.fields['stockist_id'] = stockistId.toString();
        req.fields['stockistId'] = stockistId.toString();
        debugPrint('stockist_id (converted): $stockistId');
      }
      if (_selectedChemist != null) {
        // Use the already validated and trimmed ID
        final hospitalId = int.parse(_selectedChemist!.id.trim());
        req.fields['hospital_id'] = hospitalId.toString();
        req.fields['hospitalId'] = hospitalId.toString();
        debugPrint('hospital_id (converted): $hospitalId');
      }

      final resp = await req.send();
      final responseBody = await resp.stream.bytesToString();

      if (resp.statusCode == 201) {
        // Status 201: Data generated immediately
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

        // Clear documents after successful upload
        setState(() {
          _capturedDocuments.clear();
        });

        // Navigate back or show success
        if (mounted) {
          Navigator.pop(context);
        }
      } else if (resp.statusCode == 202) {
        // Status 202: Background processing initiated
        try {
          final responseData = jsonDecode(responseBody);
          
          if (mounted) {
            // Navigate to upload status screen
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => UploadStatusScreen(
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
                  '✅ Uploaded ${validDocs.length} POD document(s) successfully. Background processing initiated.',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
          
          // Clear documents after successful upload
          setState(() {
            _capturedDocuments.clear();
          });

          // Navigate back
          if (mounted) {
            Navigator.pop(context);
          }
        }
      } else {
        debugPrint('POD upload failed: ${resp.statusCode} ${responseBody.isNotEmpty ? "- $responseBody" : ""}');
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

  // COMMENTED OUT: QR processing method - can be restored by uncommenting
  /*
  Future<void> _processAllQRCodes(List<DocumentInfo> docs) async {
    // Process QR codes for all documents
    for (int i = 0; i < docs.length; i++) {
      final doc = docs[i];
      if (doc.qrData == null) {
        final qrData = await _ensureQrForDocument(doc);
        if (qrData != null) {
          docs[i] = DocumentInfo(
            file: doc.file,
            displayName: doc.displayName,
            isValid: doc.isValid,
            qrData: qrData,
          );
        }
      }
    }
  }
  */

  MediaType _inferContentType(File file) {
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
      entries.add({
        'index': i,
        'filename': p.basename(doc.file.path),
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
      builder: (context) => AlertDialog(
        title: const Text('Clear All Documents'),
        content: Text('Are you sure you want to remove all ${_capturedDocuments.length} documents?'),
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
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// ===================== UI BUILD =====================

  @override
  Widget build(BuildContext context) {
    final validDocCount = _capturedDocuments.where((d) => d.isValid).length;
    // final docsWithQR = _capturedDocuments.where((d) => d.qrData != null).length; // COMMENTED OUT: QR processing disabled
    final showTopLoader = _isLoadingLists || _isProcessingDocuments; // UPDATED: Include document processing
    // Original: _isLoadingLists || _isProcessingImage || _processingCount > 0

    return Scaffold(
      appBar: ModernUIComponents.buildModernAppBar(
        title: 'POD Upload',
        subtitle: 'Upload Proof of Delivery documents',
        icon: Icons.description,
        color: const Color(0xFF00A0A8),
        // actions: [
        //   if (_capturedDocuments.isNotEmpty) ...[
        //     // Valid documents counter
        //     Center(
        //       child: Padding(
        //         padding: const EdgeInsets.symmetric(horizontal: 4),
        //         child: Chip(
        //           label: Text('Valid: $validDocCount'),
        //           backgroundColor: _capturedDocuments.length >= maxDocuments
        //               ? Colors.orange.shade100
        //               : Colors.green.shade100,
        //           labelStyle: TextStyle(
        //             color: _capturedDocuments.length >= maxDocuments
        //                 ? Colors.orange.shade800
        //                 : Colors.green.shade800,
        //             fontWeight: FontWeight.bold,
        //             fontSize: 11,
        //           ),
        //         ),
        //       ),
        //     ),
        //     // QR processed counter
        //     Center(
        //       child: Padding(
        //         padding: const EdgeInsets.symmetric(horizontal: 4),
        //         child: Chip(
        //           avatar: const Icon(Icons.qr_code, size: 14),
        //           label: Text('QR: $docsWithQR'),
        //           backgroundColor: docsWithQR > 0 ? Colors.green.shade100 : Colors.grey.shade100,
        //           labelStyle: TextStyle(
        //             color: docsWithQR > 0 ? Colors.green.shade800 : Colors.grey.shade800,
        //             fontWeight: FontWeight.bold,
        //             fontSize: 11,
        //           ),
        //         ),
        //       ),
        //     ),
        //   ],
        // ],
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
                                    : 'Loading lists...', // UPDATED: Show current processing message
                            // Original: (_processingCount > 0 || _isProcessingImage) ? 'Processing documents...' : 'Loading lists...'
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
                      onSelected: (opt) => setState(() => _selectedStockist = opt),
                      onClear: () => setState(() => _selectedStockist = null),
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
                      onSelected: (opt) => setState(() => _selectedChemist = opt),
                      onClear: () => setState(() => _selectedChemist = null),
                      isStockist: false,
                    ),
                  ),
                  _buildSectionCard(
                    icon: Icons.add_a_photo,
                    title: 'Add Documents',
                    subtitle: 'Images converted to PDF. POD documents ready for upload.', // COMMENTED OUT: QR extraction disabled
                    // Original: 'Images converted to PDF. POD documents auto-extract QR.'
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
                        const SizedBox(height: 8),
                        Text(
                          'Maximum $maxDocuments documents allowed',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  if (_capturedDocuments.isNotEmpty)
                    _buildSectionCard(
                      icon: Icons.collections,
                      title: 'Uploaded Documents (${_capturedDocuments.length} total, $validDocCount valid)', // COMMENTED OUT: QR count removed
                      // Original: 'Uploaded Documents (${_capturedDocuments.length} total, $validDocCount valid, $docsWithQR with QR)'
                      subtitle: 'Tap to preview, swipe to remove. Documents ready for upload.', // COMMENTED OUT: QR status removed
                      // Original: 'Tap to preview, swipe to remove. Green = QR extracted, Yellow = Processing, Red = Failed.'
                      child: Column(
                        children: [
                          // Summary stats
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
                                _buildStatItem('Total', _capturedDocuments.length, Colors.blue),
                                _buildStatItem('Valid', validDocCount, Colors.green),
                                // COMMENTED OUT: QR processed stat removed
                                // _buildStatItem('QR Processed', docsWithQR, Colors.orange),
                                _buildStatItem('Remaining', maxDocuments - _capturedDocuments.length, Colors.grey),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Clear all button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isBusy ? null : _showClearAllDialog,
                              icon: const Icon(Icons.clear_all, size: 18),
                              label: const Text('Clear All Documents'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade600,
                                side: BorderSide(color: Colors.red.shade300),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Document list
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _capturedDocuments.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
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
                      icon: _isBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: Text(
                        _isBusy
                            ? (_isUploading
                                ? 'Uploading...'
                                : _isProcessingDocuments
                                    ? 'Processing Documents...'
                                    : 'Loading...') // UPDATED: Show document processing status
                            // Original: (_isProcessingImage || _processingCount > 0) ? 'Processing QR Codes...' : (_isUploading ? 'Uploading...' : 'Loading...')
                            : 'Upload $validDocCount POD Documents',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isBusy ? Colors.grey : const Color(0xFF00A0A8),
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
        
        // If text is empty, show first 50 items from loaded list
        if (text.isEmpty) {
          return options.take(50);
        }
        
        // If less than 3 characters, filter locally
        if (text.length < 3) {
          return options.where((o) => o.label.toLowerCase().contains(text.toLowerCase())).take(50);
        }
        
        // For 3+ characters, search via API with debouncing
        if (isStockist) {
          _stockistSearchTimer?.cancel();
        } else {
          _hospitalSearchTimer?.cancel();
        }
        
        // Return current options while waiting for search
        return options.where((o) => o.label.toLowerCase().contains(text.toLowerCase())).take(50);
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
                  ),
              ],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF00A0A8)),
            ),
          ),
          onFieldSubmitted: (value) => onFieldSubmitted(),
          readOnly: selected != null, // Make read-only when selected to show name
          onChanged: (value) {
            // Trigger search when user types
            if (value.length >= 3) {
              if (isStockist) {
                _stockistSearchTimer?.cancel();
                _stockistSearchTimer = Timer(const Duration(milliseconds: 300), () async {
                  final results = await _searchStockists(value);
                  if (mounted) {
                    setState(() {
                      _allStockists = results;
                    });
                  }
                });
              } else {
                _hospitalSearchTimer?.cancel();
                _hospitalSearchTimer = Timer(const Duration(milliseconds: 300), () async {
                  final results = await _searchHospitals(value);
                  if (mounted) {
                    setState(() {
                      _allChemists = results;
                    });
                  }
                });
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
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentCard(DocumentInfo doc, int index) {
    final fileSize = _getFileSize(doc.file);
    
    // COMMENTED OUT: QR status-based border colors - now using simple validity-based colors
    // Original: Complex border colors based on QR processing status (green=completed, orange=processing, red=failed)
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
        child: const Icon(
          Icons.delete,
          color: Colors.red,
          size: 24,
        ),
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
          side: BorderSide(
            color: borderColor,
            width: borderWidth,
          ),
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
                    Icon(
                      Icons.description,
                      color: borderColor,
                      size: 20,
                    ),
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
                    // COMMENTED OUT: QR status indicator removed
                    // _buildQRStatusIndicator(doc, index),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _removeDocument(index),
                      icon: const Icon(Icons.close, size: 18),
                      color: Colors.red.shade600,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
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
                // COMMENTED OUT: QR info section removed
                // if (hasQR && doc.qrData != null) ...[
                //   const SizedBox(height: 8),
                //   _buildQRInfo(doc.qrData!),
                // ],
                // if (doc.qrStatus == QRProcessingStatus.failed && doc.errorMessage != null) ...[
                //   const SizedBox(height: 8),
                //   Container(...), // Error message container
                // ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // COMMENTED OUT: QR-related UI methods - can be restored by uncommenting
  /*
  Widget _buildQRStatusIndicator(DocumentInfo doc, int index) {
    switch (doc.qrStatus) {
      case QRProcessingStatus.completed:
        return GestureDetector(
          onTap: () => _openGSTEinvoicePage(doc),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.qr_code,
                  size: 12,
                  color: Colors.green.shade700,
                ),
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
        );
      case QRProcessingStatus.processing:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange.shade700),
                ),
              ),
              const SizedBox(width: 2),
              Text(
                'QR',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ),
        );
      case QRProcessingStatus.failed:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error,
                size: 12,
                color: Colors.red.shade700,
              ),
              const SizedBox(width: 2),
              Text(
                'QR',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
        );
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.qr_code,
                size: 12,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 2),
              Text(
                'QR',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        );
    }
  }

  void _openGSTEinvoicePage(DocumentInfo doc) {
    if (doc.qrData == null) return;
    
    // Navigate to GST E-invoice page with QR data using existing InvoiceResultScreen
    _openInvoiceDetails(doc.qrData!);
  }

  Future<void> _openInvoiceDetails(Map<String, dynamic> data) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InvoiceResultScreen(
          invoiceData: data,
          podId: '0', // POD ID not needed for display purposes
        ),
      ),
    );
  }

  Widget _buildQRInfo(Map<String, dynamic> qrData) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.qr_code_scanner,
                size: 14,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                'QR Code Data',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (qrData['DocNo'] != null)
            _buildQRField('Invoice No', qrData['DocNo'].toString()),
          if (qrData['DocDt'] != null)
            _buildQRField('Invoice Date', qrData['DocDt'].toString()),
          if (qrData['Irn'] != null)
            _buildQRField('IRN', qrData['Irn'].toString()),
          if (qrData['TotInvVal'] != null)
            _buildQRField('Total Value', qrData['TotInvVal'].toString()),
          if (qrData['BuyerName'] != null)
            _buildQRField('Buyer', qrData['BuyerName'].toString()),
          if (qrData['SellerName'] != null)
            _buildQRField('Seller', qrData['SellerName'].toString()),
        ],
      ),
    );
  }

  Widget _buildQRField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
  */

  String _getFileSize(File file) {
    try {
      final bytes = file.lengthSync();
      if (bytes < 1024) return '${bytes}B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<bool> _showRemoveDialog(String fileName) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Document'),
        content: Text('Are you sure you want to remove "$fileName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;
  }

  void _previewDocument(DocumentInfo doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfPreviewScreen(
          pdfFile: doc.file,
        ),
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

enum QRProcessingStatus {
  notStarted,
  processing,
  completed,
  failed,
}

class DocumentInfo {
  final File file;
  final String displayName;
  final bool isValid;
  final Map<String, dynamic>? qrData;
  final QRProcessingStatus qrStatus;
  final String? errorMessage;

  DocumentInfo({
    required this.file,
    required this.displayName,
    required this.isValid,
    this.qrData,
    this.qrStatus = QRProcessingStatus.notStarted,
    this.errorMessage,
  });

  DocumentInfo copyWith({
    File? file,
    String? displayName,
    bool? isValid,
    Map<String, dynamic>? qrData,
    QRProcessingStatus? qrStatus,
    String? errorMessage,
  }) {
    return DocumentInfo(
      file: file ?? this.file,
      displayName: displayName ?? this.displayName,
      isValid: isValid ?? this.isValid,
      qrData: qrData ?? this.qrData,
      qrStatus: qrStatus ?? this.qrStatus,
      errorMessage: errorMessage ?? this.errorMessage,
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
      // Handle both string and integer IDs
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
