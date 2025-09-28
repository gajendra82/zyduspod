import 'package:equatable/equatable.dart';

abstract class HospitalDashboardState extends Equatable {
  const HospitalDashboardState();

  @override
  List<Object?> get props => [];
}

class HospitalDashboardInitial extends HospitalDashboardState {
  const HospitalDashboardInitial();
}

class HospitalDashboardLoading extends HospitalDashboardState {
  const HospitalDashboardLoading();
}

class HospitalDashboardLoaded extends HospitalDashboardState {
  final Map<String, dynamic> dashboardData;
  final List<Map<String, dynamic>> recentDocuments;
  final String? selectedFilter;
  final String searchQuery;
  final bool isRefreshing;

  const HospitalDashboardLoaded({
    required this.dashboardData,
    required this.recentDocuments,
    this.selectedFilter,
    this.searchQuery = '',
    this.isRefreshing = false,
  });

  @override
  List<Object?> get props => [
        dashboardData,
        recentDocuments,
        selectedFilter,
        searchQuery,
        isRefreshing,
      ];

  HospitalDashboardLoaded copyWith({
    Map<String, dynamic>? dashboardData,
    List<Map<String, dynamic>>? recentDocuments,
    String? selectedFilter,
    String? searchQuery,
    bool? isRefreshing,
  }) {
    return HospitalDashboardLoaded(
      dashboardData: dashboardData ?? this.dashboardData,
      recentDocuments: recentDocuments ?? this.recentDocuments,
      selectedFilter: selectedFilter ?? this.selectedFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

class HospitalDashboardError extends HospitalDashboardState {
  final String message;
  final String? errorCode;

  const HospitalDashboardError({
    required this.message,
    this.errorCode,
  });

  @override
  List<Object?> get props => [message, errorCode];
}
