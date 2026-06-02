import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zydus_vistaar/Bloc/sales_dashboard_event.dart';
import 'package:zydus_vistaar/Bloc/sales_dashboard_state.dart';
import 'package:zydus_vistaar/Models/sales_dashboard_models.dart';
import 'package:zydus_vistaar/services/sales_dashboard_service.dart';

class SalesDashboardBloc extends Bloc<SalesDashboardEvent, SalesDashboardState> {
  SalesDashboardBloc(this._service) : super(const SalesDashboardInitial()) {
    on<SalesDashboardLoadRequested>(_onLoad);
    on<SalesDashboardRefreshRequested>(_onRefresh);
    on<SalesDashboardFiltersChanged>(_onFiltersChanged);
    on<SalesDashboardTopPerformerTypeChanged>(_onTopPerformerTypeChanged);
    on<SalesDashboardLeaderboardSearchChanged>(_onLeaderboardSearchChanged);
    on<SalesDashboardLeaderboardLoadMoreRequested>(_onLeaderboardLoadMore);
  }

  final SalesDashboardService _service;

  // Cached filters + leaderboard selection so refresh / filter-change events
  // can be processed without losing context.
  SalesDashboardFilters _filters = SalesDashboardFilters.empty;
  TopPerformerType _topType = TopPerformerType.kams;
  String _search = '';
  static const int _pageSize = 20;

