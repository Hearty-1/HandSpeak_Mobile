import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProgressService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Update XP for a specific level
  Future<void> updateLevelXP(String levelName, int xpToAdd) async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) return; // Exit if no user is logged in

    DocumentReference userRef = _db.collection('users').doc(currentUser.uid);

    try {
      // Use set with SetOptions(merge: true) to avoid overwriting other data
      // FieldValue.increment ensures atomic additions, preventing race conditions
      await userRef.set({
        'progress': {
          levelName: FieldValue.increment(xpToAdd),
        },
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
    } catch (e) {
      print('Error updating XP: $e');
    }
  }

  // Fetch the user's current progress to display on the UI
  Stream<DocumentSnapshot> getUserProgressStream() {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    return _db.collection('users').doc(currentUser.uid).snapshots();
  }
}