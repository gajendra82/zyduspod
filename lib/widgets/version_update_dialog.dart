import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:zydus_vistaar/services/app_version_service.dart';
import 'package:zydus_vistaar/utils/app_hard_reload.dart'
    if (dart.library.io) 'package:zydus_vistaar/utils/app_hard_reload_stub.dart';

/// "A new version is available" prompt. Non-dismissible — the only exit is
/// the Refresh action, which clears any stale acknowledgement and triggers
/// a platform-appropriate hard-reload so the browser fetches the new bundle.
class VersionUpdateDialog extends StatelessWidget {
  const VersionUpdateDialog({
    super.key,
    this.currentVersion,
    this.latestVersion,
    this.latestInfo,
  });

  final String? currentVersion;
  final String? latestVersion;

  /// The full backend version DTO. Passed for display only; acknowledgement
  /// is recorded on splash once the running bundle matches [latestInfo].
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
            // Do not acknowledge before reload — if the cache still serves
            // the old bundle, splash must show this dialog again on next load.
            await AppVersionService().clearAcknowledgement();
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
