import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
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

class DocumentUploadScreen extends StatefulWidget {
  const DocumentUploadScreen({super.key});

  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  bool _isUploading = false;
  bool _isLoadingLists = false;

  String? _selectedDocType = 'POD';

  // Removed external text controllers; rely on Autocomplete field controllers

  List<_SelectItem> _allStockists = [];
  List<_SelectItem> _allChemists = [];
  List<_SelectItem> _allPods = [];
  List<Pod> _pods = [];

  _SelectItem? _selectedStockist;
  _SelectItem? _selectedChemist;
  _SelectItem? _selectedPod;

  File? _capturedImageFile;
  Map<String, dynamic>? _einvoiceData;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    super.dispose();
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
    return 'POD ${pod.podNumber}  |  INV ${pod.invoiceNumber}  |  ${podDt}  |  ${invDt}';
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

  bool _optionMatches(_SelectItem item, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return item.label.toLowerCase().contains(q) ||
        item.id.toLowerCase().contains(q);
  }

  Future<void> _takePhoto() async {
    final ImagePicker picker = ImagePicker();
    File? acceptedFile;
    while (mounted && acceptedFile == null) {
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (photo == null) return; // User cancelled
      final candidate = File(photo.path);
      final bool confirm = await _confirmPhoto(candidate);
      if (confirm) {
        acceptedFile = candidate;
      } else {
        continue; // Retake
      }
    }
    if (!mounted || acceptedFile == null) return;
    setState(() {
      _capturedImageFile = acceptedFile;
    });
  }

