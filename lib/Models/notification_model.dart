import 'dart:convert';

import 'package:flutter/material.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String status; // e.g., info, success, warning, error, unread/read
  final String? description;
  final DateTime? createdAt;
  final Map<String, dynamic>? data;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.status,
    this.description,
    this.createdAt,
    this.data,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? json['header'] ?? 'Notification').toString(),
      body: (json['body'] ?? json['message'] ?? '').toString(),
      status: (json['status'] ?? json['type'] ?? 'info').toString(),
      description: (json['description'] ?? json['details'])?.toString(),
      createdAt: _tryParseDateTime(json['created_at'] ?? json['date']),
      data: _parseData(json['data']),
    );
  }

  static Map<String, dynamic>? _parseData(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      // jsonDecode returns nested maps typed as Map<String, dynamic> at runtime
      // but the static `is Map<String, dynamic>` check can fail for nested
      // maps, so normalize via Map.from.
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.isNotEmpty) {
      // Some backends store notification.data as an encoded JSON string.
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static DateTime? _tryParseDateTime(dynamic value) {
    if (value == null) return null;
    try {
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  Color statusColor() {
    switch (status.toLowerCase()) {
      case 'success':
      case 'approved':
      case 'verified':
        return const Color(0xFF4CAF50);
      case 'warning':
      case 'pending':
        return const Color(0xFFFFA000);
      case 'error':
      case 'rejected':
      case 'failed':
        return const Color(0xFFE53935);
      case 'info':
      default:
        return const Color(0xFF1E88E5);
    }
  }

  IconData statusIcon() {
    switch (status.toLowerCase()) {
      case 'success':
      case 'approved':
      case 'verified':
        return Icons.check_circle_rounded;
      case 'warning':
      case 'pending':
        return Icons.warning_amber_rounded;
      case 'error':
      case 'rejected':
      case 'failed':
        return Icons.error_outline_rounded;
      case 'info':
      default:
        return Icons.notifications_rounded;
    }
  }
}


