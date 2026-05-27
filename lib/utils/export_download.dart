import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

/// Persist [bytes] to disk and surface them to the user.
///
/// On web: triggers a browser download via a blob URL anchor click (no
/// server round-trip beyond the bytes we already have).
///
/// On mobile/desktop: writes to the app's temp directory and opens the
/// file with the platform's default app (Excel / Numbers / CSV viewer).
///
/// Throws [Exception] on filesystem / open errors so callers can surface
/// a toast.
Future<void> saveAndOpenExport({
  required Uint8List bytes,
  required String filename,
  String? mimeType,
}) async {
  if (kIsWeb) {
    final blob = html.Blob(
      <Uint8List>[bytes],
      mimeType ?? 'application/octet-stream',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    // Allow the browser a tick to start the download before revoking.
    Future<void>.delayed(const Duration(seconds: 1), () {
      html.Url.revokeObjectUrl(url);
    });
    return;
  }

  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/$filename';
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);

  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done) {
    throw Exception('Could not open exported file: ${result.message}');
  }
}
