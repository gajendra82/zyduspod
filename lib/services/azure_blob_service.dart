import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class AzureBlobService {
  // Use backend endpoint for web uploads (avoids CORS issues)
  static const String _backendUploadUrl =
      'YOUR_BACKEND_URL/api/upload-to-azure';

  /// Upload a file to Azure Blob Storage via backend
  Future<String> uploadFile({
    required Uint8List fileBytes,
    required String fileName,
    String? contentType,
  }) async {
    try {
      debugPrint(
        '[AZURE] Uploading via backend: $fileName (${fileBytes.length} bytes)',
      );

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final uri = Uri.parse(_backendUploadUrl);
      final request = http.MultipartRequest('POST', uri);

      // Add auth header
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Add file
      request.files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
      );

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        final blobUrl = responseData['blob_url'] ?? responseData['url'];

        debugPrint('[AZURE] ✅ Upload successful: $blobUrl');
        return blobUrl;
      } else {
        debugPrint(
          '[AZURE] ❌ Upload failed: ${response.statusCode} - ${response.body}',
        );
        throw Exception('Upload failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[AZURE] ❌ Upload error: $e');
      rethrow;
    }
  }

  /// Upload multiple files and return their blob URLs
  Future<List<String>> uploadFiles({
    required List<FileUploadData> files,
    Function(int current, int total)? onProgress,
  }) async {
    final urls = <String>[];

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      onProgress?.call(i + 1, files.length);

      final url = await uploadFile(
        fileBytes: file.bytes,
        fileName: file.fileName,
        contentType: file.contentType,
      );
      urls.add(url);
    }

    return urls;
  }
}

class FileUploadData {
  final Uint8List bytes;
  final String fileName;
  final String? contentType;

  FileUploadData({
    required this.bytes,
    required this.fileName,
    this.contentType,
  });
}
