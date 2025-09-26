import '../../models/hospital_stats.dart';

enum HospitalSortBy {
  salesDesc,
  salesAsc,
  percentDesc,
  percentAsc,
  podValueDesc,
  podValueAsc,
}

abstract class HospitalDashboardEvent {
  const HospitalDashboardEvent();
}

class HospitalDashboardLoadRequested extends HospitalDashboardEvent {
  const HospitalDashboardLoadRequested();
}

class HospitalDashboardRefreshRequested extends HospitalDashboardEvent {
  const HospitalDashboardRefreshRequested();
}

class HospitalDashboardSearchChanged extends HospitalDashboardEvent {
  final String query;
  const HospitalDashboardSearchChanged(this.query);
}

class HospitalDashboardMinPercentChanged extends HospitalDashboardEvent {
  final int minPercent;
  const HospitalDashboardMinPercentChanged(this.minPercent);
}

class HospitalDashboardSortChanged extends HospitalDashboardEvent {
  final HospitalSortBy sortBy;
  const HospitalDashboardSortChanged(this.sortBy);
}

class HospitalDashboardClearFilters extends HospitalDashboardEvent {
  const HospitalDashboardClearFilters();
}
