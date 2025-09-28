import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:zyduspod/config.dart';

class DocumentsListScreen extends StatefulWidget {
  const DocumentsListScreen({super.key});

  @override
  State<DocumentsListScreen> createState() => _DocumentsListScreenState();
}

class _DocumentsListScreenState extends State<DocumentsListScreen> {
  List<Map<String, dynamic>> _allDocuments = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'All';
  String _searchQuery = '';

  final List<String> _filterOptions = [
    'All',
    'POD',
    'GRN',
    'E-INVOICE',
    'Pending',
    'Approved',
    'Processing',
    'Rejected',
  ];

  @override
  void initState() {
    super.initState();
    _loadAllDocuments();
  }

  Future<void> _loadAllDocuments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        throw Exception('No authentication token found');
      }
      print('${API_BASE_URL}dashboard/documents/all');
      final response = await http.get(
        Uri.parse('${API_BASE_URL}dashboard/documents/all'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      print('Response: ${response.body}');
      print('Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _allDocuments = List<Map<String, dynamic>>.from(
            data['data'] ?? [],
          );
        });
      } else {
        // Mock data for development
        _setMockDocuments();
      }
    } catch (e) {
      print('Error: $e');
      // Mock data for development
      _setMockDocuments();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setMockDocuments() {
    // setState(() {
    //   _allDocuments = [
    //     {
    //       'id': '1',
    //       'name': 'POD_2024_001.pdf',
    //       'type': 'POD',
    //       'status': 'Approved',
    //       'uploaded_at': '2024-01-15T10:30:00Z',
    //       'size': '2.4 MB',
    //       'stockist': 'ABC Medical Store',
    //       'hospital': 'City Hospital',
    //       'invoice_number': 'INV-2024-001',
    //       'amount': '₹15,000',
    //     },
    //     {
    //       'id': '2',
    //       'name': 'E-Invoice_2024_002.pdf',
    //       'type': 'E-INVOICE',
    //       'status': 'Pending',
    //       'uploaded_at': '2024-01-15T09:15:00Z',
    //       'size': '1.8 MB',
    //       'stockist': 'XYZ Pharmacy',
    //       'hospital': 'General Hospital',
    //       'invoice_number': 'INV-2024-002',
    //       'amount': '₹8,500',
    //     },
    //     {
    //       'id': '3',
    //       'name': 'GRN_2024_003.pdf',
    //       'type': 'GRN',
    //       'status': 'Approved',
    //       'uploaded_at': '2024-01-14T16:45:00Z',
    //       'size': '3.2 MB',
    //       'stockist': 'MediCare Store',
    //       'hospital': 'Central Hospital',
    //       'invoice_number': 'INV-2024-003',
    //       'amount': '₹22,000',
    //     },
    //     {
    //       'id': '4',
    //       'name': 'POD_2024_004.pdf',
    //       'type': 'POD',
    //       'status': 'Processing',
    //       'uploaded_at': '2024-01-14T14:20:00Z',
    //       'size': '2.1 MB',
    //       'stockist': 'Health Plus',
    //       'hospital': 'Metro Hospital',
    //       'invoice_number': 'INV-2024-004',
    //       'amount': '₹12,500',
    //     },
    //     {
    //       'id': '5',
    //       'name': 'E-Invoice_2024_005.pdf',
    //       'type': 'E-INVOICE',
    //       'status': 'Approved',
    //       'uploaded_at': '2024-01-14T11:30:00Z',
    //       'size': '1.9 MB',
    //       'stockist': 'Life Care',
    //       'hospital': 'Regional Hospital',
    //       'invoice_number': 'INV-2024-005',
    //       'amount': '₹9,800',
    //     },
    //     {
    //       'id': '6',
    //       'name': 'POD_2024_006.pdf',
    //       'type': 'POD',
    //       'status': 'Rejected',
    //       'uploaded_at': '2024-01-13T15:45:00Z',
    //       'size': '2.8 MB',
    //       'stockist': 'Prime Medical',
    //       'hospital': 'District Hospital',
    //       'invoice_number': 'INV-2024-006',
    //       'amount': '₹18,200',
    //     },
    //     {
    //       'id': '7',
    //       'name': 'GRN_2024_007.pdf',
    //       'type': 'GRN',
    //       'status': 'Pending',
    //       'uploaded_at': '2024-01-13T12:15:00Z',
    //       'size': '2.5 MB',
    //       'stockist': 'Wellness Store',
    //       'hospital': 'Community Hospital',
    //       'invoice_number': 'INV-2024-007',
    //       'amount': '₹14,300',
    //     },
    //     {
    //       'id': '8',
    //       'name': 'E-Invoice_2024_008.pdf',
    //       'type': 'E-INVOICE',
    //       'status': 'Approved',
    //       'uploaded_at': '2024-01-12T17:30:00Z',
    //       'size': '1.6 MB',
    //       'stockist': 'MediMart',
    //       'hospital': 'Specialty Hospital',
    //       'invoice_number': 'INV-2024-008',
    //       'amount': '₹7,200',
    //     },
    //   ];
    // });
  }

  List<Map<String, dynamic>> get _filteredDocuments {
    List<Map<String, dynamic>> filtered = _allDocuments;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((doc) {
        final name = (doc['name'] ?? '').toLowerCase();
        final stockist = (doc['stockist'] ?? '').toLowerCase();
        final hospital = (doc['hospital'] ?? '').toLowerCase();
        final invoiceNumber = (doc['invoice_number'] ?? '').toLowerCase();
        final query = _searchQuery.toLowerCase();

        return name.contains(query) ||
            stockist.contains(query) ||
            hospital.contains(query) ||
            invoiceNumber.contains(query);
      }).toList();
    }

    // Apply type/status filter
    if (_selectedFilter != 'All') {
      filtered = filtered.where((doc) {
        final type = doc['type'] ?? '';
        final status = doc['status'] ?? '';
        return type == _selectedFilter || status == _selectedFilter;
      }).toList();
    }

    // Sort by upload date (newest first)
    filtered.sort((a, b) {
      final dateA = DateTime.tryParse(a['uploaded_at'] ?? '') ?? DateTime(1970);
      final dateB = DateTime.tryParse(b['uploaded_at'] ?? '') ?? DateTime(1970);
      return dateB.compareTo(dateA);
    });

    return filtered;
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Unknown';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'POD':
        return Icons.receipt_long;
      case 'GRN':
        return Icons.inventory;
      case 'E-INVOICE':
        return Icons.qr_code;
      default:
        return Icons.description;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('All Documents'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2C3E50),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loadAllDocuments,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A0A8)),
              ),
            )
          : _errorMessage != null
              ? _buildErrorWidget()
              : Column(
                  children: [
                    _buildSearchAndFilter(),
                    Expanded(
                      child: _buildDocumentsList(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load documents',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Unknown error',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadAllDocuments,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A0A8),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          // Search bar
          TextField(
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search documents...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF00A0A8), width: 2),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 12),
          // Filter chips
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _filterOptions.length,
              itemBuilder: (context, index) {
                final filter = _filterOptions[index];
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                    },
                    selectedColor: const Color(0xFF00A0A8).withOpacity(0.2),
                    checkmarkColor: const Color(0xFF00A0A8),
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFF00A0A8) : Colors.grey.shade700,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsList() {
    final filteredDocs = _filteredDocuments;

    if (filteredDocs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty || _selectedFilter != 'All'
                  ? 'No documents found'
                  : 'No documents uploaded yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty || _selectedFilter != 'All'
                  ? 'Try adjusting your search or filter'
                  : 'Start by uploading your first document',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredDocs.length,
      itemBuilder: (context, index) {
        final doc = filteredDocs[index];
        return _buildDocumentCard(doc);
      },
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> doc) {
    final status = doc['status'] ?? 'Unknown';
    final type = doc['type'] ?? 'Unknown';
    final statusColor = _getStatusColor(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          _showDocumentDetails(doc);
        },
        borderRadius: BorderRadius.circular(12),
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
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getTypeIcon(type),
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc['name'] ?? 'Unknown Document',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              type,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      'Stockist',
                      doc['stockist_name'] ?? 'Unknown',
                      Icons.store,
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
                      'Hospital',
                      doc['hospital_name'] ?? 'Unknown',
                      Icons.local_hospital,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      'Invoice',
                      doc['invoice_number'] ?? 'N/A',
                      Icons.receipt,
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
                      'Amount',
                      doc['total_amount'] ?? 'N/A',
                      Icons.currency_rupee,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      'Uploaded',
                      _formatDate(doc['uploaded_at'] ?? ''),
                      Icons.calendar_today,
                    ),
                  ),
                  Expanded(
                    child: _buildInfoItem(
                      'Size',
                      doc['size'] ?? '0 MB',
                      Icons.storage,
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

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: Colors.grey.shade600,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDocumentDetails(Map<String, dynamic> doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _getStatusColor(doc['status'] ?? '')
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _getTypeIcon(doc['type'] ?? ''),
                              color: _getStatusColor(doc['status'] ?? ''),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doc['name'] ?? 'Unknown Document',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(doc['status'] ?? '')
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    doc['status'] ?? 'Unknown',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _getStatusColor(doc['status'] ?? ''),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildDetailSection('Document Information', [
                        _buildDetailRow('Type', doc['type'] ?? 'Unknown'),
                        _buildDetailRow('Size', doc['size'] ?? '0 MB'),
                        _buildDetailRow('Upload Date', _formatDate(doc['uploaded_at'] ?? '')),
                      ]),
                      const SizedBox(height: 20),
                      _buildDetailSection('Business Information', [
                        _buildDetailRow('Stockist', doc['stockist_name'] ?? 'Unknown'),
                        _buildDetailRow('Hospital', doc['hospital_name'] ?? 'Unknown'),
                        _buildDetailRow('Invoice Number', doc['invoice_number'] ?? 'N/A'),
                        _buildDetailRow('Amount', doc['total_amount'] ?? 'N/A'),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
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
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
