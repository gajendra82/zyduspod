import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/firebase_service.dart';

class NotificationHandler extends StatefulWidget {
  final Widget child;
  
  const NotificationHandler({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<NotificationHandler> createState() => _NotificationHandlerState();
}

class _NotificationHandlerState extends State<NotificationHandler> {
  final FirebaseService _firebaseService = FirebaseService();
  OverlayEntry? _notificationOverlay;

  @override
  void initState() {
    super.initState();
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    // Listen for foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showNotificationOverlay(message);
    });
  }

  void _showNotificationOverlay(RemoteMessage message) {
    // Check if widget is still mounted
    if (!mounted) return;
    
    // Remove existing overlay if any
    _notificationOverlay?.remove();
    
    // Create new overlay
    _notificationOverlay = OverlayEntry(
      builder: (context) => _buildNotificationCard(message),
    );
    
    // Insert overlay
    Overlay.of(context).insert(_notificationOverlay!);
    
    // Auto remove after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _notificationOverlay?.remove();
        _notificationOverlay = null;
      }
    });
  }

  Widget _buildNotificationCard(RemoteMessage message) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Row(
            children: [
              // App icon or notification icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.notifications,
                  color: Colors.blue.shade600,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              
              // Notification content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.notification?.title != null)
                      Text(
                        message.notification!.title!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (message.notification?.body != null)
                      Text(
                        message.notification!.body!,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              
              // Close button
              GestureDetector(
                onTap: () {
                  _notificationOverlay?.remove();
                  _notificationOverlay = null;
                },
                child: Icon(
                  Icons.close,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notificationOverlay?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

// Update dialog widget for app distribution
class UpdateDialog extends StatelessWidget {
  final VoidCallback onUpdate;
  final VoidCallback onLater;
  final String? releaseNotes;

  const UpdateDialog({
    Key? key,
    required this.onUpdate,
    required this.onLater,
    this.releaseNotes,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Icon(
            Icons.system_update,
            color: Colors.blue.shade600,
            size: 28,
          ),
          const SizedBox(width: 12),
          const Text(
            'Update Available',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A new version of the app is available. Update now to get the latest features and improvements.',
            style: TextStyle(fontSize: 14),
          ),
          if (releaseNotes != null) ...[
            const SizedBox(height: 16),
            const Text(
              'What\'s New:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              releaseNotes!,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: onLater,
          child: Text(
            'Later',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
        ElevatedButton(
          onPressed: onUpdate,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade600,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'Update Now',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

// Notification settings widget
class NotificationSettings extends StatefulWidget {
  const NotificationSettings({Key? key}) : super(key: key);

  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings> {
  bool _notificationsEnabled = true;
  bool _updateNotificationsEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notification Preferences',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            
            // General notifications
            SwitchListTile(
              title: const Text('Enable Notifications'),
              subtitle: const Text('Receive app notifications'),
              value: _notificationsEnabled,
              onChanged: (value) {
                setState(() {
                  _notificationsEnabled = value;
                });
                // TODO: Save preference and update Firebase settings
              },
              activeColor: Colors.blue.shade600,
            ),
            
            // Update notifications
            SwitchListTile(
              title: const Text('Update Notifications'),
              subtitle: const Text('Get notified about app updates'),
              value: _updateNotificationsEnabled,
              onChanged: (value) {
                setState(() {
                  _updateNotificationsEnabled = value;
                });
                // TODO: Save preference
              },
              activeColor: Colors.blue.shade600,
            ),
            
            const SizedBox(height: 30),
            
            // Request notification permissions button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final granted = await FirebaseService().requestNotificationPermissions();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(granted 
                          ? 'Notification permissions granted!' 
                          : 'Notification permissions denied'),
                        backgroundColor: granted ? Colors.green : Colors.orange,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.notifications_active),
                label: const Text('Request Notification Permissions'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Check for updates button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await FirebaseService().checkForUpdates();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Checking for updates...'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.system_update),
                label: const Text('Check for Updates'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
