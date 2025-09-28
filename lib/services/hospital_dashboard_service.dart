import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zyduspod/config.dart';

class HospitalDashboardService {


  Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await http.get(
        Uri.parse('${API_BASE_URL}dashboard/overview'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      print(response.body);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch dashboard data');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('error: $e');
      // Return mock data for development
      return _getMockStats();
    }
  }

  Future<List<Map<String, dynamic>>> getRecentDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await http.get(
        Uri.parse('${API_BASE_URL}dashboard/documents/all?limit=10'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data'] ?? []);
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch documents');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('error: $e');
      // Return mock data for development
      return _getMockDocuments();
    }
  }

  Future<List<Map<String, dynamic>>> getAllDocuments({
    String? filter,
    String? searchQuery,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final queryParams = <String, String>{};
      if (filter != null && filter != 'All') {
        queryParams['type'] = filter;
      }
      if (searchQuery != null && searchQuery.isNotEmpty) {
        queryParams['search'] = searchQuery;
      }

      final uri = Uri.parse('${API_BASE_URL}/dashboard/documents/all').replace(
        queryParameters: queryParams,
      );

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data'] ?? []);
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch documents');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('error: $e');
      // Return mock data for development
      return _getMockDocuments();
    }
  }

  Map<String, dynamic> _getMockStats() {
    return {
      'total_documents': 0,
      'pod_count': 0,
      'grn_count': 0,
      'einvoice_count': 0,
      'pending_count': 0,
      'approved_count': 0,
      'rejected_count': 0,
      'processing_count': 0,
      'total_amount': 0,
      'monthly_uploads': 0,
      'weekly_uploads': 0,
    };
  }

  List<Map<String, dynamic>> _getMockDocuments() {
    // return [
    //   {
    //     'id': '1',
    //     'name': 'POD_2024_001.pdf',
    //     'type': 'POD',
    //     'status': 'Approved',
    //     'uploaded_at': '2024-01-15T10:30:00Z',
    //     'size': '2.4 MB',
    //     'stockist': 'ABC Medical Store',
    //     'hospital': 'City Hospital',
    //     'invoice_number': 'INV-2024-001',
    //     'amount': '₹15,000',
    //   },
    //   {
    //     'id': '2',
    //     'name': 'E-Invoice_2024_002.pdf',
    //     'type': 'E-INVOICE',
    //     'status': 'Pending',
    //     'uploaded_at': '2024-01-15T09:15:00Z',
    //     'size': '1.8 MB',
    //     'stockist': 'XYZ Pharmacy',
    //     'hospital': 'General Hospital',
    //     'invoice_number': 'INV-2024-002',
    //     'amount': '₹8,500',
    //   },
    //   {
    //     'id': '3',
    //     'name': 'GRN_2024_003.pdf',
    //     'type': 'GRN',
    //     'status': 'Approved',
    //     'uploaded_at': '2024-01-14T16:45:00Z',
    //     'size': '3.2 MB',
    //     'stockist': 'MediCare Store',
    //     'hospital': 'Central Hospital',
    //     'invoice_number': 'INV-2024-003',
    //     'amount': '₹22,000',
    //   },
    //   {
    //     'id': '4',
    //     'name': 'POD_2024_004.pdf',
    //     'type': 'POD',
    //     'status': 'Processing',
    //     'uploaded_at': '2024-01-14T14:20:00Z',
    //     'size': '2.1 MB',
    //     'stockist': 'Health Plus',
    //     'hospital': 'Metro Hospital',
    //     'invoice_number': 'INV-2024-004',
    //     'amount': '₹12,500',
    //   },
    //   {
    //     'id': '5',
    //     'name': 'E-Invoice_2024_005.pdf',
    //     'type': 'E-INVOICE',
    //     'status': 'Approved',
    //     'uploaded_at': '2024-01-14T11:30:00Z',
    //     'size': '1.9 MB',
    //     'stockist': 'Life Care',
    //     'hospital': 'Regional Hospital',
    //     'invoice_number': 'INV-2024-005',
    //     'amount': '₹9,800',
    //   },
    // ];
  
  return [];
  }
}
