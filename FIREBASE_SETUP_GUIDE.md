# Firebase Setup Guide for ZydusPod

This guide explains how to set up Firebase App Distribution and Cloud Messaging for your Flutter app.

## 1. Firebase Project Setup

### Prerequisites
- Firebase project created
- `google-services.json` file placed in `android/app/` directory
- Firebase dependencies added to `pubspec.yaml`

### Files Added/Modified
- ✅ `pubspec.yaml` - Added Firebase dependencies
- ✅ `lib/services/firebase_service.dart` - Firebase service implementation
- ✅ `lib/widgets/notification_handler.dart` - Notification UI components
- ✅ `lib/main.dart` - Firebase initialization
- ✅ `lib/screens/profile_screen.dart` - Added notification settings

## 2. Firebase App Distribution Setup

### Android Configuration
1. **Enable App Distribution in Firebase Console:**
   - Go to Firebase Console → App Distribution
   - Add your app if not already added
   - Upload your APK/AAB file

2. **Configure Testers:**
   - Add tester emails in Firebase Console
   - Testers will receive email invitations

3. **Automatic Update Checks:**
   - The app automatically checks for updates on startup
   - Users can manually check for updates in Profile → Notification Settings

### iOS Configuration (if needed)
1. Add `GoogleService-Info.plist` to `ios/Runner/`
2. Configure iOS-specific settings in Firebase Console

## 3. Push Notifications Setup

### Server-Side Implementation
To send notifications from your backend, use the FCM token stored in the app:

```javascript
// Example Node.js server code
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
const serviceAccount = require('./path/to/serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

// Send notification to specific user
async function sendNotificationToUser(fcmToken, title, body, data = {}) {
  const message = {
    token: fcmToken,
    notification: {
      title: title,
      body: body,
    },
    data: data, // Custom data for navigation
    android: {
      notification: {
        icon: 'ic_notification',
        color: '#00A0A8',
        sound: 'default',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
          badge: 1,
        },
      },
    },
  };

  try {
    const response = await admin.messaging().send(message);
    console.log('Successfully sent message:', response);
    return response;
  } catch (error) {
    console.log('Error sending message:', error);
    throw error;
  }
}

// Send to all users (topic-based)
async function sendNotificationToTopic(topic, title, body, data = {}) {
  const message = {
    topic: topic,
    notification: {
      title: title,
      body: body,
    },
    data: data,
  };

  try {
    const response = await admin.messaging().send(message);
    console.log('Successfully sent message:', response);
    return response;
  } catch (error) {
    console.log('Error sending message:', error);
    throw error;
  }
}
```

### PHP Backend Example
```php
<?php
// Send notification using cURL
function sendFCMNotification($fcmToken, $title, $body, $data = []) {
    $serverKey = 'YOUR_FCM_SERVER_KEY';
    
    $notification = [
        'title' => $title,
        'body' => $body,
    ];
    
    $fields = [
        'to' => $fcmToken,
        'notification' => $notification,
        'data' => $data,
    ];
    
    $headers = [
        'Authorization: key=' . $serverKey,
        'Content-Type: application/json',
    ];
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, 'https://fcm.googleapis.com/fcm/send');
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($fields));
    
    $result = curl_exec($ch);
    curl_close($ch);
    
    return json_decode($result, true);
}
?>
```

## 4. Notification Types

### 1. App Update Notifications
- Automatically triggered when new version is available
- Shows update dialog with release notes
- Users can update immediately or later

### 2. General Notifications
- Sent from your backend server
- Can include custom data for navigation
- Support for foreground and background handling

### 3. Custom Notification Data
```json
{
  "notification": {
    "title": "New POD Uploaded",
    "body": "A new proof of delivery has been uploaded"
  },
  "data": {
    "screen": "pod_details",
    "pod_id": "12345",
    "type": "pod_upload"
  }
}
```

## 5. Testing Notifications

### Using Firebase Console
1. Go to Firebase Console → Cloud Messaging
2. Click "Send your first message"
3. Enter title and body
4. Select target (single device, topic, or all users)
5. Send test message

### Using cURL
```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "DEVICE_FCM_TOKEN",
    "notification": {
      "title": "Test Notification",
      "body": "This is a test message"
    }
  }'
```

## 6. User Experience Features

### In-App Notifications
- Overlay notifications when app is in foreground
- Auto-dismiss after 5 seconds
- Tap to navigate to relevant screen

### Notification Settings
- Users can enable/disable notifications
- Separate settings for update notifications
- Manual update check option

### Background Handling
- Notifications received when app is closed
- Automatic navigation when tapped
- Data persistence for offline scenarios

## 7. Security Considerations

### FCM Token Management
- Tokens are automatically refreshed
- Store tokens securely on your server
- Implement token validation

### Server Key Security
- Keep FCM server key secure
- Use environment variables
- Implement rate limiting

## 8. Troubleshooting

### Common Issues
1. **Notifications not received:**
   - Check FCM token validity
   - Verify server key
   - Check device notification permissions

2. **App Distribution not working:**
   - Ensure APK is uploaded to Firebase
   - Check tester email invitations
   - Verify app signing

3. **Background notifications not working:**
   - Check background message handler
   - Verify notification payload format
   - Test on physical device

### Debug Commands
```bash
# Check Firebase configuration
flutter doctor

# Test on device
flutter run --debug

# Check logs
flutter logs
```

## 9. Next Steps

1. **Configure your backend** to send notifications
2. **Test notifications** using Firebase Console
3. **Set up App Distribution** with your APK
4. **Add more notification types** as needed
5. **Implement analytics** for notification engagement

## 10. Support

For issues or questions:
- Check Firebase documentation
- Review Flutter Firebase plugin docs
- Contact your development team

---

**Note:** Make sure to replace placeholder values (YOUR_SERVER_KEY, YOUR_FCM_TOKEN, etc.) with actual values from your Firebase project.
