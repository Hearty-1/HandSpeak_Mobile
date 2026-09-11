import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProgressService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Converts detailed level keys (e.g., 'numbers_easy_4') into base module keys
  String _normalizeCategory(String key) {
    final k = key.toLowerCase().trim();
    if (k.contains('number')) return 'numbers';
    if (k.contains('phrase') || k.contains('word') || k.contains('common')) return 'common words';
    return 'alphabet';
  }

  // Track module activity in Firestore when a user opens a module
  Future<void> trackRecentModule(String moduleKey) async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

    DocumentReference userRef = _db.collection('users').doc(currentUser.uid);

    try {
      await userRef.set({
        'recentModules': FieldValue.arrayUnion([_normalizeCategory(moduleKey)]),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error tracking recent module: $e');
    }
  }

  // Update XP for a specific level and register its base category under recentModules
  Future<void> updateLevelXP(String levelName, int xpToAdd) async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

    DocumentReference userRef = _db.collection('users').doc(currentUser.uid);

    try {
      await userRef.set({
        'progress': {
          levelName: FieldValue.increment(xpToAdd),
        },
        'recentModules': FieldValue.arrayUnion([_normalizeCategory(levelName)]),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error updating XP: $e');
    }
  }

  // Add overall XP to the user's profile
  Future<void> addXp(int xpToAdd) async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

    DocumentReference userRef = _db.collection('users').doc(currentUser.uid);
    
    try {
      await userRef.set({
        'xp': FieldValue.increment(xpToAdd),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error adding overall XP: $e');
    }
  }

  // Stream the user's current progress
  Stream<DocumentSnapshot> getUserProgressStream() {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    return _db.collection('users').doc(currentUser.uid).snapshots();
  }
}