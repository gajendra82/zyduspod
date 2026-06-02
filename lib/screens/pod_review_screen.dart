import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zydus_vistaar/config.dart';
import 'package:zydus_vistaar/widgets/modern_ui_components.dart';

/// Review screen shown after extraction completes.
///
/// Receives the `review` map from the upload-background status API and lets
/// the user tick hospitals, edit any column inline, then submit the selected
/// set to the backend for final confirmation.
class PodReviewScreen extends StatefulWidget {
  final Map<String, dynamic> review;

  const PodReviewScreen({super.key, required this.review});

  @override
  State<PodReviewScreen> createState() => _PodReviewScreenState();
}

class _PodReviewScreenState extends State<PodReviewScreen> {
  static const double _groupSimilarityThreshold = 80.0;
  static const Set<String> _nameStopwords = {
    'hospital', 'hosp', 'medical', 'med', 'center', 'centre', 'clinic',
    'health', 'care', 'pvt', 'ltd', 'private', 'and', 'the',
  };

  late final int _batchDbId;
  late final Map<String, dynamic> _stockist;
  late final List<_HospitalRow> _rows;
  late final List<_HospitalGroup> _groups;
  late final List<Map<String, dynamic>> _failedFiles;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _batchDbId = (widget.review['batch_db_id'] as num?)?.toInt() ?? 0;
    _stockist = (widget.review['stockist'] as Map<String, dynamic>?) ?? {};
    final rawRows = (widget.review['hospitals'] as List?) ?? [];
    _rows = rawRows
        .whereType<Map<String, dynamic>>()
        .map(_HospitalRow.fromJson)
        .toList();
    _groups = _buildGroups(_rows);
    _failedFiles = ((widget.review['failed_files'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Greedy clustering: each row joins the first existing group whose
  /// representative name scores â‰¥ [_groupSimilarityThreshold] against it.
  /// If a row has no master match it never collapses with another row — we
  /// don't want to fold two unrelated unmapped hospitals together by accident.
  List<_HospitalGroup> _buildGroups(List<_HospitalRow> rows) {
    final List<_HospitalGroup> groups = [];
    for (final row in rows) {
      final candidate = row.linked.name.trim().isNotEmpty
          ? row.linked.name
          : row.extracted.name;
      _HospitalGroup? matched;
      if (candidate.trim().isNotEmpty) {
        for (final g in groups) {
          if (g.representativeNameForGrouping.isEmpty) continue;
          final sim = _nameSimilarityPercent(candidate, g.representativeNameForGrouping);
          if (sim >= _groupSimilarityThreshold) {
            matched = g;
            break;
          }
        }
      }
      if (matched != null) {
        matched.rows.add(row);
      } else {
        groups.add(_HospitalGroup(representative: row, rows: [row]));
      }
    }
    return groups;
  }

  /// SÃ¸rensen–Dice on normalized + stopword-filtered tokens, expressed 0–100.
  /// Lightweight, no extra dependency, and matches the spirit of the backend
  /// fuzzy matcher.
  static double _nameSimilarityPercent(String a, String b) {
    final ta = _significantTokens(a);
    final tb = _significantTokens(b);
    if (ta.isEmpty || tb.isEmpty) return 0.0;
    final setA = ta.toSet();
    final setB = tb.toSet();
    final inter = setA.intersection(setB).length;
    if (inter == 0) return 0.0;
    return (2.0 * inter / (setA.length + setB.length)) * 100.0;
  }

  static List<String> _significantTokens(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    if (normalized.isEmpty) return const [];
    return normalized
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3 && !_nameStopwords.contains(t))
        .toList();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  int get _selectedCount => _groups.where((g) => g.selected).length;

  Future<void> _submit() async {
    if (_selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one hospital to submit.')),
      );
      return;
    }

    final selectedGroups = _groups.where((g) => g.selected).toList();
    final unmappedGroups = selectedGroups
        .where((g) => g.representative.hospitalId == null)
        .toList();
    if (unmappedGroups.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pick a master hospital for ${unmappedGroups.length} selected row(s) before submitting. '
            'Use "Change master" or "Use suggested".',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final uri = Uri.parse(
        '${API_BASE_URL}pod/batch/$_batchDbId/submit-selected',
      );

      // Mapping-only payload: each selected POD links to whatever master the
      // user has chosen (or the auto-suggested one). Master records are not
      // modified by this flow.
      final items = <Map<String, dynamic>>[];
      for (final g in selectedGroups) {
        final hospitalId = g.representative.hospitalId!;
        for (final r in g.rows) {
          items.add({
            'pod_id': r.podId,
            'hospital_id': hospitalId,
          });
        }
      }

      final resp = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'items': items}),
          )
          .timeout(const Duration(seconds: 45));

      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final msg = body['message']?.toString() ?? 'Submitted successfully.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.green),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submit failed: ${resp.statusCode} ${resp.body}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toggleAll(bool value) {
    setState(() {
      for (final g in _groups) {
        g.selected = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: ModernUIComponents.buildModernAppBar(
        title: 'Review PODs',
        subtitle: '${_groups.length} hospital(s) • ${_rows.length} invoice(s) • $_selectedCount selected',
        icon: Icons.fact_check,
        color: const Color(0xFF00A0A8),
      ),
      body: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: _buildList()),
                const VerticalDivider(width: 1),
                SizedBox(width: 360, child: _buildStockistPanel()),
              ],
            )
          : Column(
              children: [
                _buildStockistPanel(),
                const Divider(height: 1),
                Expanded(child: _buildList()),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 520;
              final selectAll = OutlinedButton.icon(
                onPressed: _rows.isEmpty ? null : () => _toggleAll(true),
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('Select all'),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    vertical: isNarrow ? 10 : 12,
                    horizontal: 8,
                  ),
                ),
              );
              final clearAll = OutlinedButton.icon(
                onPressed: _rows.isEmpty ? null : () => _toggleAll(false),
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Clear'),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    vertical: isNarrow ? 10 : 12,
                    horizontal: 8,
                  ),
                ),
              );
              final submit = ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.upload),
                label: Text(
                  _submitting
                      ? 'Submitting…'
                      : (isNarrow
                          ? 'Upload ($_selectedCount)'
                          : 'Upload $_selectedCount selected'),
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A0A8),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isNarrow ? 12 : 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );

              if (!isNarrow) {
                return Row(
                  children: [
                    Expanded(child: selectAll),
                    const SizedBox(width: 8),
                    Expanded(child: clearAll),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: submit),
                  ],
                );
              }

              // Mobile layout — Upload takes the full width on its own row,
              // with Select all / Clear sharing a secondary row below.
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: double.infinity, child: submit),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: selectAll),
                      const SizedBox(width: 8),
                      Expanded(child: clearAll),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStockistPanel() {
    final name = (_stockist['name'] ?? 'Unknown stockist').toString();
    final code = (_stockist['code'] ?? '').toString();
    final address = _joinAddress([
      _stockist['address'],
      _stockist['city'],
      _stockist['state'],
      _stockist['pincode'],
    ]);
    final gstin = (_stockist['gstin'] ?? '').toString();
    final phone = (_stockist['phone'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.store, color: Color(0xFF00A0A8)),
                const SizedBox(width: 8),
                const Text(
                  'Selected stockist',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (code.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Code: $code',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ),
            const SizedBox(height: 10),
            if (address.isNotEmpty) _kv(Icons.location_on_outlined, address),
            if (gstin.isNotEmpty) _kv(Icons.receipt_long_outlined, gstin),
            if (phone.isNotEmpty) _kv(Icons.phone, phone),
          ],
        ),
      ),
    );
  }

  Widget _kv(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.black45),
          const SizedBox(width: 6),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _joinAddress(List<dynamic> parts) {
    return parts
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  Widget _buildList() {
    if (_groups.isEmpty && _failedFiles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No invoices detected in this batch.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final banner = _failedFiles.isEmpty ? null : _buildFailedFilesBanner();
    final bannerOffset = banner == null ? 0 : 1;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: _groups.length + bannerOffset,
      itemBuilder: (_, i) {
        if (banner != null && i == 0) return banner;
        return _buildGroupCard(_groups[i - bannerOffset]);
      },
    );
  }

  Future<void> _openMasterPicker(_HospitalGroup group) async {
    // Seed the search with whatever's currently linked (or the extracted
    // name), so the picker opens already filtered.
    final r = group.representative;
    final initialQuery = r.linked.name.trim().isNotEmpty
        ? r.linked.name
        : r.extracted.name;

    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _MasterPickerDialog(initialQuery: initialQuery),
    );

    if (picked == null || !mounted) return;

    _applyLinkedMaster(group, _HospitalSnapshot.fromMap(picked));
  }

  void _useSuggestedMaster(_HospitalGroup group) {
    final s = group.representative.suggested;
    if (s == null || !s.hasId) return;
    _applyLinkedMaster(group, s);
  }

  void _applyLinkedMaster(_HospitalGroup group, _HospitalSnapshot picked) {
    setState(() {
      group.representative.linked = picked;
      group.representative.warnings.remove('hospital_not_mapped');
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mapped to "${picked.name}"'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showInvoicesDialog(_HospitalGroup group) {
    final hospitalName = group.representative.linked.name.trim().isNotEmpty
        ? group.representative.linked.name
        : group.representative.extracted.name;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Row(
            children: [
              const Icon(Icons.receipt_long, color: Color(0xFF00A0A8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${group.rows.length} invoice(s)',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hospitalName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      hospitalName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: group.rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = group.rows[i];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: const Icon(
                          Icons.description_outlined,
                          size: 18,
                          color: Colors.black54,
                        ),
                        title: Text(
                          r.invoiceNumber.isNotEmpty ? r.invoiceNumber : '—',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'POD #${r.podId}'
                          '${r.invoiceDate != null ? ' • ${r.invoiceDate}' : ''}'
                          '${r.amount != null ? ' • ₹${r.amount}' : ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGroupCard(_HospitalGroup group) {
    final row = group.representative;
    final warnings = row.warnings;
    final isUnmapped = warnings.contains('hospital_not_mapped');
    final invoiceCount = group.rows.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isUnmapped ? Colors.red.shade300 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: group.selected,
                  onChanged: (v) => setState(() => group.selected = v ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.linked.name.trim().isNotEmpty
                            ? row.linked.name
                            : (row.extracted.name.isNotEmpty
                                ? row.extracted.name
                                : 'Unnamed hospital'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00A0A8).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$invoiceCount invoice${invoiceCount == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF00A0A8),
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _showInvoicesDialog(group),
                            icon: const Icon(Icons.list_alt, size: 16),
                            label: const Text(
                              'View invoices',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: const Color(0xFF00A0A8),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _openMasterPicker(group),
                            icon: const Icon(Icons.swap_horiz, size: 16),
                            label: const Text(
                              'Change master',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: Colors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isUnmapped)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: const Text(
                      'Unmapped',
                      style: TextStyle(color: Colors.red, fontSize: 11),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _buildMatchBanner(row, group),
            _buildLinkedPanel(row),
          ],
        ),
      ),
    );
  }

  /// Read-only summary of which master this POD will be linked to on submit.
  /// Shows a yellow-warning state when no master is linked yet.
  Widget _buildLinkedPanel(_HospitalRow row) {
    final linked = row.linked;
    final hasLink = linked.hasId;
    final color = hasLink ? const Color(0xFF00A0A8) : Colors.orange;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasLink ? Icons.link : Icons.link_off,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 6),
                Text(
                  hasLink ? 'Linked to master' : 'No master linked',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (hasLink) ...[
              _kvLine('Name', linked.name.isEmpty ? '—' : linked.name),
              if (linked.btstCode.isNotEmpty)
                _kvLine('BTST code', linked.btstCode),
              if (linked.joinedAddress.isNotEmpty)
                _kvLine('Address', linked.joinedAddress),
              if (linked.gstin.isNotEmpty) _kvLine('GSTIN', linked.gstin),
              if (linked.phone.isNotEmpty) _kvLine('Phone', linked.phone),
            ] else
              Text(
                'Use "Change master" to pick the correct hospital from the master list.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange.shade900,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedFilesBanner() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.red.shade200),
      ),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_failedFiles.length} file${_failedFiles.length == 1 ? '' : 's'} failed to process',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ..._failedFiles.map((f) {
              final fileName = (f['file_name'] ?? 'unknown').toString();
              final error = (f['error'] ?? '').toString();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                    if (error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          error,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            Text(
              'Re-upload these files separately to process them.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchBanner(_HospitalRow row, _HospitalGroup group) {
    final extracted = row.extracted;
    final suggested = row.suggested;
    final hasSuggestion =
        suggested != null && suggested.name.trim().isNotEmpty;

    if (!hasSuggestion && extracted.name.isEmpty) {
      return const SizedBox.shrink();
    }

    final conf = row.suggestedConfidence ?? 'low';
    final confColor = conf == 'high'
        ? Colors.green
        : (conf == 'medium' ? Colors.orange : Colors.grey);
    final score = row.suggestedScore?.toStringAsFixed(0) ?? '';

    // "Use suggested" only makes sense when the suggestion exists, has an
    // id, and the user is not already linked to it.
    final canApplySuggested = hasSuggestion &&
        suggested.hasId &&
        suggested.hospitalId != row.linked.hospitalId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows, size: 16, color: Colors.black54),
                const SizedBox(width: 6),
                const Text(
                  'Hospital match',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                if (hasSuggestion)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: confColor.shade50,
                      border: Border.all(color: confColor.shade200),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${conf.toUpperCase()}${score.isEmpty ? '' : ' • $score%'}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: confColor.shade800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _kvLine('Extracted', extracted.name.isEmpty ? '—' : extracted.name),
            if (extracted.address.isNotEmpty)
              _kvLine('Extracted address', extracted.address),
            if (extracted.btstCode.isNotEmpty)
              _kvLine('Extracted BTST', extracted.btstCode),
            if (hasSuggestion) ...[
              const Divider(height: 10),
              _kvLine('Suggested master', suggested.name),
              if (suggested.joinedAddress.isNotEmpty)
                _kvLine('Master address', suggested.joinedAddress),
              if (suggested.btstCode.isNotEmpty)
                _kvLine('Master BTST', suggested.btstCode),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (canApplySuggested)
                    OutlinedButton.icon(
                      onPressed: () => _useSuggestedMaster(group),
                      icon: const Icon(Icons.check, size: 14),
                      label: const Text(
                        'Use suggested',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: Colors.green.shade700,
                        side: BorderSide(color: Colors.green.shade300),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                conf == 'low'
                    ? 'Low confidence — review carefully or use "Change master" to pick a different hospital.'
                    : 'Click "Use suggested" to link to this master, or "Change master" to pick a different one.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ] else ...[
              const SizedBox(height: 2),
              Text(
                'No confident master match found. Use "Change master" to link this row to the correct hospital from the master list.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kvLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

}

/// One card on the review screen. Holds a representative [_HospitalRow]
/// (whose controllers back the editable fields) plus every row that was
/// merged into this hospital based on the name-similarity threshold.
class _HospitalGroup {
  final _HospitalRow representative;
  final List<_HospitalRow> rows;

  _HospitalGroup({required this.representative, required this.rows});

  /// What we compare against when deciding if another row joins this group.
  /// Prefer the editable name (which may already reflect the master), then
  /// the suggested master, then the raw extracted name.
  String get representativeNameForGrouping {
    if (representative.linked.name.trim().isNotEmpty) {
      return representative.linked.name;
    }
    final s = representative.suggested?.name ?? '';
    if (s.trim().isNotEmpty) return s;
    return representative.extracted.name;
  }

  bool get selected => rows.any((r) => r.selected);

  set selected(bool value) {
    for (final r in rows) {
      r.selected = value;
    }
  }
}

/// Read-only snapshot of a hospital — used for both the extracted record and
/// the currently-linked master.
class _HospitalSnapshot {
  final int? hospitalId;
  final String name;
  final String btstCode;
  final String address;
  final String city;
  final String state;
  final String pincode;
  final String gstin;
  final String phone;

  const _HospitalSnapshot({
    required this.hospitalId,
    required this.name,
    required this.btstCode,
    required this.address,
    required this.city,
    required this.state,
    required this.pincode,
    required this.gstin,
    required this.phone,
  });

  factory _HospitalSnapshot.fromMap(Map<String, dynamic>? m) {
    final map = m ?? const <String, dynamic>{};
    String s(dynamic v) => (v ?? '').toString();
    return _HospitalSnapshot(
      hospitalId: (map['hospital_id'] as num?)?.toInt(),
      name: s(map['name']),
      btstCode: s(map['btst_code']),
      address: s(map['address']),
      city: s(map['city']),
      state: s(map['state']),
      pincode: s(map['pincode']),
      gstin: s(map['gstin']),
      phone: s(map['phone']),
    );
  }

  bool get hasId => hospitalId != null;
  bool get isEmpty => !hasId && name.trim().isEmpty;

  String get joinedAddress {
    final parts = <String>[address, city, state, pincode]
        .map((s) => s.trim())
        .where((s) => s.isEmpty == false)
        .toList();
    return parts.join(', ');
  }
}

class _HospitalRow {
  final int podId;
  final String invoiceNumber;
  final String? invoiceDate;
  final String? amount;
  final String? fileViewUrl;
  // Mutable so the manual master picker can clear the "unmapped" warning
  // once the user has linked the row to a master by hand.
  final List<String> warnings;

  // Extracted (raw) values — shown read-only for reference.
  final _HospitalSnapshot extracted;

  // Suggested master match — null when no confident match found.
  final _HospitalSnapshot? suggested;
  final double? suggestedScore;
  final String? suggestedConfidence;

  // Currently linked hospital. The submit endpoint reads `linked.hospitalId`.
  // Replaced wholesale by the manual master picker (or accepting the
  // suggestion); the record itself is never edited in place.
  _HospitalSnapshot linked;

  bool selected;

  _HospitalRow({
    required this.podId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.amount,
    required this.fileViewUrl,
    required this.warnings,
    required this.extracted,
    required this.suggested,
    required this.suggestedScore,
    required this.suggestedConfidence,
    required this.linked,
    required this.selected,
  });

  int? get hospitalId => linked.hospitalId;

  factory _HospitalRow.fromJson(Map<String, dynamic> json) {
    final hospital = json['hospital'] as Map<String, dynamic>?;
    final suggestedMap = json['suggested_master'] as Map<String, dynamic>?;
    final warnings = ((json['warnings'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();

    double? d(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    final extracted = _HospitalSnapshot.fromMap(hospital);
    final suggestedSnap =
        suggestedMap == null ? null : _HospitalSnapshot.fromMap(suggestedMap);
    final conf = suggestedMap?['confidence']?.toString();

    // Initial "linked" preference:
    //  1. If a high/medium-confidence master is suggested, link to it.
    //  2. Otherwise fall back to whatever the extraction step linked
    //     (which may be an existing master found via name/address match,
    //     or an auto-created hospital placeholder).
    final useSuggested =
        suggestedSnap != null && (conf == 'high' || conf == 'medium');
    final linked = (useSuggested && suggestedSnap.hasId)
        ? suggestedSnap
        : extracted;

    return _HospitalRow(
      podId: (json['pod_id'] as num).toInt(),
      invoiceNumber: (json['invoice_number'] ?? '').toString(),
      invoiceDate: json['invoice_date']?.toString(),
      amount: json['amount']?.toString(),
      fileViewUrl: json['file_view_url']?.toString(),
      warnings: warnings,
      extracted: extracted,
      suggested: suggestedSnap,
      suggestedScore: d(suggestedMap?['score']),
      suggestedConfidence: conf,
      linked: linked,
      selected: json['selected'] == true,
    );
  }

  void dispose() {
    // Nothing to dispose — no controllers held anymore.
  }
}

/// Modal that lets the user search the hospital master and pick a record to
/// override the auto-suggested mapping. Pops with the selected hospital map
/// (same shape as suggested_master), or null if cancelled.
class _MasterPickerDialog extends StatefulWidget {
  final String initialQuery;

  const _MasterPickerDialog({required this.initialQuery});

  @override
  State<_MasterPickerDialog> createState() => _MasterPickerDialogState();
}

class _MasterPickerDialogState extends State<_MasterPickerDialog> {
  late final TextEditingController _searchCtrl;
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.initialQuery);
    // Fire an initial search using whatever was typed on the row.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runSearch(_searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(value);
    });
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final uri = Uri.parse(
        '${API_BASE_URL}pod/hospital-master-search?q=${Uri.encodeQueryComponent(query.trim())}&limit=20',
      );

      final resp = await http
          .get(
            uri,
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;
      if (resp.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'Search failed (${resp.statusCode}). Please try again.';
          _results = [];
        });
        return;
      }

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (decoded['data'] as List?) ?? [];
      setState(() {
        _loading = false;
        _results = list.whereType<Map<String, dynamic>>().toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Network error: $e';
        _results = [];
      });
    }
  }

  String _joinAddress(Map<String, dynamic> h) {
    final parts = <String>[];
    for (final key in ['address', 'city', 'state', 'pincode']) {
      final v = h[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) parts.add(v);
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      title: Row(
        children: [
          const Icon(Icons.swap_horiz, color: Colors.deepPurple),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Pick hospital master',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search by name, code, BTST, GSTIN, city…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _runSearch('');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _error!,
            style: TextStyle(color: Colors.red.shade700),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _searchCtrl.text.trim().isEmpty
                ? 'Type to search the hospital master.'
                : 'No master hospitals match that search.',
            style: TextStyle(color: Colors.grey.shade700),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final h = _results[i];
        final name = (h['name'] ?? '').toString();
        final code = (h['code'] ?? '').toString();
        final btst = (h['btst_code'] ?? '').toString();
        final gstin = (h['gstin'] ?? '').toString();
        final addr = _joinAddress(h);
        return InkWell(
          onTap: () => Navigator.of(context).pop(h),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '—' : name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                if (addr.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      addr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (code.isNotEmpty) _chip('Code: $code', Colors.blueGrey),
                    if (btst.isNotEmpty) _chip('BTST: $btst', Colors.deepPurple),
                    if (gstin.isNotEmpty) _chip('GSTIN: $gstin', Colors.teal),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color.shade800,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
