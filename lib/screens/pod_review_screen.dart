import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zyduspod/config.dart';
import 'package:zyduspod/widgets/modern_ui_components.dart';

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
  late final int _batchDbId;
  late final Map<String, dynamic> _stockist;
  late final List<_HospitalRow> _rows;
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
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  int get _selectedCount => _rows.where((r) => r.selected).length;

  Future<void> _submit() async {
    if (_selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one hospital to submit.')),
      );
      return;
    }

    final unmapped = _rows
        .where((r) => r.selected && (r.name.text.trim().isEmpty))
        .toList();
    if (unmapped.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fill hospital name for ${unmapped.length} selected row(s) before submitting.',
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

      final items = _rows
          .where((r) => r.selected)
          .map((r) => {
                'pod_id': r.podId,
                'hospital': {
                  'hospital_id': r.hospitalId,
                  'name': r.name.text.trim(),
                  'address': r.address.text.trim(),
                  'city': r.city.text.trim(),
                  'state': r.state.text.trim(),
                  'pincode': r.pincode.text.trim(),
                  'gstin': r.gstin.text.trim(),
                  'phone': r.phone.text.trim(),
                  'btst_code': r.btstCode.text.trim(),
                },
              })
          .toList();

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
      for (final row in _rows) {
        row.selected = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: ModernUIComponents.buildModernAppBar(
        title: 'Review PODs',
        subtitle: '${_rows.length} invoice(s) • $_selectedCount selected',
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
    if (_rows.isEmpty) {
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: _rows.length,
      itemBuilder: (_, i) => _buildRowCard(_rows[i], i),
    );
  }

  Widget _buildRowCard(_HospitalRow row, int index) {
    final warnings = row.warnings;
    final isUnmapped = warnings.contains('hospital_not_mapped');

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
                  value: row.selected,
                  onChanged: (v) => setState(() => row.selected = v ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Invoice: ${row.invoiceNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'POD #${row.podId}'
                        '${row.invoiceDate != null ? ' • ${row.invoiceDate}' : ''}'
                        '${row.amount != null ? ' • ₹${row.amount}' : ''}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
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
            _buildMatchBanner(row),
            _field(row.name, 'Hospital name', required: true),
            _field(row.btstCode, 'BTST code'),
            _field(row.address, 'Address', maxLines: 2),
            Row(
              children: [
                Expanded(child: _field(row.city, 'City')),
                const SizedBox(width: 8),
                Expanded(child: _field(row.state, 'State')),
                const SizedBox(width: 8),
                SizedBox(width: 110, child: _field(row.pincode, 'Pincode')),
              ],
            ),
            Row(
              children: [
                Expanded(child: _field(row.gstin, 'GSTIN')),
                const SizedBox(width: 8),
                Expanded(child: _field(row.phone, 'Phone')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchBanner(_HospitalRow row) {
    final hasSuggestion = row.suggestedMasterName != null &&
        row.suggestedMasterName!.trim().isNotEmpty;

    if (!hasSuggestion && row.extractedName.isEmpty) {
      return const SizedBox.shrink();
    }

    final conf = row.suggestedConfidence ?? 'low';
    final confColor = conf == 'high'
        ? Colors.green
        : (conf == 'medium' ? Colors.orange : Colors.grey);
    final score = row.suggestedScore?.toStringAsFixed(0) ?? '';

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
            _kvLine('Extracted', row.extractedName.isEmpty ? '—' : row.extractedName),
            if (row.extractedAddress.isNotEmpty)
              _kvLine('Extracted address', row.extractedAddress),
            if (row.extractedBtstCode.isNotEmpty)
              _kvLine('Extracted BTST', row.extractedBtstCode),
            if (hasSuggestion) ...[
              const Divider(height: 10),
              _kvLine('Master match', row.suggestedMasterName!),
              if ((row.suggestedMasterAddress ?? '').isNotEmpty)
                _kvLine('Master address', row.suggestedMasterAddress!),
              if ((row.suggestedMasterBtstCode ?? '').isNotEmpty)
                _kvLine('Master BTST', row.suggestedMasterBtstCode!),
              const SizedBox(height: 4),
              Text(
                conf == 'low'
                    ? 'Low confidence — please verify the address and BTST code before submitting.'
                    : 'Fields below are prefilled from the master. Edits are saved back to the master hospital record.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ] else ...[
              const SizedBox(height: 2),
              Text(
                'No confident master match found. Fill in the correct hospital details manually.',
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

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

class _HospitalRow {
  final int podId;
  final String invoiceNumber;
  final String? invoiceDate;
  final String? amount;
  final String? fileViewUrl;
  final List<String> warnings;
  final int? hospitalId;

  // Extracted (raw) values — shown read-only for reference.
  final String extractedName;
  final String extractedBtstCode;
  final String extractedAddress;

  // Suggested master match — null when no confident match found.
  final int? suggestedMasterId;
  final String? suggestedMasterName;
  final String? suggestedMasterBtstCode;
  final String? suggestedMasterAddress;
  final double? suggestedScore;
  final String? suggestedConfidence;

  // Editable fields (prefilled from suggested master when available, else
  // from the extracted hospital).
  final TextEditingController name;
  final TextEditingController btstCode;
  final TextEditingController address;
  final TextEditingController city;
  final TextEditingController state;
  final TextEditingController pincode;
  final TextEditingController gstin;
  final TextEditingController phone;

  bool selected;

  _HospitalRow({
    required this.podId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.amount,
    required this.fileViewUrl,
    required this.warnings,
    required this.hospitalId,
    required this.extractedName,
    required this.extractedBtstCode,
    required this.extractedAddress,
    required this.suggestedMasterId,
    required this.suggestedMasterName,
    required this.suggestedMasterBtstCode,
    required this.suggestedMasterAddress,
    required this.suggestedScore,
    required this.suggestedConfidence,
    required this.name,
    required this.btstCode,
    required this.address,
    required this.city,
    required this.state,
    required this.pincode,
    required this.gstin,
    required this.phone,
    required this.selected,
  });

  factory _HospitalRow.fromJson(Map<String, dynamic> json) {
    final hospital = (json['hospital'] as Map<String, dynamic>?) ?? {};
    final suggested = json['suggested_master'] as Map<String, dynamic>?;
    final warnings = ((json['warnings'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();

    String s(dynamic v) => v?.toString() ?? '';
    double? d(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    // Prefer the suggested master's values for the editable fields when
    // confidence is medium/high; fall back to whatever was extracted.
    final conf = suggested?['confidence']?.toString();
    final useSuggested = suggested != null && (conf == 'high' || conf == 'medium');
    Map<String, dynamic> pick(String key) {
      if (useSuggested && suggested[key] != null && suggested[key].toString().trim().isNotEmpty) {
        return suggested;
      }
      return hospital;
    }

    return _HospitalRow(
      podId: (json['pod_id'] as num).toInt(),
      invoiceNumber: s(json['invoice_number']),
      invoiceDate: json['invoice_date']?.toString(),
      amount: json['amount']?.toString(),
      fileViewUrl: json['file_view_url']?.toString(),
      warnings: warnings,
      hospitalId: useSuggested
          ? (suggested['hospital_id'] as num?)?.toInt()
          : (hospital['hospital_id'] as num?)?.toInt(),
      extractedName: s(hospital['name']),
      extractedBtstCode: s(hospital['btst_code']),
      extractedAddress: s(hospital['address']),
      suggestedMasterId: (suggested?['hospital_id'] as num?)?.toInt(),
      suggestedMasterName: suggested?['name']?.toString(),
      suggestedMasterBtstCode: suggested?['btst_code']?.toString(),
      suggestedMasterAddress: suggested?['address']?.toString(),
      suggestedScore: d(suggested?['score']),
      suggestedConfidence: conf,
      name: TextEditingController(text: s(pick('name')['name'])),
      btstCode: TextEditingController(text: s(pick('btst_code')['btst_code'])),
      address: TextEditingController(text: s(pick('address')['address'])),
      city: TextEditingController(text: s(pick('city')['city'])),
      state: TextEditingController(text: s(pick('state')['state'])),
      pincode: TextEditingController(text: s(pick('pincode')['pincode'])),
      gstin: TextEditingController(text: s(pick('gstin')['gstin'])),
      phone: TextEditingController(text: s(pick('phone')['phone'])),
      selected: json['selected'] == true,
    );
  }

  void dispose() {
    name.dispose();
    btstCode.dispose();
    address.dispose();
    city.dispose();
    state.dispose();
    pincode.dispose();
    gstin.dispose();
    phone.dispose();
  }
}
