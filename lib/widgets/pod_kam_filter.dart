import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zydus_vistaar/Models/sales_dashboard_models.dart';
import 'package:zydus_vistaar/config.dart';

/// KAM filter pill for the POD Dashboard tab.
///
/// One pill, taps to a bottom-sheet picker with a search box + scrollable
/// list of KAMs the logged-in user can see (admin → all, manager → team,
/// KAM → self). Picking a KAM emits the emp_id to the parent which feeds
/// it into `SalesDashboardFilters(empId: ...)` so the executive cards +
/// hospital/stockist analytics tabs all narrow to that one KAM.
///
/// Backed by the existing
/// `GET /api/sales-dashboard/pod-entity-performance/kam` endpoint with a
/// high limit — that endpoint already returns rows scoped to the user's
/// hierarchy, so no separate "accessible KAMs" API is needed.
class PodKamFilter extends StatefulWidget {
  const PodKamFilter({
    super.key,
    required this.filters,
    required this.selectedEmpId,
    required this.onChanged,
  });

  /// The current month filter — only `dateFrom` / `dateTo` are honoured.
  /// We pass them so the picker shows KAMs that actually had activity in
  /// the selected month (matching what the executive cards count).
  final SalesDashboardFilters? filters;

  /// `null` = "All KAMs in scope" (no filter applied).
  final String? selectedEmpId;

  final ValueChanged<String?> onChanged;

  @override
  State<PodKamFilter> createState() => _PodKamFilterState();
}

class _PodKamFilterState extends State<PodKamFilter> {
  // Cache: emp_id → display label, populated from the picker fetch so the
  // pill can show "RAGHU H R (134177)" even on first render after a
  // selection is restored.
  final Map<String, String> _nameCache = {};

  Future<void> _openPicker() async {
    final picked = await showModalBottomSheet<_KamPick?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _KamPickerSheet(
        filters: widget.filters,
        selectedEmpId: widget.selectedEmpId,
      ),
    );
    if (picked == null) return; // user dismissed
    if (picked.empId != null && picked.label != null) {
      _nameCache[picked.empId!] = picked.label!;
    }
    widget.onChanged(picked.empId);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedEmpId;
    final label = selected == null
        ? 'All KAMs'
        : (_nameCache[selected] ?? 'KAM $selected');
    final accent = const Color(0xFF00A0A8);
    return InkWell(
      onTap: _openPicker,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected == null
                ? const Color(0xFFE8EEF2)
                : accent.withOpacity(0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.025),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(Icons.person_search_rounded,
                  color: accent, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'KAM filter',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF94A3B8),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected == null
                          ? const Color(0xFF2C3E50)
                          : accent,
                    ),
                  ),
                ],
              ),
            ),
            if (selected != null)
              InkWell(
                onTap: () => widget.onChanged(null),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded,
                      size: 16, color: Colors.grey.shade500),
                ),
              )
            else
              Icon(Icons.expand_more_rounded,
                  size: 18, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }
}

class _KamPick {
  final String? empId;
  final String? label;
  const _KamPick({this.empId, this.label});
}

class _KamPickerSheet extends StatefulWidget {
  const _KamPickerSheet({required this.filters, required this.selectedEmpId});

  final SalesDashboardFilters? filters;
  final String? selectedEmpId;

  @override
  State<_KamPickerSheet> createState() => _KamPickerSheetState();
}

class _KamPickerSheetState extends State<_KamPickerSheet> {
  static const int _fetchLimit = 100;

  final TextEditingController _searchCtl = TextEditingController();
  Timer? _debounce;
  String _search = '';

  Future<List<_KamRow>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<List<_KamRow>> _fetch() async {
    final q = <String, String>{
      'page': '1',
      'limit': '$_fetchLimit',
      'sort_by': 'sales',
      'sort_dir': 'desc',
    };
    final f = widget.filters;
    if (f?.dateFrom != null && f!.dateFrom!.isNotEmpty) q['date_from'] = f.dateFrom!;
    if (f?.dateTo != null && f!.dateTo!.isNotEmpty) q['date_to'] = f.dateTo!;
    if (_search.isNotEmpty) q['search'] = _search;

    final uri =
        Uri.parse('${API_BASE_URL}sales-dashboard/pod-entity-performance/kam')
            .replace(queryParameters: q);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    final res = await http.get(uri, headers: {
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    }).timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Request failed (${res.statusCode})');
    }
    final body = jsonDecode(res.body);
    final raw = ((body is Map ? body['data'] : null) as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((m) => _KamRow.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _search) return;
      setState(() {
        _search = v;
        _future = _fetch();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollCtl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'Filter by KAM',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(const _KamPick(empId: null)),
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _searchCtl,
                onChanged: _onSearchChanged,
                autofocus: true,
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search KAM name or employee ID',
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
            Expanded(
              child: FutureBuilder<List<_KamRow>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Failed to load KAMs: ${snap.error}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.red.shade700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final rows = snap.data ?? const <_KamRow>[];
                  if (rows.isEmpty) {
                    return Center(
                      child: Text(
                        _search.isEmpty
                            ? 'No KAMs in your scope for this month.'
                            : 'No matches for "$_search".',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollCtl,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey.shade100),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final selected = r.empId == widget.selectedEmpId;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(0xFF00A0A8)
                              .withOpacity(0.12),
                          child: Text(
                            r.name.isNotEmpty
                                ? r.name.characters.first.toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF00A0A8),
                            ),
                          ),
                        ),
                        title: Text(
                          r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                        subtitle: Text(
                          [
                            r.empId,
                            if (r.zone.isNotEmpty) r.zone,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: selected
                            ? const Icon(Icons.check_circle_rounded,
                                size: 18, color: Color(0xFF00A0A8))
                            : const Icon(Icons.chevron_right_rounded,
                                size: 18, color: Color(0xFF94A3B8)),
                        onTap: () => Navigator.of(context).pop(
                          _KamPick(empId: r.empId, label: r.name),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KamRow {
  final String empId;
  final String name;
  final String zone;
  const _KamRow(
      {required this.empId, required this.name, required this.zone});

  factory _KamRow.fromJson(Map<String, dynamic> j) {
    return _KamRow(
      empId: (j['emp_id'] ?? j['code'] ?? '').toString(),
      name: (j['name'] ?? 'Unknown').toString(),
      zone: (j['zone'] ?? '').toString(),
    );
  }
}
