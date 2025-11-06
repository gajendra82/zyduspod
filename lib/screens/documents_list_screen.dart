import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:zyduspod/config.dart';
import 'package:zyduspod/screens/pod_details_screen.dart';
import 'package:zyduspod/services/master_data_service.dart';

class DocumentsListScreen extends StatefulWidget {
  const DocumentsListScreen({super.key});

  @override
  State<DocumentsListScreen> createState() => _DocumentsListScreenState();
}

class _DocumentsListScreenState extends State<DocumentsListScreen> {
  List<Map<String, dynamic>> _allDocuments = [];
  List<Map<String, dynamic>> _stockistList = [];
  List<Map<String, dynamic>> _hospitalList = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalRecords = 0;
  int _perPage = 20;
  int? _nextPage;
  String? _errorMessage;
  String _selectedFilter = 'All';
  String _searchQuery = '';
  String _selectedStockistId = '';
  String _selectedHospitalId = '';
  String _selectedStockistName = '';
  String _selectedHospitalName = '';
  bool _hasApiError = false;
  DateTime? _fromDate;
  DateTime? _toDate;
  final ScrollController _scrollController = ScrollController();
  final MasterDataService _masterDataService = MasterDataService();

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
    _loadMasterDataAndDocuments();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Load master data (hospitals and stockists) and then load documents
  Future<void> _loadMasterDataAndDocuments() async {
    try {
      // Load master data in parallel
      await Future.wait([
        _loadMasterHospitals(),
        _loadMasterStockists(),
      ]);
    } catch (e) {
      print('Error loading master data: $e');
    }

    // Load documents after master data is loaded
    _loadAllDocuments();
  }

  /// Load master hospitals data
  Future<void> _loadMasterHospitals() async {
    try {
      final hospitals = await _masterDataService.getAllHospitals();
      setState(() {
        _hospitalList = hospitals;
      });
      print('Loaded ${hospitals.length} hospitals from master API');
    } catch (e) {
      print('Error loading hospitals: $e');
      setState(() {
        _hospitalList = [];
      });
    }
  }

