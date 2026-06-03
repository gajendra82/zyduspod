import 'package:equatable/equatable.dart';

abstract class HospitalDashboardEvent extends Equatable {
  const HospitalDashboardEvent();

  @override
  List<Object?> get props => [];
}

class HospitalDashboardLoadRequested extends HospitalDashboardEvent {
  /// Optional yyyy-MM-dd window — when set, the underlying /api/dashboard/*
  /// calls send `date_from` and `date_to` query params so the dashboard
  /// counts mirror the selected month.
  final String? dateFrom;
  final String? dateTo;

  const HospitalDashboardLoadRequested({this.dateFrom, this.dateTo});

  @override
  List<Object?> get props => [dateFrom, dateTo];
}

class HospitalDashboardRefreshRequested extends HospitalDashboardEvent {
  final String? dateFrom;
  final String? dateTo;

  const HospitalDashboardRefreshRequested({this.dateFrom, this.dateTo});

  @override
  List<Object?> get props => [dateFrom, dateTo];
}

class HospitalDashboardStatsRequested extends HospitalDashboardEvent {
  const HospitalDashboardStatsRequested();
}

class HospitalDashboardDocumentsRequested extends HospitalDashboardEvent {
  const HospitalDashboardDocumentsRequested();
}

class HospitalDashboardFilterChanged extends HospitalDashboardEvent {
  final String filter;
  
  const HospitalDashboardFilterChanged(this.filter);
  
  @override
  List<Object?> get props => [filter];
}

class HospitalDashboardSearchChanged extends HospitalDashboardEvent {
  final String searchQuery;
  
  const HospitalDashboardSearchChanged(this.searchQuery);
  
  @override
  List<Object?> get props => [searchQuery];
}
