import 'package:equatable/equatable.dart';

abstract class HospitalDashboardEvent extends Equatable {
  const HospitalDashboardEvent();

  @override
  List<Object?> get props => [];
}

class HospitalDashboardLoadRequested extends HospitalDashboardEvent {
  const HospitalDashboardLoadRequested();
}

class HospitalDashboardRefreshRequested extends HospitalDashboardEvent {
  const HospitalDashboardRefreshRequested();
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
