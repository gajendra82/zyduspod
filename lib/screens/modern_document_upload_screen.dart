import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zydus_vistaar/DocumentUploadScreen.dart';
import 'package:zydus_vistaar/screens/notifications_screen.dart';
import 'package:zydus_vistaar/screens/pod_upload_screen.dart';
import 'package:zydus_vistaar/screens/e_invoice_data_screen.dart';
import 'package:zydus_vistaar/screens/batches_list_screen.dart';
import 'package:zydus_vistaar/widgets/modern_ui_components.dart';
import 'package:zydus_vistaar/routes.dart';

class ModernDocumentUploadScreen extends StatefulWidget {
  const ModernDocumentUploadScreen({super.key});

  @override
  State<ModernDocumentUploadScreen> createState() =>
      _ModernDocumentUploadScreenState();
}

class _ModernDocumentUploadScreenState extends State<ModernDocumentUploadScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;

  final List<TabInfo> _tabs = [
    TabInfo(
      title: 'POD Upload',
      icon: Icons.description,
      color: const Color(0xFF00A0A8),
      page: const PODUploadPage(),
    ),
    // TabInfo(
    //   title: 'E-Invoice',
    //   icon: Icons.receipt_long,
    //   color: const Color(0xFF6EC1C7),
    //   page: const EInvoiceUploadPage(),
    // ),
    // TabInfo(
    //   title: 'GRN Upload',
    //   icon: Icons.inventory,
    //   color: const Color(0xFF4CAF50),
    //   page: const GRNUploadPage(),
    // ),
    // TabInfo(
    //   title: 'Documents',
    //   icon: Icons.folder_open,
    //   color: const Color(0xFF2196F3),
    //   page: const DocumentsPage(),
    // ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentIndex = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildModernAppBar(),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _tabs.map((tab) => tab.page).toList(),
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildModernAppBar() {
    return ModernUIComponents.buildModernAppBar(
      title: 'Document Upload',
      subtitle: 'Upload & Process Documents',
      icon: Icons.cloud_upload,
      color: const Color(0xFF00A0A8),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          child: IconButton(
            onPressed: () {
              // Add notification or settings functionality
              Navigator.pushNamed(context, AppRoutes.notifications);
            },
            icon: Stack(
              children: [
                const Icon(Icons.notifications),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return ModernUIComponents.buildTabBar(
      controller: _tabController,
      tabs: _tabs,
      currentIndex: _currentIndex,
    );
  }
}

// POD Upload Page
class PODUploadPage extends StatefulWidget {
  const PODUploadPage({super.key});

  @override
  State<PODUploadPage> createState() => _PODUploadPageState();
}

class _PODUploadPageState extends State<PODUploadPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ModernUIComponents.buildPageHeader(
            title: 'POD Upload',
            subtitle: 'Upload Proof of Delivery documents',
            icon: Icons.description,
            color: const Color(0xFF00A0A8),
          ),
          const SizedBox(height: 24),
          ModernUIComponents.buildUploadCard(
            title: 'Upload POD Documents (PDF, Images or ZIP)',
            subtitle: 'Supported formats: PDF, JPG, JPEG, PNG, ZIP',
            icon: Icons.upload_file,
            color: const Color(0xFF00A0A8),
            onTap: () async {
              // Role-aware routing: stockists must land on their dedicated
              // upload page (optional hospital/invoice selection), not the
              // KAM upload flow. Login + splash already route stockists
              // straight to StockistMainNavigation, but this card is also
              // reachable from the KAM dashboard FAB — defensive check
              // here ensures any session mix-up still lands them correctly.
              final prefs = await SharedPreferences.getInstance();
              final isStockist = prefs.getBool('isStockist') ?? false;
              final stockistId = prefs.getInt('stockistId') ?? 0;
              if (!context.mounted) return;
              final route = (isStockist && stockistId > 0)
                  ? AppRoutes.stockistUpload
                  : AppRoutes.podUpload;
              Navigator.pushNamed(context, route);
            },
          ),
          const SizedBox(height: 16),
          ModernUIComponents.buildUploadCard(
            title: 'View Uploaded Batches',
            subtitle: 'See all your uploaded batch records',
            icon: Icons.list_alt,
            color: const Color(0xFF1E88E5),
            onTap: () {
              Navigator.pushNamed(context, AppRoutes.batchesList);
            },
          ),
          const SizedBox(height: 16),
          ModernUIComponents.buildInfoCard(
            title: 'POD Requirements',
            items: [
              'Clear, readable document images',
              'Valid delivery confirmation',
              'Proper customer signatures',
              'Date and time stamps',
            ],
          ),
        ],
      ),
    );
  }
}

// E-Invoice Upload Page
class EInvoiceUploadPage extends StatefulWidget {
  const EInvoiceUploadPage({super.key});

  @override
  State<EInvoiceUploadPage> createState() => _EInvoiceUploadPageState();
}

