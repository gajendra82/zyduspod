import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zyduspod/Bloc/sales_event.dart';
import 'package:zyduspod/Bloc/sales_state.dart';
import 'package:zyduspod/services/sales_service.dart';

class SalesBloc extends Bloc<SalesEvent, SalesState> {
  final SalesService _service;

  SalesBloc(this._service) : super(const SalesInitial()) {
    on<SalesLoadRequested>(_onLoadRequested);
    on<SalesRefreshRequested>(_onRefreshRequested);
    on<SalesFilterChanged>(_onFilterChanged);
    on<SalesSearchChanged>(_onSearchChanged);
    on<HospitalSalesLoadRequested>(_onHospitalSalesLoadRequested);
    on<StockistSalesLoadRequested>(_onStockistSalesLoadRequested);
    on<SalesDataLoadRequested>(_onSalesDataLoadRequested);
    on<SalesUploadRequested>(_onSalesUploadRequested);
    on<SalesExportRequested>(_onSalesExportRequested);
  }

  Future<void> _onLoadRequested(
    SalesLoadRequested event,
    Emitter<SalesState> emit,
  ) async {
    emit(const SalesLoading());

    try {
      final salesData = await _service.getSalesData();
      final hospitalSummaries = await _service.getHospitalSalesSummaries();
      final stockistSummaries = await _service.getStockistSalesSummaries();
      final summaryStats = await _service.getSalesSummaryStats();

      emit(SalesLoaded(
        salesData: salesData,
        hospitalSummaries: hospitalSummaries,
        stockistSummaries: stockistSummaries,
        summaryStats: summaryStats,
      ));
    } catch (e) {
      emit(SalesError(message: e.toString()));
    }
  }

  Future<void> _onRefreshRequested(
    SalesRefreshRequested event,
    Emitter<SalesState> emit,
  ) async {
    if (state is SalesLoaded) {
      final currentState = state as SalesLoaded;
      emit(currentState.copyWith(isRefreshing: true));

      try {
        // final salesData = await _service.getSalesData(filter: currentState.currentFilter);
        final hospitalSummaries = await _service.getHospitalSalesSummaries();
        // final stockistSummaries = await _service.getStockistSalesSummaries();
        final summaryStats = await _service.getSalesSummaryStats();
        print('hospitalSummaries: $hospitalSummaries');
        print('summaryStats: $summaryStats');
        emit(SalesLoaded(
          salesData: [],
          hospitalSummaries: hospitalSummaries,
            stockistSummaries: [],
          currentFilter: currentState.currentFilter,
          searchQuery: currentState.searchQuery,
          isRefreshing: false,
          summaryStats: summaryStats,
        ));
      } catch (e) {
        emit(SalesError(message: e.toString()));
      }
    }
  }

  void _onFilterChanged(
    SalesFilterChanged event,
    Emitter<SalesState> emit,
  ) {
    if (state is SalesLoaded) {
      final currentState = state as SalesLoaded;
      emit(currentState.copyWith(currentFilter: event.filter));
      
      // Trigger data reload with new filter
      add(SalesDataLoadRequested(filter: event.filter));
    }
  }

  void _onSearchChanged(
    SalesSearchChanged event,
    Emitter<SalesState> emit,
  ) {
    if (state is SalesLoaded) {
      final currentState = state as SalesLoaded;
      emit(currentState.copyWith(searchQuery: event.searchQuery));
    }
  }

  Future<void> _onHospitalSalesLoadRequested(
    HospitalSalesLoadRequested event,
    Emitter<SalesState> emit,
  ) async {
    if (state is SalesLoaded) {
      final currentState = state as SalesLoaded;

      try {
        final hospitalSummaries = await _service.getHospitalSalesSummaries();

        emit(currentState.copyWith(
          hospitalSummaries: hospitalSummaries,
        ));
      } catch (e) {
        emit(SalesError(message: e.toString()));
      }
    }
  }

  Future<void> _onStockistSalesLoadRequested(
    StockistSalesLoadRequested event,
    Emitter<SalesState> emit,
  ) async {
    if (state is SalesLoaded) {
      final currentState = state as SalesLoaded;

      try {
        final stockistSummaries = await _service.getStockistSalesSummaries();

        emit(currentState.copyWith(
          stockistSummaries: stockistSummaries,
        ));
      } catch (e) {
        emit(SalesError(message: e.toString()));
      }
    }
  }

  Future<void> _onSalesDataLoadRequested(
    SalesDataLoadRequested event,
    Emitter<SalesState> emit,
  ) async {
    if (state is SalesLoaded) {
      final currentState = state as SalesLoaded;

      try {
        final salesData = await _service.getSalesData(filter: event.filter);

        emit(currentState.copyWith(
          salesData: salesData,
          currentFilter: event.filter,
        ));
      } catch (e) {
        emit(SalesError(message: e.toString()));
      }
    }
  }

  Future<void> _onSalesUploadRequested(
    SalesUploadRequested event,
    Emitter<SalesState> emit,
  ) async {
    emit(const SalesUploading());

    try {
      await _service.uploadSalesData(event.salesData);
      emit(const SalesUploaded(message: 'Sales data uploaded successfully'));
      
      // Refresh data after upload
      add(const SalesLoadRequested());
    } catch (e) {
      emit(SalesError(message: e.toString()));
    }
  }

  Future<void> _onSalesExportRequested(
    SalesExportRequested event,
    Emitter<SalesState> emit,
  ) async {
    emit(const SalesExporting());

    try {
      final filePath = await _service.exportSalesData(
        filter: event.filter,
        format: event.format,
      );
      emit(SalesExported(filePath: filePath));
    } catch (e) {
      emit(SalesError(message: e.toString()));
    }
  }
}
