import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FCMService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initializeFCM() async {
    // 1. Request permission (Required for iOS, Android 13+)
    NotificationSettings settings = await _messaging.requestPermission();
    
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // 2. Get the unique device token
      String? token = await _messaging.getToken();
      
      // 3. Save it to Firestore so GCP/Cloud Functions can target this device
      if (token != null) {
        _saveTokenToFirestore(token);
      }

      // 4. Listen for token refreshes
      _messaging.onTokenRefresh.listen(_saveTokenToFirestore);
    }
  }

  static void _saveTokenToFirestore(String token) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
    }
  }
}