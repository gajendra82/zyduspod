import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/hospital_stats.dart';

/// Replace with your backend endpoint if available.
/// If not reachable, a mock list is returned for UI development.
const String kHospitalDashboardUrl = String.fromEnvironment(
  'HOSPITAL_DASHBOARD_URL',
  defaultValue:
      '', // set via --dart-define or replace with your config constant
);

class HospitalDashboardService {
  Future<List<HospitalStats>> fetch({Map<String, dynamic>? query}) async {
    final url = Uri.parse(
      (kHospitalDashboardUrl.isNotEmpty
              ? kHospitalDashboardUrl
              : 'https://example.com/hospital-dashboard') +
          _toQuery(query),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final resp = await http.get(
        url,
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        final list = decoded is List
            ? decoded
            : (decoded is Map && decoded['data'] is List
                  ? decoded['data']
                  : []);
        return list
            .whereType<Map>()
            .map((m) => HospitalStats.fromJson(m.cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {
      // fall through to mock on any error
    }
    return _mock();
  }

  String _toQuery(Map<String, dynamic>? q) {
    if (q == null || q.isEmpty) return '';
    final entries = q.entries
        .where((e) => e.value != null && e.value.toString().isNotEmpty)
        .toList();
    if (entries.isEmpty) return '';
    return '?' +
        entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value.toString())}',
            )
            .join('&');
  }

  List<HospitalStats> _mock() {
    final data = <Map<String, dynamic>>[
      {
        'id': 'H001',
        'hospitalName': 'AARAV CARE',
        'zone': 'East',
        'salesValue': '₹22,246,406',
        'podValue': '₹23,616,925',
        'podCount': 74,
        'records': 74,
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': 'H002',
        'hospitalName': 'ANANT HOSPITAL',
        'zone': 'East',
        'salesValue': '₹20,614,049',
        'podValue': '₹21,928,149',
        'podCount': 76,
        'records': 76,
        'updated_at': DateTime.now().toIso8601String(),
      },
      {
        'id': 'H003',
        'hospitalName': 'ALFA MEDICARE',
        'zone': 'West',
        'salesValue': '₹19,873,218',
        'podValue': '₹21,200,039',
        'podCount': 72,
        'records': 72,
      },
      {
        'id': 'H004',
        'hospitalName': 'SUNRISE CLINIC',
        'zone': 'North',
        'salesValue': '₹17,360,496',
        'podValue': '₹18,907,874',
        'podCount': 64,
        'records': 64,
      },
      {
        'id': 'H005',
        'hospitalName': 'LOTUS HEALTH',
        'zone': 'South',
        'salesValue': '₹16,495,025',
        'podValue': '₹18,311,194',
        'podCount': 58,
        'records': 58,
      },
    ];
    return data.map((e) => HospitalStats.fromJson(e)).toList();
  }
}
