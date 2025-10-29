import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:zyduspod/config.dart';
import 'package:zyduspod/services/api_client.dart';
import 'package:zyduspod/Models/batch_model.dart';

class BatchService {
  final ApiClient _apiClient = ApiClient();

  Future<BatchListResponse> fetchBatches({int page = 1}) async {
    final uri = Uri.parse('${API_BATCHES_URL}?page=$page');
    final http.Response response = await _apiClient.get(uri);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load batches (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return BatchListResponse.fromJson(decoded);
  }

  Future<Batch> fetchBatchById(int batchId) async {
    final uri = Uri.parse('$API_BATCHES_URL/$batchId');
    final http.Response response = await _apiClient.get(uri);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load batch details (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    // Handle both single object and wrapped in data
    final batchData = decoded['data'] as Map<String, dynamic>? ?? decoded;
    return Batch.fromJson(batchData);
  }
}

