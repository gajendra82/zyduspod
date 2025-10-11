import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:zyduspod/config.dart';
import 'package:zyduspod/Models/sales_data.dart';
import 'package:zyduspod/services/api_client.dart';

class SalesService {
  final ApiClient _apiClient = ApiClient();

  Future<List<SalesData>> getSalesData({SalesFilter? filter}) async {
    try {
      print('${API_BASE_URL}sales/data');
      final queryParams = filter?.toQueryParams() ?? <String, String>{};
      final uri = Uri.parse('${API_BASE_URL}sales/data').replace(
        queryParameters: queryParams,
      );

      final response = await _apiClient.get(uri);
      
      print('response: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['sales_data'] ?? data['data'] ?? [])
            .map<SalesData>((item) => SalesData.fromJson(item))
            .toList();
      } else {
        print('error: ${response.body}');
        // Return mock data for development
        return _getMockSalesData();
      }
    } catch (e) { 
      print('error: $e');
      // Return mock data for development
      return _getMockSalesData();
    }
  }

  Future<List<HospitalSalesSummary>> getHospitalSalesSummaries({String? dateFrom, String? dateTo}) async {
    try {
      final queryParams = <String, String>{};
      if (dateFrom != null && dateFrom.isNotEmpty) {
        queryParams['date_from'] = dateFrom;
      }
      if (dateTo != null && dateTo.isNotEmpty) {
        queryParams['date_to'] = dateTo;
      }
      
      final uri = Uri.parse('${API_BASE_URL}dashboard/hospital-sales').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      
      final response = await _apiClient.get(
        uri,
        headers: {
          'Accept': 'application/json',
        },
      );
      
      print('response: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return (data['data'] ?? [])
              .map<HospitalSalesSummary>((item) => HospitalSalesSummary.fromJson(item))
              .toList();
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch hospital sales');
        }
      } else {
        print('error: ${response.body}');
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('error: $e');
      // Return mock data for development
      return _getMockHospitalSummaries();
    }
  }

  Future<List<StockistSalesSummary>> getStockistSalesSummaries() async {
    try {
      final response = await _apiClient.get(
        Uri.parse('${API_BASE_URL}sales/stockist-summaries'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['stockist_summaries'] ?? data['data'] ?? [])
            .map<StockistSalesSummary>((item) => StockistSalesSummary.fromJson(item))
            .toList();
      } else {
        // Return mock data for development
        return _getMockStockistSummaries();
      }
    } catch (e) {
      // Return mock data for development
      return _getMockStockistSummaries();
    }
  }

