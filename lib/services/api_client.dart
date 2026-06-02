import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zydus_vistaar/services/auth_service.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  BuildContext? _context;

  /// Set the context for navigation
  void setContext(BuildContext? context) {
    _context = context;
  }

  /// Handle 401 errors by logging out
  Future<void> _handleUnauthorized() async {
    print('401 Unauthorized - Logging out user');
    await AuthService.logout(_context);
  }

  /// GET request with automatic 401 handling
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    bool requiresAuth = true,
  }) async {
    try {
      Map<String, String> requestHeaders = headers ?? {};

      if (requiresAuth) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('authToken');

        if (token == null || token.isEmpty) {
          throw Exception('No authentication token found');
        }

        requestHeaders['Authorization'] = 'Bearer $token';
        requestHeaders['Content-Type'] = 'application/json';
      }

      final response = await http.get(uri, headers: requestHeaders);

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        throw UnauthorizedException('Session expired. Please login again.');
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// POST request with automatic 401 handling
  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool requiresAuth = true,
  }) async {
    try {
      Map<String, String> requestHeaders = headers ?? {};

      if (requiresAuth) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('authToken');

        if (token == null || token.isEmpty) {
          throw Exception('No authentication token found');
        }

        requestHeaders['Authorization'] = 'Bearer $token';
        requestHeaders['Content-Type'] = 'application/json';
      }

      final response = await http.post(
        uri,
        headers: requestHeaders,
        body: body,
        encoding: encoding,
      );

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        throw UnauthorizedException('Session expired. Please login again.');
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// PUT request with automatic 401 handling
  Future<http.Response> put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool requiresAuth = true,
  }) async {
    try {
      Map<String, String> requestHeaders = headers ?? {};

      if (requiresAuth) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('authToken');

        if (token == null || token.isEmpty) {
          throw Exception('No authentication token found');
        }

        requestHeaders['Authorization'] = 'Bearer $token';
        requestHeaders['Content-Type'] = 'application/json';
      }

      final response = await http.put(
        uri,
        headers: requestHeaders,
        body: body,
        encoding: encoding,
      );

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        throw UnauthorizedException('Session expired. Please login again.');
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// DELETE request with automatic 401 handling
  Future<http.Response> delete(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool requiresAuth = true,
  }) async {
    try {
      Map<String, String> requestHeaders = headers ?? {};

      if (requiresAuth) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('authToken');

        if (token == null || token.isEmpty) {
          throw Exception('No authentication token found');
        }

        requestHeaders['Authorization'] = 'Bearer $token';
        requestHeaders['Content-Type'] = 'application/json';
      }

      final response = await http.delete(
        uri,
        headers: requestHeaders,
        body: body,
        encoding: encoding,
      );

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        throw UnauthorizedException('Session expired. Please login again.');
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Multipart request with automatic 401 handling
  Future<http.StreamedResponse> send(
    http.MultipartRequest request, {
    bool requiresAuth = true,
  }) async {
    try {
      if (requiresAuth) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('authToken');

        if (token == null || token.isEmpty) {
          throw Exception('No authentication token found');
        }

        request.headers['Authorization'] = 'Bearer $token';
      }

      final response = await request.send();

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        throw UnauthorizedException('Session expired. Please login again.');
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }
}

/// Custom exception for unauthorized errors
class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);

  @override
  String toString() => message;
}

