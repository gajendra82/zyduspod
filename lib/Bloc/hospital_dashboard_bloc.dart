import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zyduspod/Bloc/hospital_dashboard_event.dart';
import 'package:zyduspod/Bloc/hospital_dashboard_state.dart';
import 'package:zyduspod/services/hospital_dashboard_service.dart';

class HospitalDashboardBloc extends Bloc<HospitalDashboardEvent, HospitalDashboardState> {
  final HospitalDashboardService _service;

  HospitalDashboardBloc(this._service) : super(const HospitalDashboardInitial()) {
    on<HospitalDashboardLoadRequested>(_onLoadRequested);
    on<HospitalDashboardRefreshRequested>(_onRefreshRequested);
    on<HospitalDashboardStatsRequested>(_onStatsRequested);
    on<HospitalDashboardDocumentsRequested>(_onDocumentsRequested);
    on<HospitalDashboardFilterChanged>(_onFilterChanged);
    on<HospitalDashboardSearchChanged>(_onSearchChanged);
  }

  Future<void> _onLoadRequested(
    HospitalDashboardLoadRequested event,
    Emitter<HospitalDashboardState> emit,
  ) async {
    emit(const HospitalDashboardLoading());

    try {
      final dashboardData = await _service.getDashboardStats();
      final recentDocuments = await _service.getRecentDocuments();

      emit(HospitalDashboardLoaded(
        dashboardData: dashboardData,
        recentDocuments: recentDocuments,
      ));
    } catch (e) {
      emit(HospitalDashboardError(
        message: e.toString(),
      ));
    }
  }

  Future<void> _onRefreshRequested(
    HospitalDashboardRefreshRequested event,
    Emitter<HospitalDashboardState> emit,
  ) async {
    print('onRefreshRequested');
    if (state is HospitalDashboardLoaded) {
      final currentState = state as HospitalDashboardLoaded;
      emit(currentState.copyWith(isRefreshing: true));

      try {
        final dashboardData = await _service.getDashboardStats();
        // print('dashboardData: $dashboardData');
        final recentDocuments = await _service.getRecentDocuments();
        print('recentDocuments: $recentDocuments');
        emit(HospitalDashboardLoaded(
          dashboardData: dashboardData,
          recentDocuments: recentDocuments,
          selectedFilter: currentState.selectedFilter,
          searchQuery: currentState.searchQuery,
          isRefreshing: false,
        ));
      } catch (e) {
        emit(HospitalDashboardError(
          message: e.toString(),
        ));
      }
    }
  }

  Future<void> _onStatsRequested(
    HospitalDashboardStatsRequested event,
    Emitter<HospitalDashboardState> emit,
  ) async {
    if (state is HospitalDashboardLoaded) {
      final currentState = state as HospitalDashboardLoaded;

      try {
        final dashboardData = await _service.getDashboardStats();

        emit(currentState.copyWith(
          dashboardData: dashboardData,
        ));
      } catch (e) {
        emit(HospitalDashboardError(
          message: e.toString(),
        ));
      }
    }
  }

  Future<void> _onDocumentsRequested(
    HospitalDashboardDocumentsRequested event,
    Emitter<HospitalDashboardState> emit,
  ) async {
    if (state is HospitalDashboardLoaded) {
      final currentState = state as HospitalDashboardLoaded;

      try {
        final recentDocuments = await _service.getRecentDocuments();

        emit(currentState.copyWith(
          recentDocuments: recentDocuments,
        ));
      } catch (e) {
        emit(HospitalDashboardError(
          message: e.toString(),
        ));
      }
    }
  }

  void _onFilterChanged(
    HospitalDashboardFilterChanged event,
    Emitter<HospitalDashboardState> emit,
  ) {
    if (state is HospitalDashboardLoaded) {
      final currentState = state as HospitalDashboardLoaded;
      emit(currentState.copyWith(selectedFilter: event.filter));
    }
  }

  void _onSearchChanged(
    HospitalDashboardSearchChanged event,
    Emitter<HospitalDashboardState> emit,
  ) {
    if (state is HospitalDashboardLoaded) {
      final currentState = state as HospitalDashboardLoaded;
      emit(currentState.copyWith(searchQuery: event.searchQuery));
    }
  }
}
