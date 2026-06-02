import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:zydus_vistaar/config.dart';
import 'package:zydus_vistaar/services/api_client.dart';
import 'package:zydus_vistaar/Models/batch_model.dart';

class BatchService {
  final ApiClient _apiClient = ApiClient();

  Future<BatchListResponse> fetchBatches({int page = 1}) async {
    final uri = Uri.parse('${API_BATCHES_URL}?page=$page');
    final http.Response response = await _apiClient.get(uri);
    print('Batches response: ${response.body}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load batches (${response.statusCode})');
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid response format: expected Map');
      }
      return BatchListResponse.fromJson(decoded);
    } catch (e) {
      print('Error parsing batches response: $e');
      print('Response body: ${response.body}');
      rethrow;
    }
  }

  Future<Batch> fetchBatchById(int batchId) async {
    final uri = Uri.parse('$API_BATCHES_URL/$batchId');
    final http.Response response = await _apiClient.get(uri);
    print('Batch details response: ${response.body}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load batch details (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    // Handle both single object and wrapped in data
    final batchData = decoded['data'] as Map<String, dynamic>? ?? decoded;
    return Batch.fromJson(batchData);
  }
}

