import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:zydus_vistaar/services/app_version_service.dart';
import 'package:zydus_vistaar/utils/app_hard_reload.dart'
    if (dart.library.io) 'package:zydus_vistaar/utils/app_hard_reload_stub.dart';

/// "A new version is available" prompt. Non-dismissible — the only exit is
/// the Refresh action, which records the acknowledgement (so a stuck
/// browser cache doesn't keep re-firing the dialog) and then calls the
/// platform-appropriate hard-reload.
class VersionUpdateDialog extends StatelessWidget {
  const VersionUpdateDialog({
    super.key,
    this.currentVersion,
    this.latestVersion,
    this.latestInfo,
  });

  final String? currentVersion;
  final String? latestVersion;

  /// The full backend version DTO. When provided, tapping Refresh persists
  /// it via [AppVersionService.acknowledge] before the hard-reload so the
  /// dialog won't re-fire on the next splash even if the cache still serves
  /// the old bundle.
  final AppVersionInfo? latestInfo;

  static Future<void> show(
    BuildContext context, {
    String? currentVersion,
    String? latestVersion,
    AppVersionInfo? latestInfo,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: VersionUpdateDialog(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          latestInfo: latestInfo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.system_update, color: Color(0xFF00A0A8)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Update available',
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
            'A new version is available. Please refresh to load the '
            'latest updates.',
          ),
          if (currentVersion != null && latestVersion != null) ...[
            const SizedBox(height: 12),
            Text(
              'Installed: $currentVersion\nLatest: $latestVersion',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          if (!kIsWeb) ...[
            const SizedBox(height: 8),
            const Text(
              'The app will close — please reopen it to load the new build.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
      actions: [
        ElevatedButton.icon(
          onPressed: () async {
            if (latestInfo != null) {
              await AppVersionService().acknowledge(latestInfo!);
            }
            await hardReloadApp();
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00A0A8),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }
}