class _EInvoiceUploadPageState extends State<EInvoiceUploadPage> {
  // Sample QR data for demonstration - in real app this would come from upload process
  final Map<String, dynamic> _sampleQrData = {
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
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ModernUIComponents.buildPageHeader(
            title: 'E-Invoice Upload',
            subtitle: 'Upload and process E-Invoice documents',
            icon: Icons.receipt_long,
            color: const Color(0xFF6EC1C7),
          ),
          const SizedBox(height: 24),
          ModernUIComponents.buildUploadCard(
            title: 'Upload E-Invoice',
            subtitle: 'Select and process E-Invoice files',
            icon: Icons.receipt,
            color: const Color(0xFF6EC1C7),
            onTap: () {
              _handleEInvoiceUpload();
            },
          ),
          const SizedBox(height: 16),
          ModernUIComponents.buildUploadCard(
            title: 'View Sample QR Data',
            subtitle: 'Preview scanned QR code information',
            icon: Icons.qr_code_scanner,
            color: const Color(0xFF9C27B0),
            onTap: () {
              _showSampleQrData();
            },
          ),
          const SizedBox(height: 16),
          ModernUIComponents.buildUploadCard(
            title: 'Open Empty E-Invoice Page',
            subtitle: 'Test the new QR scan functionality',
            icon: Icons.add_circle_outline,
            color: const Color(0xFFFF9800),
            onTap: () {
              _showEmptyEInvoicePage();
            },
          ),
          const SizedBox(height: 16),
          ModernUIComponents.buildInfoCard(
            title: 'E-Invoice Features',
            items: [
              'Automatic QR code extraction',
              'Manual QR code scanning',
              'GST validation',
              'Invoice data parsing',
              'Digital signature verification',
            ],
          ),
        ],
      ),
    );
  }

  void _handleEInvoiceUpload() {
    // Navigate to original DocumentUploadScreen with E-Invoice type
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DocumentUploadScreen()),
    ).then((result) {
      // Handle result from DocumentUploadScreen
      if (result != null && result is Map<String, dynamic>) {
        _showQrData(result);
      }
    });
  }

  void _showSampleQrData() {
    _showQrData(_sampleQrData, fileName: 'Sample_E-Invoice_5EN13986.pdf');
  }

  void _showEmptyEInvoicePage() {
    Navigator.pushNamed(
      context,
      AppRoutes.eInvoiceData,
      arguments: {
        'qrData': null, // No QR data - will show scan options
        'fileName': 'Test_E-Invoice.pdf',
        'uploadTime': DateTime.now(),
        'podId': '0',
      },
    );
  }

  void _showQrData(Map<String, dynamic> qrData, {String? fileName}) {
    Navigator.pushNamed(
      context,
      AppRoutes.eInvoiceData,
      arguments: {
        'qrData': qrData,
        'fileName': fileName ?? 'E-Invoice_${qrData['DocNo'] ?? 'Unknown'}.pdf',
        'uploadTime': DateTime.now(),
        'podId': '0',
      },
    );
  }
}

// GRN Upload Page
class GRNUploadPage extends StatefulWidget {
  const GRNUploadPage({super.key});

  @override
  State<GRNUploadPage> createState() => _GRNUploadPageState();
}

class _GRNUploadPageState extends State<GRNUploadPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ModernUIComponents.buildPageHeader(
            title: 'GRN Upload',
            subtitle: 'Upload Goods Receipt Notes',
            icon: Icons.inventory,
            color: const Color(0xFF4CAF50),
          ),
          const SizedBox(height: 24),
          ModernUIComponents.buildUploadCard(
            title: 'Upload GRN Documents',
            subtitle: 'Select and upload your GRN files',
            icon: Icons.inventory_2,
            color: const Color(0xFF4CAF50),
            onTap: () {
              // Navigate to original DocumentUploadScreen with GRN type
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DocumentUploadScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          ModernUIComponents.buildInfoCard(
            title: 'GRN Requirements',
            items: [
              'Clear document images',
              'Valid receipt confirmation',
              'Item details and quantities',
              'Supplier information',
            ],
          ),
        ],
      ),
    );
  }
}

// Documents Page
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ModernUIComponents.buildPageHeader(
            title: 'Document Management',
            subtitle: 'View and manage your uploaded documents',
            icon: Icons.folder_open,
            color: const Color(0xFF2196F3),
          ),
          const SizedBox(height: 24),
          _buildDocumentStats(),
          const SizedBox(height: 16),
          _buildRecentDocuments(),
        ],
      ),
    );
  }

  Widget _buildDocumentStats() {
    return Row(
      children: [
        Expanded(
          child: ModernUIComponents.buildStatCard(
            title: 'Total Documents',
            value: '24',
            icon: Icons.description,
            color: const Color(0xFF2196F3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ModernUIComponents.buildStatCard(
            title: 'Processed',
            value: '18',
            icon: Icons.check_circle,
            color: const Color(0xFF4CAF50),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ModernUIComponents.buildStatCard(
            title: 'Pending',
            value: '6',
            icon: Icons.pending,
            color: const Color(0xFFFF9800),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentDocuments() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Documents',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 16),
            ModernUIComponents.buildDocumentItem(
              title: 'POD_2024_001.pdf',
              subtitle: 'Uploaded 2 hours ago',
              status: 'Processed',
              statusColor: Colors.green,
            ),
            const Divider(),
            ModernUIComponents.buildDocumentItem(
              title: 'E-Invoice_2024_002.pdf',
              subtitle: 'Uploaded 5 hours ago',
              status: 'Processing',
              statusColor: Colors.orange,
            ),
            const Divider(),
            ModernUIComponents.buildDocumentItem(
              title: 'GRN_2024_003.pdf',
              subtitle: 'Uploaded 1 day ago',
              status: 'Processed',
              statusColor: Colors.green,
            ),
          ],
        ),
      ),
    );
  }
}
