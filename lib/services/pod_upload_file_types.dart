import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

/// Shared allowlists / MIME helpers for POD uploads (PDF, image, ZIP, Excel).
/// Keeps KAM, stockist, blob, and ZIP packaging paths in sync.
class PodUploadFileTypes {
  PodUploadFileTypes._();

  /// Extensions accepted by the document picker (without leading dot).
  static const List<String> pickerExtensions = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'zip',
    'xlsx',
    'xls',
  ];

  /// Non-ZIP entries that may be uploaded / packed into a ZIP for the backend.
  static const Set<String> processableExtensions = {
    '.pdf',
    '.jpg',
    '.jpeg',
    '.png',
    '.xlsx',
    '.xls',
  };

  static const Set<String> excelExtensions = {'.xlsx', '.xls'};
  static const Set<String> imageExtensions = {'.jpg', '.jpeg', '.png'};

  static String extensionOf(String nameOrPath) =>
      p.extension(nameOrPath).toLowerCase();

  static bool isExcel(String nameOrPath) =>
      excelExtensions.contains(extensionOf(nameOrPath));

  static bool isPdf(String nameOrPath) => extensionOf(nameOrPath) == '.pdf';

  static bool isImage(String nameOrPath) =>
      imageExtensions.contains(extensionOf(nameOrPath));

  static bool isZip(String nameOrPath) => extensionOf(nameOrPath) == '.zip';

  static bool isSupportedUploadName(String nameOrPath) =>
      processableExtensions.contains(extensionOf(nameOrPath));

  static bool isSupportedPickerName(String nameOrPath) {
    final ext = extensionOf(nameOrPath);
    return processableExtensions.contains(ext) || ext == '.zip';
  }

  static MediaType mediaTypeForName(String nameOrPath) {
    switch (extensionOf(nameOrPath)) {
      case '.zip':
        return MediaType('application', 'zip');
      case '.pdf':
        return MediaType('application', 'pdf');
      case '.jpg':
      case '.jpeg':
        return MediaType('image', 'jpeg');
      case '.png':
        return MediaType('image', 'png');
      case '.xlsx':
        return MediaType(
          'application',
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      case '.xls':
        return MediaType('application', 'vnd.ms-excel');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  static String contentTypeStringForName(String nameOrPath) {
    final mt = mediaTypeForName(nameOrPath);
    return '${mt.type}/${mt.subtype}';
  }

  static IconData iconForName(String nameOrPath) {
    final ext = extensionOf(nameOrPath);
    if (excelExtensions.contains(ext)) return Icons.table_chart;
    if (ext == '.zip') return Icons.folder_zip;
    if (imageExtensions.contains(ext)) return Icons.image;
    if (ext == '.pdf') return Icons.picture_as_pdf;
    return Icons.description;
  }

  static Color iconColorForName(String nameOrPath) {
    final ext = extensionOf(nameOrPath);
    if (excelExtensions.contains(ext)) return const Color(0xFF217346);
    if (ext == '.zip') return const Color(0xFFF9A825);
    if (imageExtensions.contains(ext)) return const Color(0xFF1E88E5);
    if (ext == '.pdf') return Colors.redAccent;
    return const Color(0xFF00A0A8);
  }

  static String qualityMessageForName(String nameOrPath) {
    if (isExcel(nameOrPath)) return 'Excel - Backend will process';
    if (isZip(nameOrPath)) {
      return 'ZIP archive — extracted and uploaded to cloud storage';
    }
    if (isImage(nameOrPath)) return 'Image - Backend will process';
    if (isPdf(nameOrPath)) return 'PDF - Backend will process';
    return 'Backend will process';
  }
}