  Future<void> _onLoad(
    SalesDashboardLoadRequested event,
    Emitter<SalesDashboardState> emit,
  ) async {
    emit(const SalesDashboardLoading());
    try {
      final results = await _fetchAll();
      emit(_buildLoaded(results));
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
      emit(_buildLoaded(results, isRefreshing: false));
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
    // back to the skeleton. Also resets leaderboard pagination — the new
    // window can change which rows exist.
    _search = '';
    final current = state;
    if (current is SalesDashboardLoaded) {
      emit(current.copyWith(filters: _filters, isRefreshing: true));
    } else {
      emit(const SalesDashboardLoading());
    }
    try {
      final results = await _fetchAll();
      emit(_buildLoaded(results));
    } catch (e) {
      emit(_toError(e));
    }
  }

  Future<void> _onTopPerformerTypeChanged(
    SalesDashboardTopPerformerTypeChanged event,
    Emitter<SalesDashboardState> emit,
  ) async {
    _topType = event.type;
    _search = '';
    final current = state;
    if (current is! SalesDashboardLoaded) return;
    // Optimistic UI: clear the rows + show the skeleton while page 1 of
    // the new type loads.
    emit(current.copyWith(
      topPerformerType: _topType,
      topPerformers: const [],
      topPerformersTotal: 0,
      leaderboardSearch: '',
      leaderboardPage: 1,
      leaderboardHasMore: false,
      isLeaderboardLoading: true,
    ));
    try {
      final paged = await _service.fetchTopPerformers(
        _filters,
        type: _topType,
        limit: _pageSize,
        page: 1,
        search: _search,
      );
      emit(current.copyWith(
        topPerformerType: _topType,
        topPerformers: paged.data,
        topPerformersTotal: paged.total,
        leaderboardSearch: '',
        leaderboardPage: paged.page,
        leaderboardHasMore: paged.hasMore,
        isLeaderboardLoading: false,
      ));
    } catch (e) {
      emit(_toError(e));
    }
  }

  Future<void> _onLeaderboardSearchChanged(
    SalesDashboardLeaderboardSearchChanged event,
    Emitter<SalesDashboardState> emit,
  ) async {
    _search = event.query;
    final current = state;
    if (current is! SalesDashboardLoaded) return;

    // Wait for at least 2 chars before hitting the backend. A 1-char
    // query on the products tab matches a huge fraction of brands and
    // has historically blown the request timeout — the proxy closes
    // the connection before PHP can respond and the user sees
    // "Connection closed before full header was received". Keep the
    // typed value in state so the text field doesn't jump, but DO NOT
    // wipe the current list or fire the fetch until the query is
    // either cleared (length 0 → reload) or ≥ 2 chars (real filter).
    final trimmed = _search.trim();
    if (trimmed.isNotEmpty && trimmed.length < 2) {
      emit(current.copyWith(leaderboardSearch: _search));
      return;
    }

    emit(current.copyWith(
      leaderboardSearch: _search,
      // Replace the list during a search reset rather than greying it
      // out — search results often have nothing in common with the
      // previous slice and stale rows look broken.
      topPerformers: const [],
      topPerformersTotal: 0,
      leaderboardPage: 1,
      leaderboardHasMore: false,
      isLeaderboardLoading: true,
    ));
    try {
      final paged = await _service.fetchTopPerformers(
        _filters,
        type: _topType,
        limit: _pageSize,
        page: 1,
        search: _search,
      );
      emit(current.copyWith(
        topPerformers: paged.data,
        topPerformersTotal: paged.total,
        leaderboardSearch: _search,
        leaderboardPage: paged.page,
        leaderboardHasMore: paged.hasMore,
        isLeaderboardLoading: false,
      ));
    } catch (e) {
      emit(_toError(e));
    }
  }

  Future<void> _onLeaderboardLoadMore(
    SalesDashboardLeaderboardLoadMoreRequested event,
    Emitter<SalesDashboardState> emit,
  ) async {
    final current = state;
    if (current is! SalesDashboardLoaded) return;
    if (!current.leaderboardHasMore) return;
    if (current.isLeaderboardLoadingMore) return;
    if (current.isLeaderboardLoading) return;

    final nextPage = current.leaderboardPage + 1;
    emit(current.copyWith(isLeaderboardLoadingMore: true));
    try {
      final paged = await _service.fetchTopPerformers(
        _filters,
        type: _topType,
        limit: _pageSize,
        page: nextPage,
        search: _search,
      );
      // Append. If the user changed search/type during the in-flight
      // request, the BLoC's _search / _topType have already moved on, but
      // the state's leaderboardSearch / topPerformerType still reflect
      // the page-1 snapshot — guard against that by re-reading from
      // current and bailing if they no longer match.
      if (current.leaderboardSearch != _search ||
          current.topPerformerType != _topType) {
        emit(current.copyWith(isLeaderboardLoadingMore: false));
        return;
      }
      emit(current.copyWith(
        topPerformers: [...current.topPerformers, ...paged.data],
        topPerformersTotal: paged.total,
        leaderboardPage: paged.page,
        leaderboardHasMore: paged.hasMore,
        isLeaderboardLoadingMore: false,
      ));
    } catch (e) {
      // Swallow load-more failures into a clean isLoadingMore=false rather
      // than tipping the entire screen into the error state — the user
      // already has page 1 visible and a retry is just another scroll.
      emit(current.copyWith(isLeaderboardLoadingMore: false));
    }
  }

  Future<(SalesSummaryCards, List<TrendPoint>, PaginatedPerformers)> _fetchAll() async {
    final results = await Future.wait([
      _service.fetchSummaryCards(_filters),
      _service.fetchTrend(_filters),
      _service.fetchTopPerformers(
        _filters,
        type: _topType,
        limit: _pageSize,
        page: 1,
        search: _search,
      ),
    ]);
    return (
      results[0] as SalesSummaryCards,
      results[1] as List<TrendPoint>,
      results[2] as PaginatedPerformers,
    );
  }

  SalesDashboardLoaded _buildLoaded(
    (SalesSummaryCards, List<TrendPoint>, PaginatedPerformers) results, {
    bool isRefreshing = false,
  }) {
    final (summary, trend, paged) = results;
    return SalesDashboardLoaded(
      summary: summary,
      trend: trend,
      topPerformers: paged.data,
      topPerformerType: _topType,
      topPerformersTotal: paged.total,
      leaderboardSearch: _search,
      leaderboardPage: paged.page,
      leaderboardHasMore: paged.hasMore,
      filters: _filters,
      isRefreshing: isRefreshing,
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