  /// Load master stockists data
  Future<void> _loadMasterStockists() async {
    try {
      final stockists = await _masterDataService.getAllStockists();
      setState(() {
        _stockistList = stockists;
      });
      print('Loaded ${stockists.length} stockists from master API');
    } catch (e) {
      print('Error loading stockists: $e');
      setState(() {
        _stockistList = [];
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMoreData && !_isLoading) {
        _loadMoreDocuments();
      }
    }
  }

  Future<void> _loadAllDocuments({bool isRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasApiError = false;
      _currentPage = 1;
      _hasMoreData = true;
      if (isRefresh) {
        _allDocuments.clear();
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        throw Exception('No authentication token found');
      }
      
      final String type = _selectedFilter == 'All' ? '' : _selectedFilter;
      final String hospitalId = _selectedHospitalId.isEmpty ? '' : _selectedHospitalId;
      final String stockistId = _selectedStockistId.isEmpty ? '' : _selectedStockistId;
      final String startDate = _fromDate != null ? _formatDateForApi(_fromDate!) : '';
      final String endDate = _toDate != null ? _formatDateForApi(_toDate!) : '';
      
      final String url = '${API_BASE_URL}dashboard/documents/all'
          '?type=$type'
          '&limit=$_perPage'
          '&page=1'
          '&hospital_id=$hospitalId'
          '&stockist_id=$stockistId'
          '&start_date=$startDate'
          '&end_date=$endDate';
      print('Loading documents: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      print('Response: ${response.body}');
      print('Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final documents = List<Map<String, dynamic>>.from(data['data'] ?? []);
        
        // Parse pagination metadata
        final pagination = data['pagination'] as Map<String, dynamic>?;
        if (pagination != null) {
          _currentPage = pagination['current_page'] ?? 1;
          _perPage = pagination['per_page'] ?? 20;
          _totalPages = pagination['total_pages'] ?? 1;
          _totalRecords = pagination['total_records'] ?? 0;
          _nextPage = pagination['next_page'];
          _hasMoreData = _nextPage != null;
          
          print('Pagination: Page $_currentPage of $_totalPages, Total: $_totalRecords records');
        } else {
          // Fallback if no pagination data
          _hasMoreData = documents.length >= _perPage;
        }

        setState(() {
          _allDocuments = documents;
          if (documents.isEmpty) {
            _hasApiError = true;
          }
        });
      } else {
        setState(() {
          _hasApiError = true;
          _errorMessage =
              'Failed to load documents. Status: ${response.statusCode}';
        });
      }
    } catch (e) {
      print('Error: $e');
      setState(() {
        _hasApiError = true;
        _errorMessage = 'Network error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreDocuments() async {
    if (_isLoadingMore || !_hasMoreData || _nextPage == null) return;

    // Store the page number we're about to request
    final pageToLoad = _nextPage!;
    
    setState(() {
      _isLoadingMore = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final String type = _selectedFilter == 'All' ? '' : _selectedFilter;
      final String hospitalId = _selectedHospitalId.isEmpty ? '' : _selectedHospitalId;
      final String stockistId = _selectedStockistId.isEmpty ? '' : _selectedStockistId;
      final String startDate = _fromDate != null ? _formatDateForApi(_fromDate!) : '';
      final String endDate = _toDate != null ? _formatDateForApi(_toDate!) : '';

      final String url = '${API_BASE_URL}dashboard/documents/all'
          '?type=$type'
          '&limit=$_perPage'
          '&page=$pageToLoad'
          '&hospital_id=$hospitalId'
          '&stockist_id=$stockistId'
          '&start_date=$startDate'
          '&end_date=$endDate';
      print('Loading more documents (Requesting Page $pageToLoad): $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final documents = List<Map<String, dynamic>>.from(data['data'] ?? []);
        
        // Only update state if we successfully got data
        if (mounted) {
          setState(() {
            // Add documents first
            _allDocuments.addAll(documents);
            
            // Then update pagination from API response
            final pagination = data['pagination'] as Map<String, dynamic>?;
            if (pagination != null) {
              _currentPage = pagination['current_page'] ?? _currentPage;
              _perPage = pagination['per_page'] ?? _perPage;
              _totalPages = pagination['total_pages'] ?? _totalPages;
              _totalRecords = pagination['total_records'] ?? _totalRecords;
              _nextPage = pagination['next_page'];
              _hasMoreData = _nextPage != null;
              
              print('Successfully loaded page $_currentPage of $_totalPages (${documents.length} documents)');
              print('Next page: ${_nextPage ?? "None (last page)"}');
            } else {
              // Fallback if no pagination data
              _hasMoreData = documents.length >= _perPage;
            }
          });

          if (documents.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Loaded ${documents.length} more documents (Page $_currentPage of $_totalPages)'),
                duration: const Duration(seconds: 1),
                backgroundColor: const Color(0xFF00A0A8),
              ),
            );
          }
        }
      } else {
        print('Failed to load more: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load more documents'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Error loading more: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  String _formatDateForApi(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> get _filteredDocuments {
    // Most filtering is now done server-side via API parameters
    // Only apply client-side search filter if needed
    List<Map<String, dynamic>> filtered = _allDocuments;

    // Apply search filter (client-side only for real-time search)
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
    final hasActiveFilters = _selectedStockistId.isNotEmpty ||
        _selectedHospitalId.isNotEmpty ||
        _selectedFilter != 'All' ||
        _fromDate != null ||
        _toDate != null;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          if (_allDocuments.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00A0A8).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF00A0A8).withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.description, size: 16, color: Colors.grey.shade700),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_allDocuments.length} of $_totalRecords documents',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Page $_currentPage of $_totalPages',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_hasMoreData)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00A0A8).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_downward, size: 12, color: const Color(0xFF00A0A8)),
                          const SizedBox(width: 4),
                          Text(
                            'Scroll for more',
                            style: TextStyle(
                              fontSize: 11,
                              color: const Color(0xFF00A0A8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
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
              const SizedBox(width: 8),
              IconButton(
                onPressed: () async {
                  await _loadAllDocuments(isRefresh: true);
                  // Optionally, show a SnackBar or update state to indicate refresh complete
                },
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: const Color(0xFF00A0A8),
                ),
              ),
              if (hasActiveFilters) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedStockistId = '';
                      _selectedHospitalId = '';
                      _selectedStockistName = '';
                      _selectedHospitalName = '';
                      _selectedFilter = 'All';
                      _searchQuery = '';
                      _fromDate = null;
                      _toDate = null;
                    });
                    _loadAllDocuments(isRefresh: true);
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
                if (_selectedStockistId.isNotEmpty)
                  Chip(
                    label: Text('Stockist: $_selectedStockistName'),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedStockistId = '';
                        _selectedStockistName = '';
                      });
                    },
                    backgroundColor: const Color(0xFF00A0A8).withOpacity(0.1),
                    labelStyle: const TextStyle(
                      color: Color(0xFF00A0A8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (_selectedHospitalId.isNotEmpty)
                  Chip(
                    label: Text('Hospital: $_selectedHospitalName'),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedHospitalId = '';
                        _selectedHospitalName = '';
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
    String tempStockistId = _selectedStockistId;
    String tempHospitalId = _selectedHospitalId;
    String tempStockistName = _selectedStockistName;
    String tempHospitalName = _selectedHospitalName;
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
                      value: tempStockistId.isEmpty ? null : tempStockistId,
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
                      items: _stockistList.map((Map<String, dynamic> stockist) {
                        return DropdownMenuItem<String>(
                          value: stockist['id']?.toString() ?? '',
                          child: Text(
                            stockist['name'] ?? 'Unknown Stockist',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (String? value) {
                        setModalState(() {
                          tempStockistId = value ?? '';
                          if (value != null && value.isNotEmpty) {
                            final selectedStockist = _stockistList.firstWhere(
                              (s) => s['id']?.toString() == value,
                              orElse: () => {'name': 'Unknown Stockist'},
                            );
                            tempStockistName = selectedStockist['name'] ?? 'Unknown Stockist';
                          } else {
                            tempStockistName = '';
                          }
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
                      value: tempHospitalId.isEmpty ? null : tempHospitalId,
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
                      items: _hospitalList.map((Map<String, dynamic> hospital) {
                        return DropdownMenuItem<String>(
                          value: hospital['id']?.toString() ?? '',
                          child: Text(
                            hospital['name'] ?? 'Unknown Hospital',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (String? value) {
                        setModalState(() {
                          tempHospitalId = value ?? '';
                          if (value != null && value.isNotEmpty) {
                            final selectedHospital = _hospitalList.firstWhere(
                              (h) => h['id']?.toString() == value,
                              orElse: () => {'name': 'Unknown Hospital'},
                            );
                            tempHospitalName = selectedHospital['name'] ?? 'Unknown Hospital';
                          } else {
                            tempHospitalName = '';
                          }
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
                            _selectedStockistId = tempStockistId;
                            _selectedHospitalId = tempHospitalId;
                            _selectedStockistName = tempStockistName;
                            _selectedHospitalName = tempHospitalName;
                            _selectedFilter = tempFilter;
                            _fromDate = tempFromDate;
                            _toDate = tempToDate;
                          });
                          _loadAllDocuments(isRefresh: true);
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
                      _selectedStockistId.isNotEmpty ||
                      _selectedHospitalId.isNotEmpty ||
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
                      _selectedStockistId.isNotEmpty ||
                      _selectedHospitalId.isNotEmpty ||
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
        await _loadAllDocuments(isRefresh: true);
      },
      color: const Color(0xFF00A0A8),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: filteredDocs.length + (_hasMoreData ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == filteredDocs.length) {
            return _buildLoadingIndicator();
          }
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

  Widget _buildLoadingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A0A8)),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading more documents...',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
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