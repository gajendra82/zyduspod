import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zyduspod/Bloc/sales_bloc.dart';
import 'package:zyduspod/Bloc/sales_event.dart';
import 'package:zyduspod/Bloc/sales_state.dart';
import 'package:zyduspod/Models/sales_data.dart';

class HospitalSalesScreen extends StatefulWidget {
  const HospitalSalesScreen({super.key});

  @override
  State<HospitalSalesScreen> createState() => _HospitalSalesScreenState();
}

class _HospitalSalesScreenState extends State<HospitalSalesScreen> {
  String _selectedFilter = 'All';
  final List<String> _filterOptions = ['All', 'High Volume', 'Low Volume', 'Recent'];
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _initializeDefaultDates();
    _loadDataWithDefaultDates();
  }

  void _initializeDefaultDates() {
    final now = DateTime.now();
    
    // Previous month start date
    final previousMonth = DateTime(now.year, now.month - 1, 1);
    _dateFrom = previousMonth;
    
    // Current month end date
    final currentMonthEnd = DateTime(now.year, now.month + 1, 0);
    _dateTo = currentMonthEnd;
    
    print('Default dates set: From ${_formatDateForDisplay(_dateFrom!)} to ${_formatDateForDisplay(_dateTo!)}');
  }

  void _loadDataWithDefaultDates() {
    if (_dateFrom != null && _dateTo != null) {
      final dateFromStr = _formatDateForApi(_dateFrom!);
      final dateToStr = _formatDateForApi(_dateTo!);
      
      context.read<SalesBloc>().add(
        HospitalSalesLoadRequested(
          dateFrom: dateFromStr,
          dateTo: dateToStr,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      // appBar: AppBar(
      //   backgroundColor: Colors.white,
      //   foregroundColor: const Color(0xFF2C3E50),
      //   elevation: 0,
      // ),
      body: BlocBuilder<SalesBloc, SalesState>(
        builder: (context, state) {
          if (state is SalesLoading) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A0A8)),
              ),
            );
          }

          if (state is SalesError) {
            return _buildErrorWidget(context, state.message);
          }

          if (state is SalesLoaded) {
            return _buildLoadedWidget(context, state);
          }

          return const Center(
            child: Text('No data available'),
          );
        },
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, String message) {
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
            'Failed to load hospital sales data',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // Retry with current date filters
              final dateFromStr = _dateFrom != null ? _formatDateForApi(_dateFrom!) : null;
              final dateToStr = _dateTo != null ? _formatDateForApi(_dateTo!) : null;
              context.read<SalesBloc>().add(
                HospitalSalesLoadRequested(
                  dateFrom: dateFromStr,
                  dateTo: dateToStr,
                ),
              );
            },
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

  Widget _buildLoadedWidget(BuildContext context, SalesLoaded state) {
    final filteredSummaries = _filterHospitalSummaries(state.hospitalSummaries);
    
    return Column(
      children: [ 
        const SizedBox(height: 8),
        _buildMonthPeriodIndicator(),
        Expanded(
          child: filteredSummaries.isEmpty
            ? RefreshIndicator(
                onRefresh: () async {
                  // Refresh with current date filters
                  final dateFromStr = _dateFrom != null ? _formatDateForApi(_dateFrom!) : null;
                  final dateToStr = _dateTo != null ? _formatDateForApi(_dateTo!) : null;
                  context.read<SalesBloc>().add(
                    HospitalSalesLoadRequested(
                      dateFrom: dateFromStr,
                      dateTo: dateToStr,
                    ),
                  );
                },
                color: const Color(0xFF00A0A8),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No data found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try adjusting your filters',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  // Refresh with current date filters
                  final dateFromStr = _dateFrom != null ? _formatDateForApi(_dateFrom!) : null;
                  final dateToStr = _dateTo != null ? _formatDateForApi(_dateTo!) : null;
                  context.read<SalesBloc>().add(
                    HospitalSalesLoadRequested(
                      dateFrom: dateFromStr,
                      dateTo: dateToStr,
                    ),
                  );
                },
                color: const Color(0xFF00A0A8),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredSummaries.length,
                  itemBuilder: (context, index) {
                    final summary = filteredSummaries[index];
                    
                    return _buildHospitalCard(context, summary);
                  },
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildFilterChipsForBottomSheet(StateSetter setModalState) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _filterOptions.map((filter) {
        final isSelected = _selectedFilter == filter;
        return FilterChip(
          label: Text(filter),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              _selectedFilter = filter;
            });
            setModalState(() {});
          },
          selectedColor: const Color(0xFF00A0A8).withOpacity(0.2),
          checkmarkColor: const Color(0xFF00A0A8),
          labelStyle: TextStyle(
            color: isSelected ? const Color(0xFF00A0A8) : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMonthPeriodIndicator() {
    if (_dateFrom == null && _dateTo == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, top: 0, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00A0A8).withOpacity(0.1),
            const Color(0xFF6EC1C7).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00A0A8).withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00A0A8).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.calendar_month,
              color: Color(0xFF00A0A8),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getFullDateRangeText(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF2C3E50),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_selectedFilter != 'All')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Filter: $_selectedFilter',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Stack(
            children: [
              IconButton(
                onPressed: () {
                  _showFilterBottomSheet(context);
                },
                icon: const Icon(
                  Icons.filter_list,
                  color: Color(0xFF00A0A8),
                  size: 20,
                ),
                tooltip: 'Filter & Date Range',
              ),
              if (_selectedFilter != 'All')
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00A0A8),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: () {
              // Refresh with current date filters
              final dateFromStr = _dateFrom != null ? _formatDateForApi(_dateFrom!) : null;
              final dateToStr = _dateTo != null ? _formatDateForApi(_dateTo!) : null;
              context.read<SalesBloc>().add(
                HospitalSalesLoadRequested(
                  dateFrom: dateFromStr,
                  dateTo: dateToStr,
                ),
              );
            },
            icon: const Icon(
              Icons.refresh,
              color: Color(0xFF00A0A8),
              size: 20,
            ),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  String _getFullDateRangeText() {
    if (_dateFrom == null || _dateTo == null) {
      return 'All Time';
    }

    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final fromDay = _dateFrom!.day;
    final fromMonth = monthNames[_dateFrom!.month - 1];
    final fromYear = _dateFrom!.year;
    
    final toDay = _dateTo!.day;
    final toMonth = monthNames[_dateTo!.month - 1];
    final toYear = _dateTo!.year;

    // Same year
    if (_dateFrom!.year == _dateTo!.year) {
      // Same month
      if (_dateFrom!.month == _dateTo!.month) {
        return '$fromDay - $toDay $fromMonth $fromYear';
      }
      return '$fromDay $fromMonth - $toDay $toMonth $fromYear';
    }

    // Different years
    return '$fromDay $fromMonth $fromYear - $toDay $toMonth $toYear';
  }

  void _showFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00A0A8).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.filter_list,
                              color: Color(0xFF00A0A8),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Filter & Date Range',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2C3E50),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Volume Filter Section
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Filter by Volume',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2C3E50),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildFilterChipsForBottomSheet(setModalState),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Divider(color: Colors.grey.shade300),
                      const SizedBox(height: 24),
                      // Date filters
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Date Range',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2C3E50),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Default: Previous month to current month end',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDateButton(
                              label: 'From Date',
                              date: _dateFrom,
                              onTap: () async {
                                await _selectDate(context, true);
                                setModalState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildDateButton(
                              label: 'To Date',
                              date: _dateTo,
                              onTap: () async {
                                await _selectDate(context, false);
                                setModalState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      if (_dateFrom != null || _dateTo != null) ...[
                        const SizedBox(height: 12),
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
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Color(0xFF00A0A8),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Filter applied: ${_dateFrom != null ? _formatDateForDisplay(_dateFrom!) : 'Any'} to ${_dateTo != null ? _formatDateForDisplay(_dateTo!) : 'Any'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF00A0A8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _clearDateFilter();
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.restart_alt, size: 18),
                              label: const Text('Reset Default'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey.shade700,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                _applyDateFilter();
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Apply Filter'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00A0A8),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDateButton({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade50,
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 16,
              color: date != null ? const Color(0xFF00A0A8) : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    date != null ? _formatDateForDisplay(date) : 'Select',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: date != null ? const Color(0xFF2C3E50) : Colors.grey.shade500,
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

  Future<void> _selectDate(BuildContext context, bool isFromDate) async {
    final initialDate = isFromDate 
        ? (_dateFrom ?? DateTime.now()) 
        : (_dateTo ?? DateTime.now());
    
    // For "From Date", allow selection from 2020
    // For "To Date", ensure it cannot be before "From Date"
    final firstDate = isFromDate 
        ? DateTime(2020)
        : (_dateFrom ?? DateTime(2020));
    
    final lastDate = DateTime.now();

    // Ensure initialDate is within the valid range
    final validInitialDate = initialDate.isBefore(firstDate) 
        ? firstDate 
        : (initialDate.isAfter(lastDate) ? lastDate : initialDate);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: validInitialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF00A0A8),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF2C3E50),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      setState(() {
        if (isFromDate) {
          _dateFrom = pickedDate;
          // If the new "From Date" is after the current "To Date", adjust "To Date"
          if (_dateTo != null && pickedDate.isAfter(_dateTo!)) {
            _dateTo = pickedDate;
          }
        } else {
          _dateTo = pickedDate;
        }
      });
    }
  }

  void _applyDateFilter() {
    String? dateFromStr;
    String? dateToStr;

    if (_dateFrom != null) {
      dateFromStr = _formatDateForApi(_dateFrom!);
    }
    if (_dateTo != null) {
      dateToStr = _formatDateForApi(_dateTo!);
    }

    context.read<SalesBloc>().add(
      HospitalSalesLoadRequested(
        dateFrom: dateFromStr,
        dateTo: dateToStr,
      ),
    );
  }

  void _clearDateFilter() {
    // Reset to default dates instead of clearing completely
    _initializeDefaultDates();
    setState(() {});
    _loadDataWithDefaultDates();
  }

  String _formatDateForDisplay(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateForApi(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildHospitalCard(BuildContext context, HospitalSalesSummary summary) {
    // Calculate performance metrics
    final performanceScore = _calculatePerformanceScore(summary);
    final growthRate = _calculateGrowthRate(summary);
    final isHighPerformer = performanceScore >= 80;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isHighPerformer 
            ? [const Color(0xFF00A0A8).withOpacity(0.1), const Color(0xFF6EC1C7).withOpacity(0.05)]
            : [Colors.white, Colors.grey.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isHighPerformer 
              ? const Color(0xFF00A0A8).withOpacity(0.2)
              : Colors.black.withOpacity(0.08),
            blurRadius: isHighPerformer ? 20 : 10,
            offset: const Offset(0, 8),
          ),
        ],
        border: isHighPerformer 
          ? Border.all(color: const Color(0xFF00A0A8).withOpacity(0.3), width: 1.5)
          : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _showHospitalDetails(context, summary);
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with hospital info and performance badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF00A0A8),
                            const Color(0xFF6EC1C7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00A0A8).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_hospital,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  summary.hospitalName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2C3E50),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isHighPerformer)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star, color: Colors.green, size: 12),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Top Performer',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00A0A8).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${summary.totalTransactions} transactions',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF00A0A8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${performanceScore}% Performance',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Main stats with enhanced design
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildEnhancedStatItem(
                              'Total Sales',
                              '₹${_formatAmount(summary.totalAmount)}',
                              Icons.currency_rupee,
                              Colors.green,
                              isHighPerformer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEnhancedStatItem(
                              'Avg. Value',
                              '₹${_formatAmount(summary.averageTransactionValue)}',
                              Icons.trending_up,
                              Colors.blue,
                              isHighPerformer,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildEnhancedStatItem(
                              'Growth Rate',
                              '${growthRate.toStringAsFixed(1)}%',
                              Icons.show_chart,
                              growthRate >= 0 ? Colors.green : Colors.red,
                              isHighPerformer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEnhancedStatItem(
                              'Last Sale',
                              _formatDate(summary.lastTransactionDate),
                              Icons.calendar_today,
                              Colors.purple,
                              isHighPerformer,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // POD vs Sales comparison with enhanced design
                _buildPodVsSalesComparison(summary),
                const SizedBox(height: 16),
                
                // Top product with enhanced design
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.inventory,
                          color: Colors.orange,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Top Product',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              summary.topProduct,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
    );
  }

  // Helper method to safely parse double values
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  Widget _buildEnhancedStatItem(String label, String value, IconData icon, Color color, bool isHighPerformer) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.1),
            color.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  int _calculatePerformanceScore(HospitalSalesSummary summary) {
    // Use API performance score if available, otherwise calculate locally
    if (summary.performanceScore != null) {
      return summary.performanceScore!;
    }
    
    // Fallback calculation based on multiple factors
    int score = 0;
    
    // Sales volume factor (40% weight)
    if (summary.totalAmount > 500000) {
      score += 40;
    } else if (summary.totalAmount > 300000) {
      score += 30;
    } else if (summary.totalAmount > 100000) {
      score += 20;
    } else {
      score += 10;
    }
    
    // Transaction frequency factor (30% weight)
    if (summary.totalTransactions > 200) {
      score += 30;
    } else if (summary.totalTransactions > 100) {
      score += 20;
    } else if (summary.totalTransactions > 50) {
      score += 15;
    } else {
      score += 10;
    }
    
    // Average transaction value factor (20% weight)
    if (summary.averageTransactionValue > 3000) {
      score += 20;
    } else if (summary.averageTransactionValue > 2000) {
      score += 15;
    } else if (summary.averageTransactionValue > 1000) {
      score += 10;
    } else {
      score += 5;
    }
    
    // Recency factor (10% weight)
    final lastDate = DateTime.tryParse(summary.lastTransactionDate);
    if (lastDate != null) {
      final daysSince = DateTime.now().difference(lastDate).inDays;
      if (daysSince <= 7) {
        score += 10;
      } else if (daysSince <= 30) {
        score += 7;
      } else if (daysSince <= 90) {
        score += 5;
      } else {
        score += 2;
      }
    }
    
    return score.clamp(0, 100);
  }

  double _calculateGrowthRate(HospitalSalesSummary summary) {
    // Use API growth rate if available, otherwise calculate locally
    if (summary.growthRate != null) {
      return summary.growthRate!;
    }
    
    // Fallback calculation - in real app, this would compare with previous period
    final random = DateTime.now().millisecondsSinceEpoch % 100;
    return (random - 50) * 0.5; // Returns growth rate between -25% and +25%
  }

  Widget _buildPodVsSalesComparison(HospitalSalesSummary summary) {
    // Use API POD vs Sales data if available, otherwise calculate locally
    double totalSystemSales;
    double podSales;
    double podPercentage;
    double systemSales;
    
    if (summary.podVsSalesAnalysis != null) {
      totalSystemSales = _parseDouble(summary.podVsSalesAnalysis!['total_system_sales']);
      podSales = _parseDouble(summary.podVsSalesAnalysis!['pod_sales']);
      podPercentage = _parseDouble(summary.podVsSalesAnalysis!['pod_coverage_percentage']);
      systemSales = _parseDouble(summary.podVsSalesAnalysis!['system_sales']);
    } else {
      // Fallback calculation
      totalSystemSales = summary.totalAmount * 2; // Example: System has 2x the POD sales
      podSales = summary.totalAmount;
      podPercentage = (podSales / totalSystemSales) * 100;
      systemSales = totalSystemSales - podSales;
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00A0A8).withOpacity(0.1),
            const Color(0xFF6EC1C7).withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00A0A8).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A0A8).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.compare_arrows,
                  color: Color(0xFF00A0A8),
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'POD vs System Sales',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildComparisonItem(
                  'POD Sales',
                  '₹${_formatAmount(podSales)}',
                  podPercentage,
                  Colors.green,
                  Icons.receipt_long,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildComparisonItem(
                  'System Sales',
                  '₹${_formatAmount(systemSales)}',
                  100 - podPercentage,
                  Colors.orange,
                  Icons.analytics,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: podPercentage < 50 ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  podPercentage < 50 ? Icons.warning : Icons.check_circle,
                  size: 12,
                  color: podPercentage < 50 ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 4),
                Text(
                  'POD Coverage: ${podPercentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: podPercentage < 50 ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonItem(String label, String value, double percentage, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 12),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${percentage.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 9,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  void _showHospitalDetails(BuildContext context, HospitalSalesSummary summary) {
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
                              color: const Color(0xFF00A0A8).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.local_hospital,
                              color: Color(0xFF00A0A8),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  summary.hospitalName,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Hospital ID: ${summary.hospitalId}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildDetailSection('Sales Summary', [
                        _buildDetailRow('Total Transactions', summary.totalTransactions.toString()),
                        _buildDetailRow('Total Sales Amount', '₹${_formatAmount(summary.totalAmount)}'),
                        _buildDetailRow('Average Transaction Value', '₹${_formatAmount(summary.averageTransactionValue)}'),
                        _buildDetailRow('Top Product', summary.topProduct),
                        _buildDetailRow('Last Transaction', _formatDate(summary.lastTransactionDate)),
                      ]),
                      const SizedBox(height: 20),
                      _buildPodVsSalesDetailSection(summary),
                      const SizedBox(height: 20),
                      _buildDetailSection('Recent Transactions', [
                        ...summary.recentTransactions.map((transaction) => 
                          _buildTransactionItem(transaction)
                        ).toList(),
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

  Widget _buildPodVsSalesDetailSection(HospitalSalesSummary summary) {
    // Use API POD vs Sales data if available, otherwise calculate locally
    double totalSystemSales;
    double podSales;
    double podPercentage;
    double systemSales;
    
    if (summary.podVsSalesAnalysis != null) {
      totalSystemSales = _parseDouble(summary.podVsSalesAnalysis!['total_system_sales']);
      podSales = _parseDouble(summary.podVsSalesAnalysis!['pod_sales']);
      podPercentage = _parseDouble(summary.podVsSalesAnalysis!['pod_coverage_percentage']);
      systemSales = _parseDouble(summary.podVsSalesAnalysis!['system_sales']);
    } else {
      // Fallback calculation
      totalSystemSales = summary.totalAmount * 2; // Example: System has 2x the POD sales
      podSales = summary.totalAmount;
      podPercentage = (podSales / totalSystemSales) * 100;
      systemSales = totalSystemSales - podSales;
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'POD vs System Sales Analysis',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF00A0A8).withOpacity(0.1),
                const Color(0xFF6EC1C7).withOpacity(0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF00A0A8).withOpacity(0.3),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildDetailComparisonItem(
                      'POD Sales (App)',
                      '₹${_formatAmount(podSales)}',
                      podPercentage,
                      Colors.green,
                      Icons.receipt_long,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDetailComparisonItem(
                      'System Sales (Total)',
                      '₹${_formatAmount(systemSales)}',
                      100 - podPercentage,
                      Colors.orange,
                      Icons.analytics,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: podPercentage < 50 ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      podPercentage < 50 ? Icons.warning : Icons.check_circle,
                      color: podPercentage < 50 ? Colors.red : Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'POD Coverage Analysis',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: podPercentage < 50 ? Colors.red : Colors.green,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            podPercentage < 50 
                                ? 'Low POD coverage detected. Only ${podPercentage.toStringAsFixed(1)}% of total sales are captured through POD uploads.'
                                : 'Good POD coverage. ${podPercentage.toStringAsFixed(1)}% of total sales are captured through POD uploads.',
                            style: TextStyle(
                              fontSize: 12,
                              color: podPercentage < 50 ? Colors.red.shade700 : Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildDetailRow('Total System Sales', '₹${_formatAmount(totalSystemSales)}'),
              _buildDetailRow('POD Sales (App)', '₹${_formatAmount(podSales)}'),
              _buildDetailRow('System Sales (Other)', '₹${_formatAmount(systemSales)}'),
              _buildDetailRow('POD Coverage', '${podPercentage.toStringAsFixed(1)}%'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailComparisonItem(String label, String value, double percentage, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${percentage.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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

  Widget _buildTransactionItem(SalesData transaction) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getStatusColor(transaction.status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              _getTypeIcon(transaction.documentType),
              color: _getStatusColor(transaction.status),
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.productName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${transaction.quantity} units × ₹${transaction.unitPrice}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${_formatAmount(transaction.totalAmount)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00A0A8),
                ),
              ),
              Text(
                transaction.date,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<HospitalSalesSummary> _filterHospitalSummaries(List<HospitalSalesSummary> summaries) {
    switch (_selectedFilter) {
      case 'High Volume':
        return summaries.where((s) => s.totalAmount > 100000).toList();
      case 'Low Volume':
        return summaries.where((s) => s.totalAmount <= 100000).toList();
      case 'Recent':
        return summaries.where((s) {
          final lastDate = DateTime.tryParse(s.lastTransactionDate);
          if (lastDate == null) return false;
          final daysSince = DateTime.now().difference(lastDate).inDays;
          return daysSince <= 7;
        }).toList();
      default:
        return summaries;
    }
  }

  String _formatAmount(double amount) {
    // if (amount >= 100000) {
    //   return '${(amount / 100000).toStringAsFixed(1)}L';
    // } else if (amount >= 1000) {
    //   return '${(amount / 1000).toStringAsFixed(1)}K';
    // } else {
    //   return amount.toStringAsFixed(0);
    // }
    return amount.toStringAsFixed(2);
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
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
}
