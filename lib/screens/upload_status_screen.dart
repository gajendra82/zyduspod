import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zydus_vistaar/config.dart';
// AppRoutes import dropped along with the in-app review navigation —
// hospital mapping now happens on the web portal.
// import 'package:zydus_vistaar/routes.dart';
import 'package:zydus_vistaar/widgets/modern_ui_components.dart';

class UploadStatusScreen extends StatefulWidget {
  final Map<String, dynamic> uploadData;
  final int totalFiles;

  const UploadStatusScreen({
    super.key,
    required this.uploadData,
    required this.totalFiles,
  });

  @override
  State<UploadStatusScreen> createState() => _UploadStatusScreenState();
}

class _UploadStatusScreenState extends State<UploadStatusScreen> {
  static const Duration _pollInterval = Duration(seconds: 4);
  static const Duration _pollTimeout = Duration(minutes: 15);

  Timer? _pollTimer;
  DateTime? _pollStartedAt;
  String _status = 'processing';
  int _progressPercentage = 0;
  int _blocksCompleted = 0;
  int _blocksTotal = 0;
  int _invoicesProcessed = 0;
  String? _currentBlock;
  String _batchId = 'N/A';
  int? _batchDbId;
  Map<String, dynamic> _steps = {};
  bool _navigatedToReview = false;
  String? _terminalResult; // e.g. 'no_new_pods'
  String? _terminalMessage;

