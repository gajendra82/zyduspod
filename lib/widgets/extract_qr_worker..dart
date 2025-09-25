import 'dart:io';
import 'package:zyduspod/widgets/EInvoiceQRExtractor.dart';

/// Runs in a background isolate via `compute`.
/// args: {'path': String, 'dpi': int, 'maxPages': int}
Future<Map<String, dynamic>?> extractQrWorker(Map<String, dynamic> args) async {
  final String path = args['path'] as String;
  final int dpi = (args['dpi'] as int?) ?? 260; // tuned down from 340
  final int maxPages = (args['maxPages'] as int?) ?? 3; // fewer pages for speed
  try {
    return await EInvoiceQRExtractor.extractQRFromPDF(
      File(path),
      dpi: dpi.toDouble(),
      maxPages: maxPages,
    );
  } catch (_) {
    return null;
  }
}
