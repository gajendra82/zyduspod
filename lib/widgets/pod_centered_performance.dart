import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zydus_vistaar/Models/sales_dashboard_models.dart';
import 'package:zydus_vistaar/config.dart';

/// Zone + KAM analytics for the POD Dashboard tab.
///
/// Sources a single payload from `/api/sales-dashboard/pod-centered-performance`
/// (returns both `by_zone` and `by_emp` in one request to keep the round-trip
/// count down). The backend already enforces the hierarchy scope used by
/// every other sales-dashboard endpoint — admin → all, KAM → own, manager
/// → team — so the lists shown here automatically respect "show me only
/// what I can see".
///
/// The widget rebuilds whenever the parent passes a new month window via
/// the `filters` prop (the POD Dashboard's month dropdown lifts state into
/// the parent and threads it through).
class PodCenteredPerformanceSection extends StatefulWidget {
  const PodCenteredPerformanceSection({super.key, this.filters});

  final SalesDashboardFilters? filters;

  @override
  State<PodCenteredPerformanceSection> createState() =>
      _PodCenteredPerformanceSectionState();
}

class _PodCenteredPerformanceSectionState
    extends State<PodCenteredPerformanceSection> {
  late Future<_PodPerf> _future;

  // KAM list controls
  final TextEditingController _searchCtl = TextEditingController();
  Timer? _searchDebounce;
  String _search = '';

  // Zone list sort
  _ZoneSort _zoneSort = _ZoneSort.salesDesc;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant PodCenteredPerformanceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.filters;
    final b = widget.filters;
    if (a?.dateFrom != b?.dateFrom || a?.dateTo != b?.dateTo) {
      setState(() => _future = _fetch());
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<_PodPerf> _fetch() async {
    final q = <String, String>{};
    final f = widget.filters;
    if (f?.dateFrom != null && f!.dateFrom!.isNotEmpty) q['date_from'] = f.dateFrom!;
    if (f?.dateTo != null && f!.dateTo!.isNotEmpty) q['date_to'] = f.dateTo!;
    final uri = Uri.parse('${API_BASE_URL}sales-dashboard/pod-centered-performance')
        .replace(queryParameters: q.isEmpty ? null : q);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    final res = await http.get(uri, headers: {
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    }).timeout(const Duration(seconds: 45));

    if (res.statusCode == 401) {
      throw const _PerfException('Session expired — please sign in again.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _PerfException('Request failed (${res.statusCode})');
    }
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic> || body['success'] != true) {
      throw const _PerfException('Unexpected response shape');
    }
    final data = (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final zones = ((data['by_zone'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => _ZoneRow.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
    final kams = ((data['by_emp'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => _KamRow.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
    return _PodPerf(zones: zones, kams: kams);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _search = value.trim().toLowerCase());
    });
  }

  void _cycleZoneSort() {
    setState(() {
      _zoneSort = _zoneSort == _ZoneSort.salesDesc
          ? _ZoneSort.completionDesc
          : _ZoneSort.salesDesc;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PodPerf>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Skeleton();
        }
        if (snap.hasError) {
          return _ErrorPanel(
            message: snap.error.toString(),
            onRetry: () => setState(() => _future = _fetch()),
          );
        }
        final data = snap.data ?? const _PodPerf(zones: [], kams: []);
        final zones = [...data.zones];
        if (_zoneSort == _ZoneSort.salesDesc) {
          zones.sort((a, b) => b.salesValue.compareTo(a.salesValue));
        } else {
          zones.sort((a, b) => b.completionPct.compareTo(a.completionPct));
        }

        final filteredKams = _search.isEmpty
            ? data.kams
            : data.kams.where((k) {
                return k.name.toLowerCase().contains(_search)
                    || k.empId.toLowerCase().contains(_search);
              }).toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ZoneSection(
              zones: zones,
              sort: _zoneSort,
              onCycleSort: _cycleZoneSort,
            ),
            const SizedBox(height: 18),
            _KamSection(
              kams: filteredKams,
              totalKams: data.kams.length,
              searchCtl: _searchCtl,
              onSearchChanged: _onSearchChanged,
            ),
          ],
        );
      },
    );
  }
}

enum _ZoneSort { salesDesc, completionDesc }

class _PodPerf {
  final List<_ZoneRow> zones;
  final List<_KamRow> kams;
  const _PodPerf({required this.zones, required this.kams});
}

class _ZoneRow {
  final String zone;
  final double salesValue;
  final double zydusPodValue;
  final double completionPct;

  const _ZoneRow({
    required this.zone,
    required this.salesValue,
    required this.zydusPodValue,
    required this.completionPct,
  });

  factory _ZoneRow.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v is num ? v.toDouble() : 0.0;
    return _ZoneRow(
      zone: (j['zone'] ?? '—').toString(),
      salesValue: d(j['sales_value']),
      zydusPodValue: d(j['zydus_pod_value']),
      completionPct: d(j['completion_pct']),
    );
  }
}

class _KamRow {
  final String empId;
  final String name;
  final String zone;
  final double salesValue;
  final double zydusPodValue;
  final double completionPct;
  final int processedPodCount;

  const _KamRow({
    required this.empId,
    required this.name,
    required this.zone,
    required this.salesValue,
    required this.zydusPodValue,
    required this.completionPct,
    required this.processedPodCount,
  });

  factory _KamRow.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v is num ? v.toDouble() : 0.0;
    int i(dynamic v) => v is num ? v.toInt() : 0;
    return _KamRow(
      empId: (j['emp_id'] ?? '').toString(),
      name: (j['name'] ?? 'Unknown').toString(),
      zone: (j['zone'] ?? '—').toString(),
      salesValue: d(j['sales_value']),
      zydusPodValue: d(j['zydus_pod_value']),
      completionPct: d(j['completion_pct']),
      processedPodCount: i(j['processed_pod_count']),
    );
  }
}

