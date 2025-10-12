import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class PythonQRService {
  // Your Hugging Face Space URL
  static const String _baseUrl =
      'https://anujakkulkarni-envoice-qr-extractor.hf.space';

  /// Extract QR code from PDF using Hugging Face API
  static Future<Map<String, dynamic>?> extractQRFromPDF(
    File pdfFile, {
    int maxPages = 6,
    int dpi = 1200,
  }) async {
    try {
      debugPrint('[HF-QR] 📤 Uploading to: $_baseUrl/extract-qr');
      debugPrint('[HF-QR] 📄 File: ${pdfFile.path}');
      debugPrint('[HF-QR] 📊 Max pages: $maxPages');
      debugPrint('[HF-QR] 🔍 DPI: $dpi');

      final uri = Uri.parse('$_baseUrl/extract-qr');

      // Create multipart request
      final request = http.MultipartRequest('POST', uri);

      // Add file
      final fileName = pdfFile.path.split('/').last;
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          pdfFile.path,
          filename: fileName,
        ),
      );

      // Add form fields
      request.fields['pages'] = maxPages.toString();
      request.fields['dpi'] = dpi.toString();

      debugPrint('[HF-QR] 📡 Sending multipart request...');
      debugPrint('[HF-QR] Fields: ${request.fields}');

      // Send request with timeout
      final streamedResponse = await request.send()
      // .timeout(
      //   const Duration(seconds: 120),
      //   onTimeout: () {
      //     throw TimeoutException('Request timed out after 120 seconds');
      //   },
      // )
      ;

      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('[HF-QR] 📨 Response status: ${response.statusCode}');
      debugPrint('[HF-QR] 📨 Response body length: ${response.body.length}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);

          // Check if success
          if (data is Map &&
              data['success'] == true &&
              data['qr_data'] != null) {
            final qrData = data['qr_data'] as Map<String, dynamic>;

            debugPrint('[HF-QR] ✅ QR extracted successfully');
            debugPrint('[HF-QR] 📋 Method: ${qrData['_detection_method']}');
            debugPrint('[HF-QR] 📋 Region: ${qrData['_detection_region']}');
            debugPrint('[HF-QR] 📋 Page: ${qrData['_page_number']}');
            debugPrint('[HF-QR] 📋 DPI Used: ${qrData['_dpi_used']}');
            debugPrint('[HF-QR] 📋 Invoice No: ${qrData['DocNo']}');

            // Remove metadata fields (starting with _) for cleaner data
            final cleanData = Map<String, dynamic>.from(qrData);
            cleanData.removeWhere((key, value) => key.startsWith('_'));

            return cleanData;
          } else if (data is Map && data['success'] == false) {
            debugPrint('[HF-QR] ❌ ${data['message']}');
            return null;
          }
        } catch (e) {
          debugPrint('[HF-QR] ⚠️ JSON parse error: $e');
          debugPrint('[HF-QR] Response body: ${response.body}');
        }
      } else if (response.statusCode == 404) {
        debugPrint('[HF-QR] ❌ 404: No QR code found');
        try {
          final data = jsonDecode(response.body);
          debugPrint('[HF-QR] Message: ${data['message']}');
        } catch (_) {}
        return null;
      } else {
        debugPrint('[HF-QR] ❌ Error: ${response.statusCode}');
        debugPrint('[HF-QR] Response: ${response.body}');
        return null;
      }
    } on TimeoutException catch (e) {
      debugPrint('[HF-QR] ⏱️ Timeout: $e');
      return null;
    } on SocketException catch (e) {
      debugPrint('[HF-QR] 🌐 Network error: $e');
      return null;
    } catch (e, stackTrace) {
      debugPrint('[HF-QR] ❌ Exception: $e');
      debugPrint('[HF-QR] Stack trace: $stackTrace');
      return null;
    }

    return null;
  }

  /// Check if Hugging Face Space is available
  static Future<bool> isApiAvailable() async {
    try {
      debugPrint('[HF-QR] 🔍 Checking API availability...');

      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 10));

      final isAvailable = response.statusCode == 200;
      debugPrint(
        '[HF-QR] ${isAvailable ? "✅" : "❌"} API ${isAvailable ? "available" : "unavailable"}',
      );

      return isAvailable;
    } catch (e) {
      debugPrint('[HF-QR] ❌ API check failed: $e');
      // Try root endpoint as fallback
      try {
        final response = await http
            .get(Uri.parse(_baseUrl))
            .timeout(const Duration(seconds: 10));
        return response.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
  }

  /// Get API base URL (for debugging)
  static String getBaseUrl() => _baseUrl;
}
