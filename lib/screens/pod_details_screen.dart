import 'package:flutter/material.dart';
import 'package:zydus_vistaar/services/pod_details_service.dart';
import 'package:zydus_vistaar/screens/e_invoice_data_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zydus_vistaar/routes.dart';

class PodDetailsScreen extends StatefulWidget {
  final int podId;
  final String documentType;

  const PodDetailsScreen({
    super.key,
    required this.podId,
    required this.documentType,
  });

  @override
  State<PodDetailsScreen> createState() => _PodDetailsScreenState();
}

class _PodDetailsScreenState extends State<PodDetailsScreen> {
  Map<String, dynamic>? _podData;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPodDetails();
  }

  Future<void> _loadPodDetails() async {
    print('Pod ID: ${widget.podId}');
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final data = await PodDetailsService.getPodDetails(widget.podId);
      print('Pod Details: $data');
      if (mounted) {
        setState(() {
          _podData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('POD Details'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPodDetails,
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? _buildErrorWidget()
              : _podData != null
              ? _buildPodDetails()
              : const Center(child: Text('No data available')),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            'Error Loading POD Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Unknown error occurred',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadPodDetails,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildPodDetails() {
    final pod = _podData!['data'];
    final stockist = pod['stockist'];
    final hospital = pod['hospital'];
    final items = pod['items'] as List<dynamic>;
    final hasPricingData = _hasPricingData(items);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          _buildHeaderCard(pod),

          // const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    // Open the file_path link in the browser
                    final url = pod['file_path'];
                    if (url != null && url is String && url.isNotEmpty) {
                      Uri uri = Uri.parse(url);
                      if (!await launchUrl(
                         uri,
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw Exception('Could not launch $url');
                      }
                    }
                  },
                  child: Container(
                    alignment: Alignment.center,
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.withOpacity(0.5)),
                    ),
                    child: Text(
                      'View File',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () async{
                    final eInvoice = pod['e_invoice'];
                    if (eInvoice == null) {
                      // Navigate to E-Invoice data screen with null data to show no-data view
                      Navigator.pushNamed(
                        context,
                        AppRoutes.eInvoiceData,
                        arguments: {
                          'qrData': null,
                          'fileName': 'POD_${pod['id']}_E-Invoice.pdf',
                          'uploadTime': DateTime.now(),
                          'podId': pod['id']?.toString() ?? '0',
                        },
                      );
                    } else {
                      // Navigate to E-Invoice data screen with existing data
                      _navigateToEInvoiceDataScreen(pod, eInvoice);
                    }
                    
                  },
                  child: Container(
                    alignment: Alignment.center,
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue.withOpacity(0.5)),
                    ),
                    child: Text(
                      'View E-Invoice',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // const SizedBox(height: 16),

          // Stockist & Hospital Info
          Row(
            children: [
              Expanded(child: _buildStockistCard(stockist)),
              const SizedBox(width: 12),
              Expanded(child: _buildHospitalCard(hospital)),
            ],
          ),
          const SizedBox(height: 16),

          // Items List
          _buildItemsCard(items, hasPricingData),

          // Summary Card
          if (hasPricingData) ...[
            const SizedBox(height: 16),
            _buildSummaryCard(pod),
          ],
        ],
      ),
    );
  }

  /// A POD can arrive with quantities only — an Excel upload with no rate column
  /// whose products also carry no Product Master price. Money fields are dropped
  /// in that case rather than shown as a column of ₹0.00.
  bool _hasPricingData(List<dynamic> items) {
    return items.any(
      (item) =>
          _toAmount(item['rate']) > 0 ||
          _toAmount(item['amount']) > 0 ||
          _toAmount(item['final_total']) > 0,
    );
  }

  double _toAmount(dynamic value) {
    if (value is num) return value.toDouble();

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Widget _buildHeaderCard(Map<String, dynamic> pod) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [const Color(0xFF00A0A8), const Color(0xFF6EC1C7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
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
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.receipt_long,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pod['pod_number'] ?? 'N/A',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Invoice: ${pod['invoice_number'] ?? 'N/A'}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(pod['status']),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildInfoItem(
                  Icons.calendar_today,
                  'POD Date',
                  _formatDate(pod['pod_date']),
                ),
                const SizedBox(width: 24),
                _buildInfoItem(
                  Icons.calendar_today,
                  'Invoice Date',
                  _formatDate(pod['invoice_date']),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String? status) {
    Color statusColor;
    switch (status?.toLowerCase()) {
      case 'pending':
        statusColor = Colors.orange;
        break;
      case 'verified':
        statusColor = Colors.green;
        break;
      case 'processed':
        statusColor = Colors.blue;
        break;
      case 'rejected':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.5)),
      ),
      child: Text(
        status?.toUpperCase() ?? 'UNKNOWN',
        style: TextStyle(
          color: statusColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.8), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockistCard(Map<String, dynamic> stockist) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A0A8).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.business,
                    color: Color(0xFF00A0A8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Stockist',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Name', stockist['name'] ?? 'N/A'),
            _buildDetailRow('Code', stockist['code'] ?? 'N/A'),
            _buildDetailRow('Email', stockist['email'] ?? 'N/A'),
            _buildDetailRow('Phone', stockist['phone'] ?? 'N/A'),
            _buildDetailRow('City', stockist['city'] ?? 'N/A'),
            _buildDetailRow('State', stockist['state'] ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildHospitalCard(Map<String, dynamic> hospital) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB24B9E).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.local_hospital,
                    color: Color(0xFFB24B9E),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Hospital',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Name', hospital['name'] ?? 'N/A'),
            _buildDetailRow('Code', hospital['code'] ?? 'N/A'),
            _buildDetailRow('Email', hospital['email'] ?? 'N/A'),
            _buildDetailRow('Phone', hospital['phone'] ?? 'N/A'),
            _buildDetailRow('City', hospital['city'] ?? 'N/A'),
            _buildDetailRow('State', hospital['state'] ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCard(List<dynamic> items, bool hasPricingData) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6EC1C7).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2,
                    color: Color(0xFF6EC1C7),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Items',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${items.length} items',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...items.map((item) => _buildItemCard(item, hasPricingData)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item, bool hasPricingData) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item['remarks'] ?? 'Product',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A0A8).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Qty: ${item['quantity']}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF00A0A8),
                  ),
                ),
              ),
            ],
          ),
          if (hasPricingData) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _buildItemDetail('Rate', '₹${item['rate']}'),
                const SizedBox(width: 16),
                _buildItemDetail('Amount', '₹${item['amount']}'),
                const SizedBox(width: 16),
                _buildItemDetail('Total', '₹${item['final_total']}'),
              ],
            ),
          ],
          if (item['batch_number'] != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _buildItemDetail('Batch', item['batch_number']),
                if (item['pack_size'] != null) ...[
                  const SizedBox(width: 16),
                  _buildItemDetail('Pack Size', item['pack_size']),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemDetail(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> pod) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calculate,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Summary',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSummaryRow(
              'Total Amount',
              '₹${pod['total_amount'] ?? '0.00'}',
            ),
            if (pod['tax_amount'] != null)
              _buildSummaryRow('Tax Amount', '₹${pod['tax_amount']}'),
            if (pod['discount_amount'] != null)
              _buildSummaryRow('Discount', '₹${pod['discount_amount']}'),
            const Divider(),
            _buildSummaryRow(
              'Final Total',
              '₹${pod['total_amount'] ?? '0.00'}',
              isTotal: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isTotal ? const Color(0xFF00A0A8) : Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isTotal ? const Color(0xFF00A0A8) : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Invalid Date';
    }
  }






  void _navigateToEInvoiceDataScreen(Map<String, dynamic> pod, Map<String, dynamic> eInvoice) {
    // Convert POD E-Invoice data to QR data format for the E-Invoice data screen
    final qrData = _convertPodEInvoiceToQrData(eInvoice);
    
    Navigator.pushNamed(
      context,
      AppRoutes.eInvoiceData,
      arguments: {
        'qrData': qrData,
        'fileName': 'POD_${pod['id']}_E-Invoice.pdf',
        'uploadTime': DateTime.now(),
        'podId': pod['id']?.toString() ?? '0',
      },
    );
  }

  Map<String, dynamic> _convertPodEInvoiceToQrData(Map<String, dynamic> eInvoice) {
    // Convert POD E-Invoice format to QR data format expected by EInvoiceDataScreen
    final qrData = <String, dynamic>{};
    
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
    
    return qrData;
  }


}
