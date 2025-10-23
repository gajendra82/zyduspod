import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  FirebaseMessaging? _messaging;
  FirebaseAnalytics? _analytics;
  FlutterLocalNotificationsPlugin? _localNotifications;
  
  // Notification token for sending targeted notifications
  String? _fcmToken;

  // Initialize Firebase services
  Future<void> initialize() async {
    try {
      // Initialize Firebase Core
      await Firebase.initializeApp();
      
      // Initialize Firebase Analytics
      _analytics = FirebaseAnalytics.instance;
      
      // Initialize Firebase Messaging
      _messaging = FirebaseMessaging.instance;
      
      // Initialize Local Notifications
      await _initializeLocalNotifications();
      
      // Request notification permissions
      await _requestNotificationPermissions();
      
      // Get FCM token
      await _getFCMToken();
      
      // Set up message handlers
      _setupMessageHandlers();
      
      if (kDebugMode) {
        print('Firebase services initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing Firebase services: $e');
      }
    }
  }

  // Initialize Local Notifications
  Future<void> _initializeLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();
    
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    
    await _localNotifications?.initialize(initializationSettings);
  }

  // Request notification permissions
  Future<void> _requestNotificationPermissions() async {
    if (Platform.isAndroid) {
      // Request Android notification permissions
      await _localNotifications?.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      
      // Request FCM permissions
      await _messaging?.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
    } else if (Platform.isIOS) {
      // Request iOS notification permissions
      await _messaging?.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
    }
  }

  // Get FCM token for sending notifications
  Future<void> _getFCMToken() async {
    try {
      _fcmToken = await _messaging?.getToken();
      if (kDebugMode) {
        print('FCM Token: $_fcmToken');
      }
      
      // You can send this token to your server for targeted notifications
      await _sendTokenToServer(_fcmToken);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting FCM token: $e');
      }
    }
  }

  // Send FCM token to your server (implement based on your backend)
  Future<void> _sendTokenToServer(String? token) async {
    if (token != null) {
      // TODO: Implement API call to send token to your server
      // Example:
      // await ApiClient().post('/fcm-token', {'token': token});
    }
  }

  // Set up message handlers for different notification states
  void _setupMessageHandlers() {
    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleForegroundMessage(message);
    });
    
    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message);
    });
    
    // Handle notification tap when app is terminated
    _messaging?.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _handleNotificationTap(message);
      }
    });
  }

  // Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      print('Received foreground message: ${message.messageId}');
      print('Title: ${message.notification?.title}');
      print('Body: ${message.notification?.body}');
    }
    
    // Show in-app notification or update UI
    _showInAppNotification(message);
  }

  // Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    if (kDebugMode) {
      print('Notification tapped: ${message.messageId}');
    }
    
    // Navigate to specific screen based on notification data
    _navigateFromNotification(message);
  }

  // Show system notification with default sound
  void _showInAppNotification(RemoteMessage message) async {
    if (message.notification != null) {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'zyduspod_channel',
        'ZydusPod Notifications',
        channelDescription: 'Notifications for ZydusPod app',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );
      
      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );
      
      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );
      
      await _localNotifications?.show(
        message.hashCode,
        message.notification?.title ?? 'ZydusPod',
        message.notification?.body ?? '',
        platformChannelSpecifics,
        payload: message.data.toString(),
      );
      
      if (kDebugMode) {
        print('System notification shown: ${message.notification!.title}');
      }
    }
  }

  // Navigate based on notification data
  void _navigateFromNotification(RemoteMessage message) {
    // Extract navigation data from message.data
    final data = message.data;
    
    if (data.containsKey('screen')) {
      final screen = data['screen'];
      // Navigate to specific screen based on the data
      // You can implement navigation logic here
      if (kDebugMode) {
        print('Navigate to screen: $screen');
      }
    }
  }

  // Manual check for updates (placeholder for future implementation)
  Future<void> checkForUpdates() async {
    if (kDebugMode) {
      print('Update checking not implemented yet');
    }
  }

  // Manually request notification permissions (call this from UI)
  Future<bool> requestNotificationPermissions() async {
    try {
      if (Platform.isAndroid) {
        // Request Android notification permissions
        final result = await _localNotifications?.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
        
        // Also request FCM permissions
        final fcmSettings = await _messaging?.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );
        
        return (result == true) && (fcmSettings?.authorizationStatus == AuthorizationStatus.authorized);
      } else if (Platform.isIOS) {
        // Request iOS notification permissions
        final settings = await _messaging?.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );
        
        return settings?.authorizationStatus == AuthorizationStatus.authorized;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting notification permissions: $e');
      }
      return false;
    }
  }

  // Get current FCM token
  String? get fcmToken => _fcmToken;

  // Get analytics instance
  FirebaseAnalytics? get analytics => _analytics;

  // Log custom events
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    await _analytics?.logEvent(name: name, parameters: parameters);
  }

  // Log user properties
  Future<void> setUserProperty(String name, String value) async {
    await _analytics?.setUserProperty(name: name, value: value);
  }
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  
  if (kDebugMode) {
    print('Handling background message: ${message.messageId}');
  }
  
  // Show system notification for background messages
  if (message.notification != null) {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'zyduspod_channel',
      'ZydusPod Notifications',
      channelDescription: 'Notifications for ZydusPod app',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );
    
    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );
    
    final FlutterLocalNotificationsPlugin localNotifications =
        FlutterLocalNotificationsPlugin();
    
    await localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'ZydusPod',
      message.notification?.body ?? '',
      platformChannelSpecifics,
      payload: message.data.toString(),
    );
  }
}
