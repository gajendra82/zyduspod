import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class QrApiClient {
  QrApiClient(this.baseUrl);

  /// Base URL examples:
  /// - Android emulator: http://10.0.2.2:5000
  /// - iOS simulator: http://127.0.0.1:5000
  /// - Physical device: http://<your-computer-LAN-IP>:5000 (ensure same Wi-Fi)
  final String baseUrl;

  /// Uploads a PDF and returns decoded QR texts (empty if none found).
  Future<List<String>> extractQrFromPdf(
    String filePath, {
    int maxPages = 4,
    int dpi = 340, // try 300–360 for small QRs
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final uri = Uri.parse('$baseUrl/extract_qr');

    final req = http.MultipartRequest('POST', uri)
      ..fields['max_pages'] = maxPages.toString()
      ..fields['dpi'] = dpi.toString()
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          contentType: MediaType('application', 'pdf'),
        ),
      );

    final streamed = await req.send().timeout(timeout);
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200) {
      throw HttpException('QR API error ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = (data['results'] as List?)?.cast<String>() ?? <String>[];

    return results;
  }
}
