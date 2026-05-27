import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

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

  /// True when [latest] is different from [current]. Any change to either
  /// the semantic version OR the build number triggers a prompt — a rebuild
  /// bump alone is enough to invalidate the cached web bundle.
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
}
