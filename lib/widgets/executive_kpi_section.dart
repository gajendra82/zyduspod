import 'package:flutter/material.dart';
import 'package:zydus_vistaar/Models/sales_dashboard_models.dart';
import 'package:zydus_vistaar/services/sales_dashboard_service.dart';

/// Executive KPI strip rendered on top of the POD Dashboard tab so a user
/// sees Sales · Zydus Product Value · Target · Achievement · Growth at a
/// glance without drilling into Sales Analytics.
///
/// Values come from the EXISTING `/api/sales-dashboard/summary-cards`
/// endpoint, which already enforces the same hierarchy scoping used by the
/// web dashboard (KAM → own; manager → team; admin → org). No new business
/// logic — this widget only renders fields the backend already computes.
///
/// "POD vs Sales Completion %" uses the backend's pre-computed
/// `sales_vs_pods_completion_rate`, which is defined as
/// `Zydus Product POD Value / Sales Value × 100` (NOT total POD value).
/// The card body therefore shows the Zydus figure as the numerator so the
/// math the user sees on screen matches the % displayed.
class ExecutiveKpiSection extends StatefulWidget {
  /// Optional date-window filter (e.g. month-pinned). When null the section
  /// falls back to `SalesDashboardFilters.empty` (= no window = backend
  /// default).
  const ExecutiveKpiSection({super.key, this.filters});

  final SalesDashboardFilters? filters;

  @override
  State<ExecutiveKpiSection> createState() => _ExecutiveKpiSectionState();
}

class _ExecutiveKpiSectionState extends State<ExecutiveKpiSection> {
  late final SalesDashboardService _service;
  late Future<SalesSummaryCards> _future;

  SalesDashboardFilters get _effectiveFilters =>
      widget.filters ?? SalesDashboardFilters.empty;

  @override
  void initState() {
    super.initState();
    _service = SalesDashboardService();
    _future = _service.fetchSummaryCards(_effectiveFilters);
  }

