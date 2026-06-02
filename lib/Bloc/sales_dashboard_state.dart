import 'package:equatable/equatable.dart';

import 'package:zydus_vistaar/Models/sales_dashboard_models.dart';

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
  /// Accumulated leaderboard rows across all loaded pages for the current
  /// (type, search) tuple. Cleared on type change, search change, or
  /// filter change.
  final List<TopPerformer> topPerformers;
  final TopPerformerType topPerformerType;
  /// Server-side total matching (hierarchy + search). Used for the
  /// "{visible.length} of {total}" label and to derive hasMore independently.
  final int topPerformersTotal;
  /// Active search string for the leaderboard, '' when no search applied.
  final String leaderboardSearch;
  /// 1-based page cursor: the next page to fetch is `currentPage + 1`.
  final int leaderboardPage;
  /// Whether the server reports more rows past the loaded set.
  final bool leaderboardHasMore;
  /// True only while an *append* fetch is in flight. The initial / search
  /// reset / type-switch fetch uses isLeaderboardLoading instead.
  final bool isLeaderboardLoadingMore;
  final SalesDashboardFilters filters;
  final bool isRefreshing;
  final bool isLeaderboardLoading;

  const SalesDashboardLoaded({
    required this.summary,
    required this.trend,
    required this.topPerformers,
    required this.topPerformerType,
    required this.filters,
    this.topPerformersTotal = 0,
    this.leaderboardSearch = '',
    this.leaderboardPage = 1,
    this.leaderboardHasMore = false,
    this.isLeaderboardLoadingMore = false,
    this.isRefreshing = false,
    this.isLeaderboardLoading = false,
  });

  SalesDashboardLoaded copyWith({
    SalesSummaryCards? summary,
    List<TrendPoint>? trend,
    List<TopPerformer>? topPerformers,
    TopPerformerType? topPerformerType,
    int? topPerformersTotal,
    String? leaderboardSearch,
    int? leaderboardPage,
    bool? leaderboardHasMore,
    bool? isLeaderboardLoadingMore,
    SalesDashboardFilters? filters,
    bool? isRefreshing,
    bool? isLeaderboardLoading,
  }) {
    return SalesDashboardLoaded(
      summary: summary ?? this.summary,
      trend: trend ?? this.trend,
      topPerformers: topPerformers ?? this.topPerformers,
      topPerformerType: topPerformerType ?? this.topPerformerType,
      topPerformersTotal: topPerformersTotal ?? this.topPerformersTotal,
      leaderboardSearch: leaderboardSearch ?? this.leaderboardSearch,
      leaderboardPage: leaderboardPage ?? this.leaderboardPage,
      leaderboardHasMore: leaderboardHasMore ?? this.leaderboardHasMore,
      isLeaderboardLoadingMore:
          isLeaderboardLoadingMore ?? this.isLeaderboardLoadingMore,
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
        topPerformersTotal,
        leaderboardSearch,
        leaderboardPage,
        leaderboardHasMore,
        isLeaderboardLoadingMore,
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
