import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_filex/open_filex.dart';
import 'package:image/image.dart' as img;
import 'package:zyduspod/GstInvoiceScanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zyduspod/config.dart';
import 'package:zyduspod/Models/pod.dart';

import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zyduspod/widgets/PdfPreviewScreen.dart';

// Runs in a background isolate via `compute` to compress an image under maxBytes
Uint8List _compressImageWorker(Map<String, dynamic> args) {
  final Uint8List data = args['data'] as Uint8List;
  final int maxBytes = args['maxBytes'] as int;

  if (data.lengthInBytes <= maxBytes) return data;

  final img.Image? decoded = img.decodeImage(data);
  if (decoded == null) return data;

  int quality = 85;
  img.Image current = decoded;
  const int minSideFloor = 700;
  int iterations = 0;

  while (iterations < 14) {
    iterations++;
    final List<int> encoded = img.encodeJpg(current, quality: quality);
    if (encoded.length <= maxBytes) {
      return Uint8List.fromList(encoded);
    }

    if (quality > 50) {
      quality -= 10;
      continue;
    }

    final int nextWidth = (current.width * 0.85).round();
    final int nextHeight = (current.height * 0.85).round();
    if (nextWidth < minSideFloor && nextHeight < minSideFloor) {
      quality = 40;
      current = img.copyResize(
        current,
        width: current.width > current.height ? minSideFloor : null,
        height: current.height >= current.width ? minSideFloor : null,
        interpolation: img.Interpolation.cubic,
      );
    } else {
      current = img.copyResize(
        current,
        width: nextWidth,
        height: nextHeight,
        interpolation: img.Interpolation.cubic,
      );
    }
  }

  final List<int> fallback = img.encodeJpg(current, quality: 40);
  return Uint8List.fromList(fallback);
}

// Enhanced image processing worker for OCR - FIXED VERSION
Map<String, dynamic> _enhanceImageForOCRWorker(Map<String, dynamic> args) {
  final Uint8List imageBytes = args['imageBytes'] as Uint8List;

  try {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) {
      return {'success': false, 'bytes': imageBytes};
    }

    // Step 1: Resize to optimal OCR resolution (300 DPI equivalent)
    const int minWidth = 1200;
    const int minHeight = 1600;

    if (image.width < minWidth || image.height < minHeight) {
      final double scaleX = minWidth / image.width;
      final double scaleY = minHeight / image.height;
      final double scale = math.max(scaleX, scaleY);

      image = img.copyResize(
        image,
        width: (image.width * scale).round(),
        height: (image.height * scale).round(),
        interpolation: img.Interpolation.cubic,
      );
    }

    // Step 2: Convert to grayscale for better OCR
    image = img.grayscale(image);

    // Step 3: Enhance contrast and brightness
    image = img.adjustColor(image, contrast: 1.2, brightness: 1.1, gamma: 0.9);

    // Step 4: Apply sharpening filter
    image = img.convolution(
      image,
      filter: [-1, -1, -1, -1, 9, -1, -1, -1, -1],
      div: 1,
    );

    // Step 5: Reduce noise with slight blur - FIXED: Use int radius
    image = img.gaussianBlur(image, radius: 1); // Changed from 0.5 to 1

    // Step 6: Apply adaptive threshold for better text contrast - FIXED
    final int width = image.width;
    final int height = image.height;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final img.Pixel pixel = image.getPixel(x, y);
        final int gray = img.getLuminance(pixel).round(); // Convert to int

        // Simple threshold - make text more distinct - FIXED: Use img.ColorRgb8
        final img.ColorRgb8 newPixel = gray > 140
            ? img.ColorRgb8(255, 255, 255) // White
            : img.ColorRgb8(0, 0, 0); // Black
        image.setPixel(x, y, newPixel);
      }
    }

    // Step 7: Encode with high quality PNG for better OCR
    final List<int> enhancedBytes = img.encodePng(image, level: 1);

    return {
      'success': true,
      'bytes': Uint8List.fromList(enhancedBytes),
      'width': image.width,
      'height': image.height,
    };
  } catch (e) {
    return {'success': false, 'bytes': imageBytes, 'error': e.toString()};
  }
}

