import 'package:flutter/material.dart';
import 'package:zyduspod/services/pod_details_service.dart';
import 'package:url_launcher/url_launcher.dart';

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
                  onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (context) {
                      final eInvoice = pod['e_invoice'];
                      if (eInvoice == null) {
                        return Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              'No E-Invoice data available.',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }

                      return Padding(
                        padding: EdgeInsets.only(
                          left: 20,
                          right: 20,
                          top: 24,
                          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'E-Invoice Details',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF00A0A8),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                              const Divider(),
                              
                              // Invoice Number
                              _buildEInvoiceListTile(
                                icon: Icons.receipt_long,
                                title: 'Invoice Number',
                                subtitle: eInvoice['invoice_number']?.toString() ?? 'N/A',
                              ),
                              
                              // IRN
                              _buildEInvoiceListTile(
                                icon: Icons.qr_code_2,
                                title: 'IRN',
                                subtitle: eInvoice['irn']?.toString() ?? 'N/A',
                              ),
                              
                              // Acknowledgement Number
                              if (eInvoice['ack_no'] != null)
                                _buildEInvoiceListTile(
                                  icon: Icons.check_circle_outline,
                                  title: 'Acknowledgement No',
                                  subtitle: eInvoice['ack_no']?.toString() ?? 'N/A',
                                ),
                              
                              // Invoice Date
                              _buildEInvoiceListTile(
                                icon: Icons.calendar_today,
                                title: 'Invoice Date',
                                subtitle: _formatDate(eInvoice['invoice_date']?.toString()),
                              ),
                              
                              // Total Amount
                              _buildEInvoiceListTile(
                                icon: Icons.currency_rupee,
                                title: 'Total Amount',
                                subtitle: '₹${eInvoice['total_amount']?.toString() ?? '0.00'}',
                              ),
                              
                              // Tax Amount
                              _buildEInvoiceListTile(
                                icon: Icons.receipt,
                                title: 'Tax Amount',
                                subtitle: '₹${eInvoice['tax_amount']?.toString() ?? '0.00'}',
                              ),
                              
                              // Discount Amount
                              if (eInvoice['discount_amount'] != null && eInvoice['discount_amount'].toString() != '0.00')
                                _buildEInvoiceListTile(
                                  icon: Icons.discount,
                                  title: 'Discount Amount',
                                  subtitle: '₹${eInvoice['discount_amount']?.toString() ?? '0.00'}',
                                ),
                              
                              // Status
                              _buildEInvoiceListTile(
                                icon: Icons.info_outline,
                                title: 'Status',
                                subtitle: eInvoice['status']?.toString().toUpperCase() ?? 'N/A',
                              ),
                              
                              // GST Status
                              _buildEInvoiceListTile(
                                icon: Icons.verified,
                                title: 'GST Status',
                                subtitle: eInvoice['gst_status']?.toString().replaceAll('_', ' ').toUpperCase() ?? 'N/A',
                              ),
                              
                              // Metadata Section
                              if (eInvoice['metadata'] != null) ...[
                                const SizedBox(height: 16),
                                const Text(
                                  'Additional Information',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF00A0A8),
                                  ),
                                ),
                                const Divider(),
                                _buildEInvoiceListTile(
                                  icon: Icons.document_scanner,
                                  title: 'Document Type',
                                  subtitle: eInvoice['metadata']['doc_type']?.toString() ?? 'N/A',
                                ),
                                _buildEInvoiceListTile(
                                  icon: Icons.event,
                                  title: 'IRN Date',
                                  subtitle: eInvoice['metadata']['irn_date']?.toString() ?? 'N/A',
                                ),
                                _buildEInvoiceListTile(
                                  icon: Icons.inventory_2,
                                  title: 'Item Count',
                                  subtitle: eInvoice['metadata']['item_count']?.toString() ?? 'N/A',
                                ),
                                _buildEInvoiceListTile(
                                  icon: Icons.business,
                                  title: 'Buyer GSTIN',
                                  subtitle: eInvoice['metadata']['buyer_gstin']?.toString() ?? 'N/A',
                                ),
                                _buildEInvoiceListTile(
                                  icon: Icons.store,
                                  title: 'Seller GSTIN',
                                  subtitle: eInvoice['metadata']['seller_gstin']?.toString() ?? 'N/A',
                                ),
                                _buildEInvoiceListTile(
                                  icon: Icons.code,
                                  title: 'Main HSN Code',
                                  subtitle: eInvoice['metadata']['main_hsn_code']?.toString() ?? 'N/A',
                                ),
                              ],
                              
                              // View PDF Button
                              if (eInvoice['file_path'] != null && eInvoice['file_path'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.open_in_new),
                                      label: const Text('View E-Invoice PDF'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00A0A8),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: () async {
                                        final url = eInvoice['file_path'];
                                        if (url != null && url is String && url.isNotEmpty) {
                                          final uri = Uri.parse(url);
                                          if (!await launchUrl(
                                            uri,
                                            mode: LaunchMode.externalApplication,
                                          )) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Could not open E-Invoice file')),
                                              );
                                            }
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                    
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
          _buildItemsCard(items),
          const SizedBox(height: 16),

          // Summary Card
          _buildSummaryCard(pod),
        ],
      ),
    );
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

  Widget _buildItemsCard(List<dynamic> items) {
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
            ...items.map((item) => _buildItemCard(item)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
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

  Widget _buildEInvoiceListTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF00A0A8)),
      title: Text(
        title,
        style: TextStyle(
          color: Colors.grey.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}
