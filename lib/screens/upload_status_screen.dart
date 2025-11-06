import 'package:flutter/material.dart';
import 'package:zyduspod/widgets/modern_ui_components.dart';

class UploadStatusScreen extends StatelessWidget {
  final Map<String, dynamic> uploadData;
  final int totalFiles;

  const UploadStatusScreen({
    super.key,
    required this.uploadData,
    required this.totalFiles,
  });

  @override
  Widget build(BuildContext context) {
    final data = uploadData['data'] as Map<String, dynamic>?;
    final batchId = data?['batch_id'] ?? 'N/A';
    final status = data?['status'] ?? 'processing';
    final correlationId = data?['correlation_id'] ?? 'N/A';
    final estimatedCompletion = data?['estimated_completion'] ?? 'N/A';
    final processingSteps = data?['processing_steps'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      appBar: ModernUIComponents.buildModernAppBar(
        title: 'Upload Status',
        subtitle: 'Background processing initiated',
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
              // Success Header
              _buildSuccessCard(),
              const SizedBox(height: 20),
              
              // Upload Summary
              _buildSectionCard(
                icon: Icons.info_outline,
                title: 'Upload Summary',
                child: Column(
                  children: [
                    _buildInfoRow('Total Files', totalFiles.toString()),
                    _buildInfoRow('Batch ID', batchId),
                    _buildInfoRow('Status', status.toUpperCase()),
                    _buildInfoRow('Correlation ID', correlationId),
                    _buildInfoRow('Estimated Completion', _formatDateTime(estimatedCompletion)),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Processing Steps
              _buildSectionCard(
                icon: Icons.timeline,
                title: 'Processing Steps',
                child: Column(
                  children: processingSteps.entries.map((entry) {
                    return _buildProcessingStep(entry.key, entry.value.toString());
                  }).toList(),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Important Notice
              _buildNoticeCard(),
              
              const SizedBox(height: 20),
              
              // Action Buttons
              _buildActionButtons(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [Colors.green.shade400, Colors.green.shade600],
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
              child: const Icon(
                Icons.check_circle,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Files Uploaded Successfully!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Background processing has been initiated. Your data will appear on the dashboard once processing is complete.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
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
            width: 120,
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
    // Convert step keys to readable format
    String readableStep = _getReadableStepName(stepKey);
    
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
                  readableStep,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                Text(
                  stepValue,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.blue.shade50,
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info,
              color: Colors.blue.shade700,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Important Notice',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your files are being processed in the background. This may take a few minutes. You can check the dashboard later to see the processed data.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade600,
                    ),
                  ),
                ],
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
              // Navigate back to dashboard or main screen
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
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              // Navigate back to upload screen
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.upload),
            label: const Text('Upload More Files'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00A0A8),
              side: const BorderSide(color: Color(0xFF00A0A8)),
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

  String _formatDateTime(String dateTimeString) {
    if (dateTimeString == 'N/A') return 'N/A';
    
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTimeString;
    }
  }

  String _getReadableStepName(String stepKey) {
    switch (stepKey) {
      case 'step_1':
        return 'File Storage';
      case 'step_2':
        return 'Data Extraction';
      case 'step_3':
        return 'E-invoice Processing';
      case 'step_4':
        return 'Data Storage';
      default:
        return stepKey.replaceAll('_', ' ').toUpperCase();
    }
  }

  Color _getStepColor(String stepValue) {
    if (stepValue.toLowerCase().contains('successfully')) {
      return Colors.green;
    } else if (stepValue.toLowerCase().contains('progress')) {
      return Colors.orange;
    } else if (stepValue.toLowerCase().contains('pending')) {
      return Colors.grey;
    } else {
      return Colors.blue;
    }
  }
}