  @override
  void initState() {
    super.initState();

    final data = widget.uploadData['data'] as Map<String, dynamic>?;
    _batchId = (data?['batch_id'] ?? 'N/A').toString();
    _batchDbId = _coerceInt(data?['batch_db_id']) ?? _coerceInt(data?['id']);
    _status = (data?['status'] ?? 'processing').toString();

    _pollStartedAt = DateTime.now();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollStatus());
    WidgetsBinding.instance.addPostFrameCallback((_) => _pollStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  int? _coerceInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  Future<void> _pollStatus() async {
    if (_navigatedToReview) return;
    if (_pollStartedAt != null &&
        DateTime.now().difference(_pollStartedAt!) > _pollTimeout) {
      _pollTimer?.cancel();
      return;
    }

    final pollKey = _batchDbId?.toString() ?? _batchId;
    if (pollKey.isEmpty || pollKey == 'N/A') {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      final uri = Uri.parse('${API_BASE_URL}pod/upload-background/$pollKey');

      final resp = await http
          .get(
            uri,
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return;

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return;
      final data = decoded['data'] as Map<String, dynamic>?;
      if (data == null) return;

      final newStatus = (data['status'] ?? _status).toString();
      final rawProgress = _coerceInt(data['progress_percentage']) ?? _progressPercentage;
      final newProgress = rawProgress.clamp(0, 100);
      final blockProgress = data['block_progress'] as Map<String, dynamic>?;
      final steps = data['steps'] as Map<String, dynamic>? ?? _steps;

      if (!mounted) return;
      setState(() {
        _status = newStatus;
        _progressPercentage = newProgress;
        _steps = steps;
        if (blockProgress != null) {
          _blocksCompleted = _coerceInt(blockProgress['blocks_completed']) ?? 0;
          _blocksTotal = _coerceInt(blockProgress['blocks_total']) ?? 0;
          _invoicesProcessed = _coerceInt(blockProgress['invoices_processed']) ?? 0;
          _currentBlock = blockProgress['current_block']?.toString();
        }
      });

      // Hospital mapping is now handled exclusively from the web backend's
      // "Hospital Mapping Review" tool. The Flutter app no longer navigates
      // to the in-app review screen on completion — once extraction finishes,
      // we drop into the same terminal state used for "all duplicates" uploads
      // and tell the user the mapping work happens on the web portal.
      //
      // Original navigation kept here, commented, in case we need to roll back:
      //   final review = data['review'] as Map<String, dynamic>?;
      //   final hospitals = review == null ? null : review['hospitals'] as List?;
      //   final hasHospitals = hospitals != null && hospitals.isNotEmpty;
      //   final failedFiles = review == null ? null : review['failed_files'] as List?;
      //   final hasFailedFiles = failedFiles != null && failedFiles.isNotEmpty;
      //   if (newStatus == 'completed' && (hasHospitals || hasFailedFiles)) {
      //     _navigatedToReview = true;
      //     _pollTimer?.cancel();
      //     Navigator.of(context).pushReplacementNamed(
      //       AppRoutes.podReview,
      //       arguments: {'review': review},
      //     );
      //   }

      final terminalResult = data['result']?.toString();

      if (newStatus == 'completed') {
        _pollTimer?.cancel();
        if (!mounted) return;
        setState(() {
          // Use the backend-supplied terminal label when present (e.g.
          // "no_new_pods" for all-duplicate batches); otherwise advertise
          // the new web-handoff message.
          _terminalResult = terminalResult ?? 'completed_review_on_web';
          _terminalMessage = data['result_message']?.toString()
              ?? 'Extraction complete. Hospital mapping is handled in the web portal — your administrator will verify these PODs there.';
        });
      } else if (newStatus == 'failed') {
        _pollTimer?.cancel();
      }
    } on TimeoutException {
      // ignore; next tick will retry
    } catch (_) {
      // ignore transient errors; polling continues
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTerminal = _terminalResult != null;
    final isProcessing = !hasTerminal && (_status == 'processing' || _status == 'pending');
    final isCompleted = _status == 'completed' || hasTerminal;
    final isFailed = _status == 'failed';

    return Scaffold(
      appBar: ModernUIComponents.buildModernAppBar(
        title: 'Upload Status',
        subtitle: isCompleted
            ? 'Extraction complete'
            : (isFailed ? 'Extraction failed' : 'Processing…'),
        icon: Icons.cloud_upload,
        color: const Color(0xFF00A0A8),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal.withOpacity(0.05), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusHeader(isProcessing, isCompleted, isFailed),
              const SizedBox(height: 20),
              _buildSectionCard(
                icon: Icons.info_outline,
                title: 'Upload Summary',
                child: Column(
                  children: [
                    _buildInfoRow('Total Files', widget.totalFiles.toString()),
                    _buildInfoRow('Batch ID', _batchId),
                    _buildInfoRow('Status', _status.toUpperCase()),
                    if (_blocksTotal > 0)
                      _buildInfoRow(
                        'Blocks',
                        '$_blocksCompleted / $_blocksTotal'
                            '${_currentBlock != null ? '  •  $_currentBlock' : ''}',
                      ),
                    if (_invoicesProcessed > 0)
                      _buildInfoRow('Invoices Extracted', _invoicesProcessed.toString()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progressPercentage > 0 ? _progressPercentage / 100 : null,
                minHeight: 8,
                backgroundColor: Colors.teal.withOpacity(0.15),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF00A0A8)),
              ),
              const SizedBox(height: 8),
              Text(
                _progressPercentage > 0 ? '$_progressPercentage%' : 'Starting…',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              if (_steps.isNotEmpty)
                _buildSectionCard(
                  icon: Icons.timeline,
                  title: 'Processing Steps',
                  child: Column(
                    children: _steps.entries
                        .map((entry) => _buildProcessingStep(
                              entry.key,
                              entry.value is Map
                                  ? (entry.value['status']?.toString() ?? '')
                                  : entry.value.toString(),
                            ))
                        .toList(),
                  ),
                ),
              const SizedBox(height: 20),
              _buildNoticeCard(isCompleted, isFailed),
              const SizedBox(height: 20),
              _buildActionButtons(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHeader(bool isProcessing, bool isCompleted, bool isFailed) {
    final color = isFailed
        ? Colors.red
        : (isCompleted ? Colors.green : Colors.teal);
    final icon = isFailed
        ? Icons.error
        : (isCompleted ? Icons.check_circle : Icons.hourglass_top);
    final isTerminalNoNew = _terminalResult == 'no_new_pods';
    final isTerminalReviewOnWeb = _terminalResult == 'completed_review_on_web';
    final title = isFailed
        ? 'Extraction Failed'
        : (isTerminalNoNew
            ? 'No New Invoices'
            : (isTerminalReviewOnWeb
                ? 'Upload Complete'
                : (isCompleted ? 'Extraction Complete' : 'Files Uploaded')));
    final subtitle = isFailed
        ? 'Something went wrong during processing. Try again.'
        : (isTerminalNoNew
            ? (_terminalMessage ??
                'All invoices in this upload were already recorded earlier.')
            : (isTerminalReviewOnWeb
                ? (_terminalMessage ??
                    'Extraction complete. Hospital mapping is handled in the web portal.')
                : (isCompleted
                    ? 'Finishing up…'
                    : 'Background processing is running. This screen auto-updates.')));

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.shade400, color.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            if (isProcessing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF00A0A8), size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C3E50),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF2C3E50),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingStep(String stepKey, String stepValue) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _getStepColor(stepValue),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stepKey.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                Text(
                  stepValue,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeCard(bool isCompleted, bool isFailed) {
    final color = isFailed
        ? Colors.red
        : (isCompleted ? Colors.green : Colors.blue);
    final isTerminalNoNew = _terminalResult == 'no_new_pods';
    final isTerminalReviewOnWeb = _terminalResult == 'completed_review_on_web';
    final text = isFailed
        ? 'Processing failed. Please retry the upload or contact support.'
        : (isTerminalNoNew
            ? (_terminalMessage ??
                'No new PODs were created — the invoices in this upload match records that already exist. Use the dashboard to review existing PODs.')
            : (isTerminalReviewOnWeb
                ? (_terminalMessage ??
                    'Extraction complete. Hospital mapping is handled in the web portal — your administrator will verify these PODs there.')
                : (isCompleted
                    ? 'Extraction finished. The web portal will handle hospital mapping.'
                    : 'Your files are being processed. This screen updates automatically every few seconds.')));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: color.shade50,
          border: Border.all(color: color.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.info, color: color.shade700, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 14, color: color.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: const Icon(Icons.dashboard),
            label: const Text('Go to Dashboard'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A0A8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _getStepColor(String stepValue) {
    final v = stepValue.toLowerCase();
    if (v.contains('completed') || v.contains('success')) return Colors.green;
    if (v.contains('progress') || v.contains('processing')) return Colors.orange;
    if (v.contains('pending')) return Colors.grey;
    if (v.contains('failed') || v.contains('error')) return Colors.red;
    return Colors.blue;
  }
}
