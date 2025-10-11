import 'package:flutter/material.dart';
import 'package:zyduspod/DocumentUploadScreen.dart';
import 'package:zyduspod/screens/profile_screen.dart';
import 'package:zyduspod/screens/unified_dashboard_screen.dart';
import 'package:zyduspod/services/api_client.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final ApiClient _apiClient = ApiClient();

  @override
  void initState() {
    super.initState();
    // Set context for API client after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _apiClient.setContext(context);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update context whenever dependencies change
    _apiClient.setContext(context);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      const UnifiedDashboardScreen(),
      const DocumentUploadScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF00A0A8),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.upload_file),
            label: 'Upload',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

