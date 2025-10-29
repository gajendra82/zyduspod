import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:zyduspod/config.dart';
import 'package:zyduspod/services/api_client.dart';
import 'package:zyduspod/Models/notification_model.dart';

// NOTE: We use ApiClient for auth and 401 handling
class NotificationService {
  final ApiClient _apiClient = ApiClient();

  Future<List<AppNotification>> fetchNotifications({int page = 1}) async {
    final uri = Uri.parse('${API_NOTIFICATIONS_URL}');
    print(uri);
    final http.Response response = await _apiClient.get(uri);
    print(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load notifications (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    final List<dynamic> list = _extractList(decoded);
    return list.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Handle various array shapes: {data: [...]}, {notifications: [...]}, or [...]
  List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic>) {
      if (decoded['data'] is List) return decoded['data'] as List;
      if (decoded['notifications'] is List) return decoded['notifications'] as List;
    }
    return [];
  }
}


