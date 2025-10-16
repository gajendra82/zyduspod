import 'dart:convert';
import 'package:zyduspod/config.dart';
import 'package:zyduspod/services/api_client.dart';

class PodDetailsService {
  static final ApiClient _apiClient = ApiClient();

  static Future<Map<String, dynamic>> getPodDetails(int podId) async {
    try {
      print('${API_BASE_URL}pods/$podId');

      final response = await _apiClient.get(
        Uri.parse('${API_BASE_URL}pods/$podId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Pod Details: $data');
        return data;
      } else {
        throw Exception('Failed to load POD details: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching POD details: $e');
    }
  }

  static Future<Map<String, dynamic>> processQrExtraction(int podId) async {
    try {
      print('Processing QR Extraction: $podId');
      final response = await _apiClient.post(
        Uri.parse('${API_BASE_URL}pod/process-qr-extraction'),
        body: jsonEncode({
          'pod_id': podId,
        }),
        headers: {'Content-Type': 'application/json'},
      );
      print('Response: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('QR Extraction: $data');
        return data;
      } else {
        print('Error response: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to process QR extraction: ${response.statusCode}');
      }
    } catch (e) {
      print('Error: $e');
      throw Exception('Error processing QR extraction: $e');
    }
  }
}
