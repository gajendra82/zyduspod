import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:zydus_vistaar/config.dart';
import 'package:zydus_vistaar/services/app_version_service.dart';

/// Native-style "Update Available" prompt for the iOS build.
///
/// Unlike the web variant (which forced a browser hard-reload to bust a
/// stale JS bundle), an iOS native build is updated through the App
/// Store, so this dialog:
///
///   • shows two buttons — [Later] (dismiss) and [Update Now] (launch
///     the App Store via url_launcher).
///   • is dismissible. We don't lock the user out of the app because
///     they might be offline, on cellular, or otherwise can't update
///     immediately. If the backend ever surfaces `is_force_update=true`
///     the caller can wrap this in a non-dismissible barrier.
///   • persists per-version acknowledgement so a user who taps "Later"
///     isn't pestered on every cold start.
///
/// The Android build does NOT use this widget — APK / Play Store handles
/// updates natively and the prompt was removed entirely from that branch.
class VersionUpdateDialog extends StatelessWidget {
  const VersionUpdateDialog({
    super.key,
    this.currentVersion,
    this.latestVersion,
    this.latestInfo,
  });

  final String? currentVersion;
  final String? latestVersion;

  /// When provided, tapping "Later" stores `latest.display` in
  /// SharedPreferences so the splash skips this same backend version on
  /// future launches until the admin bumps the row again.
  final AppVersionInfo? latestInfo;

  static Future<void> show(
    BuildContext context, {
    String? currentVersion,
    String? latestVersion,
    AppVersionInfo? latestInfo,
  }) {
    return showDialog<void>(
      context: context,
      // Dismissible — App Store updates can't be forced from inside the
      // app, so blocking the UI is just punishing the user.
      barrierDismissible: true,
      builder: (_) => VersionUpdateDialog(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        latestInfo: latestInfo,
      ),
    );
  }

  Future<void> _openAppStore(BuildContext context) async {
    final url = IOS_APP_STORE_URL.trim();
    if (url.isEmpty) {
      if (kDebugMode) {
        debugPrint('[VERSION] IOS_APP_STORE_URL is empty — set it in config.dart');
      }
      return;
    }

    final uri = Uri.parse(url);
    bool launched = false;
    try {
      launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VERSION] launchUrl failed: $e');
      }
    }

    if (!launched && context.mounted) {
      // App Store didn't open (no handler, simulator, etc.) — surface a
      // SnackBar instead of silently failing. User can copy the URL from
      // the message and open it manually.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open the App Store. Please update from: $url'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Native-leaning material dialog. Could be CupertinoAlertDialog if we
    // want to be platform-pure, but the app's other dialogs are Material
    // so this matches the app's existing chrome on iOS.
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: const [
          Icon(Icons.system_update, color: Color(0xFF00A0A8)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Update Available',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A newer version of the app is available on the App Store. '
            'Please update to continue using the app with the latest features.',
          ),
          if (currentVersion != null && latestVersion != null) ...[
            const SizedBox(height: 12),
            Text(
              'Installed: $currentVersion\nLatest: $latestVersion',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            // Persist the ack so we don't re-prompt on every cold start
            // for the same backend version. Admin bumping the row again
            // re-fires the dialog because the ack no longer matches.
            if (latestInfo != null) {
              await AppVersionService().acknowledge(latestInfo!);
            }
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Later'),
        ),
        ElevatedButton.icon(
          onPressed: () => _openAppStore(context),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Update Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00A0A8),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
        ),
      ],
    );
  }
}

/// Guard so this widget compiles only on iOS — but the file is left
/// importable on other platforms so the splash conditional check stays
/// straightforward. The actual `Platform.isIOS` decision is made by the
/// caller in splash_screen.dart.
@visibleForTesting
bool isVersionDialogSupported() => Platform.isIOS;