  Future<Map<String, dynamic>> getSalesSummaryStats() async {
    try {
      final response = await _apiClient.get(
        Uri.parse('${API_BASE_URL}/dashboard/analytics'),
        headers: {
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data']['summary_stats'] ?? {};
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch analytics');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      // Return mock data for development
      return _getMockSummaryStats();
    }
  }

  Future<void> uploadSalesData(Map<String, dynamic> salesData) async {
    final response = await _apiClient.post(
      Uri.parse('${API_BASE_URL}sales/upload'),
      body: jsonEncode(salesData),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to upload sales data: ${response.statusCode}');
    }
  }

  Future<String> exportSalesData({
    SalesFilter? filter,
    String format = 'csv',
  }) async {
    try {
      final queryParams = filter?.toQueryParams() ?? <String, String>{};
      queryParams['format'] = format;
      
      final uri = Uri.parse('${API_BASE_URL}sales/export').replace(
        queryParameters: queryParams,
      );

      final response = await _apiClient.get(uri);

      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final fileName = 'sales_export_${DateTime.now().millisecondsSinceEpoch}.$format';
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      } else {
        throw Exception('Failed to export sales data: ${response.statusCode}');
      }
    } catch (e) {
      // For development, create a mock export file
      return await _createMockExportFile(format);
    }
  }

  // Mock data methods for development
  List<SalesData> _getMockSalesData() {
    // return [
    //   SalesData(
    //     id: '1',
    //     hospitalName: 'City Hospital',
    //     stockistName: 'ABC Medical Store',
    //     productName: 'Medicine A',
    //     quantity: 100,
    //     unitPrice: 50.0,
    //     totalAmount: 5000.0,
    //     date: '2024-01-15',
    //     status: 'Completed',
    //     invoiceNumber: 'INV-001',
    //     documentType: 'POD',
    //   ),
    //   SalesData(
    //     id: '2',
    //     hospitalName: 'General Hospital',
    //     stockistName: 'XYZ Pharmacy',
    //     productName: 'Medicine B',
    //     quantity: 50,
    //     unitPrice: 75.0,
    //     totalAmount: 3750.0,
    //     date: '2024-01-14',
    //     status: 'Pending',
    //     invoiceNumber: 'INV-002',
    //     documentType: 'GRN',
    //   ),
    //   SalesData(
    //     id: '3',
    //     hospitalName: 'Central Hospital',
    //     stockistName: 'MediCare Store',
    //     productName: 'Medicine C',
    //     quantity: 200,
    //     unitPrice: 25.0,
    //     totalAmount: 5000.0,
    //     date: '2024-01-13',
    //     status: 'Completed',
    //     invoiceNumber: 'INV-003',
    //     documentType: 'E-INVOICE',
    //   ),
    // ];
    return [];
  }

  List<HospitalSalesSummary> _getMockHospitalSummaries() {
    // return [
    //   HospitalSalesSummary(
    //     hospitalId: '1',
    //     hospitalName: 'City Hospital',
    //     totalTransactions: 45,
    //     totalAmount: 125000.0,
    //     averageTransactionValue: 2777.78,
    //     topProduct: 'Medicine A',
    //     lastTransactionDate: '2024-01-15',
    //     recentTransactions: _getMockSalesData().take(2).toList(),
    //   ),
    //   HospitalSalesSummary(
    //     hospitalId: '2',
    //     hospitalName: 'General Hospital',
    //     totalTransactions: 32,
    //     totalAmount: 89000.0,
    //     averageTransactionValue: 2781.25,
    //     topProduct: 'Medicine B',
    //     lastTransactionDate: '2024-01-14',
    //     recentTransactions: _getMockSalesData().skip(1).take(2).toList(),
    //   ),
    // ];
    return [];
  }

  List<StockistSalesSummary> _getMockStockistSummaries() {
    // return [
      // StockistSalesSummary(
      //   stockistId: '1',
      //   stockistName: 'ABC Medical Store',
      //   totalTransactions: 28,
      //   totalAmount: 95000.0,
      //   averageTransactionValue: 3392.86,
      //   topProduct: 'Medicine A',
      //   lastTransactionDate: '2024-01-15',
      //   recentTransactions: _getMockSalesData().take(1).toList(),
      // ),
      // StockistSalesSummary(
      //   stockistId: '2',
      //   stockistName: 'XYZ Pharmacy',
      //   totalTransactions: 35,
      //   totalAmount: 110000.0,
      //   averageTransactionValue: 3142.86,
      //   topProduct: 'Medicine B',
      //   lastTransactionDate: '2024-01-14',
      //   recentTransactions: _getMockSalesData().skip(1).take(1).toList(),
      // ),
    // ]; 
    return [];
  }

  Map<String, dynamic> _getMockSummaryStats() {
    // return {
    //   'total_sales': 450000.0,
    //   'total_transactions': 156,
    //   'average_transaction_value': 2884.62,
    //   'top_hospital': 'City Hospital',
    //   'top_stockist': 'ABC Medical Store',
    //   'top_product': 'Medicine A',
    //   'monthly_growth': 12.5,
    //   'pending_transactions': 8,
    //   'completed_transactions': 148,
    // };
    return {};
  }

  Future<String> _createMockExportFile(String format) async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'sales_export_${DateTime.now().millisecondsSinceEpoch}.$format';
    final file = File('${directory.path}/$fileName');
    
    final mockData = _getMockSalesData();
    String content = '';
    
    if (format == 'csv') {
      content = 'ID,Hospital,Stockist,Product,Quantity,Unit Price,Total Amount,Date,Status,Invoice Number,Document Type\n';
      for (final sale in mockData) {
        content += '${sale.id},${sale.hospitalName},${sale.stockistName},${sale.productName},${sale.quantity},${sale.unitPrice},${sale.totalAmount},${sale.date},${sale.status},${sale.invoiceNumber},${sale.documentType}\n';
      }
    } else {
      content = jsonEncode(mockData.map((sale) => sale.toJson()).toList());
    }
    
    await file.writeAsString(content);
    return file.path;
  }
}
