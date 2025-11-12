import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:zyduspod/config.dart';
import 'package:zyduspod/services/api_client.dart';
import 'package:zyduspod/Models/notification_model.dart';

// NOTE: We use ApiClient for auth and 401 handling
class NotificationService {
  final ApiClient _apiClient = ApiClient();

  Future<NotificationResponse> fetchNotifications({int page = 1}) async {
    final uri = Uri.parse('${API_NOTIFICATIONS_URL}?page=$page');
    print('Fetching notifications: $uri');
    final http.Response response = await _apiClient.get(uri);
    print('Notifications response: ${response.body}');
    
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load notifications (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    
    // Handle paginated response (like Laravel pagination)
    if (decoded is Map<String, dynamic>) {
      final List<dynamic> list = _extractList(decoded);
      final notifications = list.map((e) {
        try {
          if (e is Map<String, dynamic>) {
            return AppNotification.fromJson(e);
          } else if (e is Map) {
            return AppNotification.fromJson(Map<String, dynamic>.from(e));
          }
          return null;
        } catch (err) {
          print('Error parsing notification: $err');
          return null;
        }
      }).whereType<AppNotification>().toList();
      
      // Check for pagination info
      final hasNextPage = decoded['next_page_url'] != null && decoded['next_page_url'].toString().isNotEmpty;
      final currentPage = decoded['current_page'] is int ? decoded['current_page'] as int : page;
      final lastPage = decoded['last_page'] is int ? decoded['last_page'] as int : null;
      
      return NotificationResponse(
        notifications: notifications,
        hasNextPage: hasNextPage,
        currentPage: currentPage,
        lastPage: lastPage,
      );
    }
    
    // Handle simple array response (no pagination)
    final List<dynamic> list = _extractList(decoded);
    final notifications = list.map((e) {
      try {
        if (e is Map<String, dynamic>) {
          return AppNotification.fromJson(e);
        } else if (e is Map) {
          return AppNotification.fromJson(Map<String, dynamic>.from(e));
        }
        return null;
      } catch (err) {
        print('Error parsing notification: $err');
        return null;
      }
    }).whereType<AppNotification>().toList();
    
    // If it's a simple array and we're on page 1, assume all data is loaded
    // If we're on page > 1 and got empty list, no more pages
    return NotificationResponse(
      notifications: notifications,
      hasNextPage: false,
      currentPage: page,
      lastPage: page,
    );
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

class NotificationResponse {
  final List<AppNotification> notifications;
  final bool hasNextPage;
  final int currentPage;
  final int? lastPage;

  NotificationResponse({
    required this.notifications,
    required this.hasNextPage,
    required this.currentPage,
    this.lastPage,
  });
}


