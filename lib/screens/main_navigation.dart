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

  Future<bool> _onWillPop() async {
    // Only show exit dialog when on the first tab (Dashboard)
    if (_currentIndex == 0) {
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.exit_to_app,
                color: const Color(0xFF00A0A8),
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'Exit App',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
            ],
          ),
          content: const Text(
            'Do you want to exit the app?',
            style: TextStyle(
              color: Color(0xFF7F8C8D),
              fontSize: 16,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF7F8C8D),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A0A8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'Exit',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      );
      return shouldExit ?? false;
    } else {
      // Navigate back to Dashboard tab instead of exiting
      setState(() {
        _currentIndex = 0;
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      const UnifiedDashboardScreen(),
      const DocumentUploadScreen(),
      const ProfileScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
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
      ),
    );
  }
}