class DocumentUploadScreen extends StatefulWidget {
  const DocumentUploadScreen({super.key});

  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  bool _isUploading = false;
  bool _isLoadingLists = false;
  bool _isProcessingImage = false;

  String? _selectedDocType = 'POD';

  List<_SelectItem> _allStockists = [];
  List<_SelectItem> _allChemists = [];
  List<_SelectItem> _allPods = [];
  List<Pod> _pods = [];

  _SelectItem? _selectedStockist;
  _SelectItem? _selectedChemist;
  _SelectItem? _selectedPod;

  File? _capturedImageFile;
  Map<String, dynamic>? _einvoiceData;

  // Add keys to force rebuild of Autocomplete widgets
  Key _stockistKey = UniqueKey();
  Key _chemistKey = UniqueKey();
  Key _podKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  Future<void> _loadLists() async {
    setState(() => _isLoadingLists = true);
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
        _allPods = _pods
            .map(
              (p) =>
                  _SelectItem(id: p.id.toString(), label: _formatPodLabel(p)),
            )
            .toList();
      });
      print('Stockists loaded: ${_allStockists.length}');
      print('Chemists loaded: ${_allChemists.length}');
      print('Pods loaded: ${_allPods.length}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load lists: $e')));
    } finally {
      if (mounted) setState(() => _isLoadingLists = false);
    }
  }

  Future<List<_SelectItem>> _fetchSelectItems(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    final resp = await http.get(
      Uri.parse(url),
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final dynamic decoded = _safeDecode(resp.bodyBytes);
    final List<dynamic> rawList = _unwrapToList(decoded);
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
    final List<dynamic> list = decoded is Map && decoded['data'] is List
        ? (decoded['data'] as List)
        : (decoded is List ? decoded : <dynamic>[]);
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => Pod.fromJson(m))
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
    return 'POD ${pod.podNumber}  |  INV ${pod.invoiceNumber}  |  $podDt  |  $invDt';
  }

  List<dynamic> _unwrapToList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in ['data', 'items', 'results']) {
        final v = decoded[key];
        if (v is List) return v;
      }
    }
    return [];
  }

  // Enhanced image processing for OCR
  Future<File> _enhanceImageForOCR(File originalFile) async {
    try {
      setState(() => _isProcessingImage = true);

      final Uint8List originalBytes = await originalFile.readAsBytes();

      print("🔍 Enhancing image for OCR...");

      // Use compute to run enhancement in background
      final Map<String, dynamic> result = await compute(
        _enhanceImageForOCRWorker,
        {'imageBytes': originalBytes},
      );

      if (result['success'] == true) {
        final Uint8List enhancedBytes = result['bytes'] as Uint8List;

        // Save enhanced image
        final tempDir = await getTemporaryDirectory();
        final enhancedPath =
            '${tempDir.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.png';
        final enhancedFile = File(enhancedPath);
        await enhancedFile.writeAsBytes(enhancedBytes);

        print(
          "✅ Image enhanced successfully: ${result['width']}x${result['height']}",
        );
        return enhancedFile;
      } else {
        print(
          "⚠️ Image enhancement failed: ${result['error'] ?? 'Unknown error'}",
        );
        return originalFile;
      }
    } catch (e) {
      print('❌ Error enhancing image for OCR: $e');
      return originalFile;
    } finally {
      if (mounted) setState(() => _isProcessingImage = false);
    }
  }

  // Convert enhanced image to high-quality PDF
  Future<File> _convertImageToPDF(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final pdfDoc = pw.Document();

      final pwImage = pw.MemoryImage(bytes);

      pdfDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(0), // No margin for full page
          build: (ctx) => pw.Center(
            child: pw.Image(
              pwImage,
              fit: pw.BoxFit.contain,
              dpi: 300, // High DPI for better OCR
            ),
          ),
        ),
      );

      final pdfBytes = await pdfDoc.save();

      final tempDir = await getTemporaryDirectory();
      final pdfPath =
          '${tempDir.path}/ocr_ready_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final pdfFile = File(pdfPath);
      await pdfFile.writeAsBytes(pdfBytes);

      return pdfFile;
    } catch (e) {
      print('Error converting to PDF: $e');
      return imageFile;
    }
  }

  Future<void> _takePhoto() async {
    try {
      setState(() => _isProcessingImage = true);

      // Configure scanner for better OCR results
      final scannedDocs = await FlutterDocScanner().getScanDocuments(page: 1);

      print("📄 Raw scannedDocs: $scannedDocs");

      if (scannedDocs != null && scannedDocs is Map) {
        String? filePath;

        // Check for different possible keys
        final pdfUri = scannedDocs['pdfUri']?.toString();
        final imageUri = scannedDocs['imageUri']?.toString();
        final docUri = scannedDocs['documentUri']?.toString();

        filePath = pdfUri ?? imageUri ?? docUri;

        if (filePath != null && filePath.isNotEmpty) {
          final path = filePath.replaceFirst("file://", "");
          final original = File(path);

          if (await original.exists()) {
            File processedFile;

            // If it's an image, enhance it for OCR
            if (path.toLowerCase().endsWith('.jpg') ||
                path.toLowerCase().endsWith('.jpeg') ||
                path.toLowerCase().endsWith('.png')) {
              print("🔍 Processing image for better OCR...");

              // Enhance image for OCR
              final enhancedImage = await _enhanceImageForOCR(original);

              // Convert enhanced image to PDF
              processedFile = await _convertImageToPDF(enhancedImage);

              // Clean up temporary enhanced image
              if (enhancedImage.path != original.path) {
                try {
                  await enhancedImage.delete();
                } catch (e) {
                  print("Warning: Could not delete temporary file: $e");
                }
              }
            } else {
              // If it's already a PDF, use as is
              processedFile = original;
            }

            final tempDir = await getTemporaryDirectory();
            final savedPath =
                "${tempDir.path}/scanned_${DateTime.now().millisecondsSinceEpoch}.pdf";
            final savedFile = await processedFile.copy(savedPath);

            if (!mounted) return;
            setState(() {
              _capturedImageFile = savedFile;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("✅ Document processed for OCR!")),
            );
          }
        }
      }
    } catch (e) {
      print("❌ Scanner error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error while scanning: $e")));
    } finally {
      if (mounted) setState(() => _isProcessingImage = false);
    }
  }

  Future<bool> _checkPermissions() async {
    // Request camera & storage permissions
    final statuses = await [Permission.camera, Permission.storage].request();

    // On Android 11+ scoped storage, sometimes only MANAGE_EXTERNAL_STORAGE works
    final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
    final storageGranted = statuses[Permission.storage]?.isGranted ?? false;

    if (!cameraGranted || !storageGranted) {
      openAppSettings(); // Ask user to enable manually if denied permanently
      return false;
    }

    return true;
  }

  Future<bool> _confirmPhoto(File file) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Use this photo?'),
            content: SizedBox(
              width: double.maxFinite,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(file, fit: BoxFit.contain),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Retake'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Use Photo'),
              ),
            ],
          ),
        ) ??
        false;
  }

  MediaType _inferContentType(File file) {
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.pdf') return MediaType('application', 'pdf');
    if (ext == '.png') return MediaType('image', 'png');
    if (ext == '.heic' || ext == '.heif') return MediaType('image', 'heic');
    return MediaType('image', 'jpeg');
  }

  bool _isPodDoc() => (_selectedDocType ?? '') == 'POD';
  bool _isEinvoiceDoc() =>
      (_selectedDocType ?? '') == 'EINVOICE' ||
      (_selectedDocType ?? '') == 'E-INVOICE';

  Future<File> _ensureImageUnderLimit(
    File original, {
    int maxBytes = 4 * 1024 * 1024,
  }) async {
    final Uint8List data = await original.readAsBytes();
    if (data.lengthInBytes <= maxBytes) return original;

    final Uint8List encoded = await compute(_compressImageWorker, {
      'data': data,
      'maxBytes': maxBytes,
    });

    final tmpDir = await getTemporaryDirectory();
    final outPath = p.join(
      tmpDir.path,
      'compressed_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final out = File(outPath);
    await out.writeAsBytes(encoded, flush: true);
    return out;
  }

  Future<void> _uploadCaptured() async {
    if (_isUploading) return;
    if (_capturedImageFile == null || _selectedDocType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a photo and select document type.'),
        ),
      );
      return;
    }

    if (_isPodDoc()) {
      if (_selectedStockist == null || _selectedChemist == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select Stockist and Hospital for POD.'),
          ),
        );
        return;
      }
    } else {
      if (_selectedPod == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please select a POD to upload GRN/E-Invoice against.',
            ),
          ),
        );
        return;
      }
    }

    setState(() => _isUploading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      // The file is already enhanced for OCR in _takePhoto
      final File documentFile = _capturedImageFile!;

      // Determine content type
      final MediaType contentType = _inferContentType(documentFile);

      final bool isPod = _isPodDoc();
      final uri = Uri.parse(isPod ? API_POD_UPLOAD_URL : API_DOC_UPLOAD_URL);
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            documentFile.path,
            filename: p.basename(documentFile.path),
            contentType: contentType,
          ),
        );

      // Add OCR-ready flags to help backend
      request.fields['ocr_enhanced'] = 'true';
      request.fields['document_quality'] = 'high';
      request.fields['dpi'] = '300';
      request.fields['processed_for_ocr'] = 'true';

      if (isPod) {
        if (_selectedStockist != null) {
          request.fields['stockist_id'] = _selectedStockist!.id;
        }
        if (_selectedChemist != null) {
          request.fields['hospital_id'] = _selectedChemist!.id;
        }
      } else {
        if (_selectedPod != null) {
          request.fields['pod_id'] = _selectedPod!.id;
        }
        if (_isEinvoiceDoc()) {
          if (_selectedStockist != null) {
            request.fields['stockistId'] = _selectedStockist!.id;
          }
          if (_selectedChemist != null) {
            request.fields['hospitalId'] = _selectedChemist!.id;
          }
        }
      }

      if (_isEinvoiceDoc() && _einvoiceData != null) {
        request.fields['einvoice'] = jsonEncode(_einvoiceData);
      }

      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ Document uploaded successfully! OCR processing started.',
            ),
          ),
        );
        setState(() {
          _capturedImageFile = null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<File> _generateAndSavePdfCopy({String? suggestedFileName}) async {
    if (_capturedImageFile == null) throw Exception('No image captured');
    final bytes = await _capturedImageFile!.readAsBytes();
    final pdfDoc = pw.Document();
    final pwImage = pw.MemoryImage(bytes);
    pdfDoc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Center(
          child: pw.FittedBox(child: pw.Image(pwImage), fit: pw.BoxFit.contain),
        ),
      ),
    );
    final pdfBytes = await pdfDoc.save();
    final dir = await getApplicationDocumentsDirectory();
    final filename =
        suggestedFileName ??
        'doc_preview_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final outPath = p.join(dir.path, filename);
    final file = File(outPath);
    await file.writeAsBytes(pdfBytes, flush: true);
    return file;
  }

  Future<void> _downloadPreviewPdf() async {
    try {
      final saved = await _generateAndSavePdfCopy();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved: ${p.basename(saved.path)}')),
      );
      await OpenFilex.open(saved.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save/open PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: WillPopScope(
        onWillPop: () async {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return false;
          }
          return true;
        },
        child: Scaffold(
          appBar: AppBar(title: const Text("Upload Document")),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.teal.withOpacity(0.05),
                  Colors.teal.withOpacity(0.0),
                ],
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              children: [
                if (_isLoadingLists || _isProcessingImage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        Text(
                          _isProcessingImage
                              ? 'Processing document for OCR...'
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
                      ButtonSegment(value: 'POD', label: Text("POD")),
                      ButtonSegment(value: 'GRN', label: Text("GRN")),
                      ButtonSegment(
                        value: 'E-INVOICE',
                        label: Text("E-Invoice"),
                      ),
                    ],
                    selected: {_selectedDocType ?? 'POD'},
                    onSelectionChanged: _isUploading
                        ? null
                        : (value) {
                            setState(() {
                              _selectedDocType = value.first;
                              // Always clear all dependent selections
                              _selectedStockist = null;
                              _selectedChemist = null;
                              _selectedPod = null;
                              _einvoiceData = null;
                              // Force rebuild of Autocomplete widgets by changing keys
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
                    subtitle: 'Search and select a stockist',
                    child: _customAutocomplete(
                      key: _stockistKey,
                      options: _allStockists,
                      selected: _selectedStockist,
                      label: "Search Stockist",
                      onSelected: (opt) =>
                          setState(() => _selectedStockist = opt),
                      onClear: () => setState(() => _selectedStockist = null),
                    ),
                  ),
                  _buildSectionCard(
                    icon: Icons.local_hospital,
                    title: 'Hospital',
                    subtitle: 'Search and select a hospital',
                    child: _customAutocomplete(
                      key: _chemistKey,
                      options: _allChemists,
                      selected: _selectedChemist,
                      label: "Search Hospital",
                      onSelected: (opt) =>
                          setState(() => _selectedChemist = opt),
                      onClear: () => setState(() => _selectedChemist = null),
                    ),
                  ),
                ],
                _buildSectionCard(
                  icon: Icons.receipt_long,
                  title: 'POD',
                  subtitle: 'Search and select a POD to link GRN / E-Invoice',
                  child: _customAutocomplete(
                    key: _podKey,
                    options: _allPods,
                    selected: _selectedPod,
                    label: "Search POD",
                    onSelected: (opt) => setState(() => _selectedPod = opt),
                    onClear: () => setState(() => _selectedPod = null),
                  ),
                ),
                _buildSectionCard(
                  icon: Icons.camera_alt,
                  title: 'Capture / Scan',
                  subtitle: _isProcessingImage
                      ? 'Processing document for better OCR accuracy...'
                      : 'Documents are automatically enhanced for OCR',
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed:
                              (_isUploading ||
                                  _isProcessingImage ||
                                  _isEinvoiceDoc() ||
                                  (!_isPodDoc() && _selectedPod == null))
                              ? null
                              : _takePhoto,
                          icon: _isProcessingImage
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.photo_camera),
                          label: Text(
                            _isProcessingImage ? 'Processing...' : 'Take Photo',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed:
                              (_isUploading ||
                                  _isProcessingImage ||
                                  _selectedPod == null)
                              ? null
                              : () async {
                                  final result =
                                      await Navigator.push<
                                        Map<String, dynamic>
                                      >(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              GstQrApp(podId: _selectedPod!.id),
                                        ),
                                      );
                                  if (result != null) {
                                    setState(() => _einvoiceData = result);
                                  }
                                },
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan E-Invoice'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_capturedImageFile != null)
                  _buildSectionCard(
                    icon: Icons.picture_as_pdf,
                    title: 'Preview & Upload',
                    subtitle: 'Document has been optimized for OCR processing',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.black12,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.picture_as_pdf,
                                  size: 48,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "📄 OCR-Ready PDF",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  p.basename(_capturedImageFile!.path),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "Enhanced for OCR",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PdfPreviewScreen(
                                  pdfFile: _capturedImageFile!,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text("Open PDF Preview"),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _isUploading ? null : _uploadCaptured,
                          icon: _isUploading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload),
                          label: const Text("Upload OCR-Ready PDF"),
                        ),
                      ],
                    ),
                  ),
                if (_isUploading && _capturedImageFile == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
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
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
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
      displayStringForOption: (opt) => opt.label,
      optionsBuilder: (TextEditingValue tev) {
        final text = tev.text.toLowerCase();
        if (text.isEmpty) return options.take(50);
        return options.where(
          (e) =>
              e.label.toLowerCase().contains(text) ||
              e.id.toLowerCase().contains(text),
        );
      },
      optionsViewBuilder: (context, onSelectedOpt, iterable) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: iterable.length,
                itemBuilder: (ctx, i) {
                  final opt = iterable.elementAt(i);
                  return ListTile(
                    title: Text(opt.label),
                    onTap: () => onSelectedOpt(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        // Only set text if something is selected and the field is empty
        if (selected != null && textController.text.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (textController.text.isEmpty) {
              textController.text = selected.label;
              textController.selection = TextSelection.fromPosition(
                TextPosition(offset: textController.text.length),
              );
            }
          });
        }
        return TextField(
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.grey.shade50,
            suffixIcon: textController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      textController.clear();
                      onClear();
                    },
                  ),
          ),
        );
      },
      onSelected: onSelected,
    );
  }
}

class _SelectItem {
  final String id;
  final String label;

  _SelectItem({required this.id, required this.label});

  static _SelectItem? fromDynamic(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return _SelectItem(id: value, label: value);
    }
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
