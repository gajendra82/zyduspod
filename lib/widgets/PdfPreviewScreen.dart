import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class PdfPreviewScreen extends StatefulWidget {
  final File? pdfFile;
  final Uint8List? pdfBytes;
  final String? title;

  const PdfPreviewScreen({Key? key, this.pdfFile, this.pdfBytes, this.title})
    : super(key: key);

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  PdfController? _pdfController;
  bool _isLoading = true;
  String? _errorMessage;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // Don't initialize here - wait for didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Only initialize once
    if (!_initialized) {
      _initialized = true;
      _initializePdf();
    }
  }

  Future<void> _initializePdf() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Extract arguments from route if not passed directly
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      final file = widget.pdfFile ?? args?['pdfFile'] as File?;
      final bytes = widget.pdfBytes ?? args?['pdfBytes'] as Uint8List?;

      debugPrint(
        '[PDF] Initializing with file: ${file?.path}, bytes: ${bytes?.length}',
      );

      if (file == null && bytes == null) {
        throw Exception('PDF file or bytes required');
      }

      // Check if file exists
      if (file != null && !await file.exists()) {
        throw Exception('PDF file not found: ${file.path}');
      }

      // Create PDF document
      PdfDocument document;
      if (file != null) {
        debugPrint('[PDF] Loading from file: ${file.path}');
        document = await PdfDocument.openFile(file.path);
      } else {
        debugPrint('[PDF] Loading from bytes: ${bytes!.length} bytes');
        document = await PdfDocument.openData(bytes);
      }

      debugPrint('[PDF] Document loaded with ${document.pagesCount} pages');

      // Initialize controller
      _pdfController = PdfController(document: Future.value(document));

      if (mounted) {
        setState(() {
          _totalPages = document.pagesCount;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('[PDF] Error loading PDF: $e');
      debugPrint('[PDF] Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load PDF: ${e.toString()}';
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

  void _goToPage(int page) {
    if (_pdfController != null && page > 0 && page <= _totalPages) {
      _pdfController!.jumpToPage(page);
    }
  }

  void _showPageSelector() {
    showDialog(
      context: context,
      builder: (context) {
        int selectedPage = _currentPage;
        return AlertDialog(
          title: const Text('Go to Page'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter page number (1-$_totalPages):'),
              const SizedBox(height: 16),
              TextField(
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Page number',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                autofocus: true,
                onChanged: (value) {
                  selectedPage = int.tryParse(value) ?? _currentPage;
                },
                onSubmitted: (value) {
                  final page = int.tryParse(value);
                  if (page != null && page > 0 && page <= _totalPages) {
                    Navigator.pop(context);
                    _goToPage(page);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedPage > 0 && selectedPage <= _totalPages) {
                  Navigator.pop(context);
                  _goToPage(selectedPage);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A0A8),
                foregroundColor: Colors.white,
              ),
              child: const Text('Go'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final title = widget.title ?? args?['title'] as String? ?? 'PDF Preview';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
            if (_totalPages > 0)
              Text(
                'Page $_currentPage of $_totalPages',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF00A0A8),
        foregroundColor: Colors.white,
        actions: [
          if (_totalPages > 1) ...[
            IconButton(
              icon: const Icon(Icons.first_page),
              onPressed: _currentPage > 1 ? () => _goToPage(1) : null,
              tooltip: 'First page',
            ),
            IconButton(
              icon: const Icon(Icons.navigate_before),
              onPressed:
                  _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
              tooltip: 'Previous page',
            ),
            IconButton(
              icon: const Icon(Icons.numbers),
              onPressed: _showPageSelector,
              tooltip: 'Go to page',
            ),
            IconButton(
              icon: const Icon(Icons.navigate_next),
              onPressed:
                  _currentPage < _totalPages
                      ? () => _goToPage(_currentPage + 1)
                      : null,
              tooltip: 'Next page',
            ),
            IconButton(
              icon: const Icon(Icons.last_page),
              onPressed:
                  _currentPage < _totalPages
                      ? () => _goToPage(_totalPages)
                      : null,
              tooltip: 'Last page',
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A0A8)),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading PDF...',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
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
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A0A8),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_pdfController == null) {
      return const Center(child: Text('PDF controller not initialized'));
    }

    return PdfView(
      controller: _pdfController!,
      onPageChanged: (page) {
        setState(() {
          _currentPage = page;
        });
      },
      onDocumentLoaded: (document) {
        debugPrint('[PDF] Document loaded: ${document.pagesCount} pages');
      },
      onDocumentError: (error) {
        debugPrint('[PDF] Document error: $error');
        if (mounted) {
          setState(() {
            _errorMessage = error.toString();
          });
        }
      },
      scrollDirection: Axis.vertical,
      pageSnapping: true,
      physics: const BouncingScrollPhysics(),
      builders: PdfViewBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder:
            (_) => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A0A8)),
              ),
            ),
        pageLoaderBuilder:
            (_) => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A0A8)),
              ),
            ),
        errorBuilder:
            (_, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error loading page: $error',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
      ),
    );
  }
}
