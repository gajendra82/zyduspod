import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:zydus_vistaar/screens/profile_screen.dart';
import 'package:zydus_vistaar/screens/stockist_pod_upload_screen.dart';

/// Bottom-nav shell for stockist logins. Mirrors [MainNavigation] (the KAM
/// shell) but only exposes the two screens stockists need: POD upload and
/// Profile (which carries the logout action).
class StockistMainNavigation extends StatefulWidget {
  const StockistMainNavigation({super.key});

  @override
  State<StockistMainNavigation> createState() => _StockistMainNavigationState();
}

class _StockistMainNavigationState extends State<StockistMainNavigation> {
  int _currentIndex = 0;

  Future<bool> _onWillPop() async {
    if (_currentIndex == 0) {
      await showDialog<bool>(
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
              onPressed: () {
                SystemNavigator.pop();
                if (Theme.of(context).platform == TargetPlatform.iOS) {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    exit(0);
                  });
                } else {
                  Navigator.of(context).pop(true);
                  SystemNavigator.pop();
                }
              },
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
      return false;
    } else {
      setState(() {
        _currentIndex = 0;
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = const [
      StockistPodUploadScreen(),
      ProfileScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onWillPop();
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
