import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zyduspod/Bloc/sales_dashboard_event.dart';
import 'package:zyduspod/Bloc/sales_dashboard_state.dart';
import 'package:zyduspod/Models/sales_dashboard_models.dart';
import 'package:zyduspod/services/sales_dashboard_service.dart';

class SalesDashboardBloc extends Bloc<SalesDashboardEvent, SalesDashboardState> {
  SalesDashboardBloc(this._service) : super(const SalesDashboardInitial()) {
    on<SalesDashboardLoadRequested>(_onLoad);
    on<SalesDashboardRefreshRequested>(_onRefresh);
    on<SalesDashboardFiltersChanged>(_onFiltersChanged);
    on<SalesDashboardTopPerformerTypeChanged>(_onTopPerformerTypeChanged);
  }

  final SalesDashboardService _service;

  // Cached filters + leaderboard selection so refresh / filter-change events
  // can be processed without losing context.
  SalesDashboardFilters _filters = SalesDashboardFilters.empty;
  TopPerformerType _topType = TopPerformerType.kams;

  Future<void> _onLoad(
    SalesDashboardLoadRequested event,
    Emitter<SalesDashboardState> emit,
  ) async {
    emit(const SalesDashboardLoading());
    try {
      final results = await _fetchAll();
      emit(SalesDashboardLoaded(
        summary: results.$1,
        trend: results.$2,
        topPerformers: results.$3,
        topPerformerType: _topType,
        filters: _filters,
      ));
    } catch (e) {
      emit(_toError(e));
    }
  }

  Future<void> _onRefresh(
    SalesDashboardRefreshRequested event,
    Emitter<SalesDashboardState> emit,
  ) async {
    final current = state;
    if (current is! SalesDashboardLoaded) {
      add(const SalesDashboardLoadRequested());
      return;
    }
    emit(current.copyWith(isRefreshing: true));
    try {
      final results = await _fetchAll();
      emit(current.copyWith(
        summary: results.$1,
        trend: results.$2,
        topPerformers: results.$3,
        isRefreshing: false,
      ));
    } catch (e) {
      emit(_toError(e));
    }
  }

  Future<void> _onFiltersChanged(
    SalesDashboardFiltersChanged event,
    Emitter<SalesDashboardState> emit,
  ) async {
    _filters = event.filters;
    // Treat filter changes as a refresh so the user keeps seeing the old
    // numbers (greyed out) until the new ones arrive — better than a flash
    // back to the skeleton.
    final current = state;
    if (current is SalesDashboardLoaded) {
      emit(current.copyWith(filters: _filters, isRefreshing: true));
    } else {
      emit(const SalesDashboardLoading());
    }
    try {
      final results = await _fetchAll();
      emit(SalesDashboardLoaded(
        summary: results.$1,
        trend: results.$2,
        topPerformers: results.$3,
        topPerformerType: _topType,
        filters: _filters,
      ));
    } catch (e) {
      emit(_toError(e));
    }
  }

  Future<void> _onTopPerformerTypeChanged(
    SalesDashboardTopPerformerTypeChanged event,
    Emitter<SalesDashboardState> emit,
  ) async {
    _topType = event.type;
    final current = state;
    if (current is! SalesDashboardLoaded) return;
    emit(current.copyWith(
      topPerformerType: _topType,
      isLeaderboardLoading: true,
    ));
    try {
      final leaders = await _service.fetchTopPerformers(_filters, type: _topType);
      emit(current.copyWith(
        topPerformers: leaders,
        topPerformerType: _topType,
        isLeaderboardLoading: false,
      ));
    } catch (e) {
      emit(_toError(e));
    }
  }

  Future<(SalesSummaryCards, List<TrendPoint>, List<TopPerformer>)> _fetchAll() async {
    // Fire all three requests in parallel — the backend serves them
    // independently, so total latency is bounded by the slowest of the three.
    final results = await Future.wait([
      _service.fetchSummaryCards(_filters),
      _service.fetchTrend(_filters),
      _service.fetchTopPerformers(_filters, type: _topType),
    ]);
    return (
      results[0] as SalesSummaryCards,
      results[1] as List<TrendPoint>,
      results[2] as List<TopPerformer>,
    );
  }

  SalesDashboardError _toError(Object e) {
    if (e is SalesDashboardException) {
      return SalesDashboardError(e.message, statusCode: e.statusCode);
    }
    return SalesDashboardError(e.toString());
  }

  @override
  Future<void> close() {
    _service.dispose();
    return super.close();
  }
}
