import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zydus_vistaar/config.dart';

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
      return _fromJson(data);
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

  /// Negative when [current] is older than [latest], zero when equal, positive
  /// when [current] is newer (deployed ahead of DB).
  int compare(AppVersionInfo current, AppVersionInfo latest) {
    final semver = _compareSemver(
      current.version.trim(),
      latest.version.trim(),
    );
    if (semver != 0) return semver;

    final cb = current.buildNumber ?? 0;
    final lb = latest.buildNumber ?? 0;
    return cb.compareTo(lb);
  }

  /// True only when the installed bundle is **behind** the server record.
  bool needsUpdate(AppVersionInfo current, AppVersionInfo latest) {
    if (latest.version.trim().isEmpty) return false;
    return compare(current, latest) < 0;
  }

  /// True when the installed bundle is **ahead** of the server record
  /// (common when web was deployed but app_versions was not updated).
  bool isAheadOfServer(AppVersionInfo current, AppVersionInfo latest) {
    if (latest.version.trim().isEmpty) return false;
    return compare(current, latest) > 0;
  }

  /// @deprecated Use [needsUpdate] — kept for callers migrating gradually.
  bool isOutdated(AppVersionInfo current, AppVersionInfo latest) =>
      needsUpdate(current, latest);

  /// POST installed version to the server. When the bundle is newer than DB,
  /// app_versions is bumped so the update dialog stops looping.
  Future<bool> reportRefresh(AppVersionInfo installed, {String platform = 'flutter'}) async {
    try {
      final uri = Uri.parse('$_endpoint/refresh');
      final resp = await http
          .post(
            uri,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'platform': platform,
              'version': installed.version,
              if (installed.buildNumber != null)
                'build_number': installed.buildNumber,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['success'] != true) return false;

      final data = body['data'];
      if (data is Map<String, dynamic>) {
        return data['synced'] == true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppVersionService] reportRefresh failed: $e');
      }
      return false;
    }
  }

  /// If the running bundle is ahead of DB, sync server and return true.
  Future<bool> syncAheadBundleIfNeeded(AppVersionInfo current, AppVersionInfo latest) async {
    if (!isAheadOfServer(current, latest)) return false;
    return reportRefresh(current);
  }

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

  Future<void> acknowledge(AppVersionInfo version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ackPrefsKey, version.display);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppVersionService] acknowledge failed: $e');
      }
    }
  }

  Future<void> clearAcknowledgement() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_ackPrefsKey);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppVersionService] clearAcknowledgement failed: $e');
      }
    }
  }

  AppVersionInfo _fromJson(Map<String, dynamic> data) {
    final raw = data['build_number'];
    final build = raw is int
        ? raw
        : (raw == null ? null : int.tryParse(raw.toString()));
    return AppVersionInfo(
      version: (data['version'] ?? '').toString(),
      buildNumber: build,
      isForceUpdate: data['is_force_update'] == true,
    );
  }

  int _compareSemver(String a, String b) {
    final partsA = _parseSemver(a);
    final partsB = _parseSemver(b);
    final length = partsA.length > partsB.length ? partsA.length : partsB.length;

    for (var i = 0; i < length; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  List<int> _parseSemver(String version) {
    if (version.trim().isEmpty) return [0];
    return version.split('.').map((part) {
      final digits = RegExp(r'^\d+').firstMatch(part.trim());
      return digits != null ? int.parse(digits.group(0)!) : 0;
    }).toList();
  }
}
