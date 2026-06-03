import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zydus_vistaar/Models/sales_dashboard_models.dart';
import 'package:zydus_vistaar/config.dart';

/// Stockist + Hospital analytics for the POD Dashboard tab.
///
/// These two sections sit BELOW Zone Performance and KAM Performance (which
/// live in [PodCenteredPerformanceSection]) and share the exact same month
/// window + hierarchy scope as the rest of the dashboard — the parent threads
/// the selected month through the `filters` prop and the backend enforces the
/// "show me only what I can see" scope (KAM → mapped stockists / own
/// hospitals, manager → team, regional head → hierarchy, admin → everything).
///
/// Unlike the Zone/KAM sections — which load a small, bounded list in one shot
/// — stockists and hospitals can run into the thousands, so these sections are
/// **server-paginated**: the widget pulls one page at a time, appends with a
/// "Load more" control (lazy loading), and pushes search + sort to the server
/// so we never download the full table to filter it client-side.
///
/// Expected backend contracts (mirrors the per-emp aggregators the headline
/// KPIs already use; completion % = Zydus product POD value / sales value × 100):
///
///   GET /api/sales-dashboard/pod-stockist-performance
///   GET /api/sales-dashboard/pod-hospital-performance
///     query: date_from, date_to, search, sort, dir, page, per_page
///     data: { rows: [...], page, per_page, total, has_more }
///
/// Stockist row : stockist_name, stockist_code, sales_value,
///                zydus_pod_value, completion_pct, processed_pod_count
/// Hospital row : hospital_name, btst_code, city, sales_value,
///                zydus_pod_value, completion_pct, processed_pod_count

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC SECTIONS
// ─────────────────────────────────────────────────────────────────────────────

/// Stockist Performance — paginated, searchable (name + code), sortable.
class PodStockistPerformanceSection extends StatelessWidget {
  const PodStockistPerformanceSection({super.key, this.filters});

  final SalesDashboardFilters? filters;

  @override
  Widget build(BuildContext context) {
    return _PaginatedPerfSection<_StockistRow>(
      title: 'Stockist Performance',
      icon: Icons.store_mall_directory_rounded,
      endpoint: 'sales-dashboard/pod-stockist-performance',
      searchHint: 'Search stockist name or code',
      countLabel: 'stockists',
      filters: filters,
      parse: _StockistRow.fromJson,
      buildRow: (rank, row) => _StockistCard(rank: rank, row: row),
    );
  }
}

/// Hospital Performance — paginated, searchable (name + BTST code + city),
/// sortable.
class PodHospitalPerformanceSection extends StatelessWidget {
  const PodHospitalPerformanceSection({super.key, this.filters});

  final SalesDashboardFilters? filters;

