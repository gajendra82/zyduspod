import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:zyduspod/Bloc/hospital_dashboard_bloc.dart';
import 'package:zyduspod/Bloc/hospital_dashboard_event.dart';
import 'package:zyduspod/Bloc/hospital_dashboard_state.dart';
import 'package:zyduspod/DocumentUploadScreen.dart';

// Adjust this import path if your screen is in a different file.

import '../models/hospital_stats.dart';

class HospitalDashboardPane extends StatelessWidget {
  const HospitalDashboardPane({super.key});

  void _openUploader(BuildContext context, HospitalStats h) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentUploadScreen(
          preselectHospitalId: h.id,
          preselectHospitalName: h.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HospitalDashboardBloc, HospitalDashboardState>(
      builder: (context, state) {
        final theme = Theme.of(context);
        final currency = NumberFormat.currency(
          locale: 'en_IN',
          symbol: '₹',
          decimalDigits: 0,
        );

        if (state.loading && state.all.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.error != null && state.all.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 48),
              Icon(Icons.wifi_off, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Center(child: Text('Failed to load: ${state.error}')),
              const SizedBox(height: 12),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () => context.read<HospitalDashboardBloc>().add(
                    const HospitalDashboardLoadRequested(),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ],
          );
        }

        return RefreshIndicator(
          onRefresh: () async => context.read<HospitalDashboardBloc>().add(
            const HospitalDashboardRefreshRequested(),
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _filters(context, state),
              const SizedBox(height: 12),
              _summary(context, state, currency),
              const SizedBox(height: 12),
              _header(theme),
              const SizedBox(height: 8),
              ...state.filtered.map((h) => _rowCard(context, h, currency)),
              if (state.filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Column(
                    children: [
                      const Icon(Icons.inbox, size: 42, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text(
                        'No hospitals match the filters',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _filters(BuildContext context, HospitalDashboardState state) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Responsive Search + Sort row
            LayoutBuilder(
              builder: (ctx, constraints) {
                final twoCols = constraints.maxWidth >= 520;
                final sortFieldMaxWidth = twoCols
                    ? 200.0
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      width: twoCols
                          ? (constraints.maxWidth - (sortFieldMaxWidth + 8))
                          : constraints.maxWidth,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Search hospital or zone',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => context
                            .read<HospitalDashboardBloc>()
                            .add(HospitalDashboardSearchChanged(v)),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: 160,
                        maxWidth: sortFieldMaxWidth,
                      ),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Sort by',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<HospitalSortBy>(
                            value: state.sortBy,
                            isDense: true,
                            isExpanded: true,
                            onChanged: (v) {
                              if (v != null) {
                                context.read<HospitalDashboardBloc>().add(
                                  HospitalDashboardSortChanged(v),
                                );
                              }
                            },
                            items: const [
                              DropdownMenuItem(
                                value: HospitalSortBy.salesDesc,
                                child: Text('Sales (High→Low)'),
                              ),
                              DropdownMenuItem(
                                value: HospitalSortBy.salesAsc,
                                child: Text('Sales (Low→High)'),
                              ),
                              DropdownMenuItem(
                                value: HospitalSortBy.percentDesc,
                                child: Text('% Uploaded (High→Low)'),
                              ),
                              DropdownMenuItem(
                                value: HospitalSortBy.percentAsc,
                                child: Text('% Uploaded (Low→High)'),
                              ),
                              DropdownMenuItem(
                                value: HospitalSortBy.podValueDesc,
                                child: Text('POD Value (High→Low)'),
                              ),
                              DropdownMenuItem(
                                value: HospitalSortBy.podValueAsc,
                                child: Text('POD Value (Low→High)'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Keep slider (min % filter)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Min % Uploaded: ${state.minPercent}%'),
                      Slider(
                        value: state.minPercent.toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 20,
                        label: '${state.minPercent}%',
                        onChanged: (v) => context
                            .read<HospitalDashboardBloc>()
                            .add(HospitalDashboardMinPercentChanged(v.round())),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => context.read<HospitalDashboardBloc>().add(
                    const HospitalDashboardClearFilters(),
                  ),
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(
    BuildContext context,
    HospitalDashboardState state,
    NumberFormat currency,
  ) {
    final pct = state.overallPercent.clamp(0, 100);
    final pctColor = _percentColor(pct.toDouble());

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                _kpi(
                  context,
                  'Total Sales',
                  currency.format(state.totalSales),
                  Icons.payments,
                ),
                const SizedBox(width: 12),
                _kpi(
                  context,
                  'POD Value',
                  currency.format(state.totalPod),
                  Icons.inventory_2,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpi(
                    context,
                    '% Uploaded',
                    '${pct.toStringAsFixed(1)}%',
                    Icons.percent,
                    color: pctColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 10,
              color: pctColor,
              backgroundColor: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpi(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (color ?? theme.colorScheme.primary).withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (color ?? theme.colorScheme.primary).withOpacity(0.15),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: (color ?? theme.colorScheme.primary).withOpacity(
                0.15,
              ),
              child: Icon(
                icon,
                size: 18,
                color: color ?? theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final h = theme.textTheme.labelSmall!.copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(flex: 3, child: Text('HOSPITAL', style: h)),
          Expanded(flex: 2, child: Text('SALES', style: h)),
          Expanded(flex: 2, child: Text('POD VALUE', style: h)),
          Expanded(flex: 2, child: Text('% UPLOADED', style: h)),
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  // Updated layout:
  // - First row: Avatar + Hospital name (left), Upload button (right)
  // - Below: chips (zone, recs, pods)
  // - Below: metrics row (Sales, POD, % with progress)
  Widget _rowCard(
    BuildContext context,
    HospitalStats h,
    NumberFormat currency,
  ) {
    final pct = h.percentUploaded.clamp(0, 100);
    final color = _percentColor(pct.toDouble());

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Name + Upload button
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.blueGrey.shade50,
                  child: Text(
                    h.name.isNotEmpty ? h.name[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    h.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openUploader(context, h),
                  icon: const Icon(Icons.cloud_upload, size: 18),
                  label: const Text('Upload'),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Chips row
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip(h.zone),
                if (h.records > 0)
                  _chip('Recs: ${h.records}', color: Colors.indigo),
                _chip('PODs: ${h.podCount}', color: Colors.green),
              ],
            ),

            const SizedBox(height: 10),

            // Metrics row (Sales | POD | %)
            Row(
              children: [
                Expanded(
                  child: _metricTile(
                    title: 'Sales',
                    value: currency.format(h.salesValue),
                    icon: Icons.payments,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricTile(
                    title: 'POD Value',
                    value: currency.format(h.podValue),
                    icon: Icons.inventory_2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${pct.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: (pct / 100).clamp(0.0, 1.0),
                          minHeight: 8,
                          color: color,
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricTile({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: (color ?? Colors.blueGrey).withOpacity(0.1),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: (color ?? Colors.blueGrey).withOpacity(0.25)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: color ?? Colors.blueGrey),
    ),
  );

  void _showDetails(
    BuildContext context,
    HospitalStats h,
    NumberFormat currency,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(h.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Zone', h.zone),
            _kv('Sales', currency.format(h.salesValue)),
            _kv('POD Value', currency.format(h.podValue)),
            _kv('POD Count', '${h.podCount}'),
            _kv('% Uploaded', '${h.percentUploaded.toStringAsFixed(2)}%'),
            if (h.updatedAt != null) _kv('Updated', '${h.updatedAt}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$k:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Color _percentColor(double pct) {
    if (pct >= 90) return Colors.green.shade600;
    if (pct >= 70) return Colors.teal.shade600;
    if (pct >= 50) return Colors.orange.shade700;
    return Colors.red.shade600;
  }
}
