import 'package:flutter/material.dart';
import 'package:zydus_vistaar/Models/sales_dashboard_models.dart';
import 'package:zydus_vistaar/services/sales_dashboard_service.dart';

/// Executive KPI strip rendered on top of the Dashboard / Home screen so a
/// user sees Sales · POD · Target · Achievement · Growth at a glance without
/// drilling into Sales Analytics.
///
/// Values come from the EXISTING `/api/sales-dashboard/summary-cards`
/// endpoint, which already enforces the same hierarchy scoping used by the
/// web dashboard (KAM → own; manager → team; admin → org). No new business
/// logic is introduced here — this widget only renders fields the backend
/// already computes.
///
/// Two cards (Total POD Value, POD vs Sales Completion %) read fields that
/// the public summary-cards endpoint does not yet expose; they degrade to a
/// "—" placeholder until the backend ships those keys. See the model's
/// `totalPodValue` / `salesVsPodsCompletion` for the keys it looks for.
class ExecutiveKpiSection extends StatefulWidget {
  const ExecutiveKpiSection({super.key});

  @override
  State<ExecutiveKpiSection> createState() => _ExecutiveKpiSectionState();
}

class _ExecutiveKpiSectionState extends State<ExecutiveKpiSection> {
  late final SalesDashboardService _service;
  late Future<SalesSummaryCards> _future;

  @override
  void initState() {
    super.initState();
    _service = SalesDashboardService();
    _future = _service.fetchSummaryCards(SalesDashboardFilters.empty);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _service.fetchSummaryCards(SalesDashboardFilters.empty);
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
    final podValue = summary.totalPodValue;
    final podVsSalesPct = summary.salesVsPodsCompletion
        ?? _deriveCompletion(podValue, summary.totalSalesAmount);

    final cards = <_KpiCardData>[
      _KpiCardData(
        title: 'Total Sales Value',
        value: '\u{20B9}${_formatAmount(summary.totalSalesAmount)}',
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFF00A0A8),
      ),
      _KpiCardData(
        title: 'Total POD Value',
        value: podValue == null
            ? '—'
            : '\u{20B9}${_formatAmount(podValue)}',
        icon: Icons.inventory_2_rounded,
        color: const Color(0xFF7C4DFF),
        hint: podValue == null
            ? 'Pending backend (summary-cards.total_pod_value)'
            : null,
      ),
      _KpiCardData(
        title: 'POD vs Sales Completion',
        value: podVsSalesPct == null
            ? '—'
            : '${podVsSalesPct.toStringAsFixed(1)}%',
        icon: Icons.donut_small_rounded,
        color: const Color(0xFF26A69A),
        progress: podVsSalesPct == null
            ? null
            : (podVsSalesPct / 100).clamp(0.0, 1.0).toDouble(),
        progressCaption: podVsSalesPct == null
            ? null
            : '\u{20B9}${_formatAmount(podValue ?? 0)} / _${_formatAmount(summary.totalSalesAmount)}',
        hint: podVsSalesPct == null
            ? 'Pending backend (summary-cards.sales_vs_pods_completion_rate)'
            : null,
      ),
      _KpiCardData(
        title: 'Total Target',
        value: '\u{20B9}${_formatAmount(summary.totalTargetAmount)}',
        icon: Icons.flag_rounded,
        color: const Color(0xFF6366F1),
      ),
      _KpiCardData(
        title: 'Total Achievement',
        value: '\u{20B9}${_formatAmount(summary.netSalesAmount)}',
        icon: Icons.emoji_events_rounded,
        color: const Color(0xFF42A5F5),
      ),
      _KpiCardData(
        title: 'Achievement %',
        value: '${summary.achievementPercentage.toStringAsFixed(1)}%',
        icon: Icons.percent_rounded,
        color: const Color(0xFF1E88E5),
        progress: (summary.achievementPercentage / 100).clamp(0.0, 1.0).toDouble(),
      ),
      _KpiCardData(
        title: 'Gap to Target',
        value: '\u{20B9}${_formatAmount(summary.gapToTarget.abs())}',
        icon: summary.gapToTarget > 0
            ? Icons.trending_down_rounded
            : Icons.check_circle_rounded,
        color: summary.gapToTarget > 0
            ? const Color(0xFFEF5350)
            : const Color(0xFF66BB6A),
      ),
      _KpiCardData(
        title: 'Growth vs Last Year',
        value: '${summary.growthPercentage >= 0 ? '+' : ''}${summary.growthPercentage.toStringAsFixed(1)}%',
        icon: summary.growthPercentage >= 0
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded,
        color: summary.growthPercentage >= 0
            ? const Color(0xFF66BB6A)
            : const Color(0xFFEF5350),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // Mobile 2 / Tablet 3 / Desktop 4 — per spec.
        final cols = w >= 1024 ? 4 : (w >= 600 ? 3 : 2);
        // Compact aspect so 4 rows fit above-the-fold on phones.
        final aspect = w >= 1024 ? 1.45 : (w >= 600 ? 1.35 : 1.15);
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
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: aspect,
              ),
              itemBuilder: (context, i) => _KpiCard(data: cards[i]),
            ),
          ],
        );
      },
    );
  }

  static double? _deriveCompletion(double? podValue, double salesValue) {
    if (podValue == null) return null;
    if (salesValue <= 0) return 0;
    return (podValue / salesValue) * 100;
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
  final IconData icon;
  final Color color;
  final double? progress;
  final String? progressCaption;
  final String? hint;

  const _KpiCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.progress,
    this.progressCaption,
    this.hint,
  });
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});

  final _KpiCardData data;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EEF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: data.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(data.icon, color: data.color, size: 16),
              ),
              const Spacer(),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  data.value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: data.color,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              if (data.progress != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: data.progress,
                    minHeight: 4,
                    backgroundColor: data.color.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(data.color),
                  ),
                ),
                if (data.progressCaption != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    data.progressCaption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ],
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
        final aspect = w >= 1024 ? 1.45 : (w >= 600 ? 1.35 : 1.15);
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
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: aspect,
              ),
              itemBuilder: (_, __) => Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F6F8),
                  borderRadius: BorderRadius.circular(12),
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

String _formatAmount(double amount) {
  if (amount.abs() >= 10000000) {
    return '${(amount / 10000000).toStringAsFixed(2)} Cr';
  } else if (amount.abs() >= 100000) {
    return '${(amount / 100000).toStringAsFixed(2)} L';
  } else if (amount.abs() >= 1000) {
    return '${(amount / 1000).toStringAsFixed(1)} K';
  }
  return amount.toStringAsFixed(0);
}