  @override
  void didUpdateWidget(covariant ExecutiveKpiSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.filters;
    final b = widget.filters;
    final changed = a?.dateFrom != b?.dateFrom || a?.dateTo != b?.dateTo;
    if (changed) {
      setState(() {
        _future = _service.fetchSummaryCards(_effectiveFilters);
      });
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _service.fetchSummaryCards(_effectiveFilters);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SalesSummaryCards>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _SkeletonGrid();
        }
        if (snapshot.hasError) {
          return _ErrorPanel(
            message: snapshot.error.toString(),
            onRetry: _reload,
          );
        }
        final s = snapshot.data ?? SalesSummaryCards.empty;
        return _KpiGrid(summary: s);
      },
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.summary});

  final SalesSummaryCards summary;

  @override
  Widget build(BuildContext context) {
    // Zydus product value is what feeds the completion-% formula on the
    // backend. Fall back to nothing rather than guessing if the field is
    // absent — the card degrades to "—" so the user knows the value
    // upstream hasn't been computed yet.
    final zydusValue = summary.zydusProductValue;
    final salesValue = summary.totalSalesAmount;
    final podVsSalesPct = summary.salesVsPodsCompletion
        ?? _deriveCompletion(zydusValue, salesValue);

    final cards = <_KpiCardData>[
      _KpiCardData(
        title: 'Total Sales Value',
        value: _inr(salesValue),
        subtitle: 'Achievement (net sales)',
        icon: Icons.account_balance_wallet_rounded,
        gradient: const [Color(0xFF0EA5E9), Color(0xFF38BDF8)], // blue
      ),
      _KpiCardData(
        title: 'Zydus Product Value',
        value: zydusValue == null ? '—' : _inr(zydusValue),
        subtitle: 'Zydus lines on PODs',
        icon: Icons.medication_rounded,
        gradient: const [Color(0xFF6366F1), Color(0xFF818CF8)], // indigo
        hint: zydusValue == null
            ? 'Pending backend: summary-cards.zydus_product_value'
            : null,
      ),
      _KpiCardData(
        title: 'POD vs Sales Completion',
        value: podVsSalesPct == null
            ? '—'
            : '${podVsSalesPct.toStringAsFixed(1)}%',
        subtitle: zydusValue != null && salesValue > 0
            ? '${_inr(zydusValue)} / ${_inr(salesValue)}'
            : 'Zydus / Sales',
        icon: Icons.donut_small_rounded,
        gradient: const [Color(0xFF10B981), Color(0xFF34D399)], // green
        progress: podVsSalesPct == null
            ? null
            : (podVsSalesPct / 100).clamp(0.0, 1.0).toDouble(),
      ),
      _KpiCardData(
        title: 'Total Target',
        value: _inr(summary.totalTargetAmount),
        subtitle: 'Sum of hospital targets',
        icon: Icons.flag_rounded,
        gradient: const [Color(0xFF8B5CF6), Color(0xFFA78BFA)], // violet
      ),
      _KpiCardData(
        title: 'Total Achievement',
        value: _inr(summary.netSalesAmount),
        subtitle: 'Net sales (sales − returns)',
        icon: Icons.emoji_events_rounded,
        gradient: const [Color(0xFF06B6D4), Color(0xFF22D3EE)], // cyan
      ),
      // Achievement % — honest "—" when there's no target in the window
      // (e.g. monthly view where seed only has yearly targets) so the user
      // doesn't read "0.0%" as "actually zero achievement". When a target
      // exists, recompute defensively from achievement/target so the card
      // never disagrees with the two numbers above it.
      () {
        final hasTarget = summary.totalTargetAmount > 0;
        final pct = hasTarget
            ? (summary.netSalesAmount / summary.totalTargetAmount) * 100
            : null;
        return _KpiCardData(
          title: 'Achievement %',
          value: pct == null ? '—' : '${pct.toStringAsFixed(1)}%',
          subtitle: hasTarget ? 'vs target' : 'No target in window',
          icon: Icons.percent_rounded,
          gradient: pct == null
              ? const [Color(0xFF94A3B8), Color(0xFFCBD5E1)] // slate (neutral)
              : _pctGradient(pct),
          progress: pct == null ? null : (pct / 100).clamp(0.0, 1.0).toDouble(),
        );
      }(),
      // Gap to Target — show SIGNED variance so a KAM who's exceeded the
      // target sees their surplus instead of a flat "₹0". Backend's
      // `gap_to_target` is clamped to ≥ 0 which hides surplus; use
      // `variance_amount` (net − target, signed) for the right semantic.
      () {
        final variance = summary.varianceAmount; // signed
        final isSurplus = variance > 0;
        final hasTarget = summary.totalTargetAmount > 0;
        return _KpiCardData(
          title: 'Gap to Target',
          value: variance == 0
              ? _inr(0)
              : (isSurplus ? '+${_inr(variance)}' : _inr(variance.abs())),
          subtitle: !hasTarget
              ? 'No target — surplus over zero'
              : isSurplus
                  ? 'Target met or exceeded'
                  : 'Still to achieve',
          icon: isSurplus
              ? Icons.check_circle_rounded
              : Icons.trending_down_rounded,
          gradient: isSurplus
              ? const [Color(0xFF059669), Color(0xFF10B981)] // green (surplus)
              : const [Color(0xFFEF4444), Color(0xFFF87171)], // red (shortfall)
        );
      }(),
      // Processed POD Count — replaces the "Growth vs Last Year" card per
      // product call (growth is already on the Sales Analytics tab and
      // showing it twice was redundant).
      _KpiCardData(
        title: 'Processed POD Count',
        value: summary.processedPodCount == null
            ? '—'
            : _int(summary.processedPodCount!),
        subtitle: 'PODs with status=processed',
        icon: Icons.task_alt_rounded,
        gradient: const [Color(0xFF14B8A6), Color(0xFF2DD4BF)], // teal
        hint: summary.processedPodCount == null
            ? 'Pending backend: summary-cards.processed_pod_count'
            : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // Mobile 2 / Tablet 3 / Desktop 4 — per spec.
        final cols = w >= 1024 ? 4 : (w >= 600 ? 3 : 2);
        // Slightly wider-than-tall on phones; closer to square on large
        // screens to match the Sales Analytics grid.
        final aspect = w >= 1100 ? 1.65 : (w >= 600 ? 1.55 : 1.35);
        final spacing = cols >= 3 ? 12.0 : 10.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: aspect,
              ),
              itemBuilder: (context, i) => _KpiCard(data: cards[i]),
            ),
          ],
        );
      },
    );
  }

  static double? _deriveCompletion(double? zydusValue, double salesValue) {
    if (zydusValue == null) return null;
    if (salesValue <= 0) return 0;
    return (zydusValue / salesValue) * 100;
  }

  static List<Color> _pctGradient(double pct) {
    if (pct >= 100) return const [Color(0xFF059669), Color(0xFF10B981)];
    if (pct >= 75) return const [Color(0xFF0EA5E9), Color(0xFF38BDF8)];
    if (pct >= 50) return const [Color(0xFFF59E0B), Color(0xFFFBBF24)];
    return const [Color(0xFFEF4444), Color(0xFFF87171)];
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF00A0A8).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.insights_rounded,
            color: Color(0xFF00A0A8),
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'Executive Overview',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2C3E50),
          ),
        ),
      ],
    );
  }
}

