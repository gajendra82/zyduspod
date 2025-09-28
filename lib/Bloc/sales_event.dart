import 'package:equatable/equatable.dart';
import 'package:zyduspod/Models/sales_data.dart';

abstract class SalesEvent extends Equatable {
  const SalesEvent();

  @override
  List<Object?> get props => [];
}

class SalesLoadRequested extends SalesEvent {
  const SalesLoadRequested();
}

class SalesRefreshRequested extends SalesEvent {
  const SalesRefreshRequested();
}

class SalesFilterChanged extends SalesEvent {
  final SalesFilter filter;
  
  const SalesFilterChanged(this.filter);
  
  @override
  List<Object?> get props => [filter];
}

class SalesSearchChanged extends SalesEvent {
  final String searchQuery;
  
  const SalesSearchChanged(this.searchQuery);
  
  @override
  List<Object?> get props => [searchQuery];
}

class HospitalSalesLoadRequested extends SalesEvent {
  const HospitalSalesLoadRequested();
}

class StockistSalesLoadRequested extends SalesEvent {
  const StockistSalesLoadRequested();
}

class SalesDataLoadRequested extends SalesEvent {
  final SalesFilter? filter;
  
  const SalesDataLoadRequested({this.filter});
  
  @override
  List<Object?> get props => [filter];
}

class SalesUploadRequested extends SalesEvent {
  final Map<String, dynamic> salesData;
  
  const SalesUploadRequested(this.salesData);
  
  @override
  List<Object?> get props => [salesData];
}

class SalesExportRequested extends SalesEvent {
  final SalesFilter? filter;
  final String format; // 'csv', 'pdf', 'excel'
  
  const SalesExportRequested({this.filter, this.format = 'csv'});
  
  @override
  List<Object?> get props => [filter, format];
}
