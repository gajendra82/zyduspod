import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'package:zydus_vistaar/services/PodZipExpander.dart';

/// Build a single ZIP for blob upload (server extracts and processes).
class PodZipPackager {
  /// If [items] is already one ZIP, return it unchanged. Otherwise expand any
  /// nested ZIPs client-side and pack all supported PDF/image/Excel files into a
  /// new ZIP archive (handles multi-ZIP picks and mixed ZIP + PDF selections).
  static Future<PodUploadItem> packageForUpload(
    List<PodUploadItem> items, {
    String? archiveName,
  }) async {
    if (items.isEmpty) {
      throw PodZipPackException('No files to upload.');
    }

    // Single ZIP — upload as-is; Laravel unpacks server-side.
    if (items.length == 1 && PodZipExpander.isZipName(items.first.fileName)) {
      return items.first;
    }

    // Multiple files and/or ZIPs: expand ZIPs first so we package PDF/images/Excel.
    // Backend unwrap accepts flat PDF/JPG/PNG/XLSX/XLS entries — not nested ZIPs.
    final List<PodUploadItem> packable;
    try {
      packable = await PodZipExpander.expandItems(items);
    } on PodZipExpandException catch (e) {
      throw PodZipPackException(e.message);
    }

    if (packable.isEmpty) {
      final zipCount =
          items.where((i) => PodZipExpander.isZipName(i.fileName)).length;
      if (zipCount > 0) {
        throw PodZipPackException(
          'No PDF, image, or Excel files found inside the selected ZIP archive(s).',
        );
      }
      throw PodZipPackException('No PDF, image, or Excel files to package.');
    }

    final archive = Archive();
    final usedNames = <String>{};

    for (final item in packable) {
      if (!PodZipExpander.isSupportedUploadName(item.fileName)) {
        continue;
      }

      final Uint8List bytes;
      if (item.bytes != null) {
        bytes = item.bytes!;
      } else if (item.file != null) {
        bytes = await item.file!.readAsBytes();
      } else {
        continue;
      }

      if (bytes.isEmpty) continue;

      var entryName = p.basename(item.fileName);
      entryName = entryName.replaceAll(RegExp(r'[\\/]'), '_');
      var dedupe = 1;
      var uniqueName = entryName;
      while (usedNames.contains(uniqueName)) {
        final stem = p.basenameWithoutExtension(entryName);
        final ext = p.extension(entryName);
        uniqueName = '${stem}_$dedupe$ext';
        dedupe++;
      }
      usedNames.add(uniqueName);

      archive.addFile(ArchiveFile(uniqueName, bytes.length, bytes));
    }

    if (archive.files.isEmpty) {
      throw PodZipPackException('No PDF, image, or Excel files to package.');
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null || zipBytes.isEmpty) {
      throw PodZipPackException('Could not create ZIP archive.');
    }

    final name = archiveName ??
        'pod_upload_${DateTime.now().millisecondsSinceEpoch}.zip';

    return PodUploadItem(
      fileName: name.endsWith('.zip') ? name : '$name.zip',
      bytes: Uint8List.fromList(zipBytes),
    );
  }
}

class PodZipPackException implements Exception {
  final String message;
  PodZipPackException(this.message);
  @override
  String toString() => message;
}