  @override
  Widget build(BuildContext context) {
    return _PaginatedPerfSection<_HospitalRow>(
      title: 'Hospital Performance',
      icon: Icons.local_hospital_rounded,
      endpoint: 'sales-dashboard/pod-hospital-performance',
      searchHint: 'Search hospital, BTST code or city',
      countLabel: 'hospitals',
      filters: filters,
      parse: _HospitalRow.fromJson,
      buildRow: (rank, row) => _HospitalCard(rank: rank, row: row),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SORTING
// ─────────────────────────────────────────────────────────────────────────────

class _SortOption {
  final String key; // server-side sort key
  final String label;
  const _SortOption(this.key, this.label);
}

const List<_SortOption> _sortOptions = [
  _SortOption('sales', 'Sales Value'),
  _SortOption('zydus', 'Zydus Value'),
  _SortOption('completion', 'Completion %'),
  _SortOption('pods', 'POD Count'),
];

// ─────────────────────────────────────────────────────────────────────────────
// GENERIC PAGINATED SECTION
// ─────────────────────────────────────────────────────────────────────────────

typedef _RowParser<T> = T Function(Map<String, dynamic>);
typedef _RowBuilder<T> = Widget Function(int rank, T row);

/// One self-contained, server-paginated performance card. Drives the fetch
/// loop (page-by-page lazy loading), the debounced server-side search box and
/// the sort menu. The row shape is entirely delegated to [parse] / [buildRow]
/// so the same machinery powers both the Stockist and Hospital sections.
class _PaginatedPerfSection<T> extends StatefulWidget {
  const _PaginatedPerfSection({
    required this.title,
    required this.icon,
    required this.endpoint,
    required this.searchHint,
    required this.countLabel,
    required this.parse,
    required this.buildRow,
    this.filters,
  });

  final String title;
  final IconData icon;
  final String endpoint;
  final String searchHint;
  final String countLabel;
  final SalesDashboardFilters? filters;
  final _RowParser<T> parse;
  final _RowBuilder<T> buildRow;

  @override
  State<_PaginatedPerfSection<T>> createState() =>
      _PaginatedPerfSectionState<T>();
}

class _PaginatedPerfSectionState<T> extends State<_PaginatedPerfSection<T>> {
  static const int _perPage = 20;

  final TextEditingController _searchCtl = TextEditingController();
  Timer? _searchDebounce;

  final List<T> _rows = [];
  int _page = 0; // highest page loaded; 0 = none yet
  bool _hasMore = true;
  bool _loading = false; // initial / reset load
  bool _loadingMore = false;
  String? _error;
  int? _total;

  String _search = '';
  String _sortKey = _sortOptions.first.key; // default: highest Sales Value

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant _PaginatedPerfSection<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.filters;
    final b = widget.filters;
    // Month window changed upstream → reload from page 1 with the new period.
    if (a?.dateFrom != b?.dateFrom || a?.dateTo != b?.dateTo) {
      _reset();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _rows.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
      _total = null;
    });
    _loadPage(initial: true);
  }

  Future<void> _loadPage({required bool initial}) async {
    if (initial) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    final next = _page + 1;
    try {
      final result = await _fetch(next);
      if (!mounted) return;
      setState(() {
        _rows.addAll(result.rows);
        _page = next;
        _hasMore = result.hasMore;
        _total = result.total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<_Page<T>> _fetch(int page) async {
    final q = <String, String>{
      'page': page.toString(),
      'per_page': _perPage.toString(),
      'sort': _sortKey,
      'dir': 'desc',
    };
    final f = widget.filters;
    if (f?.dateFrom != null && f!.dateFrom!.isNotEmpty) q['date_from'] = f.dateFrom!;
    if (f?.dateTo != null && f!.dateTo!.isNotEmpty) q['date_to'] = f.dateTo!;
    if (_search.isNotEmpty) q['search'] = _search;

    final uri = Uri.parse('${API_BASE_URL}${widget.endpoint}')
        .replace(queryParameters: q);

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
    final rawRows = (data['rows'] as List?) ?? const [];
    final rows = rawRows
        .whereType<Map>()
        .map((m) => widget.parse(m.cast<String, dynamic>()))
        .toList(growable: false);

    int? total;
    final t = data['total'];
    if (t is num) total = t.toInt();

    // Trust an explicit has_more flag; otherwise infer from page fullness.
    bool hasMore;
    if (data['has_more'] is bool) {
      hasMore = data['has_more'] as bool;
    } else {
      hasMore = rows.length >= _perPage;
    }

    return _Page<T>(rows: rows, hasMore: hasMore, total: total);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final v = value.trim();
      if (!mounted || v == _search) return;
      _search = v;
      _reset();
    });
  }

  void _onSortSelected(String key) {
    if (key == _sortKey) return;
    _sortKey = key;
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionHeader(icon: widget.icon, title: widget.title),
              const Spacer(),
              if (_total != null)
                Text(
                  '$_total ${widget.countLabel}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtl,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.searchHint,
                    hintStyle:
                        TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    filled: true,
                    fillColor: const Color(0xFFF1F4F8),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SortMenu(selectedKey: _sortKey, onSelected: _onSortSelected),
            ],
          ),
          const SizedBox(height: 10),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const _InlineSkeleton();
    }
    if (_error != null && _rows.isEmpty) {
      return _ErrorPanel(
        title: widget.title,
        message: _error!,
        onRetry: _reset,
      );
    }
    if (_rows.isEmpty) {
      return _EmptyState(
        message: _search.isEmpty
            ? 'No ${widget.countLabel} for the selected month.'
            : 'No ${widget.countLabel} match "$_search".',
      );
    }

    return Column(
      children: [
        for (var i = 0; i < _rows.length; i++)
          widget.buildRow(i + 1, _rows[i]),
        const SizedBox(height: 4),
        if (_error != null && _rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Could not load more. $_error',
              style: TextStyle(fontSize: 11, color: Colors.red.shade400),
            ),
          ),
        if (_hasMore) _buildLoadMore(),
      ],
    );
  }