class _KpiCardData {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final double? progress;
  final String? hint;

  const _KpiCardData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.progress,
    this.hint,
  });
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});

  final _KpiCardData data;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.of(context).size.width < 600;
    final cardPad = mobile ? 11.0 : 13.0;
    final iconSize = mobile ? 16.0 : 18.0;
    final iconBoxPad = mobile ? 6.0 : 7.0;
    final progressDim = mobile ? 30.0 : 34.0;
    final titleSize = mobile ? 11.0 : 12.0;
    final valueSize = mobile ? 20.0 : 24.0;
    final subtitleSize = mobile ? 10.0 : 11.0;

    final card = Container(
      padding: EdgeInsets.all(cardPad),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: data.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(mobile ? 14 : 16),
        boxShadow: [
          BoxShadow(
            color: data.gradient.first.withOpacity(0.28),
            blurRadius: mobile ? 9 : 14,
            offset: Offset(0, mobile ? 4 : 6),
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
                child: Icon(data.icon, color: Colors.white, size: iconSize),
              ),
              const Spacer(),
              if (data.progress != null)
                SizedBox(
                  width: progressDim,
                  height: progressDim,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: data.progress,
                        strokeWidth: mobile ? 3.5 : 4,
                        backgroundColor: Colors.white.withOpacity(0.25),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                      Text(
                        '${((data.progress ?? 0) * 100).round()}%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: mobile ? 8 : 9,
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
            data.title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: titleSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data.value,
              style: TextStyle(
                color: Colors.white,
                fontSize: valueSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: subtitleSize,
            ),
            maxLines: mobile ? 2 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (data.hint == null) return card;
    return Tooltip(message: data.hint!, child: card);
  }
}

class _SkeletonGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 1024 ? 4 : (w >= 600 ? 3 : 2);
        final aspect = w >= 1100 ? 1.65 : (w >= 600 ? 1.55 : 1.35);
        final spacing = cols >= 3 ? 12.0 : 10.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 8,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: aspect,
              ),
              itemBuilder: (_, __) => Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F6F8),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade400, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Executive KPIs failed to load. $message',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Indian-grouped integer formatter (e.g. 1234567 → "12,34,567").
String _int(int n) {
  final s = n.abs().toString();
  if (s.length <= 3) return (n < 0 ? '-' : '') + s;
  final last3 = s.substring(s.length - 3);
  final rest = s.substring(0, s.length - 3);
  final grouped = rest.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{2})+$)'),
    (m) => '${m.group(1)},',
  );
  return (n < 0 ? '-' : '') + '$grouped,$last3';
}

String _inr(double amount) {
  // Unicode escape for the Indian rupee glyph (U+20B9) — avoids the
  // CP1252/UTF-8 round-trip mojibake that turned earlier literal '₹'
  // characters into '_' on disk.
  const rupee = '₹';
  if (amount.abs() >= 10000000) {
    return '$rupee${(amount / 10000000).toStringAsFixed(2)} Cr';
  } else if (amount.abs() >= 100000) {
    return '$rupee${(amount / 100000).toStringAsFixed(2)} L';
  } else if (amount.abs() >= 1000) {
    return '$rupee${(amount / 1000).toStringAsFixed(1)} K';
  }
  return '$rupee${amount.toStringAsFixed(0)}';
}
