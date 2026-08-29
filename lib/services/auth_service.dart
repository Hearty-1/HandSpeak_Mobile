import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/providers/theme_provider.dart'; 

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- ACTIVITY LOG HELPER ---
  Future<void> _logAccountActivity({
    required String uid,
    required String action,
    required String description,
  }) async {
    try {
      String formattedTime = DateFormat("MMMM d, yyyy 'at' h:mm:ss a").format(DateTime.now());

      await _db
          .collection('users')
          .doc(uid)
          .collection('login_activity')
          .add({
        'action': action,
        'description': description,
        'status': 'active',
        'timestamp': formattedTime,
        'uid': uid,
      });
    } catch (e) {
      debugPrint("Failed to log activity: $e");
    }
  }

  // --- PUBLIC DEVICE HISTORY HELPER ---
  Future<void> registerDeviceSession(String uid) async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String deviceName = "Unknown Device";
      String os = "Unknown OS";
      String deviceId = "unknown_device_id";

      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        deviceName = webInfo.browserName.name;
        os = "Web Browser";
        deviceId = webInfo.userAgent?.hashCode.toString() ?? "web_client";
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        String manufacturer = androidInfo.manufacturer.isNotEmpty 
            ? androidInfo.manufacturer 
            : "Android";
        String model = androidInfo.model.isNotEmpty 
            ? androidInfo.model 
            : "Device";
            
        deviceName = "$manufacturer $model".trim();
        os = "Android ${androidInfo.version.release}";
        deviceId = androidInfo.id.isNotEmpty ? androidInfo.id : "android_${uid.substring(0, 5)}";
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = iosInfo.name;
        os = "${iosInfo.systemName} ${iosInfo.systemVersion}";
        deviceId = iosInfo.identifierForVendor ?? "ios_device";
      }

      print("Attempting to write device session: $deviceName ($deviceId) for UID: $uid");

      // Path: users -> [UID] -> device_sessions -> [deviceId]
      await _db
          .collection('users')
          .doc(uid)
          .collection('device_sessions')
          .doc(deviceId)
          .set({
        'deviceId': deviceId,
        'deviceName': deviceName,
        'os': os,
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print("Device session successfully written to Firestore!");
    } catch (e, stack) {
      print("Error registering device session: $e");
      print(stack);
    }
  }

  // Sign Up with Student Details
  Future<User?> signUpWithStudentDetails({
    required String email,
    required String password,
    required String firstName,
    required String middleName,
    required String lastName,
    required String studentId,
    required String section,
    required String gradeLevel,
  }) async {
    try {
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      User? user = credential.user;

      if (user != null) {
        String fullName = middleName.trim().isNotEmpty 
            ? "${firstName.trim()} ${middleName.trim()} ${lastName.trim()}" 
            : "${firstName.trim()} ${lastName.trim()}";

        await _db.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': fullName,
          'firstName': firstName.trim(),
          'middleName': middleName.trim(),
          'lastName': lastName.trim(),
          'email': email,
          'studentId': studentId,
          'section': section,
          'gradeLevel': gradeLevel,
          'role': 'student',
          'status': 'pending', 
          'themePreference': 'defaultWarm', // Default theme preference on signup
          'createdAt': FieldValue.serverTimestamp(),
        });

        await _logAccountActivity(
          uid: user.uid,
          action: "Account Created",
          description: "Student registered a new account.",
        );
        await registerDeviceSession(user.uid);
      }
      return user;
    } catch (e) {
      debugPrint("Sign Up Error: $e");
      return null;
    }
  }

  // Sign In with Status Check (Syncs Theme from Firestore)
  Future<Map<String, dynamic>?> signInWithStatusCheck(String email, String password) async {
    try {
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = credential.user;
      if (user != null) {
        DocumentSnapshot doc = await _db.collection('users').doc(user.uid).get();
        if (doc.exists) {
          Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;
          
          // Pull account theme from Firestore and apply to local device
          if (userData.containsKey('themePreference')) {
            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setString(ThemeProvider.themePrefKey, userData['themePreference']);
          }

          await _logAccountActivity(
            uid: user.uid,
            action: "User Logged In",
            description: "Successful authentication into the app.",
          );
          await registerDeviceSession(user.uid);

          return userData;
        }
      }
      return null;
    } catch (e) {
      debugPrint("Sign In Error: $e");
      return null;
    }
  }

  // Sign Out while preserving the theme on the login screen
  Future<void> signOut() async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        await _logAccountActivity(
          uid: user.uid,
          action: "User Logged Out",
          description: "User manually signed out of the app.",
        );
      }

      // Perform Firebase Sign Out
      await _auth.signOut();

      // Note: We intentionally do NOT clear SharedPreferences here 
      // so the theme persists on the device after signing out.

    } catch (e) {
      debugPrint("Sign Out Error: $e");
    }
  }
}