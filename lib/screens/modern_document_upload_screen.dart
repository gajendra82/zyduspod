import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zyduspod/DocumentUploadScreen.dart';
import 'package:zyduspod/screens/pod_upload_screen.dart';
import 'package:zyduspod/widgets/modern_ui_components.dart';

class ModernDocumentUploadScreen extends StatefulWidget {
  const ModernDocumentUploadScreen({super.key});

  @override
  State<ModernDocumentUploadScreen> createState() => _ModernDocumentUploadScreenState();
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
    TabInfo(
      title: 'E-Invoice',
      icon: Icons.receipt_long,
      color: const Color(0xFF6EC1C7),
      page: const EInvoiceUploadPage(),
    ),
    TabInfo(
      title: 'GRN Upload',
      icon: Icons.inventory,
      color: const Color(0xFF4CAF50),
      page: const GRNUploadPage(),
    ),
    TabInfo(
      title: 'Documents',
      icon: Icons.folder_open,
      color: const Color(0xFF2196F3),
      page: const DocumentsPage(),
    ),
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
            },
            icon: Stack(
              children: [
                const Icon(Icons.notifications_outlined),
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
            title: 'Upload POD Documents',
            subtitle: 'Select and upload your POD files',
            icon: Icons.upload_file,
            color: const Color(0xFF00A0A8),
            onTap: () {
              // Navigate to dedicated POD upload screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PODUploadScreen(),
                ),
              );
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
              // Navigate to original DocumentUploadScreen with E-Invoice type
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
            title: 'E-Invoice Features',
            items: [
              'Automatic QR code extraction',
              'GST validation',
              'Invoice data parsing',
              'Digital signature verification',
            ],
          ),
        ],
      ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
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
