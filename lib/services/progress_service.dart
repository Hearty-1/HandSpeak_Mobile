import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
  Future<void> recordGestureAttempt({
    required String sign,
    required String levelId,
    required String questionId,
    required bool isCorrect,
    required double score,
    String category = 'general',
    bool isCameraGesture = true,
  }) async {
    if (!isCameraGesture) return;

    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

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
      debugPrint('Error recording camera gesture attempt: $e');
    }
  }

  /// Records group challenge performance data to Firestore for web dashboard tracking
  Future<void> recordGroupChallengeHistory({
    required String roomId,
    required String challengeTitle,
    required String category,
    required int score,
    required int xpEarned,
    required int rank,
    required int totalPlayers,
    required int correctCount,
    required int mistakesCount,
    required List<Map<String, dynamic>> standings,
    required List<Map<String, dynamic>> questionBreakdown,
  }) async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      await _db
          .collection('users')
          .doc(currentUser.uid)
          .collection('group_challenge_history')
          .add({
        'roomId': roomId,
        'challengeTitle': challengeTitle,
        'category': _normalizeCategory(category),
        'score': score,
        'xpEarned': xpEarned,
        'rank': rank,
        'totalPlayers': totalPlayers,
        'correctCount': correctCount,
        'mistakesCount': mistakesCount,
        'standings': standings,
        'questionBreakdown': questionBreakdown,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error recording group challenge history: $e');
    }
  }

  /// Records solo challenge performance data to Firestore for progress history and user stats tracking
  Future<void> recordSoloChallengeHistory({
    required String category,
    required int score,
    required int correctCount,
    required int totalQuestions,
    required double accuracy,
    required int peakStreak,
  }) async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final normalizedCat = _normalizeCategory(category);
    final batch = _db.batch();
    final userRef = _db.collection('users').doc(currentUser.uid);

    // 1. Update primary user document metrics (Added dynamic challenge XP tracking to progress map)
    batch.set(
      userRef,
      {
        'xp': FieldValue.increment(score),
        'dailyXp': FieldValue.increment(score),
        'totalGamesPlayed': FieldValue.increment(1),
        'soloChallengesCompleted': FieldValue.increment(1),
        'totalQuestionsAnswered': FieldValue.increment(totalQuestions),
        'totalCorrectAnswers': FieldValue.increment(correctCount),
        'lastActive': FieldValue.serverTimestamp(),
        'recentModules': FieldValue.arrayUnion([normalizedCat]),
        'progress': {
          '${normalizedCat.replaceAll(' ', '_')}_challenge_xp': FieldValue.increment(score)
        }
      },
      SetOptions(merge: true),
    );

    // 2. Add session entry to progress history subcollection
    final historyRef = userRef.collection('progress_history').doc();
    batch.set(historyRef, {
      'category': normalizedCat,
      'score': score,
      'correctCount': correctCount,
      'totalQuestions': totalQuestions,
      'accuracy': accuracy,
      'peakStreak': peakStreak,
      'completedAt': FieldValue.serverTimestamp(),
      'mode': 'solo_challenge',
    });

    // 3. Update category progress aggregate inside the `category_progress` subcollection
    final catProgressRef = userRef
        .collection('category_progress')
        .doc(normalizedCat.replaceAll(' ', '_'));
    batch.set(
      catProgressRef,
      {
        'category': normalizedCat,
        'totalAttempts': FieldValue.increment(1),
        'completedRounds': FieldValue.increment(1),
        'totalCorrect': FieldValue.increment(correctCount),
        'totalQuestions': FieldValue.increment(totalQuestions),
        'lastScore': score,
        'lastPlayed': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    try {
      await batch.commit();
    } catch (e) {
      debugPrint('Error recording solo challenge history: $e');
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
      debugPrint('Error recording activity attempt: $e');
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
      debugPrint('Error tracking recent module: $e');
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
      debugPrint('Error updating XP: $e');
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
      debugPrint('Error adding overall XP: $e');
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