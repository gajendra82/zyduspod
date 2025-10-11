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
}