  Widget _buildLoadMore() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A0A8)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _loadPage(initial: false),
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          label: const Text('Load more'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF00A0A8),
            side: const BorderSide(color: Color(0xFFCFE6E8)),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}

class _Page<T> {
  final List<T> rows;
  final bool hasMore;
  final int? total;
  const _Page({required this.rows, required this.hasMore, this.total});
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.selectedKey, required this.onSelected});

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = _sortOptions.firstWhere(
      (o) => o.key == selectedKey,
      orElse: () => _sortOptions.first,
    );
    return PopupMenuButton<String>(
      tooltip: 'Sort',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final o in _sortOptions)
          PopupMenuItem<String>(
            value: o.key,
            child: Row(
              children: [
                Icon(
                  o.key == selectedKey
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: o.key == selectedKey
                      ? const Color(0xFF00A0A8)
                      : Colors.grey.shade400,
                ),
                const SizedBox(width: 8),
                Text(o.label, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
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
              selected.label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C3E50),
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded,
                size: 16, color: Color(0xFF2C3E50)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROW MODELS
// ─────────────────────────────────────────────────────────────────────────────

class _StockistRow {
  final String name;
  final String code;
  final double salesValue;
  final double zydusPodValue;
  final double completionPct;
  final int processedPodCount;

  const _StockistRow({
    required this.name,
    required this.code,
    required this.salesValue,
    required this.zydusPodValue,
    required this.completionPct,
    required this.processedPodCount,
  });

  factory _StockistRow.fromJson(Map<String, dynamic> j) {
    return _StockistRow(
      name: (j['stockist_name'] ?? 'Unknown').toString(),
      code: (j['stockist_code'] ?? '').toString(),
      salesValue: _d(j['sales_value']),
      zydusPodValue: _d(j['zydus_pod_value']),
      completionPct: _d(j['completion_pct']),
      processedPodCount: _i(j['processed_pod_count']),
    );
  }
}

class _HospitalRow {
  final String name;
  final String btstCode;
  final String city;
  final double salesValue;
  final double zydusPodValue;
  final double completionPct;
  final int processedPodCount;

  const _HospitalRow({
    required this.name,
    required this.btstCode,
    required this.city,
    required this.salesValue,
    required this.zydusPodValue,
    required this.completionPct,
    required this.processedPodCount,
  });

  factory _HospitalRow.fromJson(Map<String, dynamic> j) {
    return _HospitalRow(
      name: (j['hospital_name'] ?? 'Unknown').toString(),
      btstCode: (j['btst_code'] ?? '').toString(),
      city: (j['city'] ?? '').toString(),
      salesValue: _d(j['sales_value']),
      zydusPodValue: _d(j['zydus_pod_value']),
      completionPct: _d(j['completion_pct']),
      processedPodCount: _i(j['processed_pod_count']),
    );
  }
}

double _d(dynamic v) => v is num ? v.toDouble() : 0.0;
int _i(dynamic v) => v is num ? v.toInt() : 0;

class _PerfException implements Exception {
  final String message;
  const _PerfException(this.message);
  @override
  String toString() => message;
}

// ─────────────────────────────────────────────────────────────────────────────
// ROW CARDS
// ─────────────────────────────────────────────────────────────────────────────

class _StockistCard extends StatelessWidget {
  const _StockistCard({required this.rank, required this.row});

  final int rank;
  final _StockistRow row;

  @override
  Widget build(BuildContext context) {
    final pct = row.completionPct.clamp(0.0, 100.0).toDouble();
    final pctColor = _completionColor(pct);
    final subtitle = row.code.isEmpty ? null : row.code;
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
              _RankChip(rank: rank),
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
                    if (subtitle != null)
                      Text(
                        subtitle,
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
              _PctPill(pct: pct, color: pctColor),
            ],
          ),
          const SizedBox(height: 10),
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
                  value: _intGrouped(row.processedPodCount),
                  color: const Color(0xFF14B8A6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _CompletionBar(pct: pct, color: pctColor),
        ],
      ),
    );
  }
}

