import '../../models/hospital_stats.dart';
import 'hospital_dashboard_event.dart';

class HospitalDashboardState {
  final bool loading;
  final String? error;
  final List<HospitalStats> all;
  final List<HospitalStats> filtered;
  final String search;
  final int minPercent;
  final HospitalSortBy sortBy;

  // Summary
  final double totalSales;
  final double totalPod;
  final double overallPercent;

  const HospitalDashboardState({
    required this.loading,
    required this.error,
    required this.all,
    required this.filtered,
    required this.search,
    required this.minPercent,
    required this.sortBy,
    required this.totalSales,
    required this.totalPod,
    required this.overallPercent,
  });

  factory HospitalDashboardState.initial() => const HospitalDashboardState(
    loading: false,
    error: null,
    all: [],
    filtered: [],
    search: '',
    minPercent: 0,
    sortBy: HospitalSortBy.salesDesc,
    totalSales: 0,
    totalPod: 0,
    overallPercent: 0,
  );

  HospitalDashboardState copyWith({
    bool? loading,
    String? error,
    List<HospitalStats>? all,
    List<HospitalStats>? filtered,
    String? search,
    int? minPercent,
    HospitalSortBy? sortBy,
    double? totalSales,
    double? totalPod,
    double? overallPercent,
    bool errorToNull = false,
  }) {
    return HospitalDashboardState(
      loading: loading ?? this.loading,
      error: errorToNull ? null : (error ?? this.error),
      all: all ?? this.all,
      filtered: filtered ?? this.filtered,
      search: search ?? this.search,
      minPercent: minPercent ?? this.minPercent,
      sortBy: sortBy ?? this.sortBy,
      totalSales: totalSales ?? this.totalSales,
      totalPod: totalPod ?? this.totalPod,
      overallPercent: overallPercent ?? this.overallPercent,
    );
  }
}
