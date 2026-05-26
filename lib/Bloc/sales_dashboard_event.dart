import 'package:equatable/equatable.dart';

import 'package:zyduspod/Models/sales_dashboard_models.dart';

abstract class SalesDashboardEvent extends Equatable {
  const SalesDashboardEvent();

  @override
  List<Object?> get props => const [];
}

/// Load (or reload) every section of the dashboard for the current filters.
class SalesDashboardLoadRequested extends SalesDashboardEvent {
  const SalesDashboardLoadRequested();
}

/// Pull-to-refresh — same as load but emits a refreshing flag on the state.
class SalesDashboardRefreshRequested extends SalesDashboardEvent {
  const SalesDashboardRefreshRequested();
}

/// Replace filters and refetch.
class SalesDashboardFiltersChanged extends SalesDashboardEvent {
  final SalesDashboardFilters filters;
  const SalesDashboardFiltersChanged(this.filters);

  @override
  List<Object?> get props => [filters];
}

/// Switch which leaderboard the Top Performers card is showing.
class SalesDashboardTopPerformerTypeChanged extends SalesDashboardEvent {
  final TopPerformerType type;
  const SalesDashboardTopPerformerTypeChanged(this.type);

  @override
  List<Object?> get props => [type];
}
