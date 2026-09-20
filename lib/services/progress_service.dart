import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProgressService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Normalizes and formats level keys/categories dynamically for all modules
  String _normalizeCategory(String key) {
    final k = key.toLowerCase().trim();
    if (k.isEmpty) return 'general';
    if (k.contains('number')) return 'numbers';
    if (k.contains('phrase') || k.contains('word') || k.contains('common')) return 'common words';
    if (k.contains('civic')) return 'civic';
    if (k.contains('alpha') || k.contains('letter')) return 'alphabet';
    return k; 
  }

  /// Records an individual gesture attempt for camera gesture recognition in activities across any category.
  /// Standard multiple-choice or written questions bypass this method via the [isCameraGesture] guard.
  Future<void> recordGestureAttempt({
    required String sign,
    required String levelId,
    required String questionId,
    required bool isCorrect,
    required double score,
    String category = 'general',
    bool isCameraGesture = true,
  }) async {
    // Strictly restrict logging to camera-detected gesture recognition attempts
    if (!isCameraGesture) return;

    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Preserve original string case if sign is a Firebase Storage or HTTP URL
    final formattedSign = sign.toLowerCase().startsWith('http') ? sign : sign.toUpperCase();

    try {
      await _db.collection('gesture_attempts').add({
        'userId': currentUser.uid,
        'sign': formattedSign,
        'category': _normalizeCategory(category),
        'levelId': levelId,
        'questionId': questionId,
        'isCorrect': isCorrect,
        'score': score.round(),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error recording camera gesture attempt: $e');
    }
  }

  /// Record activity attempt and completion summary for any module category
  Future<void> recordActivityAttempt({
    required String levelId,
    required String category,
    required bool isCompleted,
    required int starsEarned,
  }) async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      await _db.collection('activity_attempts').add({
        'userId': currentUser.uid,
        'levelId': levelId,
        'category': _normalizeCategory(category),
        'isCompleted': isCompleted,
        'starsEarned': starsEarned,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error recording activity attempt: $e');
    }
  }

  /// Track module activity in Firestore when a user opens any category module
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

  /// Update XP for a specific level and register its base category under recentModules
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

  /// Add overall XP to the user's profile
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

  /// Stream the user's current progress
  Stream<DocumentSnapshot> getUserProgressStream() {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    return _db.collection('users').doc(currentUser.uid).snapshots();
  }
}