// DTOs for the Sales Analytics Dashboard. These mirror the JSON returned by
// the Laravel `Api\SalesDashboardApiController` endpoints introduced in
// Phase 1 of the Sales Analytics module:
//
//   GET /api/sales-dashboard/summary-cards
//   GET /api/sales-dashboard/target-achievement-trend
//   GET /api/sales-dashboard/top-performers
//
// Field names match the backend exactly — keep them in sync if the
// service contract changes.

class SalesSummaryCards {
  final double totalTargetAmount;
  final double netSalesAmount; // achievement
  final double achievementPercentage;
  final double gapToTarget;
  final double varianceAmount; // signed: positive when over-target
  final double growthPercentage; // YoY
  final double currentYearSales;
  final double lastYearSales;
  final double totalSalesAmount;
  final double totalReturnsAmount;
  final int activeKamsCount;
  final int activeHospitalsCount;
  final int activeStockistsCount;
  final int totalProductSalesQty;
  final int totalStatements;

  const SalesSummaryCards({
    required this.totalTargetAmount,
    required this.netSalesAmount,
    required this.achievementPercentage,
    required this.gapToTarget,
    required this.varianceAmount,
    required this.growthPercentage,
    required this.currentYearSales,
    required this.lastYearSales,
    required this.totalSalesAmount,
    required this.totalReturnsAmount,
    required this.activeKamsCount,
    required this.activeHospitalsCount,
    required this.activeStockistsCount,
    required this.totalProductSalesQty,
    required this.totalStatements,
  });

  factory SalesSummaryCards.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v ?? 0) is num ? (v as num).toDouble() : 0.0;
    int i(dynamic v) => (v ?? 0) is num ? (v as num).toInt() : 0;
    return SalesSummaryCards(
      totalTargetAmount: d(json['total_target_amount']),
      netSalesAmount: d(json['net_sales_amount']),
      achievementPercentage: d(json['achievement_percentage']),
      gapToTarget: d(json['gap_to_target']),
      varianceAmount: d(json['variance_amount']),
      growthPercentage: d(json['growth_percentage']),
      currentYearSales: d(json['current_year_sales']),
      lastYearSales: d(json['last_year_sales']),
      totalSalesAmount: d(json['total_sales_amount']),
      totalReturnsAmount: d(json['total_returns_amount']),
      activeKamsCount: i(json['active_kams_count']),
      activeHospitalsCount: i(json['active_hospitals_count']),
      activeStockistsCount: i(json['active_stockists_count']),
      totalProductSalesQty: i(json['total_product_sales_qty']),
      totalStatements: i(json['total_statements']),
    );
  }

  static const empty = SalesSummaryCards(
    totalTargetAmount: 0,
    netSalesAmount: 0,
    achievementPercentage: 0,
    gapToTarget: 0,
    varianceAmount: 0,
    growthPercentage: 0,
    currentYearSales: 0,
    lastYearSales: 0,
    totalSalesAmount: 0,
    totalReturnsAmount: 0,
    activeKamsCount: 0,
    activeHospitalsCount: 0,
    activeStockistsCount: 0,
    totalProductSalesQty: 0,
    totalStatements: 0,
  );
}

class TrendPoint {
  final String month; // YYYY-MM
  final String label; // 'Aug-25'
  final double target;
  final double achievement;
  final double achievementPct;

