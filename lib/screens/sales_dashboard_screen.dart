import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import 'package:zydus_vistaar/Bloc/sales_dashboard_bloc.dart';
import 'package:zydus_vistaar/Bloc/sales_dashboard_event.dart';
import 'package:zydus_vistaar/Bloc/sales_dashboard_state.dart';
import 'package:zydus_vistaar/Models/sales_dashboard_models.dart';
import 'package:zydus_vistaar/services/sales_dashboard_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Responsive helpers — used throughout to tighten paddings, font sizes and
// chart dimensions on phones without redesigning the premium look. Breakpoints
// match the conventional Material 3 / web-app tiers.
// ─────────────────────────────────────────────────────────────────────────────

const double _bpMobile = 600;   // < 600px = phone
const double _bpTablet = 1024;  // < 1024px = tablet

bool _isMobile(BuildContext context) =>
    MediaQuery.of(context).size.width < _bpMobile;
bool _isTablet(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  return w >= _bpMobile && w < _bpTablet;
}

/// Premium "executive BI" Sales Analytics Dashboard.
///
/// Layout (top → bottom):
///  1. Filter bar (date range, zone, leaderboard type, refresh)
///  2. KPI grid — 8 large cards (Target / Achievement / Achievement % /
///     Gap / Growth / Active KAMs / Hospitals / Stockists)
///  3. Target vs Achievement Trend line chart (last 12 months)
///  4. Top Performers leaderboard with a tab strip for the eight types
///
/// Responsive: switches between 1/2/4-column KPI grid based on width.
///
/// Two entry points:
///   * [SalesDashboardScreen] — standalone full-screen route at
///     `/sales-analytics`, wraps the body in its own Scaffold + AppBar.
///   * [SalesDashboardBody] — embeddable widget that owns its own BLoC
///     but renders NO Scaffold. Use this when slotting the analytics view
///     into an existing tab/page (e.g. the dashboard's "Sales Analytics"
///     tab) so we don't nest two app bars.
class SalesDashboardScreen extends StatelessWidget {
  const SalesDashboardScreen({super.key});

  static const routeName = '/sales-analytics';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: const Text('Sales Analytics'),
        elevation: 0,
        backgroundColor: const Color(0xFF00A0A8),
        foregroundColor: Colors.white,
      ),
      body: const SalesDashboardBody(),
    );
  }
}

