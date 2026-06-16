import 'dart:io' show File;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// One file ready for direct blob upload (from a pick or a ZIP entry).
class PodUploadItem {
  final String fileName;
  final File? file;
  final Uint8List? bytes;

  const PodUploadItem({
    required this.fileName,
    this.file,
    this.bytes,
  });

  Future<int> length() async {
    if (file != null) return file!.length();
    return bytes?.length ?? 0;
  }
}

/// Expands ZIP archives client-side so each PDF/image is uploaded via blob.
class PodZipExpander {
  static const Set<String> _supportedExt = {'.pdf', '.jpg', '.jpeg', '.png'};
  static const int maxEntriesPerZip = 300;
  static const int maxTotalUncompressedBytes = 10 * 1024 * 1024 * 1024; // 10 GB

  static bool isZipName(String name) =>
      p.extension(name).toLowerCase() == '.zip';

  static bool isSupportedUploadName(String name) {
    final ext = p.extension(name).toLowerCase();
    return _supportedExt.contains(ext);
  }

  /// Expand [PodUploadItem] list — ZIPs become individual supported files.
  static Future<List<PodUploadItem>> expandItems(
    List<PodUploadItem> items,
  ) async {
    final out = <PodUploadItem>[];
    for (final item in items) {
      if (isZipName(item.fileName)) {
        final expanded = await _expandZipItem(item);
        out.addAll(expanded);
      } else if (isSupportedUploadName(item.fileName)) {
        out.add(item);
      }
    }
    return out;
  }

  static Future<List<PodUploadItem>> _expandZipItem(PodUploadItem zip) async {
    final Uint8List raw;
    if (zip.bytes != null) {
      raw = zip.bytes!;
    } else if (zip.file != null) {
      raw = await zip.file!.readAsBytes();
    } else {
      throw PodZipExpandException('ZIP has no readable data: ${zip.fileName}');
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(raw, verify: true);
    } catch (e) {
      throw PodZipExpandException(
        'Could not open ZIP "${zip.fileName}": $e',
      );
    }

    if (archive.files.isEmpty) {
      throw PodZipExpandException('ZIP "${zip.fileName}" is empty.');
    }

    if (archive.files.length > maxEntriesPerZip) {
      throw PodZipExpandException(
        'ZIP "${zip.fileName}" has too many entries '
        '(max $maxEntriesPerZip).',
      );
    }

    final out = <PodUploadItem>[];
    var totalBytes = 0;
    final zipStem = p.basenameWithoutExtension(zip.fileName);

    for (final entry in archive.files) {
      if (!entry.isFile || entry.name.isEmpty) continue;

      final baseName = p.basename(entry.name);
      final ext = p.extension(baseName).toLowerCase();
      if (!_supportedExt.contains(ext)) continue;

      final content = entry.content;
      if (content == null) continue;

      final Uint8List fileBytes;
      if (content is Uint8List) {
        fileBytes = content;
      } else if (content is List<int>) {
        fileBytes = Uint8List.fromList(content);
      } else {
        continue;
      }

      if (fileBytes.isEmpty) continue;

      totalBytes += fileBytes.length;
      if (totalBytes > maxTotalUncompressedBytes) {
        throw PodZipExpandException(
          'ZIP "${zip.fileName}" uncompressed content exceeds limit.',
        );
      }

      // Prefix with zip stem so names stay unique across nested folders.
      final uploadName = '${zipStem}__${baseName.replaceAll(RegExp(r'[\\/]'), '_')}';

      out.add(PodUploadItem(
        fileName: uploadName,
        bytes: fileBytes,
      ));
    }

    if (out.isEmpty) {
      throw PodZipExpandException(
        'ZIP "${zip.fileName}" contains no PDF/JPG/PNG files.',
      );
    }

    return out;
  }
}

class PodZipExpandException implements Exception {
  final String message;
  PodZipExpandException(this.message);
  @override
  String toString() => message;
}
