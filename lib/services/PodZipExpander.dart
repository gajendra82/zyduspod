import 'dart:io' show File;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'package:zydus_vistaar/services/pod_upload_file_types.dart';

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

/// Expands ZIP archives client-side so each PDF/image/Excel is uploaded via blob.
class PodZipExpander {
  /// Max processable files per ZIP (matches backend `pod.max_files_per_request`).
  static const int maxSupportedFilesPerZip = 500;
  static const int maxTotalUncompressedBytes = 10 * 1024 * 1024 * 1024; // 10 GB

  static bool isZipName(String name) => PodUploadFileTypes.isZip(name);

  static bool isSupportedUploadName(String name) =>
      PodUploadFileTypes.isSupportedUploadName(name);

  /// Junk paths created by macOS/Windows archivers — not real POD files.
  static bool _isSkippableArchivePath(String name) {
    final normalized = name.replaceAll('\\', '/');
    if (normalized.contains('__MACOSX/')) return true;
    if (normalized.contains('/.')) return true;
    final base = p.basename(normalized).toLowerCase();
    if (base == 'thumbs.db' || base == 'desktop.ini' || base == '.ds_store') {
      return true;
    }
    return false;
  }

  static bool _isSupportedArchiveEntry(ArchiveFile entry) {
    if (!entry.isFile || entry.name.isEmpty) return false;
    if (_isSkippableArchivePath(entry.name)) return false;
    return PodUploadFileTypes.isSupportedUploadName(p.basename(entry.name));
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

    final supportedEntries =
        archive.files.where(_isSupportedArchiveEntry).toList();

    if (supportedEntries.isEmpty) {
      throw PodZipExpandException(
        'ZIP "${zip.fileName}" contains no PDF/JPG/PNG files.',
      );
    }

    if (supportedEntries.length > maxSupportedFilesPerZip) {
      throw PodZipExpandException(
        'ZIP "${zip.fileName}" contains ${supportedEntries.length} PDF/image '
        'files (max $maxSupportedFilesPerZip). '
        'Split into smaller ZIPs or upload files in batches.',
      );
    }

    final out = <PodUploadItem>[];
    var totalBytes = 0;
    final zipStem = p.basenameWithoutExtension(zip.fileName);

    for (final entry in supportedEntries) {
      final baseName = p.basename(entry.name);

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