/// Embeddable variant — drops the Scaffold/AppBar so it can be slotted into
/// an existing tab without nesting app bars. Refresh is surfaced inline on
/// the filter bar and via pull-to-refresh.
class SalesDashboardBody extends StatelessWidget {
  const SalesDashboardBody({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SalesDashboardBloc>(
      create: (_) => SalesDashboardBloc(SalesDashboardService())
        // Bootstrap with the current month pre-selected — matches the
        // default of the Month dropdown on the filter bar so the user sees
        // a populated dashboard immediately on open and KPI cards (incl.
        // "Growth vs Last Year") are anchored on a real window.
        ..add(SalesDashboardFiltersChanged(_currentMonthFilters())),
      child: const _SalesDashboardView(),
    );
  }
}

/// First day → last day of the current month as ISO yyyy-MM-dd strings.
/// Exposed as a top-level helper so the filter bar can compare against it
/// (to highlight "this month" vs. a custom range).
SalesDashboardFilters _currentMonthFilters() {
  final now = DateTime.now();
  return SalesDashboardFilters(
    dateFrom: _monthFirstIso(now),
    dateTo: _monthLastIso(now),
  );
}

String _monthFirstIso(DateTime d) =>
    DateFormat('yyyy-MM-dd').format(DateTime(d.year, d.month, 1));
String _monthLastIso(DateTime d) =>
    DateFormat('yyyy-MM-dd').format(DateTime(d.year, d.month + 1, 0));

class _SalesDashboardView extends StatelessWidget {
  const _SalesDashboardView();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF6F8FB),
      child: BlocBuilder<SalesDashboardBloc, SalesDashboardState>(
        builder: (context, state) {
          if (state is SalesDashboardInitial || state is SalesDashboardLoading) {
            return const _SkeletonView();
          }
          if (state is SalesDashboardError) {
            return _ErrorView(message: state.message);
          }
          if (state is SalesDashboardLoaded) {
            return RefreshIndicator(
              onRefresh: () async => context
                  .read<SalesDashboardBloc>()
                  .add(const SalesDashboardRefreshRequested()),
              child: _LoadedView(state: state),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOADED VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _LoadedView extends StatelessWidget {
  const _LoadedView({required this.state});
  final SalesDashboardLoaded state;

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    final hPad = mobile ? 10.0 : 16.0;
    final vPad = mobile ? 12.0 : 16.0;
    final sectionGap = mobile ? 14.0 : 20.0;

    // The leaderboard previously sat inside a fixed-height SizedBox with
    // its own ScrollController, which trapped scroll gestures and made
    // it impossible to scroll past it on phones. Now the leaderboard
    // renders its rows inline as ListView items in this outer ListView,
    // and a NotificationListener watches the *page* scroll to fire
    // load-more when the user nears the bottom — there is only one
    // scrollable on this page.
    final outerListView = ListView(
      padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, mobile ? 24 : 32),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _FilterBar(filters: state.filters),
        SizedBox(height: mobile ? 12 : 16),
        if (state.isRefreshing) const LinearProgressIndicator(minHeight: 2),
        SizedBox(height: mobile ? 6 : 8),
        _KpiGrid(summary: state.summary),
        SizedBox(height: sectionGap),
        _TrendCard(points: state.trend),
        SizedBox(height: sectionGap),
        _LeaderboardCard(state: state),
      ],
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // Fire load-more when the outer scroll position is within 220 px
        // of the bottom AND there's another page available. Throttle is
        // implicit — the BLoC's `isLoadingMore` check de-dupes concurrent
        // triggers, and ScrollNotification fires liberally enough that
        // even a slow scroll catches it.
        if (n.metrics.axis != Axis.vertical) return false;
        if (!state.leaderboardHasMore) return false;
        if (state.isLeaderboardLoadingMore) return false;
        if (state.isLeaderboardLoading) return false;
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 220) {
          context
              .read<SalesDashboardBloc>()
              .add(const SalesDashboardLeaderboardLoadMoreRequested());
        }
        return false; // don't swallow — let scroll continue
      },
      child: outerListView,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER BAR — minimal in Phase 2; expand with more dropdowns as needed
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filters});
  final SalesDashboardFilters filters;

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    // Drop the year on phones: "1 May" instead of "1 May 2026" — the
    // Month dropdown already shows the year so it's redundant on the
    // From/To chips and was the main reason the bar overflowed.
    final dateFmt = DateFormat(mobile ? 'd MMM' : 'd MMM yyyy');
    final fromLabel = filters.dateFrom != null && filters.dateFrom!.isNotEmpty
        ? dateFmt.format(DateTime.tryParse(filters.dateFrom!) ?? DateTime.now())
        : 'From';
    final toLabel = filters.dateTo != null && filters.dateTo!.isNotEmpty
        ? dateFmt.format(DateTime.tryParse(filters.dateTo!) ?? DateTime.now())
        : 'To';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 10 : 14,
        vertical: mobile ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _MonthDropdown(filters: filters),
          _FilterChip(
            icon: Icons.calendar_today_rounded,
            label: fromLabel,
            onTap: () => _pickDate(context, isFrom: true),
          ),
          const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.black45),
          _FilterChip(
            icon: Icons.event_rounded,
            label: toLabel,
            onTap: () => _pickDate(context, isFrom: false),
          ),
          if (filters.zone != null && filters.zone!.isNotEmpty)
            _ActiveFilterChip(
              label: 'Zone: ${filters.zone}',
              onClear: () => context
                  .read<SalesDashboardBloc>()
                  .add(SalesDashboardFiltersChanged(filters.copyWith(clearZone: true))),
            ),
          // Spacer pushes the action group to the right when the row is wide
          // enough; on narrow widths it just wraps to the next line via Wrap.
          const SizedBox(width: 4),
          _FilterChip(
            icon: Icons.refresh_rounded,
            label: 'Refresh',
            onTap: () => context
                .read<SalesDashboardBloc>()
                .add(const SalesDashboardRefreshRequested()),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(BuildContext context, {required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (DateTime.tryParse(filters.dateFrom ?? '') ?? DateTime(now.year, now.month, 1))
        : (DateTime.tryParse(filters.dateTo ?? '') ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !context.mounted) return;
    final iso = DateFormat('yyyy-MM-dd').format(picked);
    final updated = isFrom
        ? filters.copyWith(dateFrom: iso)
        : filters.copyWith(dateTo: iso);
    context.read<SalesDashboardBloc>().add(SalesDashboardFiltersChanged(updated));
  }
}

/// Month dropdown for the filter bar.
///
/// Lists the last 24 calendar months (newest first) plus a synthetic
/// "Custom" entry that is auto-selected when the From/To pickers produce a
/// range that doesn't line up with a whole calendar month. Picking a month
/// rewrites both [dateFrom] and [dateTo] to that month's first/last day —
/// the existing pickers stay fully functional for users who want a finer
/// granularity.
class _MonthDropdown extends StatelessWidget {
  const _MonthDropdown({required this.filters});
  final SalesDashboardFilters filters;

  static const String _customKey = '__custom__';

  @override
  Widget build(BuildContext context) {
    final months = _generateMonths();
    final selected = _selectedKey(months);
    final labels = _MonthDropdown._labelMap(months);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.date_range_rounded, size: 16, color: Color(0xFF00A0A8)),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected,
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C3E50),
              ),
              items: [
                for (final m in months)
                  DropdownMenuItem<String>(
                    value: _monthKey(m),
                    child: Text(labels[_monthKey(m)] ?? _monthKey(m)),
                  ),
                if (selected == _customKey)
                  const DropdownMenuItem<String>(
                    value: _customKey,
                    child: Text('Custom range'),
                  ),
              ],
              onChanged: (v) {
                if (v == null || v == _customKey) return;
                final parts = v.split('-');
                final y = int.parse(parts[0]);
                final m = int.parse(parts[1]);
                final first = DateTime(y, m, 1);
                final last = DateTime(y, m + 1, 0);
                final updated = filters.copyWith(
                  dateFrom: _monthFirstIso(first),
                  dateTo: _monthLastIso(last),
                );
                context
                    .read<SalesDashboardBloc>()
                    .add(SalesDashboardFiltersChanged(updated));
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Last 24 months including the current month, newest first.
  List<DateTime> _generateMonths() {
    final now = DateTime.now();
    return List<DateTime>.generate(
      24,
      (i) => DateTime(now.year, now.month - i, 1),
    );
  }

  /// yyyy-MM key used as the DropdownButton value (so equality is stable).
  static String _monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  static Map<String, String> _labelMap(List<DateTime> months) {
    final fmt = DateFormat('MMM yyyy');
    return {for (final m in months) _monthKey(m): fmt.format(m)};
  }

  /// Return the dropdown value that matches the current filter window. If
  /// the user has set a custom range via the From/To pickers (date_from ≠
  /// first-of-month or date_to ≠ last-of-month), fall back to the synthetic
  /// "__custom__" key so the dropdown doesn't lie about what's selected.
  String _selectedKey(List<DateTime> months) {
    final from = DateTime.tryParse(filters.dateFrom ?? '');
    final to = DateTime.tryParse(filters.dateTo ?? '');
    if (from == null || to == null) {
      // Nothing selected yet — point at the current month so the very first
      // build shows a sensible default before BLoC bootstrap finishes.
      return _monthKey(months.first);
    }
    final firstOfMonth = DateTime(from.year, from.month, 1);
    final lastOfMonth = DateTime(from.year, from.month + 1, 0);
    final aligned = from.year == firstOfMonth.year &&
        from.month == firstOfMonth.month &&
        from.day == 1 &&
        to.year == lastOfMonth.year &&
        to.month == lastOfMonth.month &&
        to.day == lastOfMonth.day;
    if (!aligned) return _customKey;
    return _monthKey(firstOfMonth);
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F4F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF00A0A8)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onClear});
  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      onDeleted: onClear,
      backgroundColor: const Color(0xFFE0F4F5),
      labelStyle: const TextStyle(color: Color(0xFF00858C), fontWeight: FontWeight.w600),
      deleteIconColor: const Color(0xFF00858C),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI GRID
