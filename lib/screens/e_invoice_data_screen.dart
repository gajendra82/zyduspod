import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:zyduspod/widgets/modern_ui_components.dart';
import 'package:zyduspod/GstInvoiceScanner.dart';
import 'package:zyduspod/services/PythonQRService.dart';
import 'package:zyduspod/widgets/EInvoiceQRExtractor.dart';
import 'package:zyduspod/services/pod_details_service.dart';

class EInvoiceDataScreen extends StatefulWidget {
  final Map<String, dynamic>? qrData;
  final String fileName;
  final DateTime uploadTime;
  final String? podId;

  const EInvoiceDataScreen({
    super.key,
    this.qrData,
    required this.fileName,
    required this.uploadTime,
    this.podId,
  });

  @override
  State<EInvoiceDataScreen> createState() => _EInvoiceDataScreenState();
}

class _EInvoiceDataScreenState extends State<EInvoiceDataScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _currentQrData;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentQrData = widget.qrData;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _hasValidData => _currentQrData != null && _currentQrData!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildHeaderCard(),
          if (_hasValidData) ...[
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBasicInfoTab(),
                  _buildDetailedDataTab(),
                ],
              ),
            ),
          ] else
            _buildNoDataView(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return ModernUIComponents.buildModernAppBar(
      title: 'E-Invoice Data',
      subtitle: _hasValidData ? 'QR Code Information' : 'No Data Available',
      icon: Icons.receipt_long,
      color: const Color(0xFF6EC1C7),
      // actions: _hasValidData
      //     ? [
      //         IconButton(
      //           onPressed: _shareData,
      //           icon: const Icon(Icons.share),
      //           tooltip: 'Share Data',
      //         ),
      //         IconButton(
      //           onPressed: _exportData,
      //           icon: const Icon(Icons.download),
      //           tooltip: 'Export Data',
      //         ),
      //       ]
      //     : null,
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _hasValidData
                  ? [const Color(0xFF6EC1C7), const Color(0xFF4ECDC4)]
                  : [const Color(0xFFFF9800), const Color(0xFFFFB74D)],
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _hasValidData ? Icons.qr_code_scanner : Icons.warning,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasValidData
                              ? 'E-Invoice Scanned Successfully'
                              : 'No QR Data Available',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.fileName,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hasValidData)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_currentQrData!.length} fields',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Scanned on ${_formatDateTime(widget.uploadTime)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _hasValidData ? Icons.check_circle : Icons.info,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _hasValidData ? 'Valid QR Code' : 'Data Required',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoDataView() {
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    spreadRadius: 1,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_outlined,
                      size: 64,
                      color: Color(0xFFFF9800),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'No E-Invoice Data Found',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This POD doesn\'t have E-Invoice data yet.\nChoose an option below to add invoice information.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _handleManualScan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR Code Manually'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isLoading 
                            ? Colors.grey 
                            : const Color(0xFF6EC1C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _handleAutoFetch,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_fix_high),
                      label: Text(_isLoading 
                          ? 'Processing...' 
                          : widget.podId != null && widget.podId!.isNotEmpty
                              ? 'Auto Fetch from POD'
                              : 'Auto Fetch from File'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildHelpCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.help_outline,
                    color: Color(0xFF2196F3),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'How to get QR Data',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2196F3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildHelpItem(
              icon: Icons.qr_code_scanner,
              title: 'Manual Scan',
              description: 'Use camera to scan QR code from physical document',
              color: const Color(0xFF6EC1C7),
            ),
            const SizedBox(height: 12),
            _buildHelpItem(
              icon: Icons.auto_fix_high,
              title: 'Auto Fetch',
              description: widget.podId != null && widget.podId!.isNotEmpty
                  ? 'Automatically extract QR data from POD file using API'
                  : 'Automatically extract QR data from uploaded PDF file',
              color: const Color(0xFF4CAF50),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            color: color,
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E50),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF6EC1C7),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF6EC1C7),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        tabs: const [
          Tab(
            icon: Icon(Icons.info_outline, size: 20),
            text: 'Basic Info',
          ),
          Tab(
            icon: Icon(Icons.description, size: 20),
            text: 'Details',
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoTab() {
    final basicFields = _getBasicInfoFields();
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionCard(
            title: 'Invoice Information',
            icon: Icons.receipt,
            color: const Color(0xFF6EC1C7),
            children: [
              if (basicFields['DocNo'] != null)
                _buildInfoRow('Invoice Number', basicFields['DocNo']),
              if (basicFields['DocDt'] != null)
                _buildInfoRow('Invoice Date', basicFields['DocDt']),
              if (basicFields['DocTyp'] != null)
                _buildInfoRow('Document Type', basicFields['DocTyp']),
              if (basicFields['TotInvVal'] != null)
                _buildInfoRow('Total Invoice Value', '₹${basicFields['TotInvVal']}'),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'GST Information',
            icon: Icons.account_balance,
            color: const Color(0xFF4CAF50),
            children: [
              if (basicFields['Gstin'] != null)
                _buildInfoRow('GSTIN', basicFields['Gstin']),
              if (basicFields['CgstAmt'] != null)
                _buildInfoRow('CGST Amount', '₹${basicFields['CgstAmt']}'),
              if (basicFields['SgstAmt'] != null)
                _buildInfoRow('SGST Amount', '₹${basicFields['SgstAmt']}'),
              if (basicFields['IgstAmt'] != null)
                _buildInfoRow('IGST Amount', '₹${basicFields['IgstAmt']}'),
              if (basicFields['TotGstAmt'] != null)
                _buildInfoRow('Total GST Amount', '₹${basicFields['TotGstAmt']}'),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'Parties Information',
            icon: Icons.business,
            color: const Color(0xFF2196F3),
            children: [
              if (basicFields['SellerName'] != null)
                _buildInfoRow('Seller Name', basicFields['SellerName']),
              if (basicFields['BuyerName'] != null)
                _buildInfoRow('Buyer Name', basicFields['BuyerName']),
              if (basicFields['BuyerGstin'] != null)
                _buildInfoRow('Buyer GSTIN', basicFields['BuyerGstin']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedDataTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionCard(
            title: 'All Invoice Data',
            icon: Icons.table_chart,
            color: const Color(0xFF9C27B0),
            children: _currentQrData!.entries
                .map((entry) => _buildInfoRow(
                      _formatFieldName(entry.key),
                      entry.value?.toString() ?? 'N/A',
                      isExpandable: true,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }


  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isExpandable = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Color(0xFF666666),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C3E50),
                fontSize: 14,
              ),
            ),
          ),
          if (isExpandable)
            IconButton(
              onPressed: () {
                _showFullTextDialog(label, value);
              },
              icon: const Icon(
                Icons.open_in_full,
                size: 16,
                color: Color(0xFF6EC1C7),
              ),
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getBasicInfoFields() {
    if (_currentQrData == null) return {};
    return {
      'DocNo': _currentQrData!['DocNo'],
      'DocDt': _currentQrData!['DocDt'],
      'DocTyp': _currentQrData!['DocTyp'],
      'TotInvVal': _currentQrData!['TotInvVal'],
      'Gstin': _currentQrData!['Gstin'],
      'CgstAmt': _currentQrData!['CgstAmt'],
      'SgstAmt': _currentQrData!['SgstAmt'],
      'IgstAmt': _currentQrData!['IgstAmt'],
      'TotGstAmt': _currentQrData!['TotGstAmt'],
      'SellerName': _currentQrData!['SellerName'],
      'BuyerName': _currentQrData!['BuyerName'],
      'BuyerGstin': _currentQrData!['BuyerGstin'],
    };
  }

  String _formatFieldName(String key) {
    return key
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
        .trim()
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }


  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _handleManualScan() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Navigate to QR scanner
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => GstQrApp(podId: widget.podId ?? '0'),
        ),
      );

      if (result != null) {
        // Navigate to data screen with the scanned data
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => EInvoiceDataScreen(
              qrData: result,
              fileName: widget.fileName,
              uploadTime: DateTime.now(),
              podId: widget.podId,
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error scanning QR code: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleAutoFetch() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // If we have a podId, use the POD API to auto-fetch QR data
      if (widget.podId != null && widget.podId!.isNotEmpty) {
        await _handlePodAutoFetch();
      } else {
        // For standalone usage, show file selection dialog
        await _handleFileAutoFetch();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error extracting QR data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handlePodAutoFetch() async {
    try {
      // Show loading message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('Processing QR extraction from POD...'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );

      final podId = int.parse(widget.podId!);
      final response = await PodDetailsService.processQrExtraction(podId);
      
      if (mounted) {
        if (response['success'] == true) {
          // Convert POD E-Invoice data to QR format
          final qrData = _convertPodResponseToQrData(response);
          
          // Navigate to data screen with the fetched data
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => EInvoiceDataScreen(
                qrData: qrData,
                fileName: widget.fileName,
                uploadTime: DateTime.now(),
                podId: widget.podId,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response['message'] ?? 'Failed to extract QR data from POD file'
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleFileAutoFetch() async {
    // Show progress message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Extracting QR data from file...'),
        backgroundColor: Colors.blue,
      ),
    );

    // Show dialog to select file or use sample data
    final result = await _showFileSelectionDialog();
    
    if (result != null) {
      // Navigate to data screen with the extracted data
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => EInvoiceDataScreen(
            qrData: result,
            fileName: widget.fileName,
            uploadTime: DateTime.now(),
            podId: widget.podId,
          ),
        ),
      );
    }
  }

  Map<String, dynamic> _convertPodResponseToQrData(Map<String, dynamic> response) {
    // Convert POD API response to QR data format
    final qrData = <String, dynamic>{};
    
    // Extract E-Invoice data from response
    final eInvoice = response['data']?['e_invoice'] ?? response['e_invoice'];
    if (eInvoice != null) {
      // Map basic fields
      qrData['DocNo'] = eInvoice['invoice_number'];
      qrData['DocDt'] = eInvoice['invoice_date'];
      qrData['DocTyp'] = eInvoice['metadata']?['doc_type'] ?? 'INV';
      qrData['TotInvVal'] = eInvoice['total_amount'];
      qrData['Gstin'] = eInvoice['metadata']?['seller_gstin'];
      qrData['CgstAmt'] = eInvoice['tax_amount'] != null ? 
          (double.tryParse(eInvoice['tax_amount'].toString()) ?? 0) / 2 : null;
      qrData['SgstAmt'] = eInvoice['tax_amount'] != null ? 
          (double.tryParse(eInvoice['tax_amount'].toString()) ?? 0) / 2 : null;
      qrData['IgstAmt'] = '0.00';
      qrData['TotGstAmt'] = eInvoice['tax_amount'];
      qrData['SellerName'] = eInvoice['metadata']?['seller_name'];
      qrData['BuyerName'] = eInvoice['metadata']?['buyer_name'];
      qrData['BuyerGstin'] = eInvoice['metadata']?['buyer_gstin'];
      qrData['Irn'] = eInvoice['irn'];
      qrData['AckNo'] = eInvoice['ack_no'];
      qrData['AckDt'] = eInvoice['metadata']?['irn_date'];
      qrData['Status'] = eInvoice['status'];
      qrData['GstStatus'] = eInvoice['gst_status'];
      
      // Add metadata
      if (eInvoice['metadata'] != null) {
        qrData['ItemCount'] = eInvoice['metadata']['item_count'];
        qrData['MainHsnCode'] = eInvoice['metadata']['main_hsn_code'];
        qrData['DiscountAmount'] = eInvoice['discount_amount'];
      }
      
      // Add file path if available
      if (eInvoice['file_path'] != null) {
        qrData['FilePath'] = eInvoice['file_path'];
      }
    }
    
    return qrData;
  }

  Future<Map<String, dynamic>?> _showFileSelectionDialog() async {
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auto Fetch QR Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose how to extract QR data:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.file_present, color: Colors.blue),
              title: const Text('Use Sample PDF'),
              subtitle: const Text('Extract from sample E-Invoice'),
              onTap: () => Navigator.pop(context, _getSampleQrData()),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.green),
              title: const Text('Upload PDF File'),
              subtitle: const Text('Select a PDF file to process'),
              onTap: () async {
                Navigator.pop(context); // Close dialog first
                await _processPdfFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.grey),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context, null),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getSampleQrData() {
    return {
      'DocNo': '5EN13986',
      'DocDt': '15/12/2024',
      'DocTyp': 'INV',
      'TotInvVal': '25000.00',
      'Gstin': '27AABCU9603R1ZX',
      'CgstAmt': '2250.00',
      'SgstAmt': '2250.00',
      'IgstAmt': '0.00',
      'TotGstAmt': '4500.00',
      'SellerName': 'Zydus Healthcare Ltd',
      'BuyerName': 'Global Healthcare Solutions',
      'BuyerGstin': '07AABCU9603R1ZX',
      'ItemName': 'Pharmaceutical Products',
      'HsnCode': '3004',
      'Qty': '100',
      'UnitPrice': '250.00',
      'TaxableAmt': '25000.00',
      'Irn': 'ZYDUS12345678901234567890',
      'AckNo': 'ACK123456789',
      'AckDt': '15/12/2024',
    };
  }

  Future<void> _processPdfFile() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Pick PDF file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final File pdfFile = File(result.files.single.path!);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Processing PDF file...'),
            backgroundColor: Colors.blue,
          ),
        );

        // Try to extract QR data using PythonQRService first
        Map<String, dynamic>? qrData;
        
        try {
          qrData = await PythonQRService.extractQRFromPDF(
            pdfFile,
            maxPages: 3,
            dpi: 400,
          ).timeout(
            const Duration(seconds: 90),
            onTimeout: () => null,
          );
        } catch (e) {
          debugPrint('PythonQRService failed: $e');
        }

        // Fallback to local EInvoiceQRExtractor if PythonQRService fails
        if (qrData == null) {
          try {
            qrData = await EInvoiceQRExtractor.extractQRFromPDF(
              pdfFile,
              dpi: 600,
              maxPages: 2,
            ).timeout(
              const Duration(seconds: 30),
              onTimeout: () => null,
            );
          } catch (e) {
            debugPrint('EInvoiceQRExtractor failed: $e');
          }
        }

        if (qrData != null && qrData.isNotEmpty) {
          // Navigate to data screen with the extracted data
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => EInvoiceDataScreen(
                qrData: qrData,
                fileName: result.files.single.name,
                uploadTime: DateTime.now(),
                podId: widget.podId,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No QR code found in the PDF file'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No file selected'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showFullTextDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SelectableText(content),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
              Navigator.pop(context);
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }



}
