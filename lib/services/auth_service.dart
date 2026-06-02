import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zydus_vistaar/routes.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Logout user and navigate to login screen
  static Future<void> logout(BuildContext? context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Clear all stored authentication data
      await prefs.remove('authToken');
      await prefs.remove('userEmail');
      await prefs.remove('userName');
      
      // Optional: Clear all preferences
      // await prefs.clear();
      
      print('User logged out successfully');
      
      // Navigate to login screen if context is provided
      if (context != null && context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.login,
          (route) => false,
        );
      }
    } catch (e) {
      print('Error during logout: $e');
    }
  }

  /// Check if user is authenticated
  static Future<bool> isAuthenticated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');
      return token != null && token.isNotEmpty;
    } catch (e) {
      print('Error checking authentication: $e');
      return false;
    }
  }

  /// Get stored auth token
  static Future<String?> getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('authToken');
    } catch (e) {
      print('Error getting auth token: $e');
      return null;
    }
  }

  /// Get user email
  static Future<String?> getUserEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('userEmail');
    } catch (e) {
      print('Error getting user email: $e');
      return null;
    }
  }

  /// Get user name
  static Future<String?> getUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('userName');
    } catch (e) {
      print('Error getting user name: $e');
      return null;
    }
  }
}