// ─────────────────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.summary});
  final SalesSummaryCards summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Column rules:
        //   • ≥ 1100 px  → 4 cards/row (full desktop)
        //   • ≥ 720 px   → 3 cards/row (small desktop / large tablet)
        //   • else       → 2 cards/row, including phones in portrait.
        // Phones used to drop to a single column which felt web-oriented:
        // 8 KPIs × 1 col = 8 vertical scroll units. Two columns halves that
        // and keeps each card readable since the value uses FittedBox.
        final w = constraints.maxWidth;
        final columns = w >= 1100
            ? 4
            : w >= 720
                ? 3
                : 2;
        // Aspect (width / height). Tighter than before — the old phone
        // bucket (1.1) made cards nearly square with a stretched-out
        // empty middle. Compact buckets put more KPIs in the viewport
        // and reduce wasted whitespace. _KpiCard internals were trimmed
        // (padding, icon size, gaps) to match.
        final aspect = columns == 4
            ? 1.75
            : columns == 3
                ? 1.65
                : w >= 480
                    ? 1.7      // tablet / wide phone landscape
                    : 1.5;     // narrow phone portrait — short + dense
        final spacing = columns >= 3 ? 12.0 : (w >= 480 ? 9.0 : 8.0);
        final cards = _buildCards();
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: aspect,
          ),
          itemCount: cards.length,
          itemBuilder: (_, i) => cards[i],
        );
      },
    );
  }

  List<Widget> _buildCards() {
    return [
      _KpiCard(
        title: 'Total Target',
        value: _inr(summary.totalTargetAmount),
        subtitle: 'Sum of hospital targets in window',
        icon: Icons.flag_rounded,
        gradient: const [Color(0xFF6366F1), Color(0xFF818CF8)],
      ),
      _KpiCard(
        title: 'Total Achievement',
        value: _inr(summary.netSalesAmount),
        subtitle: 'Net sales (sales − returns)',
        icon: Icons.trending_up_rounded,
        gradient: const [Color(0xFF10B981), Color(0xFF34D399)],
      ),
      _KpiCard(
        title: 'Achievement %',
        value: '${summary.achievementPercentage.toStringAsFixed(1)}%',
        subtitle: 'vs target',
        icon: Icons.percent_rounded,
        gradient: _pctGradient(summary.achievementPercentage),
        progress: (summary.achievementPercentage / 100).clamp(0.0, 1.0),
      ),
      _KpiCard(
        title: 'Gap to Target',
        value: _inr(summary.gapToTarget),
        subtitle: summary.gapToTarget <= 0 ? 'Target met or exceeded' : 'Still to achieve',
        icon: Icons.south_rounded,
        gradient: summary.gapToTarget <= 0
            ? const [Color(0xFF059669), Color(0xFF10B981)]
            : const [Color(0xFFEF4444), Color(0xFFF87171)],
      ),
      _KpiCard(
        title: 'Growth vs Last Year',
        value: '${summary.growthPercentage >= 0 ? '+' : ''}${summary.growthPercentage.toStringAsFixed(1)}%',
        subtitle: 'YoY net sales',
        icon: summary.growthPercentage >= 0
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded,
        gradient: summary.growthPercentage >= 0
            ? const [Color(0xFF0EA5E9), Color(0xFF38BDF8)]
            : const [Color(0xFFF59E0B), Color(0xFFFBBF24)],
      ),
      _KpiCard(
        title: 'Active KAMs',
        value: _int(summary.activeKamsCount),
        subtitle: 'Unique employees with sales',
        icon: Icons.people_alt_rounded,
        gradient: const [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
      ),
      _KpiCard(
        title: 'Active Hospitals',
        value: _int(summary.activeHospitalsCount),
        subtitle: 'Unique hospitals served',
        icon: Icons.local_hospital_rounded,
        gradient: const [Color(0xFFEC4899), Color(0xFFF472B6)],
      ),
      _KpiCard(
        title: 'Active Stockists',
        value: _int(summary.activeStockistsCount),
        subtitle: 'Unique stockists in window',
        icon: Icons.warehouse_rounded,
        gradient: const [Color(0xFF14B8A6), Color(0xFF2DD4BF)],
      ),
    ];
  }

  List<Color> _pctGradient(double pct) {
    if (pct >= 100) return const [Color(0xFF059669), Color(0xFF10B981)];
    if (pct >= 75) return const [Color(0xFF0EA5E9), Color(0xFF38BDF8)];
    if (pct >= 50) return const [Color(0xFFF59E0B), Color(0xFFFBBF24)];
    return const [Color(0xFFEF4444), Color(0xFFF87171)];
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.progress,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    // Size off the card's actual rendered width rather than screen width —
    // a 2-col phone places cards at ~180px while a 2-col tablet places
    // them at ~340px. The phone case needs noticeably tighter padding and
    // smaller chrome to keep the value + subtitle from getting squeezed.
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final narrow = w < 200;  // 2-col phone bucket
      final compact = w < 260; // small phone or large phone landscape pair

      // Trimmed from the previous values to kill empty whitespace —
      // padding, icon, badge dim, radius, and shadow were sized for a
      // taller card; with the grid's larger aspect ratio (shorter cell)
      // the old chrome made the cards look swollen.
      final cardPad = narrow ? 9.0 : (compact ? 11.0 : 13.0);
      final iconSize = narrow ? 14.0 : (compact ? 16.0 : 18.0);
      final iconBoxPad = narrow ? 5.0 : (compact ? 6.0 : 7.0);
      final progressDim = narrow ? 26.0 : (compact ? 30.0 : 34.0);
      final titleSize = narrow ? 10.0 : (compact ? 11.0 : 12.0);
      final valueSize = narrow ? 17.0 : (compact ? 20.0 : 24.0);
      final subtitleSize = narrow ? 9.0 : (compact ? 10.0 : 11.0);
      final radius = narrow ? 12.0 : (compact ? 14.0 : 16.0);
      final blur = narrow ? 6.0 : (compact ? 9.0 : 14.0);
      final yShadow = narrow ? 3.0 : (compact ? 4.0 : 6.0);
      // On the narrowest tiles drop the subtitle entirely — value +
      // title + (optional) progress badge are the priorities; the
      // explanatory subtitle is the first thing to sacrifice.
      final showSubtitle = !narrow;

      return Container(
        padding: EdgeInsets.all(cardPad),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withOpacity(0.28),
              blurRadius: blur,
              offset: Offset(0, yShadow),
            ),
          ],
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(iconBoxPad),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: iconSize),
              ),
              const Spacer(),
              if (progress != null)
                SizedBox(
                  width: progressDim,
                  height: progressDim,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: narrow ? 3.0 : (compact ? 3.5 : 4.0),
                        backgroundColor: Colors.white.withOpacity(0.25),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                      Text(
                        '${((progress ?? 0) * 100).round()}%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: narrow ? 7.5 : (compact ? 8.0 : 9.0),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: titleSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: narrow ? 2 : 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: valueSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (showSubtitle) ...[
            SizedBox(height: narrow ? 2 : 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.78),
                fontSize: subtitleSize,
              ),
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARGET vs ACHIEVEMENT TREND
// ─────────────────────────────────────────────────────────────────────────────

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.points});
  final List<TrendPoint> points;

  /// Hard floor — never render trend points from before this month. The
  /// backend also clamps to Jan 2026; this is a defensive safety net so a
  /// stale cached response can't show pre-2026 history. TrendPoint.month
  /// is the 'YYYY-MM' string the API returns, so a lex compare is correct.
  static const String _trendFloorYm = '2026-01';

  @override
  Widget build(BuildContext context) {
    final visible = points
        .where((p) => p.month.compareTo(_trendFloorYm) >= 0)
        .toList(growable: false);

    if (visible.isEmpty) {
      return _SectionCard(
        title: 'Target vs Achievement Trend',
        subtitle: 'From Jan 2026',
        child: const _EmptyState(message: 'No data in the selected window.'),
      );
    }

    final maxY = visible
        .map((p) => p.target > p.achievement ? p.target : p.achievement)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final niceMax = maxY <= 0 ? 1.0 : maxY * 1.15;

    return _SectionCard(
      title: 'Target vs Achievement Trend',
      subtitle: 'From Jan 2026 (${visible.length} months) — hierarchy-scoped',
      child: SizedBox(
        // Tighter on phones so the chart doesn't hog the viewport.
        height: _isMobile(context) ? 180 : 260,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: niceMax,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) =>
                  FlLine(color: Colors.black.withOpacity(0.06), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              show: true,
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  // Narrower axis gutter on phones — gives the line ~10px
                  // more horizontal room for the same chart width.
                  reservedSize: _isMobile(context) ? 38 : 52,
                  getTitlesWidget: (value, _) => Text(
                    _compactInr(value),
                    style: TextStyle(
                      fontSize: _isMobile(context) ? 9 : 10,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: 1,
                  getTitlesWidget: (value, _) {
                    final i = value.toInt();
                    if (i < 0 || i >= visible.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        visible[i].label,
                        style: const TextStyle(fontSize: 10, color: Colors.black54),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                isCurved: true,
                color: const Color(0xFF6366F1),
                barWidth: 3,
                dotData: const FlDotData(show: false),
                spots: [
                  for (var i = 0; i < visible.length; i++) FlSpot(i.toDouble(), visible[i].target),
                ],
                belowBarData: BarAreaData(
                  show: true,
                  color: const Color(0xFF6366F1).withOpacity(0.06),
                ),
              ),
              LineChartBarData(
                isCurved: true,
                color: const Color(0xFF10B981),
                barWidth: 3,
                dotData: const FlDotData(show: false),
                spots: [
                  for (var i = 0; i < visible.length; i++) FlSpot(i.toDouble(), visible[i].achievement),
                ],
                belowBarData: BarAreaData(
                  show: true,
                  color: const Color(0xFF10B981).withOpacity(0.08),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => Colors.black87,
                getTooltipItems: (spots) => spots.map((s) {
                  final isTarget = s.barIndex == 0;
                  return LineTooltipItem(
                    '${isTarget ? 'Target' : 'Achievement'}\n${_inr(s.y)}',
                    TextStyle(
                      color: isTarget ? const Color(0xFFC7D2FE) : const Color(0xFFA7F3D0),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
      extra: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: const [
            _LegendDot(color: Color(0xFF6366F1), label: 'Target'),
            SizedBox(width: 16),
            _LegendDot(color: Color(0xFF10B981), label: 'Achievement'),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEADERBOARD — All KAMs / All Hospitals / All Products (Brands)
//
// One paginated, searchable list. Server-side hierarchy scope is applied
// before pagination, so a KAM only sees their own slice + the total
// reflects that scope. The dropdown only offers the three live types now;
// managers/HQs/regions/zones/stockists were dropped from the dashboard.
// ─────────────────────────────────────────────────────────────────────────────

class _LeaderboardCard extends StatefulWidget {
  const _LeaderboardCard({required this.state});
  final SalesDashboardLoaded state;

  @override
  State<_LeaderboardCard> createState() => _LeaderboardCardState();
}

class _LeaderboardCardState extends State<_LeaderboardCard> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.state.leaderboardSearch;
  }

  @override
  void didUpdateWidget(covariant _LeaderboardCard old) {
    super.didUpdateWidget(old);
    // Keep the text field in sync if the state's search was reset by
    // some other path (type switch, filter change) — but don't clobber
    // active typing.
    final stateText = widget.state.leaderboardSearch;
    if (stateText != _searchCtrl.text && !_searchCtrl.value.composing.isValid) {
      _searchCtrl.value = TextEditingValue(
        text: stateText,
        selection: TextSelection.collapsed(offset: stateText.length),
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      context
          .read<SalesDashboardBloc>()
          .add(SalesDashboardLeaderboardSearchChanged(value));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final selectedType = state.topPerformerType;
    final performers = state.topPerformers;
    final isInitialLoading = state.isLeaderboardLoading;
    final mobile = _isMobile(context);

    // Rows render inline inside the outer page ListView — no nested
    // scrollable, no fixed height. Load-more is fired by a
    // NotificationListener on the parent (_LoadedView) watching the
    // outer scroll. That fixes the scroll-trapping bug where a finger
    // landing inside the leaderboard couldn't scroll past it.
    final rows = <Widget>[];
    if (isInitialLoading) {
      rows.add(const _LeaderboardSkeleton());
    } else if (performers.isEmpty) {
      rows.add(_EmptyState(
        message: state.leaderboardSearch.isEmpty
            ? 'No data for this leaderboard.'
            : 'No matches for "${state.leaderboardSearch}".',
      ));
    } else {
      for (var i = 0; i < performers.length; i++) {
        rows.add(_KamLeaderboardRow(
          rank: i + 1,
          performer: performers[i],
          type: selectedType,
        ));
      }
      if (state.isLeaderboardLoadingMore) {
        // 3 shimmer rows hinting at the next page being fetched.
        rows.add(const _LeaderboardSkeletonRow());
        rows.add(const _LeaderboardSkeletonRow());
        rows.add(const _LeaderboardSkeletonRow());
      } else if (!state.leaderboardHasMore) {
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
              '— end of list —',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black.withOpacity(0.4),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ));
      }
    }

    return _SectionCard(
      title: selectedType.label,
      subtitle: _buildSubtitle(state),
      headerTrailing: mobile ? null : _TypeSwitcher(selected: selectedType),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mobile) ...[
            const SizedBox(height: 4),
            _TypeSwitcher(selected: selectedType),
            const SizedBox(height: 10),
          ],
          _LeaderboardSearchField(
            controller: _searchCtrl,
            placeholder: selectedType.searchPlaceholder,
            onChanged: _onSearchChanged,
            onClear: () {
              _searchCtrl.clear();
              _searchDebounce?.cancel();
              context
                  .read<SalesDashboardBloc>()
                  .add(const SalesDashboardLeaderboardSearchChanged(''));
            },
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  String _buildSubtitle(SalesDashboardLoaded state) {
    final shown = state.topPerformers.length;
    final total = state.topPerformersTotal;
    if (total == 0 && shown == 0) {
      return 'Hierarchy-scoped to your role';
    }
    if (state.leaderboardSearch.isEmpty) {
      return 'Showing $shown of $total — hierarchy-scoped';
    }
    return 'Showing $shown of $total for "${state.leaderboardSearch}"';
  }
}

class _LeaderboardSearchField extends StatelessWidget {
  const _LeaderboardSearchField({
    required this.controller,
    required this.placeholder,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TextStyle(
              fontSize: 13,
              color: Colors.black.withOpacity(0.4),
            ),
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onClear,
                    tooltip: 'Clear',
                  ),
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF1F4F8),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF00A0A8), width: 1),
            ),
          ),
          style: const TextStyle(fontSize: 14),
        );
      },
    );
  }
}

/// Three pills — KAMs / Hospitals / Products. Active pill is filled with
/// the teal brand colour; inactive pills sit on the neutral surface. Wraps
/// when the row is too narrow.
class _TypeSwitcher extends StatelessWidget {
  const _TypeSwitcher({required this.selected});
  final TopPerformerType selected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: TopPerformerType.values.map((t) {
        final isActive = t == selected;
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: isActive
              ? null
              : () => context
                  .read<SalesDashboardBloc>()
                  .add(SalesDashboardTopPerformerTypeChanged(t)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF00A0A8)
                  : const Color(0xFFF1F4F8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              t.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.white : const Color(0xFF374151),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

/// Initial-load skeleton — 4 placeholder rows mimicking the KAM row layout
/// (rank dot, name+code stack, value column, metric pills, progress bar).
class _LeaderboardSkeleton extends StatelessWidget {
  const _LeaderboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _LeaderboardSkeletonRow(),
        _LeaderboardSkeletonRow(),
        _LeaderboardSkeletonRow(),
        _LeaderboardSkeletonRow(),
      ],
    );
  }
}

class _LeaderboardSkeletonRow extends StatelessWidget {
  const _LeaderboardSkeletonRow();

  @override
  Widget build(BuildContext context) {
    final base = Colors.grey.shade300;
    final highlight = Colors.grey.shade100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        period: const Duration(milliseconds: 1200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _shimmerBox(width: 28, height: 28, radius: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _shimmerBox(width: double.infinity, height: 12),
                      const SizedBox(height: 6),
                      _shimmerBox(width: 80, height: 10),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _shimmerBox(width: 30, height: 9),
                    const SizedBox(height: 4),
                    _shimmerBox(width: 60, height: 12),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Wrap(
                spacing: 8,
                children: [
                  _shimmerBox(width: 70, height: 28, radius: 10),
                  _shimmerBox(width: 70, height: 28, radius: 10),
                  _shimmerBox(width: 70, height: 28, radius: 10),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _shimmerBox(width: double.infinity, height: 6, radius: 3),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBox({required double width, required double height, double radius = 4}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Richer leaderboard row used for the "All KAMs" section.
///
/// Layout adapts to width:
///   • mobile (< 600px): name + sales on the top line, the three secondary
///     metrics (Target / Achievement % / Gap) wrap into pill chips below,
///     then the progress bar. No horizontal scroll needed.
///   • wider screens (≥ 600px): the row stays compact and the metrics
///     render as a single right-aligned strip beside the name.
///
/// Achievement % drives the progress bar so the user can eyeball who is
/// behind / on track / over-target. Bar capped at 100% visually; the
/// numeric % stays unbounded.
class _KamLeaderboardRow extends StatelessWidget {
  const _KamLeaderboardRow({
    required this.rank,
    required this.performer,
    required this.type,
  });

  final int rank;
  final TopPerformer performer;
  final TopPerformerType type;

  static const Color _green = Color(0xFF16A34A);
  static const Color _red = Color(0xFFB91C1C);
  static const Color _teal = Color(0xFF00A0A8);

  Color _statusColor(double pct) {
    if (pct >= 100) return _green;            // over target
    if (pct >= 75) return _teal;              // on track
    if (pct >= 50) return const Color(0xFFF59E0B); // amber — behind
    return const Color(0xFFEF4444);           // red — far behind
  }

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    final pct = performer.achievementPct;
    final isProduct = type == TopPerformerType.products;

    // Products: pct is share-of-total (0–100); use a neutral teal bar.
    // KAMs/Hospitals: pct is achievement-vs-target; colour by status.
    final statusColor = isProduct ? _teal : _statusColor(pct);
    final barFraction = (pct / 100).clamp(0.0, 1.0);

    final List<Widget> metrics;
    if (isProduct) {
      // Brands have no target → no Target / Gap pills. Show the share of
      // total brand sales instead.
      metrics = [
        _MetricPill(
          label: '% of Sales',
          value: '${pct.toStringAsFixed(1)}%',
          color: _teal,
        ),
      ];
    } else {
      // Gap pill: green surplus when target met/exceeded, red shortfall
      // otherwise, neutral dash when no target is on file.
      Widget gapPill;
      if (performer.target <= 0) {
        gapPill = const _MetricPill(label: 'Gap', value: '—');
      } else if (performer.isSurplus) {
        gapPill = _MetricPill(
          label: 'Surplus',
          value: '+${_inr(performer.surplus)}',
          color: _green,
        );
      } else {
        gapPill = _MetricPill(
          label: 'Gap',
          value: _inr(performer.targetGap),
          color: _red,
        );
      }
      metrics = [
        _MetricPill(label: 'Target', value: _inr(performer.target)),
        _MetricPill(
          label: 'Ach %',
          value: '${pct.toStringAsFixed(1)}%',
          color: statusColor,
        ),
        gapPill,
      ];
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _RankBadge(rank: rank),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // displayName adds " (City — BTST)" for hospitals,
                      // falls back to plain name for KAMs / Products.
                      performer.displayName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (performer.code != null &&
                        performer.code!.isNotEmpty &&
                        // Hospitals already surface the code via
                        // displayName, so don't repeat it below the name.
                        performer.btstCode.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          performer.code!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Sales value lives on the top-right corner on every breakpoint
              // so the most-important number is always visible without scroll.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Sales',
                    style: TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _inr(performer.achievement),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Metric strip — pills wrap onto a second row on narrow phones.
          Padding(
            padding: EdgeInsets.only(left: mobile ? 0 : 40),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: mobile ? WrapAlignment.start : WrapAlignment.end,
              children: metrics,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: barFraction,
              minHeight: 6,
              backgroundColor: const Color(0xFFEEF2F7),
              valueColor: AlwaysStoppedAnimation(statusColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small label-over-value chip used on the KAM row's metric strip. Keeps
/// the row readable at mobile widths without overflowing.
class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color ?? const Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    final colors = rank == 1
        ? const [Color(0xFFFFD700), Color(0xFFFFA500)]
        : rank == 2
            ? const [Color(0xFFC0C0C0), Color(0xFF9CA3AF)]
            : rank == 3
                ? const [Color(0xFFCD7F32), Color(0xFFA85C28)]
                : const [Color(0xFFE5E7EB), Color(0xFFD1D5DB)];
    final textColor = rank <= 3 ? Colors.white : const Color(0xFF374151);
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.subtitle,
    this.headerTrailing,
    required this.child,
    this.extra,
  });

  final String title;
  final String? subtitle;
  final Widget? headerTrailing;
  final Widget child;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    final pad = mobile
        ? const EdgeInsets.fromLTRB(14, 12, 14, 14)
        : const EdgeInsets.fromLTRB(18, 16, 18, 18);
    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(mobile ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: mobile ? 14 : 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: mobile ? 11 : 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (headerTrailing != null) headerTrailing!,
            ],
          ),
          SizedBox(height: mobile ? 12 : 14),
          child,
          if (extra != null) extra!,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, size: 36, color: Colors.black.withOpacity(0.2)),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

class _SkeletonView extends StatelessWidget {
  const _SkeletonView();

  @override
  Widget build(BuildContext context) {
    Widget box({double height = 100, double width = double.infinity}) => Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(16),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        box(height: 56),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: box(height: 110)),
            const SizedBox(width: 12),
            Expanded(child: box(height: 110)),
            const SizedBox(width: 12),
            Expanded(child: box(height: 110)),
            const SizedBox(width: 12),
            Expanded(child: box(height: 110)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: box(height: 110)),
            const SizedBox(width: 12),
            Expanded(child: box(height: 110)),
            const SizedBox(width: 12),
            Expanded(child: box(height: 110)),
            const SizedBox(width: 12),
            Expanded(child: box(height: 110)),
          ],
        ),
        const SizedBox(height: 16),
        box(height: 280),
        const SizedBox(height: 16),
        box(height: 360),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
              onPressed: () => context
                  .read<SalesDashboardBloc>()
                  .add(const SalesDashboardLoadRequested()),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORMATTING HELPERS
// ─────────────────────────────────────────────────────────────────────────────

String _inr(double v) {
  // Indian rupee with Cr/L suffixes for compactness.
  if (v.abs() >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v.abs() >= 100000) return '₹${(v / 100000).toStringAsFixed(2)} L';
  if (v.abs() >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
  return '₹${v.toStringAsFixed(0)}';
}

String _compactInr(double v) {
  if (v.abs() >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
  if (v.abs() >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
  return v.toStringAsFixed(0);
}

String _int(int v) => NumberFormat.decimalPattern('en_IN').format(v);
