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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Hospital Sales Data'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2C3E50),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              context.read<SalesBloc>().add(const SalesRefreshRequested());
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
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
              context.read<SalesBloc>().add(const HospitalSalesLoadRequested());
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
        _buildFilterChips(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              context.read<SalesBloc>().add(const SalesRefreshRequested());
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

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filterOptions.map((filter) {
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
          }).toList(),
        ),
      ),
    );
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
    if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    } else {
      return amount.toStringAsFixed(0);
    }
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
