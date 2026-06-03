import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zydus_vistaar/Models/sales_dashboard_models.dart';
import 'package:zydus_vistaar/config.dart';

/// POD-centric analytics section pinned below the executive KPI strip on
/// the POD Dashboard tab.
///
/// Layout: Zone summary card (fast single call) → TabBar → TabBarView with
/// three paginated, searchable, sortable lists (KAM / Hospital / Stockist).
///
/// Backend contracts:
///   GET /api/sales-dashboard/pod-centered-performance      → zone summary
///   GET /api/sales-dashboard/pod-entity-performance/{kam|hospital|stockist}
///       ?page=N&limit=M&search=...&sort_by=sales|zydus|completion|processed
///       &sort_dir=desc|asc&date_from=...&date_to=...
///
/// Both endpoints enforce the same hierarchy scope the rest of the
/// dashboard uses (admin → all; KAM → self; manager → team).
class PodCenteredPerformanceSection extends StatefulWidget {
  const PodCenteredPerformanceSection({super.key, this.filters});

  final SalesDashboardFilters? filters;

  @override
  State<PodCenteredPerformanceSection> createState() =>
      _PodCenteredPerformanceSectionState();
}

class _PodCenteredPerformanceSectionState
    extends State<PodCenteredPerformanceSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtl;
  int _activeTab = 0;
  Future<List<_ZoneRow>>? _zoneFuture;

  @override
  void initState() {
    super.initState();
    _tabCtl = TabController(length: 3, vsync: this);
    _tabCtl.addListener(_onTabChanged);
    _zoneFuture = _fetchZones();
  }

  void _onTabChanged() {
    // Only react when the swipe/tap actually settles on a new index — not
    // while the indicator is mid-animation. Saves a needless rebuild.
    if (_tabCtl.indexIsChanging || _tabCtl.index == _activeTab) return;
    if (!mounted) return;
    setState(() => _activeTab = _tabCtl.index);
  }

  @override
  void didUpdateWidget(covariant PodCenteredPerformanceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.filters;
    final b = widget.filters;
    if (a?.dateFrom != b?.dateFrom || a?.dateTo != b?.dateTo) {
      setState(() => _zoneFuture = _fetchZones());
    }
  }

  @override
  void dispose() {
    _tabCtl.removeListener(_onTabChanged);
    _tabCtl.dispose();
    super.dispose();
  }

  Future<List<_ZoneRow>> _fetchZones() async {
    final q = <String, String>{};
    final f = widget.filters;
    if (f?.dateFrom != null && f!.dateFrom!.isNotEmpty) q['date_from'] = f.dateFrom!;
    if (f?.dateTo != null && f!.dateTo!.isNotEmpty) q['date_to'] = f.dateTo!;
    final uri = Uri.parse('${API_BASE_URL}sales-dashboard/pod-centered-performance')
        .replace(queryParameters: q.isEmpty ? null : q);
    final res = await _authedGet(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _PerfException('Request failed (${res.statusCode})');
    }
    final body = jsonDecode(res.body);
    final data = (body is Map && body['data'] is Map)
        ? (body['data'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final zones = ((data['by_zone'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => _ZoneRow.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
    return zones;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ZoneSummary(future: _zoneFuture),
        const SizedBox(height: 14),
        Container(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: Row(
                  children: const [
                    _SectionHeader(
                      icon: Icons.bar_chart_rounded,
                      title: 'Performance Breakdown',
                    ),
                  ],
                ),
              ),
              Material(
                color: Colors.transparent,
                child: TabBar(
                  controller: _tabCtl,
                  labelColor: const Color(0xFF00A0A8),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF00A0A8),
                  indicatorWeight: 2.4,
                  labelStyle:
                      const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  unselectedLabelStyle:
                      const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: 'KAM'),
                    Tab(text: 'Hospital'),
                    Tab(text: 'Stockist'),
                  ],
                ),
              ),
              // Tab content: only the active tab takes vertical space, but
              // all three stay mounted (via Offstage) so search/scroll/
              // pagination state survives tab switches. There is NO fixed
              // height + no TabBarView wrapper — that previously trapped
              // every inner ListView with its own ScrollController, which
              // is exactly the nested-scroll conflict this widget is
              // fixing. The parent SingleChildScrollView in
              // UnifiedDashboardScreen._buildOverviewContent now scrolls
              // the entire dashboard (KPI cards + zone summary + tabs +
              // rows) as ONE list, so the user experiences a single
              // continuous page just like Sales Analytics.
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _OffstageTabs(
                  activeIndex: _activeTab,
                  children: [
                    _EntityTab(
                      key: const PageStorageKey('pod-entity-tab-kam'),
                      entity: 'kam',
                      filters: widget.filters,
                      searchHint: 'Search KAM name or employee ID',
                    ),
                    _EntityTab(
                      key: const PageStorageKey('pod-entity-tab-hospital'),
                      entity: 'hospital',
                      filters: widget.filters,
                      searchHint: 'Search hospital, BTST code, or city',
                    ),
                    _EntityTab(
                      key: const PageStorageKey('pod-entity-tab-stockist'),
                      entity: 'stockist',
                      filters: widget.filters,
                      searchHint: 'Search stockist name or code',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Renders one of [children] at full intrinsic height and keeps the others
/// mounted but invisible (Offstage) so their state survives tab switches.
///
/// This replaces the TabBarView + fixed-height SizedBox we used to have —
/// that was what trapped each tab's ListView with its own ScrollController
/// and caused the nested-scroll conflict on the POD Dashboard. With the
/// active child rendered inline, the whole dashboard scrolls as a single
/// page.
class _OffstageTabs extends StatelessWidget {
  const _OffstageTabs({required this.activeIndex, required this.children});

  final int activeIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i++)
          Offstage(
            offstage: i != activeIndex,
            // TickerMode prevents off-stage tabs from running animations or
            // network retries that depend on the ticker — saves a few CPU
            // cycles when the user lingers on one tab.
            child: TickerMode(
              enabled: i == activeIndex,
              child: children[i],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ZONE SUMMARY (always 4 zones — fast single call)
// ─────────────────────────────────────────────────────────────────────────────

class _ZoneSummary extends StatelessWidget {
  const _ZoneSummary({required this.future});
  final Future<List<_ZoneRow>>? future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_ZoneRow>>(
      future: future,
      builder: (context, snap) {
        final zones = snap.data ?? const <_ZoneRow>[];
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
                  if (snap.connectionState == ConnectionState.waiting)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (snap.hasError && !snap.hasData)
                Text(
                  'Zone summary failed to load: ${snap.error}',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                )
              else if (zones.isEmpty &&
                  snap.connectionState != ConnectionState.waiting)
                Text(
                  'No zone data for the selected month.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                )
              else
                Column(
                  children: [
                    for (final z in zones) _ZoneRowTile(row: z),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ZoneRowTile extends StatelessWidget {
  const _ZoneRowTile({required this.row});
  final _ZoneRow row;

  @override
  Widget build(BuildContext context) {
    final pct = row.completionPct.clamp(0.0, 100.0).toDouble();
    final color = _completionColor(pct);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
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
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
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
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 4,
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
// ENTITY TAB (paginated + searchable + sortable)
// ─────────────────────────────────────────────────────────────────────────────

class _EntityTab extends StatefulWidget {
  const _EntityTab({
    super.key,
    required this.entity,
    required this.filters,
    required this.searchHint,
  });

  final String entity; // 'kam' | 'hospital' | 'stockist'
  final SalesDashboardFilters? filters;
  final String searchHint;

  @override
  State<_EntityTab> createState() => _EntityTabState();
}

class _EntityTabState extends State<_EntityTab> {
  // No AutomaticKeepAliveClientMixin and no inner ScrollController —
  // parent uses Offstage to keep this state alive across tab switches,
  // and the WHOLE POD Dashboard now scrolls as a single page via the
  // outer SingleChildScrollView in _buildOverviewContent. Pagination is
  // driven by an explicit "Load more" button at the end of the list
  // instead of auto-fire-on-scroll, because there is no inner scroll
  // position to observe anymore.
  static const int _pageSize = 20;

  final TextEditingController _searchCtl = TextEditingController();
  Timer? _searchDebounce;

  List<_EntityRow> _rows = const [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _total = 0;
  int _page = 1;
  String _search = '';
  String _sortBy = 'sales'; // 'sales' | 'zydus' | 'completion' | 'processed'
  String _sortDir = 'desc';
  Object? _lastError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _EntityTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.filters;
    final b = widget.filters;
    if (a?.dateFrom != b?.dateFrom || a?.dateTo != b?.dateTo) {
      _reload();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _page = 1;
      _isInitialLoading = true;
      _lastError = null;
      _rows = const [];
      _hasMore = false;
    });
    try {
      final res = await _fetch(page: 1);
      if (!mounted) return;
      setState(() {
        _rows = res.rows;
        _total = res.total;
        _hasMore = res.hasMore;
        _isInitialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitialLoading = false;
        _lastError = e;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final res = await _fetch(page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _rows = [..._rows, ...res.rows];
        _total = res.total;
        _hasMore = res.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Swallow load-more errors into a clean isLoadingMore=false rather than
      // wiping out the visible rows — the user can scroll to retry.
      setState(() => _isLoadingMore = false);
    }
  }

  Future<_EntityPage> _fetch({required int page}) async {
    final q = <String, String>{
      'page': page.toString(),
      'limit': _pageSize.toString(),
      'sort_by': _sortBy,
      'sort_dir': _sortDir,
    };
    final f = widget.filters;
    if (f?.dateFrom != null && f!.dateFrom!.isNotEmpty) q['date_from'] = f.dateFrom!;
    if (f?.dateTo != null && f!.dateTo!.isNotEmpty) q['date_to'] = f.dateTo!;
    if (_search.isNotEmpty) q['search'] = _search;

    final uri = Uri.parse('${API_BASE_URL}sales-dashboard/pod-entity-performance/${widget.entity}')
        .replace(queryParameters: q);
    final res = await _authedGet(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _PerfException('Request failed (${res.statusCode})');
    }
    final body = jsonDecode(res.body);
    if (body is! Map || body['success'] != true) {
      throw const _PerfException('Unexpected response shape');
    }
    final raw = (body['data'] as List?) ?? const [];
    final pageRows = raw
        .whereType<Map>()
        .map((m) => _EntityRow.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
    final pag = (body['pagination'] as Map?)?.cast<String, dynamic>() ?? const {};
    return _EntityPage(
      rows: pageRows,
      total: pag['total'] is num ? (pag['total'] as num).toInt() : pageRows.length,
      hasMore: pag['has_more'] == true,
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _search) return;
      setState(() => _search = v);
      _reload();
    });
  }

  void _onSortChanged(String by) {
    setState(() {
      if (_sortBy == by) {
        _sortDir = _sortDir == 'desc' ? 'asc' : 'desc';
      } else {
        _sortBy = by;
        _sortDir = 'desc';
      }
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchAndSortBar(
            controller: _searchCtl,
            hint: widget.searchHint,
            onChanged: _onSearchChanged,
            sortBy: _sortBy,
            sortDir: _sortDir,
            onSortChanged: _onSortChanged,
            total: _total,
          ),
          const SizedBox(height: 8),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isInitialLoading) {
      // shrinkWrap so the skeleton sits inside the outer page scroll
      // without trying to take its own height.
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(top: 8),
          height: 78,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6F8),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
    if (_lastError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Failed to load. ${_lastError.toString()}',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            _search.isEmpty
                ? 'No data for the selected month.'
                : 'No matches for "$_search".',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The list itself is shrink-wrapped and non-scrollable so the
        // parent page scrolls cleanly through the whole dashboard.
        // Pagination is driven by the Load More button below — there is
        // no inner scroll position to observe anymore.
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _rows.length,
          itemBuilder: (context, i) => _EntityTile(
            rank: i + 1,
            entity: widget.entity,
            row: _rows[i],
          ),
        ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: _isLoadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : OutlinedButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more_rounded, size: 18),
                      label: Text(
                        'Load more (${_rows.length} of $_total)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00A0A8),
                        side: const BorderSide(color: Color(0xFF00A0A8)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                '— end of list ($_total) —',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEARCH + SORT BAR
// ─────────────────────────────────────────────────────────────────────────────

class _SearchAndSortBar extends StatelessWidget {
  const _SearchAndSortBar({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.sortBy,
    required this.sortDir,
    required this.onSortChanged,
    required this.total,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final String sortBy;
  final String sortDir;
  final ValueChanged<String> onSortChanged;
  final int total;

  static const _opts = <Map<String, String>>[
    {'key': 'sales', 'label': 'Sales'},
    {'key': 'zydus', 'label': 'Zydus'},
    {'key': 'completion', 'label': '%'},
    {'key': 'processed', 'label': 'Processed'},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
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
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '$total rows',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const Spacer(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final o in _opts)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _SortChip(
                        label: o['label']!,
                        selected: sortBy == o['key'],
                        direction: sortBy == o['key'] ? sortDir : null,
                        onTap: () => onSortChanged(o['key']!),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.direction,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final String? direction; // 'asc' | 'desc' | null
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF00A0A8);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.12) : const Color(0xFFF1F4F8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent.withOpacity(0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected ? accent : const Color(0xFF2C3E50),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 2),
              Icon(
                direction == 'asc'
                    ? Icons.arrow_drop_up_rounded
                    : Icons.arrow_drop_down_rounded,
                size: 16,
                color: accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTITY TILE
// ─────────────────────────────────────────────────────────────────────────────

class _EntityTile extends StatelessWidget {
  const _EntityTile({
    required this.rank,
    required this.entity,
    required this.row,
  });

  final int rank;
  final String entity;
  final _EntityRow row;

  @override
  Widget build(BuildContext context) {
    final pct = row.completionPct.clamp(0.0, 100.0).toDouble();
    final pctColor = _completionColor(pct);

    // Subtitle is entity-specific so the right context fields surface
    // without bloating the row.
    String subtitle;
    switch (entity) {
      case 'hospital':
        final btst = row.code.isEmpty ? '' : 'BTST ${row.code}';
        final parts = <String>[
          if (row.city.isNotEmpty) row.city,
          if (btst.isNotEmpty) btst,
        ];
        subtitle = parts.join(' · ');
        if (subtitle.isEmpty) subtitle = 'Hospital';
        break;
      case 'stockist':
        subtitle = row.code.isEmpty ? 'Stockist' : 'Code ${row.code}';
        break;
      case 'kam':
      default:
        subtitle = row.zone.isEmpty
            ? 'Emp ${row.code}'
            : 'Emp ${row.code} · ${row.zone}';
    }

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
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
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

// ─────────────────────────────────────────────────────────────────────────────
// DATA + NETWORKING
// ─────────────────────────────────────────────────────────────────────────────

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

class _EntityRow {
  final String id;
  final String name;
  final String code;
  final String city;
  final String zone;
  final double salesValue;
  final double zydusPodValue;
  final double completionPct;
  final int processedPodCount;

  const _EntityRow({
    required this.id,
    required this.name,
    required this.code,
    required this.city,
    required this.zone,
    required this.salesValue,
    required this.zydusPodValue,
    required this.completionPct,
    required this.processedPodCount,
  });

  factory _EntityRow.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v is num ? v.toDouble() : 0.0;
    int i(dynamic v) => v is num ? v.toInt() : 0;
    return _EntityRow(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? 'Unknown').toString(),
      code: (j['code'] ?? '').toString(),
      city: (j['city'] ?? '').toString(),
      zone: (j['zone'] ?? '').toString(),
      salesValue: d(j['sales_value']),
      zydusPodValue: d(j['zydus_pod_value']),
      completionPct: d(j['completion_pct']),
      processedPodCount: i(j['processed_pod_count']),
    );
  }
}

class _EntityPage {
  final List<_EntityRow> rows;
  final int total;
  final bool hasMore;
  const _EntityPage({
    required this.rows,
    required this.total,
    required this.hasMore,
  });
}

class _PerfException implements Exception {
  final String message;
  const _PerfException(this.message);
  @override
  String toString() => message;
}

Future<http.Response> _authedGet(Uri uri) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('authToken');
  return http.get(uri, headers: {
    'Accept': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  }).timeout(const Duration(seconds: 45));
}

// ─────────────────────────────────────────────────────────────────────────────
// FORMATTERS
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
  if (pct >= 75) return const Color(0xFF059669);
  if (pct >= 50) return const Color(0xFF0EA5E9);
  if (pct >= 25) return const Color(0xFFF59E0B);
  return const Color(0xFFEF4444);
}