  Future<bool> _confirmPhoto(File file) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return AlertDialog(
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
            );
          },
        ) ??
        false;
  }

  MediaType _inferImageContentType(File file) {
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.png') return MediaType('image', 'png');
    if (ext == '.heic' || ext == '.heif') return MediaType('image', 'heic');
    return MediaType('image', 'jpeg');
  }

  bool _isPodDoc() => (_selectedDocType ?? '') == 'POD';
  bool _isEinvoiceDoc() =>
      (_selectedDocType ?? '') == 'EINVOICE' ||
      (_selectedDocType ?? '') == 'E-INVOICE';

  // Compress image under 4 MB off the UI thread
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

      // Ensure image is <= 4MB
      final File imageFile = await _ensureImageUnderLimit(_capturedImageFile!);
      final MediaType mediaType = _inferImageContentType(imageFile);

      final bool isPod = _isPodDoc();
      final uri = Uri.parse(isPod ? API_POD_UPLOAD_URL : API_DOC_UPLOAD_URL);
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            imageFile.path,
            filename: p.basename(imageFile.path),
            contentType: mediaType,
          ),
        );
      // if (!isPod) {
      //   request.fields['docType'] = _selectedDocType!;
      // }
      if (isPod) {
        if (_selectedStockist != null) {
          request.fields['stockist_id'] = _selectedStockist!.id;
        }
        if (_selectedChemist != null) {
          request.fields['hospital_id'] = _selectedChemist!.id;
        }
      } else {
        // GRN/E-Invoice branch uses ${API_BASE_URL}grn/upload-pdf
        // For GRN specifically, only send pod_id and file
        if (_selectedPod != null) {
          request.fields['pod_id'] = _selectedPod!.id;
        }
        // Keep any additional fields only for E-Invoice, not for GRN
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Uploaded successfully')));
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
    if (_capturedImageFile == null) {
      throw Exception('No image captured');
    }
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
    return Scaffold(
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
            if (_isLoadingLists)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),

            _buildSectionCard(
              icon: Icons.description,
              title: 'Document Type',
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedDocType,
                      decoration: const InputDecoration(
                        labelText: 'Choose type',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'POD', child: Text('POD')),
                        DropdownMenuItem(value: 'GRN', child: Text('GRN')),
                        DropdownMenuItem(
                          value: 'E-INVOICE',
                          child: Text('E-Invoice'),
                        ),
                      ],
                      onChanged: _isUploading
                          ? null
                          : (v) => setState(() => _selectedDocType = v),
                    ),
                  ),
                ],
              ),
            ),

            _buildSectionCard(
              icon: Icons.store_mall_directory,
              title: 'Stockist',
              subtitle: 'Search and select a stockist',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Autocomplete<_SelectItem>(
                    displayStringForOption: (opt) => opt.label,
                    optionsBuilder: (TextEditingValue tev) {
                      final text = tev.text;
                      final source = _allStockists;
                      if (text.isEmpty) {
                        return source.take(50);
                      }
                      return source
                          .where((e) => _optionMatches(e, text))
                          .take(50);
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                          if (_selectedStockist != null &&
                              controller.text != _selectedStockist!.label) {
                            controller.text = _selectedStockist!.label;
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                          }
                          // Do not auto-clear selected stockist while typing in other fields
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'Search Stockist',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              suffixIcon: controller.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        controller.clear();
                                        setState(
                                          () => _selectedStockist = null,
                                        );
                                      },
                                    ),
                            ),
                          );
                        },
                    onSelected: (opt) {
                      setState(() {
                        _selectedStockist = opt;
                      });
                    },
                  ),
                  if (_selectedStockist != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _selectedPill(
                        label: _selectedStockist!.label,
                        onClear: () => setState(() => _selectedStockist = null),
                      ),
                    ),
                ],
              ),
            ),

            _buildSectionCard(
              icon: Icons.local_hospital,
              title: 'Hospital',
              subtitle: 'Search and select a hospital',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Autocomplete<_SelectItem>(
                    displayStringForOption: (opt) => opt.label,
                    optionsBuilder: (TextEditingValue tev) {
                      final text = tev.text;
                      final source = _allChemists;
                      if (text.isEmpty) {
                        return source.take(50);
                      }
                      return source
                          .where((e) => _optionMatches(e, text))
                          .take(50);
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                          if (_selectedChemist != null &&
                              controller.text != _selectedChemist!.label) {
                            controller.text = _selectedChemist!.label;
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                          }
                          // Keep selected hospital until explicitly cleared
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'Search Hospital',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              suffixIcon: controller.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        controller.clear();
                                        setState(() => _selectedChemist = null);
                                      },
                                    ),
                            ),
                          );
                        },
                    onSelected: (opt) {
                      setState(() {
                        _selectedChemist = opt;
                      });
                    },
                  ),
                  if (_selectedChemist != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _selectedPill(
                        label: _selectedChemist!.label,
                        onClear: () => setState(() => _selectedChemist = null),
                      ),
                    ),
                ],
              ),
            ),

            _buildSectionCard(
              icon: Icons.receipt_long,
              title: 'POD',
              subtitle: 'Search and select a POD to link GRN / E-Invoice',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Autocomplete<_SelectItem>(
                    displayStringForOption: (opt) => opt.label,
                    optionsBuilder: (TextEditingValue tev) {
                      final text = tev.text;
                      final source = _allPods;
                      if (text.isEmpty) {
                        return source.take(50);
                      }
                      return source
                          .where((e) => _optionMatches(e, text))
                          .take(50);
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                          if (_selectedPod != null &&
                              controller.text != _selectedPod!.label) {
                            controller.text = _selectedPod!.label;
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                          }
                          // Keep selected POD until explicitly cleared
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'Search POD',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              suffixIcon: controller.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        controller.clear();
                                        setState(() => _selectedPod = null);
                                      },
                                    ),
                            ),
                          );
                        },
                    onSelected: (opt) {
                      setState(() {
                        _selectedPod = opt;
                      });
                    },
                  ),
                  if (_selectedPod != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _selectedPill(
                        label: _selectedPod!.label,
                        onClear: () => setState(() => _selectedPod = null),
                      ),
                    ),
                ],
              ),
            ),

            _buildSectionCard(
              icon: Icons.camera_alt,
              title: 'Capture / Scan',
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
                              (!_isPodDoc() && _selectedPod == null))
                          ? null
                          : _takePhoto,
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Take Photo'),
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
                      onPressed: (_isUploading || _selectedPod == null)
                          ? null
                          : () async {
                              final result =
                                  await Navigator.push<Map<String, dynamic>>(
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
                icon: Icons.image,
                title: 'Preview & Upload',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: Colors.black12,
                        height: 240,
                        child: Image.file(
                          _capturedImageFile!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
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
                      label: const Text('Upload'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isUploading ? null : _downloadPreviewPdf,
                      icon: const Icon(Icons.download),
                      label: const Text('Save & Open PDF'),
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

  Widget _selectedPill({required String label, required VoidCallback onClear}) {
    return Wrap(
      children: [
        InputChip(
          label: Text(label),
          onDeleted: onClear,
          deleteIcon: const Icon(Icons.close),
        ),
      ],
    );
  }

  // (Horizontal chip list removed; switched to Autocomplete)
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
