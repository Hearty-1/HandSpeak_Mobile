import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/providers/theme_provider.dart'; 

/// Result of [AuthService.signInWithGoogle].
enum GoogleSignInOutcome {
  approved, // signed in, profile in [GoogleSignInResult.profile]
  cancelled, // user closed the Google account picker
  pending, // student account exists but is not approved yet
  notApproved, // account rejected / disabled / not a student
  notRegistered, // no HandSpeak student account for this Google email
  needsPassword, // email registered with a password: sign in with it once to link Google
  error,
}

class GoogleSignInResult {
  final GoogleSignInOutcome outcome;
  final Map<String, dynamic>? profile;
  final String? email;
  final String? message;
  const GoogleSignInResult(this.outcome, {this.profile, this.email, this.message});
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<void>? _googleInit;

  /// Google credential waiting to be linked after a password sign-in (the
  /// email was registered with a password, see [GoogleSignInOutcome.needsPassword]).
  static AuthCredential? _pendingGoogleCredential;
  static String? _pendingGoogleEmail;
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

  // --- GOOGLE SSO (approved students only) ---
  /// Signs in with Google through Firebase. Only students whose `users/{uid}`
  /// profile exists with role "student" and status "approved" get in; anyone
  /// else is signed straight back out (and a brand-new Google-only Firebase
  /// user is deleted so no orphan accounts are left behind).
  Future<GoogleSignInResult> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    String? email;
    try {
      await (_googleInit ??= google.initialize());
      final account = await google.authenticate();
      email = account.email;
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        return const GoogleSignInResult(GoogleSignInOutcome.error, message: 'Google did not return an ID token.');
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);

      UserCredential userCred;
      try {
        userCred = await _auth.signInWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'account-exists-with-different-credential') {
          // Registered with email + password: link Google after a password login.
          _pendingGoogleCredential = credential;
          _pendingGoogleEmail = email;
          await _googleSignOutQuietly();
          return GoogleSignInResult(GoogleSignInOutcome.needsPassword, email: email);
        }
        rethrow;
      }

      final user = userCred.user;
      if (user == null) {
        return const GoogleSignInResult(GoogleSignInOutcome.error, message: 'Sign-in failed.');
      }

      final doc = await _db.collection('users').doc(user.uid).get();
      final data = doc.data();
      if (data == null) {
        // No HandSpeak profile: not a registered student.
        if (userCred.additionalUserInfo?.isNewUser ?? false) {
          try {
            await user.delete();
          } catch (_) {}
        }
        await _signOutEverywhere();
        return GoogleSignInResult(GoogleSignInOutcome.notRegistered, email: email);
      }

      final status = (data['status'] ?? 'pending').toString();
      final role = (data['role'] ?? 'student').toString();
      if (status != 'approved' || role != 'student') {
        await _signOutEverywhere();
        return GoogleSignInResult(
          status == 'pending' ? GoogleSignInOutcome.pending : GoogleSignInOutcome.notApproved,
          email: email,
        );
      }

      await _applyThemePreference(data);
      await _logAccountActivity(
        uid: user.uid,
        action: "User Logged In",
        description: "Successful authentication with Google.",
      );
      await registerDeviceSession(user.uid);
      return GoogleSignInResult(GoogleSignInOutcome.approved, profile: data, email: email);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const GoogleSignInResult(GoogleSignInOutcome.cancelled);
      }
      debugPrint("Google Sign-In Error: ${e.code} ${e.description}");
      return GoogleSignInResult(GoogleSignInOutcome.error, message: e.description ?? e.code.name);
    } catch (e) {
      debugPrint("Google Sign-In Error: $e");
      await _signOutEverywhere();
      return GoogleSignInResult(GoogleSignInOutcome.error, email: email, message: '$e');
    }
  }

  /// Links a Google credential saved by [signInWithGoogle] to the account
  /// that just signed in with its password, so Google works next time.
  Future<void> _linkPendingGoogle(User user) async {
    final cred = _pendingGoogleCredential;
    if (cred == null) return;
    if ((_pendingGoogleEmail ?? '').toLowerCase() != (user.email ?? '').toLowerCase()) return;
    try {
      await user.linkWithCredential(cred);
      await _logAccountActivity(
        uid: user.uid,
        action: "Google Linked",
        description: "Google sign-in linked to this account.",
      );
    } catch (e) {
      debugPrint("Google link skipped: $e");
    } finally {
      _pendingGoogleCredential = null;
      _pendingGoogleEmail = null;
    }
  }

  Future<void> _applyThemePreference(Map<String, dynamic> userData) async {
    if (userData.containsKey('themePreference')) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(ThemeProvider.themePrefKey, userData['themePreference']);
    }
  }

  Future<void> _googleSignOutQuietly() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  Future<void> _signOutEverywhere() async {
    await _googleSignOutQuietly();
    try {
      await _auth.signOut();
    } catch (_) {}
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
          await _applyThemePreference(userData);
          if (userData['status'] == 'approved') await _linkPendingGoogle(user);

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

      // Perform Firebase Sign Out (and Google, so the account picker shows next time)
      await _googleSignOutQuietly();
      await _auth.signOut();

      // Note: We intentionally do NOT clear SharedPreferences here 
      // so the theme persists on the device after signing out.

    } catch (e) {
      debugPrint("Sign Out Error: $e");
    }
  }

  // --- PASSWORD RESET HELPER ---
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null; 
    } on FirebaseAuthException catch (e) {
      return e.message; 
    } catch (e) {
      return "An unexpected error occurred. Please try again.";
    }
  }
}