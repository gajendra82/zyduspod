import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zyduspod/config.dart';
import 'package:zyduspod/Models/sales_dashboard_models.dart';

/// HTTP client for the Sales Analytics Dashboard endpoints.
///
/// The backend lives under /api/sales-dashboard/* — see
/// `Api\SalesDashboardApiController`. All requests honor the logged-in
/// user's hierarchy (a KAM only ever gets their own data back, a manager
/// gets their team, etc.), so this client does NOT add scoping params.
class SalesDashboardService {
  SalesDashboardService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path, Map<String, String> query) {
    return Uri.parse('${API_BASE_URL}sales-dashboard/$path')
        .replace(queryParameters: query.isEmpty ? null : query);
  }

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    return {
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<SalesSummaryCards> fetchSummaryCards(SalesDashboardFilters filters) async {
    final res = await _client
        .get(_uri('summary-cards', filters.toQuery()), headers: await _headers())
        .timeout(const Duration(seconds: 30));
    final body = _decode(res);
    return SalesSummaryCards.fromJson(body);
  }

  Future<List<TrendPoint>> fetchTrend(
    SalesDashboardFilters filters, {
    int months = 12,
  }) async {
    final query = {...filters.toQuery(), 'months': months.toString()};
    final res = await _client
        .get(_uri('target-achievement-trend', query), headers: await _headers())
        .timeout(const Duration(seconds: 30));
    final body = _decode(res);
    final list = (body['data'] as List? ?? const []);
    return list
        .whereType<Map<String, dynamic>>()
        .map(TrendPoint.fromJson)
        .toList(growable: false);
  }

  Future<List<TopPerformer>> fetchTopPerformers(
    SalesDashboardFilters filters, {
    TopPerformerType type = TopPerformerType.kams,
    int limit = 10,
  }) async {
    final query = {
      ...filters.toQuery(),
      'type': type.apiValue,
      'limit': limit.toString(),
    };
    final res = await _client
        .get(_uri('top-performers', query), headers: await _headers())
        .timeout(const Duration(seconds: 30));
    final body = _decode(res);
    final list = (body['data'] as List? ?? const []);
    return list
        .whereType<Map<String, dynamic>>()
        .map(TopPerformer.fromJson)
        .toList(growable: false);
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode == 401) {
      throw const SalesDashboardException('Session expired — please sign in again.', 401);
    }
    if (res.statusCode == 403) {
      throw const SalesDashboardException("You don't have access to the sales dashboard.", 403);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SalesDashboardException('Request failed (${res.statusCode}).', res.statusCode);
    }
    try {
      final raw = jsonDecode(res.body);
      if (raw is Map<String, dynamic>) return raw;
      throw const SalesDashboardException('Unexpected response shape.', 0);
    } on FormatException {
      throw const SalesDashboardException('Invalid JSON response.', 0);
    }
  }

  void dispose() => _client.close();
}

class SalesDashboardException implements Exception {
  final String message;
  final int statusCode;
  const SalesDashboardException(this.message, this.statusCode);

  @override
  String toString() => message;
}
