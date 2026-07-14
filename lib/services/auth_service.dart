import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Sign Up with Email and Password + Save student details to Firestore
  Future<User?> signUpWithStudentDetails({
    required String email,
    required String password,
    required String fullName,
    required String studentId,
    required String section,
    required String gradeLevel,
  }) async {
    try {
      // 1. Create user in Firebase Authentication
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      User? user = credential.user;

      if (user != null) {
        // 2. Create a corresponding profile document in Cloud Firestore
        await _db.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': fullName,
          'email': email,
          'studentId': studentId,
          'section': section,
          'gradeLevel': gradeLevel,
          'role': 'student',
          'status': 'approved', // Hardcoded as 'approved' for now. Flip to 'pending' later when web dashboard is built!
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return user;
    } catch (e) {
      print("Sign Up Error: $e");
      return null;
    }
  }

  // Sign In with Verification Check
  Future<Map<String, dynamic>?> signInWithStatusCheck(String email, String password) async {
    try {
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = credential.user;
      if (user != null) {
        // Fetch student document profile from Firestore
        DocumentSnapshot doc = await _db.collection('users').doc(user.uid).get();
        if (doc.exists) {
          return doc.data() as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      print("Sign In Error: $e");
      return null;
    }
  }
}