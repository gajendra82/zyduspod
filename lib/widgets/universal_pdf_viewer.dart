import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdfx/pdfx.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class UniversalPdfViewer extends StatefulWidget {
  final Uint8List pdfBytes;
  final String title;

  const UniversalPdfViewer({
    super.key,
    required this.pdfBytes,
    this.title = 'PDF Preview',
  });

  @override
  State<UniversalPdfViewer> createState() => _UniversalPdfViewerState();
}

class _UniversalPdfViewerState extends State<UniversalPdfViewer> {
  PdfController? _pdfController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _initializePdfController();
    }
  }

  Future<void> _initializePdfController() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final document = await PdfDocument.openData(widget.pdfBytes);

      if (mounted) {
        setState(() {
          _pdfController = PdfController(document: Future.value(document));
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[PDF Viewer] Error loading PDF: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load PDF: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebViewer();
    } else {
      return _buildMobileViewer();
    }
  }

  Widget _buildWebViewer() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading PDF... '),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              'Error Loading PDF',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _initializePdfController,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A0A8),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (_pdfController == null) {
      return const Center(child: Text('No PDF loaded'));
    }

    return PdfView(controller: _pdfController!, scrollDirection: Axis.vertical);
  }

  Widget _buildMobileViewer() {
    // Use Syncfusion for mobile (more reliable on mobile)
    try {
      return SfPdfViewer.memory(
        widget.pdfBytes,
        onDocumentLoadFailed: (details) {
          debugPrint('[PDF Viewer] Load failed: ${details.error}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to load PDF: ${details.description}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      );
    } catch (e) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              'Error Loading PDF',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                e.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      );
    }
  }
}
