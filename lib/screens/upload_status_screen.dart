import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zydus_vistaar/config.dart';
// AppRoutes import dropped along with the in-app review navigation —
// hospital mapping now happens on the web portal.
// import 'package:zydus_vistaar/routes.dart';
import 'package:zydus_vistaar/services/pod_background_upload_manager.dart';
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
  Timer? _bgUploadTimer;
  DateTime? _pollStartedAt;
  String _status = 'processing';
  int _progressPercentage = 0;
  int _blocksCompleted = 0;
  int _blocksTotal = 0;
  int _blocksFailed = 0;
  int _invoicesProcessed = 0;
  int _processedFiles = 0;
  int _failedFiles = 0;
  int _totalFilesServer = 0;
  String? _currentBlock;
  String _batchId = 'N/A';
  int? _batchDbId;
  String? _backgroundUploadId;
  Map<String, dynamic> _steps = {};
  bool _navigatedToReview = false;
  String? _terminalResult; // e.g. 'no_new_pods'
  String? _terminalMessage;
  String? _statusMessage;
  // Keep for internal debugging only (do not surface to user).
  // ignore: unused_field
  int _consecutivePollFailures = 0;

  @override
  void initState() {
    super.initState();

    final data = widget.uploadData['data'] as Map<String, dynamic>?;
    _batchId = (data?['batch_id'] ?? 'N/A').toString();
    _batchDbId = _coerceInt(data?['batch_db_id']) ?? _coerceInt(data?['id']);
    _status = (data?['status'] ?? 'processing').toString();
    _backgroundUploadId = data?['background_upload_id']?.toString();

    _pollStartedAt = DateTime.now();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollStatus());
    _bgUploadTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _syncBackgroundUpload());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
      _syncBackgroundUpload();
      _pollStatus();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _bgUploadTimer?.cancel();
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    super.dispose();
  }

  void _syncBackgroundUpload() {
    if (_backgroundUploadId == null || _backgroundUploadId!.isEmpty) return;
    final s = PodBackgroundUploadManager.instance.state.value;
    if (s == null || s.uploadId != _backgroundUploadId) return;

    if (!mounted) return;

    // If upload produced batch ids, start polling the server.
    if (_batchDbId == null && s.podUploadBatchId != null) {
      setState(() {
        _batchDbId = s.podUploadBatchId;
        _batchId = s.externalBatchId ?? _batchId;
        _status = 'processing';
        _statusMessage = 'Upload complete. Processing on server…';
      });
      return;
    }

    // While still uploading to Azure, show local progress and avoid scary
    // network/CORS messages (the status API isn't available yet).
    if (_batchDbId == null && s.isRunning) {
      final pct = s.percent;
      final fileIdx = s.currentFileIndex <= 0 ? 1 : s.currentFileIndex;
      final total = s.totalFiles <= 0 ? widget.totalFiles : s.totalFiles;
      setState(() {
        _status = 'uploading_to_cloud';
        _progressPercentage = pct ?? 0;
        _statusMessage =
            '${s.message} (file $fileIdx/$total)${pct != null ? ' — $pct%' : ''}';
      });
    }

    if (_batchDbId == null && !s.isRunning && s.errorMessage != null) {
      setState(() {
        _status = 'failed';
        _terminalMessage = s.errorMessage;
      });
    }
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
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Processing your files. Large uploads may take a few minutes.';
      });
      return;
    }

    final pollKey = _batchDbId?.toString() ?? _batchId;
    if (pollKey.isEmpty || pollKey == 'N/A') {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      // `include_review=0` keeps the status API lightweight while processing
      // (review payload can be expensive and cause timeouts).
      final uri = Uri.parse('${API_BASE_URL}pod/upload-background/$pollKey?include_review=0');

      final resp = await http
          .get(
            uri,
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        _pollTimer?.cancel();
        if (!mounted) return;
        setState(() {
          _status = 'failed';
          _terminalResult = 'auth_required';
          _terminalMessage =
              'Session expired. Please log in again, then retry the upload.';
        });
        return;
      }

      if (resp.statusCode == 404) {
        if (_pollStartedAt != null &&
            DateTime.now().difference(_pollStartedAt!) >
                const Duration(seconds: 20)) {
          if (!mounted) return;
          setState(() {
            // Keep UX friendly: don't show polling errors.
            _statusMessage =
                'Your files are being processed in the background. Please wait…';
          });
        }
        return;
      }

      if (resp.statusCode != 200) {
        _consecutivePollFailures++;
        // Silent retry; keep last known progress on screen.
        return;
      }

      Map<String, dynamic> decoded;
      try {
        final raw = jsonDecode(resp.body);
        if (raw is! Map<String, dynamic>) return;
        decoded = raw;
      } on FormatException {
        _consecutivePollFailures++;
        // Silent retry.
        return;
      }

      if (decoded['success'] == false) {
        _consecutivePollFailures++;
        // Silent retry.
        return;
      }

      final data = decoded['data'] as Map<String, dynamic>?;
      if (data == null) return;

      final newStatus = (data['status'] ?? _status).toString();
      final rawProgress = _coerceInt(data['progress_percentage']) ?? _progressPercentage;
      final newProgress = rawProgress.clamp(0, 100);
      final blockProgress = data['block_progress'] as Map<String, dynamic>?;
      final steps = data['steps'] as Map<String, dynamic>? ?? _steps;
      final statusMessage = data['status_message']?.toString();
      final totalFilesServer = _coerceInt(data['total_files']) ?? 0;
      final processedFiles = _coerceInt(data['processed_files']) ?? 0;
      final failedFiles = _coerceInt(data['failed_files']) ?? 0;

      if (!mounted) return;
      setState(() {
        _consecutivePollFailures = 0;
        _status = newStatus;
        _progressPercentage = newProgress;
        _steps = steps;
        _totalFilesServer = totalFilesServer;
        _processedFiles = processedFiles;
        _failedFiles = failedFiles;
        if (statusMessage != null && statusMessage.isNotEmpty) {
          _statusMessage = statusMessage;
        }
        if (blockProgress != null) {
          _blocksCompleted = _coerceInt(blockProgress['blocks_completed']) ?? 0;
          _blocksTotal = _coerceInt(blockProgress['blocks_total'])
              ?? _coerceInt(blockProgress['split_count'])
              ?? 0;
          _blocksFailed = _coerceInt(blockProgress['blocks_failed']) ?? 0;
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

      if (newStatus == 'completed' || newStatus == 'partially_completed') {
        _pollTimer?.cancel();
        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        setState(() {
          _terminalResult = terminalResult
              ?? (newStatus == 'partially_completed'
                  ? 'partial_success'
                  : 'completed_review_on_web');
          _terminalMessage = data['result_message']?.toString()
              ?? (newStatus == 'partially_completed'
                  ? 'Partial extraction complete. Successfully processed PODs are saved; failed blocks can be resumed from the web portal.'
                  : 'Extraction complete. Hospital mapping is handled in the web portal — your administrator will verify these PODs there.');
        });
      } else if (newStatus == 'failed') {
        _pollTimer?.cancel();
        if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
      }
    } on TimeoutException {
      _consecutivePollFailures++;
      // Silent retry.
    } catch (e) {
      _consecutivePollFailures++;
      // Silent retry.
    }
  }

  String _progressDetailText() {
    if (_progressPercentage > 0) {
      return '$_progressPercentage% — ${_statusMessage ?? 'Processing…'}';
    }
    if (_blocksTotal > 0) {
      return _statusMessage ?? 'Extracting blocks… (large files can take several minutes per block)';
    }
    return _statusMessage ?? 'Server is preparing your file…';
  }

  @override
  Widget build(BuildContext context) {
    final hasTerminal = _terminalResult != null;
    final isProcessing = !hasTerminal &&
        (_status == 'processing' ||
            _status == 'pending' ||
            _status == 'uploading_to_cloud');
    final isCompleted = _status == 'completed'
        || _status == 'partially_completed'
        || hasTerminal;
    final isFailed = _status == 'failed';

    return Scaffold(
      appBar: ModernUIComponents.buildModernAppBar(
        title: 'Upload Status',
        subtitle: isCompleted
            ? (_terminalResult == 'partial_success'
                ? 'Partial extraction complete'
                : 'Extraction complete')
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
                    if (_statusMessage != null && _statusMessage!.isNotEmpty)
                      _buildInfoRow('Current Step', _statusMessage!),
                    if (_totalFilesServer > 0)
                      _buildInfoRow(
                        'Files Processed',
                        '$_processedFiles / $_totalFilesServer'
                            '${_failedFiles > 0 ? '  •  $_failedFiles failed' : ''}',
                      ),
                    if (_blocksTotal > 0)
                      _buildInfoRow(
                        'Blocks',
                        '$_blocksCompleted / $_blocksTotal'
                            '${_blocksFailed > 0 ? '  •  $_blocksFailed failed' : ''}'
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
                _progressDetailText(),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                icon: Icons.timeline,
                title: 'Processing Stages',
                child: Column(
                  children: _buildStageRows(),
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
    final isTerminalPartial = _terminalResult == 'partial_success';
    final isTerminalNoNew = _terminalResult == 'no_new_pods';
    final isTerminalReviewOnWeb = _terminalResult == 'completed_review_on_web';
    final color = isFailed
        ? Colors.red
        : (isTerminalPartial
            ? Colors.orange
            : (isCompleted ? Colors.green : Colors.teal));
    final icon = isFailed
        ? Icons.error
        : (isTerminalPartial
            ? Icons.warning_amber_rounded
            : (isCompleted ? Icons.check_circle : Icons.hourglass_top));
    final title = isFailed
        ? 'Extraction Failed'
        : (isTerminalNoNew
            ? 'No New Invoices'
            : (isTerminalPartial
                ? 'Partial Extraction'
                : (isTerminalReviewOnWeb
                    ? 'Upload Complete'
                    : (isCompleted
                        ? 'Extraction Complete'
                        : 'Your files are being processed in the background.'))));
    final subtitle = isFailed
        ? 'Something went wrong during processing. Try again.'
        : (isTerminalNoNew
            ? (_terminalMessage ??
                'All invoices in this upload were already recorded earlier.')
            : (isTerminalPartial
                ? (_terminalMessage ??
                    'Some blocks could not be extracted. Successfully processed PODs are saved; failed blocks can be resumed from the web portal.')
                : (isTerminalReviewOnWeb
                    ? (_terminalMessage ??
                        'Extraction complete. Hospital mapping is handled in the web portal.')
                    : (isCompleted
                        ? 'Finishing up…'
                        : "You don't need to keep this page open. You can safely leave this page or upload additional files while processing continues. We'll keep your uploads processing in the background."))));

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

  // Kept for rollback (old UI), currently unused.
  // ignore: unused_element
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

  List<Widget> _buildStageRows() {
    String statusOf(dynamic step) {
      if (step is Map) return (step['status']?.toString() ?? '');
      if (step is String) return step;
      return '';
    }

    final zipStatus = statusOf(_steps['step_0_zip_unpacking']).toLowerCase();
    final splitStatus = statusOf(_steps['step_0_split_pdf_processing']).toLowerCase();
    final extractStatus = statusOf(_steps['step_1_extract_processing']).toLowerCase();

    // Stage 1: Files uploaded (we only land on this screen after upload request).
    final filesUploadedDone = true;

    // Stage 2: Either server-side ZIP unpack, or split-pdf.
    final preparingLabel =
        zipStatus.isNotEmpty ? 'ZIP Processing' : 'Split PDF Processing';
    final preparingDone = zipStatus.contains('completed') ||
        splitStatus.contains('completed') ||
        splitStatus.contains('skipped');
    final preparingActive = !preparingDone &&
        (zipStatus.contains('progress') ||
            zipStatus.contains('in_progress') ||
            zipStatus.contains('processing') ||
            splitStatus.contains('progress') ||
            splitStatus.contains('in_progress') ||
            splitStatus.contains('processing'));

    // Stage 3: Extraction progress.
    final extractionDone = extractStatus.contains('completed') ||
        extractStatus.contains('success') ||
        extractStatus.contains('partial_success');
    final extractionActive = !extractionDone &&
        (extractStatus.contains('progress') ||
            extractStatus.contains('in_progress') ||
            extractStatus.contains('processing') ||
            extractStatus.isEmpty);

    final extractionPct = _progressPercentage.clamp(0, 100);
    final extractionDetail = (_totalFilesServer > 0)
        ? '$_processedFiles / $_totalFilesServer files processed'
        : (_blocksTotal > 0
            ? '$_blocksCompleted / $_blocksTotal blocks processed'
            : (_invoicesProcessed > 0 ? '$_invoicesProcessed invoices extracted' : ''));

    return [
      _stageRow(
        title: 'Files Uploaded',
        trailing: '100%',
        isDone: filesUploadedDone,
        isActive: false,
        subtitle: '100% Completed',
      ),
      const SizedBox(height: 8),
      _stageRow(
        title: preparingLabel,
        trailing: preparingDone ? '100%' : 'Processing…',
        isDone: preparingDone,
        isActive: preparingActive,
        subtitle: preparingDone ? '100% Completed' : 'Processing…',
      ),
      const SizedBox(height: 8),
      _stageRow(
        title: 'Data Extraction',
        trailing: extractionDone ? '100%' : '$extractionPct%',
        isDone: extractionDone,
        isActive: extractionActive,
        subtitle: extractionDone
            ? '100% Completed'
            : (extractionDetail.isNotEmpty ? extractionDetail : 'Processing…'),
      ),
    ];
  }

  Widget _stageRow({
    required String title,
    required String trailing,
    required bool isDone,
    required bool isActive,
    required String subtitle,
  }) {
    final color = isDone ? Colors.green : (isActive ? Colors.orange : Colors.grey);
    final icon = isDone
        ? Icons.check_circle
        : (isActive ? Icons.hourglass_top : Icons.radio_button_unchecked);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                    ),
                    Text(
                      trailing,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeCard(bool isCompleted, bool isFailed) {
    final isTerminalPartial = _terminalResult == 'partial_success';
    final color = isFailed
        ? Colors.red
        : (isTerminalPartial
            ? Colors.orange
            : (isCompleted ? Colors.green : Colors.blue));
    final isTerminalNoNew = _terminalResult == 'no_new_pods';
    final isTerminalReviewOnWeb = _terminalResult == 'completed_review_on_web';
    final text = isFailed
        ? 'Processing failed. Please retry the upload or contact support.'
        : (isTerminalNoNew
            ? (_terminalMessage ??
                'No new PODs were created — the invoices in this upload match records that already exist. Use the dashboard to review existing PODs.')
            : (isTerminalPartial
                ? (_terminalMessage ??
                    'Partial extraction complete. Successfully extracted PODs are saved and visible in the web portal. Failed blocks can be resumed later without reprocessing completed work.')
                : (isTerminalReviewOnWeb
                    ? (_terminalMessage ??
                        'Extraction complete. Hospital mapping is handled in the web portal — your administrator will verify these PODs there.')
                    : (isCompleted
                        ? 'Extraction finished. The web portal will handle hospital mapping.'
                        : (_statusMessage ??
                            'Your files are being processed in the background. This may take a few minutes for large uploads.')))));

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
    if (v.contains('partial')) return Colors.orange;
    if (v.contains('completed') || v.contains('success')) return Colors.green;
    if (v.contains('progress') || v.contains('processing')) return Colors.orange;
    if (v.contains('pending')) return Colors.grey;
    if (v.contains('failed') || v.contains('error')) return Colors.red;
    return Colors.blue;
  }
}
