import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zyduspod/config.dart';

class AppVersionInfo {
  AppVersionInfo({
    required this.version,
    this.buildNumber,
    this.isForceUpdate = false,
  });

  final String version;
  final int? buildNumber;
  final bool isForceUpdate;

  String get display =>
      buildNumber != null ? '$version+$buildNumber' : version;
}

/// Talks to the backend `app_versions` row to decide whether the running
/// Flutter bundle is stale. The splash calls this on every launch.
class AppVersionService {
  static String get _endpoint => '${API_BASE_URL}app-version';

  // SharedPreferences key for the per-device "I have already acknowledged
  // this backend version" record. Kept here so callers don't drift on the
  // string literal.
  static const String _ackPrefsKey = 'app_version_acknowledged';

  Future<AppVersionInfo?> fetchLatest({String platform = 'flutter'}) async {
    try {
      final uri = Uri.parse('$_endpoint?platform=$platform');
      final resp = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;
      final data = body['data'] as Map<String, dynamic>;
      final raw = data['build_number'];
      final build = raw is int
          ? raw
          : (raw == null ? null : int.tryParse(raw.toString()));
      return AppVersionInfo(
        version: (data['version'] ?? '').toString(),
        buildNumber: build,
        isForceUpdate: data['is_force_update'] == true,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppVersionService] fetchLatest failed: $e');
      }
      return null;
    }
  }

  Future<AppVersionInfo> getCurrent() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersionInfo(
      version: info.version,
      buildNumber: int.tryParse(info.buildNumber),
    );
  }

  /// True when [latest] differs from the running [current] bundle. Any
  /// mismatch (semver or build number) triggers a prompt — a rebuild bump
  /// alone is enough to invalidate the cached web bundle.
  bool isOutdated(AppVersionInfo current, AppVersionInfo latest) {
    final v = latest.version.trim();
    if (v.isEmpty) return false;
    if (current.version.trim() != v) return true;
    if (latest.buildNumber != null &&
        current.buildNumber != null &&
        latest.buildNumber != current.buildNumber) {
      return true;
    }
    return false;
  }

  /// Returns the backend version this device has already acknowledged via
  /// the Refresh button, or null if nothing recorded yet. Used to break the
  /// re-prompt loop when the browser cache keeps serving the same stale
  /// bundle after a hard-reload.
  Future<String?> getAcknowledgedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_ackPrefsKey);
      if (v == null || v.trim().isEmpty) return null;
      return v;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppVersionService] getAcknowledgedVersion failed: $e');
      }
      return null;
    }
  }

  /// Persists the backend [latest] as "user has tapped Refresh for this
  /// version on this device". The splash skips the prompt next launch if
  /// the backend version still matches this value.
  Future<void> acknowledge(AppVersionInfo latest) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ackPrefsKey, latest.display);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppVersionService] acknowledge failed: $e');
      }
    }
  }
}
