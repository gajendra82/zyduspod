import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zyduspod/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _userEmail;
  String? _userName;
  String? _userToken;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userEmail = prefs.getString('userEmail') ?? 'user@example.com';
        _userName = prefs.getString('userName') ?? 'User Name';
        _userToken = prefs.getString('authToken') ?? '';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2C3E50),
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Section
                  _buildHeader(context),
                  const SizedBox(height: 24),
                  
                  // User Info Card
                  _buildUserInfoCard(context),
                  const SizedBox(height: 24),
                  
                  // Account Actions
                  _buildAccountActions(context),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00A0A8),
            const Color(0xFF6EC1C7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00A0A8).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your account',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserInfoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Profile Avatar
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00A0A8),
                  const Color(0xFF6EC1C7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          
          // User Info
          Text(
            _userName ?? 'User Name',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _userEmail ?? 'user@example.com',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF7F8C8D),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Active',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4CAF50),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Token Info (for debugging)
          if (_userToken != null && _userToken!.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.security_rounded,
                  color: Color(0xFF7F8C8D),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Authentication Status:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7F8C8D),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Authenticated',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountActions(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Logout Button
          _buildActionButton(
            context,
            'Logout',
            Icons.logout_rounded,
            const Color(0xFFFF9800),
            () => _showLogoutDialog(context),
          ),
          _buildDivider(),
          
          // Delete Account Button
          _buildActionButton(
            context,
            'Delete Account',
            Icons.delete_forever_rounded,
            Colors.red.shade600,
            () => _showDeleteAccountDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.grey.shade400,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(
        height: 1,
        color: Colors.grey.shade200,
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Logout',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
          content: const Text(
            'Are you sure you want to logout?',
            style: TextStyle(
              color: Color(0xFF7F8C8D),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF7F8C8D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => _logout(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Logout',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.warning_rounded,
                color: Colors.red.shade600,
                size: 28,
              ),
              const SizedBox(width: 8),
              const Text(
                'Delete Account',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to delete your account?',
                style: TextStyle(
                  color: Color(0xFF2C3E50),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_rounded,
                          color: Colors.red.shade600,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Important Notice',
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your account will be permanently removed in 60 working days. This action cannot be undone.',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF7F8C8D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => _deleteAccount(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Delete Account',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('authToken');
      await prefs.remove('userEmail');
      await prefs.remove('userName');
      
      if (!context.mounted) return;
      
      Navigator.of(context).pop(); // Close dialog
      
      // Navigate to login screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logged out successfully'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error during logout: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    try {
      // Show processing dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Processing account deletion...'),
            ],
          ),
        ),
      );

      // Simulate API call delay
      await Future.delayed(const Duration(seconds: 2));

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('authToken');
      await prefs.remove('userEmail');
      await prefs.remove('userName');
      
      if (!context.mounted) return;
      
      Navigator.of(context).pop(); // Close processing dialog
      Navigator.of(context).pop(); // Close delete dialog
      
      // Navigate to login screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Account deletion request submitted. Your account will be removed in 60 working days.',
            style: const TextStyle(fontSize: 12),
          ),
          backgroundColor: Colors.orange.shade600,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      
      Navigator.of(context).pop(); // Close processing dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error during account deletion: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
