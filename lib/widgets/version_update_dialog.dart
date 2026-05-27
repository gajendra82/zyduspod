import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:zyduspod/utils/app_hard_reload.dart'
    if (dart.library.io) 'package:zyduspod/utils/app_hard_reload_stub.dart';

/// "A new version is available" prompt. Non-dismissible — the only exit is
/// the Refresh action, which calls the platform-appropriate hard-reload.
class VersionUpdateDialog extends StatelessWidget {
  const VersionUpdateDialog({
    super.key,
    this.currentVersion,
    this.latestVersion,
  });

  final String? currentVersion;
  final String? latestVersion;

  static Future<void> show(
    BuildContext context, {
    String? currentVersion,
    String? latestVersion,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: VersionUpdateDialog(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
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
