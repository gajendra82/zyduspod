import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/hospital_stats.dart';
import '../../services/hospital_dashboard_service.dart';
import 'hospital_dashboard_event.dart';
import 'hospital_dashboard_state.dart';

class HospitalDashboardBloc
    extends Bloc<HospitalDashboardEvent, HospitalDashboardState> {
  final HospitalDashboardService service;

  HospitalDashboardBloc(this.service)
    : super(HospitalDashboardState.initial()) {
    on<HospitalDashboardLoadRequested>(_onLoad);
    on<HospitalDashboardRefreshRequested>(_onRefresh);
    on<HospitalDashboardSearchChanged>(_onSearch);
    on<HospitalDashboardMinPercentChanged>(_onMinPercent);
    on<HospitalDashboardSortChanged>(_onSort);
    on<HospitalDashboardClearFilters>(_onClear);
  }

  Future<void> _onLoad(
    HospitalDashboardLoadRequested e,
    Emitter<HospitalDashboardState> emit,
  ) async {
    emit(state.copyWith(loading: true, errorToNull: true));
    try {
      final data = await service.fetch();
      final s = state.copyWith(all: data);
      final applied = _applyFilters(s);
      emit(applied.copyWith(loading: false));
    } catch (err) {
      emit(state.copyWith(loading: false, error: err.toString()));
    }
  }

  Future<void> _onRefresh(
    HospitalDashboardRefreshRequested e,
    Emitter<HospitalDashboardState> emit,
  ) async {
    add(const HospitalDashboardLoadRequested());
  }

  void _onSearch(
    HospitalDashboardSearchChanged e,
    Emitter<HospitalDashboardState> emit,
  ) {
    final s = state.copyWith(search: e.query);
    emit(_applyFilters(s));
  }

  void _onMinPercent(
    HospitalDashboardMinPercentChanged e,
    Emitter<HospitalDashboardState> emit,
  ) {
    final s = state.copyWith(minPercent: e.minPercent);
    emit(_applyFilters(s));
  }

  void _onSort(
    HospitalDashboardSortChanged e,
    Emitter<HospitalDashboardState> emit,
  ) {
    final s = state.copyWith(sortBy: e.sortBy);
    emit(_applyFilters(s));
  }

  void _onClear(
    HospitalDashboardClearFilters e,
    Emitter<HospitalDashboardState> emit,
  ) {
    final s = state.copyWith(
      search: '',
      minPercent: 0,
      sortBy: HospitalSortBy.salesDesc,
    );
    emit(_applyFilters(s));
  }

  HospitalDashboardState _applyFilters(HospitalDashboardState base) {
    var list = base.all;

    final q = base.search.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (h) =>
                h.name.toLowerCase().contains(q) ||
                h.zone.toLowerCase().contains(q),
          )
          .toList();
    }

    list = list.where((h) => h.percentUploaded >= base.minPercent).toList();

    list.sort((a, b) {
      switch (base.sortBy) {
        case HospitalSortBy.salesDesc:
          return b.salesValue.compareTo(a.salesValue);
        case HospitalSortBy.salesAsc:
          return a.salesValue.compareTo(b.salesValue);
        case HospitalSortBy.percentDesc:
          return b.percentUploaded.compareTo(a.percentUploaded);
        case HospitalSortBy.percentAsc:
          return a.percentUploaded.compareTo(b.percentUploaded);
        case HospitalSortBy.podValueDesc:
          return b.podValue.compareTo(a.podValue);
        case HospitalSortBy.podValueAsc:
          return a.podValue.compareTo(b.podValue);
      }
    });

    final totalSales = list.fold<double>(0, (s, h) => s + h.salesValue);
    final totalPod = list.fold<double>(0, (s, h) => s + h.podValue);
    final overallPercent = totalSales <= 0 ? 0 : (totalPod / totalSales) * 100;

    return base.copyWith(
      filtered: list,
      totalSales: totalSales,
      totalPod: totalPod,
      overallPercent: overallPercent.toDouble(),
      errorToNull: true,
    );
  }
}
