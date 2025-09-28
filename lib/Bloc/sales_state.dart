import 'package:equatable/equatable.dart';
import 'package:zyduspod/Models/sales_data.dart';

abstract class SalesState extends Equatable {
  const SalesState();

  @override
  List<Object?> get props => [];
}

class SalesInitial extends SalesState {
  const SalesInitial();
}

class SalesLoading extends SalesState {
  const SalesLoading();
}

class SalesLoaded extends SalesState {
  final List<SalesData> salesData;
  final List<HospitalSalesSummary> hospitalSummaries;
  final List<StockistSalesSummary> stockistSummaries;
  final SalesFilter? currentFilter;
  final String searchQuery;
  final bool isRefreshing;
  final Map<String, dynamic> summaryStats;

  const SalesLoaded({
    required this.salesData,
    required this.hospitalSummaries,
    required this.stockistSummaries,
    this.currentFilter,
    this.searchQuery = '',
    this.isRefreshing = false,
    required this.summaryStats,
  });

  @override
  List<Object?> get props => [
        salesData,
        hospitalSummaries,
        stockistSummaries,
        currentFilter,
        searchQuery,
        isRefreshing,
        summaryStats,
      ];

  SalesLoaded copyWith({
    List<SalesData>? salesData,
    List<HospitalSalesSummary>? hospitalSummaries,
    List<StockistSalesSummary>? stockistSummaries,
    SalesFilter? currentFilter,
    String? searchQuery,
    bool? isRefreshing,
    Map<String, dynamic>? summaryStats,
  }) {
    return SalesLoaded(
      salesData: salesData ?? this.salesData,
      hospitalSummaries: hospitalSummaries ?? this.hospitalSummaries,
      stockistSummaries: stockistSummaries ?? this.stockistSummaries,
      currentFilter: currentFilter ?? this.currentFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      summaryStats: summaryStats ?? this.summaryStats,
    );
  }
}

class SalesError extends SalesState {
  final String message;
  final String? errorCode;

  const SalesError({
    required this.message,
    this.errorCode,
  });

  @override
  List<Object?> get props => [message, errorCode];
}

class SalesUploading extends SalesState {
  const SalesUploading();
}

class SalesUploaded extends SalesState {
  final String message;
  
  const SalesUploaded({required this.message});
  
  @override
  List<Object?> get props => [message];
}

class SalesExporting extends SalesState {
  const SalesExporting();
}

class SalesExported extends SalesState {
  final String filePath;
  
  const SalesExported({required this.filePath});
  
  @override
  List<Object?> get props => [filePath];
}