class _HospitalCard extends StatelessWidget {
  const _HospitalCard({required this.rank, required this.row});

  final int rank;
  final _HospitalRow row;

  @override
  Widget build(BuildContext context) {
    final pct = row.completionPct.clamp(0.0, 100.0).toDouble();
    final pctColor = _completionColor(pct);
    // "(BTST12345 | Mumbai)" — drop whichever piece is missing.
    final meta = [
      if (row.btstCode.isNotEmpty) row.btstCode,
      if (row.city.isNotEmpty) row.city,
    ].join(' | ');
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
              _RankChip(rank: rank),
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
                    if (meta.isNotEmpty)
                      Text(
                        meta,
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
              _PctPill(pct: pct, color: pctColor),
            ],
          ),
          const SizedBox(height: 10),
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
                  label: 'Zydus Value',
                  value: _inr(row.zydusPodValue),
                  color: const Color(0xFF8B5CF6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCell(
                  label: 'Processed PODs',
                  value: _intGrouped(row.processedPodCount),
                  color: const Color(0xFF14B8A6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _CompletionBar(pct: pct, color: pctColor),
        ],
      ),
    );
  }
}

class _RankChip extends StatelessWidget {
  const _RankChip({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _PctPill extends StatelessWidget {
  const _PctPill({required this.pct, required this.color});
  final double pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${pct.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _CompletionBar extends StatelessWidget {
  const _CompletionBar({required this.pct, required this.color});
  final double pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: (pct / 100).clamp(0.0, 1.0).toDouble(),
        minHeight: 5,
        backgroundColor: color.withOpacity(0.12),
        valueColor: AlwaysStoppedAnimation<Color>(color),
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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

class _InlineSkeleton extends StatelessWidget {
  const _InlineSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, {double h = 12}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6F8),
            borderRadius: BorderRadius.circular(4),
          ),
        );
    return Column(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Container(
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
                bar(160),
                const SizedBox(height: 12),
                bar(double.infinity, h: 10),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.title,
    required this.message,
    required this.onRetry,
  });
  final String title;
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
              '$title failed to load. $message',
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

String _intGrouped(int n) {
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

/// Completion buckets for the Stockist / Hospital sections, per product spec:
///   > 75  → green · 50–75 → amber · < 50 → red.
/// (Deliberately a 3-bucket scheme — distinct from the Zone/KAM 4-bucket
/// palette — so these tables read as a simple pass / watch / fail signal.)
Color _completionColor(double pct) {
  if (pct > 75) return const Color(0xFF059669); // green
  if (pct >= 50) return const Color(0xFFF59E0B); // amber
  return const Color(0xFFEF4444); // red
}
