import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zyduspod/config.dart';

class PodDetailsService {
  static Future<Map<String, dynamic>> getPodDetails(int podId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        throw Exception('No authentication token found');
      }
      print('${API_BASE_URL}pod/$podId');

      final response = await http.get(
        Uri.parse('${API_BASE_URL}pods/$podId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
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
