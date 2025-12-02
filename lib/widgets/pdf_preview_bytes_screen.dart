import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

/// PDF Preview Screen for bytes (memory-based PDFs)
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
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF00A0A8),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SfPdfViewer.memory(pdfBytes),
    );
  }
}
