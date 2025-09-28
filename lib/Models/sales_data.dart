class SalesData {
  final String id;
  final String hospitalName;
  final String stockistName;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double totalAmount;
  final String date;
  final String status;
  final String invoiceNumber;
  final String documentType;
  final String? notes;

  SalesData({
    required this.id,
    required this.hospitalName,
    required this.stockistName,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    required this.date,
    required this.status,
    required this.invoiceNumber,
    required this.documentType,
    this.notes,
  });

  factory SalesData.fromJson(Map<String, dynamic> json) {
    return SalesData(
      id: json['transaction_id']?.toString() ?? json['id']?.toString() ?? '',
      hospitalName: json['hospital_name'] ?? json['hospitalName'] ?? '',
      stockistName: json['stockist_name'] ?? json['stockistName'] ?? '',
      productName: json['product_name'] ?? json['productName'] ?? '',
      quantity: (json['quantity'] ?? 0).toDouble(),
      unitPrice: (json['unit_price'] ?? json['unitPrice'] ?? 0).toDouble(),
      totalAmount: (json['total_amount'] ?? json['totalAmount'] ?? 0).toDouble(),
      date: json['date'] ?? '',
      status: json['status'] ?? '',
      invoiceNumber: json['invoice_number'] ?? json['invoiceNumber'] ?? '',
      documentType: json['document_type'] ?? json['documentType'] ?? '',
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hospital_name': hospitalName,
      'stockist_name': stockistName,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_amount': totalAmount,
      'date': date,
      'status': status,
      'invoice_number': invoiceNumber,
      'document_type': documentType,
      'notes': notes,
    };
  }
}

class HospitalSalesSummary {
  final String hospitalId;
  final String hospitalName;
  final String? hospitalCode;
  final String? location;
  final Map<String, dynamic>? contactInfo;
  final int totalTransactions;
  final double totalAmount;
  final double averageTransactionValue;
  final String topProduct;
  final String lastTransactionDate;
  final List<SalesData> recentTransactions;
  
  // Enhanced fields from API
  final int? performanceScore;
  final String? performanceGrade;
  final double? growthRate;
  final String? growthPeriod;
  final bool? isHighPerformer;
  final Map<String, dynamic>? podVsSalesAnalysis;
  final Map<String, dynamic>? historicalPerformance;
  final List<Map<String, dynamic>>? productBreakdown;
  final Map<String, dynamic>? metrics;

  HospitalSalesSummary({
    required this.hospitalId,
    required this.hospitalName,
    this.hospitalCode,
    this.location,
    this.contactInfo,
    required this.totalTransactions,
    required this.totalAmount,
    required this.averageTransactionValue,
    required this.topProduct,
    required this.lastTransactionDate,
    required this.recentTransactions,
    this.performanceScore,
    this.performanceGrade,
    this.growthRate,
    this.growthPeriod,
    this.isHighPerformer,
    this.podVsSalesAnalysis,
    this.historicalPerformance,
    this.productBreakdown,
    this.metrics,
  });

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  factory HospitalSalesSummary.fromJson(Map<String, dynamic> json) {
    return HospitalSalesSummary(
      hospitalId: json['hospital_id']?.toString() ?? '',
      hospitalName: json['hospital_name'] ?? json['hospitalName'] ?? '',
      hospitalCode: json['hospital_code'],
      location: json['location'],
      contactInfo: json['contact_info'],
      totalTransactions: _parseInt(json['total_transactions'] ?? json['totalTransactions']),
      totalAmount: _parseDouble(json['total_amount'] ?? json['totalAmount']),
      averageTransactionValue: _parseDouble(json['average_transaction_value'] ?? json['averageTransactionValue']),
      topProduct: json['top_product'] ?? json['topProduct'] ?? '',
      lastTransactionDate: json['last_transaction_date'] ?? json['lastTransactionDate'] ?? '',
      recentTransactions: (json['recent_transactions'] ?? json['recentTransactions'] ?? [])
          .map<SalesData>((item) => SalesData.fromJson(item))
          .toList(),
      performanceScore: _parseInt(json['performance_score']),
      performanceGrade: json['performance_grade'],
      growthRate: _parseDouble(json['growth_rate']),
      growthPeriod: json['growth_period'],
      isHighPerformer: json['is_high_performer'],
      podVsSalesAnalysis: json['pod_vs_sales_analysis'],
      historicalPerformance: json['historical_performance'],
      productBreakdown: json['product_breakdown'] != null 
          ? List<Map<String, dynamic>>.from(json['product_breakdown'])
          : null,
      metrics: json['metrics'],
    );
  }
}

class StockistSalesSummary {
  final String stockistId;
  final String stockistName;
  final int totalTransactions;
  final double totalAmount;
  final double averageTransactionValue;
  final String topProduct;
  final String lastTransactionDate;
  final List<SalesData> recentTransactions;

  StockistSalesSummary({
    required this.stockistId,
    required this.stockistName,
    required this.totalTransactions,
    required this.totalAmount,
    required this.averageTransactionValue,
    required this.topProduct,
    required this.lastTransactionDate,
    required this.recentTransactions,
  });

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  factory StockistSalesSummary.fromJson(Map<String, dynamic> json) {
    return StockistSalesSummary(
      stockistId: json['stockist_id']?.toString() ?? '',
      stockistName: json['stockist_name'] ?? json['stockistName'] ?? '',
      totalTransactions: _parseInt(json['total_transactions'] ?? json['totalTransactions']),
      totalAmount: _parseDouble(json['total_amount'] ?? json['totalAmount']),
      averageTransactionValue: _parseDouble(json['average_transaction_value'] ?? json['averageTransactionValue']),
      topProduct: json['top_product'] ?? json['topProduct'] ?? '',
      lastTransactionDate: json['last_transaction_date'] ?? json['lastTransactionDate'] ?? '',
      recentTransactions: (json['recent_transactions'] ?? json['recentTransactions'] ?? [])
          .map<SalesData>((item) => SalesData.fromJson(item))
          .toList(),
    );
  }
}

class SalesFilter {
  final String? hospitalId;
  final String? stockistId;
  final String? productName;
  final String? status;
  final String? documentType;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? minAmount;
  final double? maxAmount;

  SalesFilter({
    this.hospitalId,
    this.stockistId,
    this.productName,
    this.status,
    this.documentType,
    this.startDate,
    this.endDate,
    this.minAmount,
    this.maxAmount,
  });

  Map<String, dynamic> toQueryParams() {
    final params = <String, String>{};
    
    if (hospitalId != null) params['hospital_id'] = hospitalId!;
    if (stockistId != null) params['stockist_id'] = stockistId!;
    if (productName != null && productName!.isNotEmpty) params['product_name'] = productName!;
    if (status != null && status!.isNotEmpty) params['status'] = status!;
    if (documentType != null && documentType!.isNotEmpty) params['document_type'] = documentType!;
    if (startDate != null) params['start_date'] = startDate!.toIso8601String().split('T')[0];
    if (endDate != null) params['end_date'] = endDate!.toIso8601String().split('T')[0];
    if (minAmount != null) params['min_amount'] = minAmount!.toString();
    if (maxAmount != null) params['max_amount'] = maxAmount!.toString();
    
    return params;
  }
}
