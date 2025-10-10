import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:zyduspod/config.dart';
import 'package:zyduspod/screens/pod_details_screen.dart';

class DocumentsListScreen extends StatefulWidget {
  const DocumentsListScreen({super.key});

  @override
  State<DocumentsListScreen> createState() => _DocumentsListScreenState();
}

class _DocumentsListScreenState extends State<DocumentsListScreen> {
  List<Map<String, dynamic>> _allDocuments = [];
  List<String> _stockistList = [];
  List<String> _hospitalList = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'All';
  String _searchQuery = '';
  String _selectedStockist = '';
  String _selectedHospital = '';
  bool _hasApiError = false;
  DateTime? _fromDate;
  DateTime? _toDate;

  final List<String> _filterOptions = [
    'All',
    'POD',
    'GRN',
    'E-INVOICE',
    'Pending',
    'Verified',
    'Processed',
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
      _hasApiError = false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        throw Exception('No authentication token found');
      }
      // Example for query params: ?type=POD&limit=20&hospital_id=&stockist_id=&start_date=2025-10-08&end_date=2025-10-08
      // final String type = _selectedFilter;
      final String type = 'POD';
      final int limit = 20;
      final String hospitalId = _selectedHospital.isEmpty ? '' : _selectedHospital;
      final String stockistId = _selectedStockist.isEmpty ? '' : _selectedStockist;
      final String startDate = _fromDate != null ? _fromDate!.toString() : '';
      final String endDate = _toDate != null ? _toDate!.toString() : '';
      final String url = '${API_BASE_URL}dashboard/documents/all'
          '?type=$type'
          '&limit=$limit'
          '&hospital_id=$hospitalId'
          '&stockist_id=$stockistId'
          '&start_date=$startDate'
          '&end_date=$endDate';
      print(url);
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      print('Response: ${response.body}');
      print('Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final documents = List<Map<String, dynamic>>.from(data['data'] ?? []);

        if (documents.isEmpty) {
          setState(() {
            _hasApiError = true;
            _allDocuments = [];
            _extractStockistAndHospitalLists();
          });
        } else {
          setState(() {
            _allDocuments = documents;
            _extractStockistAndHospitalLists();
          });
        }
      } else {
        setState(() {
          _hasApiError = true;
          _errorMessage =
              'Failed to load documents. Status: ${response.statusCode}';
        });
        // Mock data for development
        // _setMockDocuments();
      }
    } catch (e) {
      print('Error: $e');
      setState(() {
        _hasApiError = true;
        _errorMessage = 'Network error: ${e.toString()}';
      });
      // Mock data for development
      // _setMockDocuments();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _extractStockistAndHospitalLists() {
    Set<String> stockists = {};
    Set<String> hospitals = {};

    for (var doc in _allDocuments) {
      if (doc['stockist_name'] != null &&
          doc['stockist_name'].toString().isNotEmpty) {
        stockists.add(doc['stockist_name'].toString());
      }
      if (doc['hospital_name'] != null &&
          doc['hospital_name'].toString().isNotEmpty) {
        hospitals.add(doc['hospital_name'].toString());
      }
    }

    _stockistList = stockists.toList()..sort();
    print('Stockists: ${_stockistList}');
    _hospitalList = hospitals.toList()..sort();
    print('Hospitals: ${_hospitalList}');
  }

  List<Map<String, dynamic>> get _filteredDocuments {
    List<Map<String, dynamic>> filtered = _allDocuments;

    // Apply date range filter
    if (_fromDate != null || _toDate != null) {
      filtered = filtered.where((doc) {
        final uploadedAtStr = doc['uploaded_at'];
        if (uploadedAtStr == null) return false;
        
        final uploadedAt = DateTime.tryParse(uploadedAtStr);
        if (uploadedAt == null) return false;

        // Normalize dates to start and end of day
        if (_fromDate != null) {
          final fromDateNormalized = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
          if (uploadedAt.isBefore(fromDateNormalized)) return false;
        }

        if (_toDate != null) {
          final toDateNormalized = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);
          if (uploadedAt.isAfter(toDateNormalized)) return false;
        }

        return true;
      }).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered =
          filtered.where((doc) {
            final name = (doc['name'] ?? '').toLowerCase();
            final stockist = (doc['stockist_name'] ?? '').toLowerCase();
            final hospital = (doc['hospital_name'] ?? '').toLowerCase();
            final invoiceNumber = (doc['invoice_number'] ?? '').toLowerCase();
            final query = _searchQuery.toLowerCase();

            return name.contains(query) ||
                stockist.contains(query) ||
                hospital.contains(query) ||
                invoiceNumber.contains(query);
          }).toList();
    }

    // Apply stockist filter
    if (_selectedStockist.isNotEmpty) {
      filtered =
          filtered.where((doc) {
            final stockist = doc['stockist_name'] ?? '';
            return stockist == _selectedStockist;
          }).toList();
    }

    // Apply hospital filter
    if (_selectedHospital.isNotEmpty) {
      filtered =
          filtered.where((doc) {
            final hospital = doc['hospital_name'] ?? '';
            return hospital == _selectedHospital;
          }).toList();
    }

    // Apply type/status filter
    if (_selectedFilter != 'All') {
      filtered =
          filtered.where((doc) {
            final type = doc['type'] ?? '';
            final status = doc['status'] ?? '';
            return type == _selectedFilter || status.toLowerCase() == _selectedFilter.toLowerCase();
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
      case 'verified':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'processed':
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
      // appBar: AppBar(
      //   // title: const Text('All Documents'),
      //   backgroundColor: Colors.white,
      //   foregroundColor: const Color(0xFF2C3E50),
      //   elevation: 0,
      //   centerTitle: true,
      //   actions: [
      //     if (_hasApiError || _errorMessage != null || _allDocuments.isEmpty)
      //       IconButton(
      //         onPressed: _loadAllDocuments,
      //         icon: const Icon(Icons.refresh),
      //         tooltip: 'Refresh',
      //       ),
      //   ],
      // ),
      body:
          _isLoading
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
                  Expanded(child: _buildDocumentsList()),
                ],
              ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
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
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
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
    final hasActiveFilters = _selectedStockist.isNotEmpty ||
        _selectedHospital.isNotEmpty ||
        _selectedFilter != 'All' ||
        _fromDate != null ||
        _toDate != null;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showFilterBottomSheet,
                  icon: const Icon(Icons.filter_list),
                  label: const Text('Show All Filters'),
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
              if (hasActiveFilters) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedStockist = '';
                      _selectedHospital = '';
                      _selectedFilter = 'All';
                      _searchQuery = '';
                      _fromDate = null;
                      _toDate = null;
                    });
                  },
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'Clear All Filters',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ],
          ),
          if (hasActiveFilters) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_selectedStockist.isNotEmpty)
                  Chip(
                    label: Text('Stockist: $_selectedStockist'),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedStockist = '';
                      });
                    },
                    backgroundColor: const Color(0xFF00A0A8).withOpacity(0.1),
                    labelStyle: const TextStyle(
                      color: Color(0xFF00A0A8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (_selectedHospital.isNotEmpty)
                  Chip(
                    label: Text('Hospital: $_selectedHospital'),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedHospital = '';
                      });
                    },
                    backgroundColor: const Color(0xFF00A0A8).withOpacity(0.1),
                    labelStyle: const TextStyle(
                      color: Color(0xFF00A0A8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (_selectedFilter != 'All')
                  Chip(
                    label: Text('Type: $_selectedFilter'),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedFilter = 'All';
                      });
                    },
                    backgroundColor: const Color(0xFF00A0A8).withOpacity(0.1),
                    labelStyle: const TextStyle(
                      color: Color(0xFF00A0A8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (_fromDate != null)
                  Chip(
                    label: Text('From: ${_fromDate!.day}/${_fromDate!.month}/${_fromDate!.year}'),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _fromDate = null;
                      });
                    },
                    backgroundColor: const Color(0xFF00A0A8).withOpacity(0.1),
                    labelStyle: const TextStyle(
                      color: Color(0xFF00A0A8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (_toDate != null)
                  Chip(
                    label: Text('To: ${_toDate!.day}/${_toDate!.month}/${_toDate!.year}'),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _toDate = null;
                      });
                    },
                    backgroundColor: const Color(0xFF00A0A8).withOpacity(0.1),
                    labelStyle: const TextStyle(
                      color: Color(0xFF00A0A8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showFilterBottomSheet() {
    // Temporary state variables for the bottom sheet
    String tempStockist = _selectedStockist;
    String tempHospital = _selectedHospital;
    String tempFilter = _selectedFilter;
    DateTime? tempFromDate = _fromDate;
    DateTime? tempToDate = _toDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filter Documents',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00A0A8),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Date selectors
                    const Text(
                      'Date Range',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: tempFromDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: Color(0xFF00A0A8),
                                        onPrimary: Colors.white,
                                        onSurface: Colors.black,
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (pickedDate != null) {
                                setModalState(() {
                                  tempFromDate = pickedDate;
                                  if (tempToDate != null && tempFromDate!.isAfter(tempToDate!)) {
                                    tempToDate = tempFromDate;
                                  }
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.grey.shade50,
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today, size: 20, color: Color(0xFF00A0A8)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'From Date',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        Text(
                                          tempFromDate != null
                                              ? '${tempFromDate!.day}/${tempFromDate!.month}/${tempFromDate!.year}'
                                              : 'Select date',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: tempFromDate != null ? Colors.black : Colors.grey.shade500,
                                            fontWeight: tempFromDate != null ? FontWeight.w500 : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: tempToDate ?? DateTime.now(),
                                firstDate: tempFromDate ?? DateTime(2020),
                                lastDate: DateTime.now(),
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: Color(0xFF00A0A8),
                                        onPrimary: Colors.white,
                                        onSurface: Colors.black,
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (pickedDate != null) {
                                setModalState(() {
                                  tempToDate = pickedDate;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.grey.shade50,
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today, size: 20, color: Color(0xFF00A0A8)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'To Date',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        Text(
                                          tempToDate != null
                                              ? '${tempToDate!.day}/${tempToDate!.month}/${tempToDate!.year}'
                                              : 'Select date',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: tempToDate != null ? Colors.black : Colors.grey.shade500,
                                            fontWeight: tempToDate != null ? FontWeight.w500 : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Stockist dropdown
                    const Text(
                      'Stockist',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: tempStockist.isEmpty ? null : tempStockist,
                      decoration: InputDecoration(
                        hintText: 'Select Stockist',
                        prefixIcon: const Icon(Icons.store),
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
                          borderSide: const BorderSide(
                            color: Color(0xFF00A0A8),
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      isExpanded: true,
                      items: _stockistList.map((String stockist) {
                        return DropdownMenuItem<String>(
                          value: stockist,
                          child: Text(
                            stockist,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (String? value) {
                        setModalState(() {
                          tempStockist = value ?? '';
                        });
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Hospital dropdown
                    const Text(
                      'Hospital',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: tempHospital.isEmpty ? null : tempHospital,
                      decoration: InputDecoration(
                        hintText: 'Select Hospital',
                        prefixIcon: const Icon(Icons.local_hospital),
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
                          borderSide: const BorderSide(
                            color: Color(0xFF00A0A8),
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      isExpanded: true,
                      items: _hospitalList.map((String hospital) {
                        return DropdownMenuItem<String>(
                          value: hospital,
                          child: Text(
                            hospital,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (String? value) {
                        setModalState(() {
                          tempHospital = value ?? '';
                        });
                      },
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Filter chips
                    const Text(
                      'Document Type / Status',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _filterOptions.map((filter) {
                        final isSelected = tempFilter == filter;
                        return FilterChip(
                          label: Text(filter),
                          selected: isSelected,
                          onSelected: (selected) {
                            setModalState(() {
                              tempFilter = filter;
                            });
                          },
                          selectedColor: const Color(0xFF00A0A8).withOpacity(0.2),
                          checkmarkColor: const Color(0xFF00A0A8),
                          labelStyle: TextStyle(
                            color: isSelected ? const Color(0xFF00A0A8) : Colors.grey.shade700,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Apply Filter Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedStockist = tempStockist;
                            _selectedHospital = tempHospital;
                            _selectedFilter = tempFilter;
                            _fromDate = tempFromDate;
                            _toDate = tempToDate;
                          });
                          _loadAllDocuments();
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00A0A8),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Apply Filters',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
              _searchQuery.isNotEmpty ||
                      _selectedFilter != 'All' ||
                      _selectedStockist.isNotEmpty ||
                      _selectedHospital.isNotEmpty ||
                      _fromDate != null ||
                      _toDate != null
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
              _searchQuery.isNotEmpty ||
                      _selectedFilter != 'All' ||
                      _selectedStockist.isNotEmpty ||
                      _selectedHospital.isNotEmpty ||
                      _fromDate != null ||
                      _toDate != null
                  ? 'Try adjusting your search or filter'
                  : 'Start by uploading your first document',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            if (_hasApiError || _errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ElevatedButton.icon(
                  onPressed: _loadAllDocuments,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A0A8),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadAllDocuments();
      },
      color: const Color(0xFF00A0A8),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredDocs.length,
        itemBuilder: (context, index) {
          final doc = filteredDocs[index];
          return _buildDocumentCard(doc);
        },
      ),
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> doc) {
    final status = doc['status'] ?? 'Unknown';
    final type = doc['type'] ?? 'Unknown';
    final statusColor = _getStatusColor(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        Icon(icon, size: 14, color: Colors.grey.shade600),
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
    // Extract document ID and type
    final docIdRaw = doc['id'];
    final docType = doc['type'] ?? 'POD';
    print(docIdRaw);
    // Convert docId to integer, handling both string and int types
    int? docId;
    if (docIdRaw != null) {
      if (docIdRaw is int) {
        docId = docIdRaw;
      } else if (docIdRaw is String) {
        docId = int.tryParse(docIdRaw);
      }
    }
    
    if (docId != null) {
      // Navigate to POD details screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PodDetailsScreen(
            podId: docId!,
            documentType: docType,
          ),
        ),
      );
    } else {
      // Show error if no valid ID found
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid document ID'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

}