  const TrendPoint({
    required this.month,
    required this.label,
    required this.target,
    required this.achievement,
    required this.achievementPct,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v ?? 0) is num ? (v as num).toDouble() : 0.0;
    return TrendPoint(
      month: (json['month'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      target: d(json['target']),
      achievement: d(json['achievement']),
      achievementPct: d(json['achievement_pct']),
    );
  }
}

class TopPerformer {
  final String? id;
  final String? code;
  final String name;
  final double achievement;
  final double target;
  final double achievementPct;

  const TopPerformer({
    required this.id,
    required this.code,
    required this.name,
    required this.achievement,
    required this.target,
    required this.achievementPct,
  });

  /// Positive "still to achieve" amount, clamped to zero when the performer
  /// is already above target. Negative gap (over-achievement) is reported as
  /// 0 because the UI tile is meant to highlight remaining work.
  double get targetGap => target > achievement ? (target - achievement) : 0.0;

  factory TopPerformer.fromJson(Map<String, dynamic> json) {
    double d(dynamic v) => (v ?? 0) is num ? (v as num).toDouble() : 0.0;
    return TopPerformer(
      id: json['id']?.toString(),
      code: json['code']?.toString(),
      name: (json['name'] ?? '(unknown)').toString(),
      achievement: d(json['achievement']),
      target: d(json['target']),
      achievementPct: d(json['achievement_pct']),
    );
  }
}

/// Filters applied across all sales-dashboard requests. Mirrors the keys
/// accepted by `SalesDashboardController::getFiltersForRequest`.
class SalesDashboardFilters {
  final String? dateFrom; // YYYY-MM-DD
  final String? dateTo;
  final String? zone;
  final String? empId;
  final int? stockistId;
  final int? hospitalId;
  final int? year;

  const SalesDashboardFilters({
    this.dateFrom,
    this.dateTo,
    this.zone,
    this.empId,
    this.stockistId,
    this.hospitalId,
    this.year,
  });

  Map<String, String> toQuery() {
    final m = <String, String>{};
    if (dateFrom != null && dateFrom!.isNotEmpty) m['date_from'] = dateFrom!;
    if (dateTo != null && dateTo!.isNotEmpty) m['date_to'] = dateTo!;
    if (zone != null && zone!.isNotEmpty) m['zone'] = zone!;
    if (empId != null && empId!.isNotEmpty) m['emp_id'] = empId!;
    if (stockistId != null) m['stockist_id'] = stockistId!.toString();
    if (hospitalId != null) m['hospital_id'] = hospitalId!.toString();
    if (year != null) m['year'] = year!.toString();
    return m;
  }

  SalesDashboardFilters copyWith({
    String? dateFrom,
    String? dateTo,
    String? zone,
    String? empId,
    int? stockistId,
    int? hospitalId,
    int? year,
    bool clearZone = false,
    bool clearEmp = false,
    bool clearStockist = false,
    bool clearHospital = false,
  }) {
    return SalesDashboardFilters(
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      zone: clearZone ? null : (zone ?? this.zone),
      empId: clearEmp ? null : (empId ?? this.empId),
      stockistId: clearStockist ? null : (stockistId ?? this.stockistId),
      hospitalId: clearHospital ? null : (hospitalId ?? this.hospitalId),
      year: year ?? this.year,
    );
  }

  static const empty = SalesDashboardFilters();
}

/// Identifiers for the three leaderboards the Sales Analytics widget
/// supports. Managers/HQs/Regions/Zones/Stockists were dropped from the
/// dashboard dropdown — they're still in the backend `switch` history but
/// the API now returns an empty page for those types.
enum TopPerformerType {
  kams,
  hospitals,
  products;

  String get apiValue => name;

  String get label {
    switch (this) {
      case TopPerformerType.kams:
        return 'All KAMs';
      case TopPerformerType.hospitals:
        return 'All Hospitals';
      case TopPerformerType.products:
        return 'All Products (Brands)';
    }
  }

  String get searchPlaceholder {
    switch (this) {
      case TopPerformerType.kams:
        return 'Search KAM...';
      case TopPerformerType.hospitals:
        return 'Search Hospital...';
      case TopPerformerType.products:
        return 'Search Brand/Product...';
    }
  }
}

/// One page of leaderboard rows + the cursor needed for infinite scroll.
class PaginatedPerformers {
  final List<TopPerformer> data;
  final int total;
  final int page;
  final int limit;
  final bool hasMore;

  const PaginatedPerformers({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.hasMore,
  });

  factory PaginatedPerformers.fromJson(Map<String, dynamic> json) {
    int i(dynamic v) => (v is num) ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0;
    final raw = (json['data'] as List?) ?? const [];
    return PaginatedPerformers(
      data: raw
          .whereType<Map>()
          .map((m) => TopPerformer.fromJson(m.cast<String, dynamic>()))
          .toList(growable: false),
      total: i(json['total']),
      page: i(json['page']),
      limit: i(json['limit']),
      hasMore: json['has_more'] == true,
    );
  }

  static const empty = PaginatedPerformers(
    data: [],
    total: 0,
    page: 1,
    limit: 20,
    hasMore: false,
  );
}