class _PerfException implements Exception {
  final String message;
  const _PerfException(this.message);
  @override
  String toString() => message;
}

// ─────────────────────────────────────────────────────────────────────────────
// ZONE SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _ZoneSection extends StatelessWidget {
  const _ZoneSection({
    required this.zones,
    required this.sort,
    required this.onCycleSort,
  });

  final List<_ZoneRow> zones;
  final _ZoneSort sort;
  final VoidCallback onCycleSort;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionHeader(
                icon: Icons.public_rounded,
                title: 'Zone Performance',
              ),
              const Spacer(),
              InkWell(
                onTap: onCycleSort,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F4F8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort_rounded, size: 14, color: Color(0xFF00A0A8)),
                      const SizedBox(width: 4),
                      Text(
                        sort == _ZoneSort.salesDesc ? 'Sales' : 'Completion %',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (zones.isEmpty)
            const _EmptyState(message: 'No zone data for the selected month.')
          else
            Column(
              children: [
                for (final z in zones) _ZoneTile(row: z),
              ],
            ),
        ],
      ),
    );
  }
}

class _ZoneTile extends StatelessWidget {
  const _ZoneTile({required this.row});

  final _ZoneRow row;

  @override
  Widget build(BuildContext context) {
    final pct = row.completionPct.clamp(0.0, 100.0).toDouble();
    final color = _completionColor(pct);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  row.zone,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_inr(row.salesValue)} sales · ${_inr(row.zydusPodValue)} zydus',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${row.completionPct.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 5,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KAM SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _KamSection extends StatelessWidget {
  const _KamSection({
    required this.kams,
    required this.totalKams,
    required this.searchCtl,
    required this.onSearchChanged,
  });

  final List<_KamRow> kams;
  final int totalKams;
  final TextEditingController searchCtl;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionHeader(
                icon: Icons.people_alt_rounded,
                title: 'KAM Performance',
              ),
              const Spacer(),
              Text(
                '$totalKams KAMs',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: searchCtl,
            onChanged: onSearchChanged,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search KAM name or employee ID',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              filled: true,
              fillColor: const Color(0xFFF1F4F8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (kams.isEmpty)
            const _EmptyState(message: 'No KAMs match the current filter.')
          else
            Column(
              children: [
                for (var i = 0; i < kams.length; i++)
                  _KamCard(rank: i + 1, row: kams[i]),
              ],
            ),
        ],
      ),
    );
  }
}

class _KamCard extends StatelessWidget {
  const _KamCard({required this.rank, required this.row});

  final int rank;
  final _KamRow row;

  @override
  Widget build(BuildContext context) {
    final pct = row.completionPct.clamp(0.0, 100.0).toDouble();
    final pctColor = _completionColor(pct);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EEF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF00A0A8).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF00A0A8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    Text(
                      '${row.empId} · ${row.zone}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: pctColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${pct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: pctColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Triplet line: Sales | Zydus | Processed PODs. On the narrowest
          // phones this wraps onto a single horizontal scroller, but in
          // practice the three pills + their values fit on a 360-px viewport.
          Row(
            children: [
              Expanded(
                child: _MetricCell(
                  label: 'Sales',
                  value: _inr(row.salesValue),
                  color: const Color(0xFF0EA5E9),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCell(
                  label: 'Zydus',
                  value: _inr(row.zydusPodValue),
                  color: const Color(0xFF8B5CF6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCell(
                  label: 'Processed',
                  value: _int(row.processedPodCount),
                  color: const Color(0xFF14B8A6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED CHROME
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EEF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF00A0A8).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF00A0A8), size: 16),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2C3E50),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w) => Container(
          width: w,
          height: 12,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6F8),
            borderRadius: BorderRadius.circular(4),
          ),
        );
    return Column(
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(160),
              const SizedBox(height: 16),
              for (var i = 0; i < 4; i++) ...[
                bar(double.infinity),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(180),
              const SizedBox(height: 16),
              for (var i = 0; i < 4; i++) ...[
                bar(double.infinity),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
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
              'Zone / KAM analytics failed to load. $message',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORMATTERS / SHARED HELPERS
// ─────────────────────────────────────────────────────────────────────────────

String _inr(double amount) {
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

Color _completionColor(double pct) {
  if (pct >= 75) return const Color(0xFF059669); // green
  if (pct >= 50) return const Color(0xFF0EA5E9); // blue
  if (pct >= 25) return const Color(0xFFF59E0B); // amber
  return const Color(0xFFEF4444); // red
}
