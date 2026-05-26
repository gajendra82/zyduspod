import 'package:equatable/equatable.dart';

import 'package:zyduspod/Models/sales_dashboard_models.dart';

abstract class SalesDashboardState extends Equatable {
  const SalesDashboardState();

  @override
  List<Object?> get props => const [];
}

class SalesDashboardInitial extends SalesDashboardState {
  const SalesDashboardInitial();
}

/// First load with no prior data — drives the full skeleton.
class SalesDashboardLoading extends SalesDashboardState {
  const SalesDashboardLoading();
}

/// Everything fetched. Sub-section reloads (filter / leaderboard switch)
/// surface as flags on this state so partial skeletons can be shown without
/// dropping back to [SalesDashboardLoading].
class SalesDashboardLoaded extends SalesDashboardState {
  final SalesSummaryCards summary;
  final List<TrendPoint> trend;
  final List<TopPerformer> topPerformers;
  final TopPerformerType topPerformerType;
  final SalesDashboardFilters filters;
  final bool isRefreshing;
  final bool isLeaderboardLoading;

  const SalesDashboardLoaded({
    required this.summary,
    required this.trend,
    required this.topPerformers,
    required this.topPerformerType,
    required this.filters,
    this.isRefreshing = false,
    this.isLeaderboardLoading = false,
  });

  SalesDashboardLoaded copyWith({
    SalesSummaryCards? summary,
    List<TrendPoint>? trend,
    List<TopPerformer>? topPerformers,
    TopPerformerType? topPerformerType,
    SalesDashboardFilters? filters,
    bool? isRefreshing,
    bool? isLeaderboardLoading,
  }) {
    return SalesDashboardLoaded(
      summary: summary ?? this.summary,
      trend: trend ?? this.trend,
      topPerformers: topPerformers ?? this.topPerformers,
      topPerformerType: topPerformerType ?? this.topPerformerType,
      filters: filters ?? this.filters,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLeaderboardLoading: isLeaderboardLoading ?? this.isLeaderboardLoading,
    );
  }

  @override
  List<Object?> get props => [
        summary,
        trend,
        topPerformers,
        topPerformerType,
        filters,
        isRefreshing,
        isLeaderboardLoading,
      ];
}

class SalesDashboardError extends SalesDashboardState {
  final String message;
  final int? statusCode;
  const SalesDashboardError(this.message, {this.statusCode});

  @override
  List<Object?> get props => [message, statusCode];
}
