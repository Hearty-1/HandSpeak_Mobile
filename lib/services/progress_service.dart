import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '/services/activity_log.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gesture_analytics.dart';
import 'offline_sync.dart';
import 'role_service.dart' show RoleProvider;
import 'xp_rewards.dart';

class ProgressService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// The signed-in student. A Faculty / Parent guest's anonymous session is
  /// ignored: no progress, XP or mastery is written for it.
  User? get _studentUser {
    final u = _auth.currentUser;
    return u == null || u.isAnonymous ? null : u;
  }

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

  /// Module XP field of a category name ("Alphabet", "Common Phrases",
  /// "civic", "numbers_easy_3", ...), or '' when it is not a module.
  static String moduleXpField(String? category) {
    final k = (category ?? '').toLowerCase();
    if (k.contains('number')) return 'numbersXp';
    if (k.contains('phrase') || k.contains('word') || k.contains('common')) return 'phraseXp';
    if (k.contains('civic')) return 'civicXp';
    if (k.contains('alpha') || k.contains('letter')) return 'alphabetXp';
    return '';
  }

  /// The module the learner is working toward: the first one in the unlock
  /// chain (Alphabet -> Words/Phrases -> Civic, module.dart) still below
  /// [XpRewards.moduleGoal]. General daily-quest XP goes there, so quests
  /// always help with the next unlock.
  static String currentModuleXpField(Map<String, dynamic>? user) {
    int v(String f) => (user?[f] as num?)?.toInt() ?? 0;
    if (v('alphabetXp') < XpRewards.moduleGoal) return 'alphabetXp';
    final words = v('phraseXp') > v('wordsXp') ? v('phraseXp') : v('wordsXp');
    if (words < XpRewards.moduleGoal) return 'phraseXp';
    return 'civicXp';
  }

  /// Adds challenge XP to a category's module XP (group challenges); the
  /// global XP is added separately with [addXp].
  Future<void> addModuleXp(String category, int xp) async {
    final user = _studentUser;
    final field = moduleXpField(category);
    if (user == null || field.isEmpty || xp <= 0) return;
    try {
      await _db.collection('users').doc(user.uid).set({
        field: FieldValue.increment(xp),
        ..._touchModule(category),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error adding module XP: $e');
    }
  }

  /// The four learning modules, as stored in `recentModules` / `moduleLastOpened`.
  static const List<String> modules = ['alphabet', 'numbers', 'common words', 'civic'];

  /// Fields that mark [moduleKey]'s module as just used: the legacy
  /// `recentModules` set plus `moduleLastOpened.<module>` (a timestamp, so the
  /// home screen can order modules by recency; arrayUnion keeps first-use order).
  Map<String, dynamic> _touchModule(String moduleKey) {
    final cat = _normalizeCategory(moduleKey);
    return {
      'recentModules': FieldValue.arrayUnion([cat]),
      // Built-in modules and the web app's categories (activity_categories
      // ids), so Continue Learning can show either.
      if (cat != 'general') 'moduleLastOpened': {cat: FieldValue.serverTimestamp()},
    };
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
    String? modelVersion, // file that scored the sign (gesture_attempts)
  }) async {
    if (!isCameraGesture) return;

    User? currentUser = _studentUser;
    if (currentUser == null) return;

    // Same organised layout as the activities: one session document per
    // level with an `attempts` subcollection (see gesture_analytics.dart).
    await GestureAttemptTracker.forScreen(category: _normalizeCategory(category), levelId: levelId).recordAttempt(
      sign: sign,
      questionId: questionId,
      isCorrect: isCorrect,
      score: score,
      handsDetected: score > 0,
      modelVersion: modelVersion,
    );
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
    User? currentUser = _studentUser;
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
    User? currentUser = _studentUser;
    if (currentUser == null) return;

    final normalizedCat = _normalizeCategory(category);
    unawaited(ActivityLog.instance.log('challenge.solo_completed',
        category: ActivityCategory.challenge,
        title: 'Finished a ${ActivityLog.moduleName(normalizedCat)} Solo Challenge ($correctCount/$totalQuestions)',
        details: {'category': normalizedCat, 'score': score, 'correct': correctCount, 'total': totalQuestions, 'accuracy': accuracy}));
    final batch = _db.batch();
    final userRef = _db.collection('users').doc(currentUser.uid);

    // 1. Update primary user document metrics (Added dynamic challenge XP tracking to progress map)
    batch.set(
      userRef,
      {
        'xp': FieldValue.increment(score),
        ...periodXp(score),
        // Counts toward the category's module XP (and its unlock).
        if (moduleXpField(category).isNotEmpty) moduleXpField(category): FieldValue.increment(score),
        'totalGamesPlayed': FieldValue.increment(1),
        'soloChallengesCompleted': FieldValue.increment(1),
        'totalQuestionsAnswered': FieldValue.increment(totalQuestions),
        'totalCorrectAnswers': FieldValue.increment(correctCount),
        'lastActive': FieldValue.serverTimestamp(),
        ..._touchModule(normalizedCat),
        'progress': {
          '${normalizedCat.replaceAll(' ', '_')}_challenge_xp': FieldValue.increment(score)
        }
      },
      SetOptions(merge: true),
    );

    // The game itself is recorded once, in the root 'solo_challenges'
    // collection (solo_challenge.dart), not in users/{uid}/progress_history.

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

  /// Full activity records, one per play (kept apart from the older,
  /// larger activity_attempts so new records are easy to find).
  static const String activitySessions = 'activity_sessions';

  /// Records one play of an activity level (activity_sessions): completion,
  /// stars, hearts left, score, which try of the level this is, how long it
  /// took, and every answer:
  ///   { userId, levelId, category, isCompleted, starsEarned, heartsLeft,
  ///     correctCount, totalQuestions, attemptNumber, durationSec,
  ///     answers: [ { questionId, type, sign, chosen, correct } ], timestamp }
  Future<void> recordActivityAttempt({
    required String levelId,
    required String category,
    required bool isCompleted,
    required int starsEarned,
    int? heartsLeft,
    int? totalQuestions,
    DateTime? startedAt,
    List<Map<String, dynamic>> answers = const [],
  }) async {
    User? currentUser = _studentUser;
    if (currentUser == null) return;

    try {
      // This play's number for the level (1 = first time).
      var attemptNumber = 1;
      try {
        final prev = await _db
            .collection(activitySessions)
            .where('userId', isEqualTo: currentUser.uid)
            .where('levelId', isEqualTo: levelId)
            .count()
            .get();
        attemptNumber = (prev.count ?? 0) + 1;
      } catch (e) {
        debugPrint('activity attempt number unavailable: $e');
      }
      final correct = answers.where((a) => a['correct'] == true).length;
      unawaited(ActivityLog.instance.log(isCompleted ? 'activity.completed' : 'activity.failed',
          category: ActivityCategory.activity,
          title: isCompleted
              ? 'Completed ${ActivityLog.levelName(levelId)} ($starsEarned★)'
              : 'Ran out of hearts in ${ActivityLog.levelName(levelId)}',
          details: {
            'levelId': levelId,
            'category': _normalizeCategory(category),
            'stars': starsEarned,
            'heartsLeft': heartsLeft,
            'correct': correct,
            'total': totalQuestions,
          }));
      await _db.collection(activitySessions).add({
        'userId': currentUser.uid,
        'levelId': levelId,
        'category': _normalizeCategory(category),
        'isCompleted': isCompleted,
        'starsEarned': starsEarned,
        'heartsLeft': ?heartsLeft,
        'correctCount': answers.where((a) => a['correct'] == true).length,
        'totalQuestions': ?totalQuestions,
        'attemptNumber': attemptNumber,
        if (startedAt != null) 'durationSec': DateTime.now().difference(startedAt).inSeconds,
        'answers': answers,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error recording activity attempt: $e');
    }
  }

  /// Track module activity in Firestore when a user opens any category module
  Future<void> trackRecentModule(String moduleKey) async {
    User? currentUser = _studentUser;
    if (currentUser == null) return;

    DocumentReference userRef = _db.collection('users').doc(currentUser.uid);
    unawaited(ActivityLog.instance.log('learning.module_opened',
        category: ActivityCategory.learning,
        title: 'Opened ${ActivityLog.moduleName(moduleKey)}',
        details: {'module': moduleKey},
        dedupeKey: moduleKey));

    try {
      await userRef.set({
        ..._touchModule(moduleKey),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error tracking recent module: $e');
    }
  }

  /// Update XP for a specific level and register its base category under recentModules
  Future<void> updateLevelXP(String levelName, int xpToAdd) async {
    User? currentUser = _studentUser;
    if (currentUser == null) return;

    DocumentReference userRef = _db.collection('users').doc(currentUser.uid);

    try {
      await userRef.set({
        'progress': {
          levelName: FieldValue.increment(xpToAdd),
        },
        ..._touchModule(levelName),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating XP: $e');
    }
  }

  /// Add overall XP to the user's profile
  Future<void> addXp(int xpToAdd) async {
    User? currentUser = _studentUser;
    if (currentUser == null) return;

    DocumentReference userRef = _db.collection('users').doc(currentUser.uid);

    try {
      await userRef.set({
        'xp': FieldValue.increment(xpToAdd),
        // Group challenges: counts for today's quests and the Weekly League too.
        ...periodXp(xpToAdd),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error adding overall XP: $e');
    }
  }

  /// Awards [xp] the FIRST time [itemKey] is completed in [moduleKey]
  /// (tutorial sign, practice sign, Lupang Hinirang line). Repeating an item
  /// that is already completed gives the small repeat XP instead, within the
  /// daily cap per category (xp_rewards.dart), so practice is still rewarded
  /// but XP cannot be farmed.
  /// Completed items are kept on the user document as
  /// `tutorialMastery.<moduleKey>.<itemKey> = timestamp` (the tutorial lists
  /// use them for the green "mastered" outline).
  /// Returns the XP actually awarded (0 when the repeat cap is reached or
  /// nobody is signed in).
  Future<int> awardFirstMastery({
    required String moduleKey,
    required String itemKey,
    required int xp,
    required String xpField, // module XP field, e.g. 'alphabetXp'
    bool countsAsLesson = true, // completedLessons (daily quests): tutorials only
  }) async {
    final user = _studentUser;
    final key = itemKey.trim();
    if (key.isEmpty) return 0;
    if (user == null) {
      // Faculty / Parent guest: no XP, but the mastery is kept on the device
      // so the tutorial lists can show the green "mastered" outline.
      if (RoleProvider.guestActive) await _saveGuestMastery(moduleKey, key);
      return 0;
    }
    final userRef = _db.collection('users').doc(user.uid);
    try {
      return await OfflineSync.run<int>((tx) async {
        final snap = await tx.get(userRef);
        final data = snap.data() ?? const <String, dynamic>{};
        final mastery = (data['tutorialMastery'] as Map?)?[moduleKey];
        if (mastery is Map && mastery.containsKey(key)) {
          return _awardRepeat(tx, userRef, data, xpField);
        }
        tx.set(
          userRef,
          {
            ..._xpFields(xpField, xp),
            if (countsAsLesson) 'completedLessons': FieldValue.increment(1),
            'lastActive': FieldValue.serverTimestamp(),
            ..._touchModule(moduleKey),
            'tutorialMastery': {
              moduleKey: {key: FieldValue.serverTimestamp()},
            },
          },
          SetOptions(merge: true),
        );
        return xp;
      });
    } catch (e) {
      debugPrint('Error awarding XP: $e');
      return 0;
    }
  }

  /// Lupang Hinirang tutorial line (kept for existing callers).
  Future<int> awardTutorialLineXp({
    required String moduleKey,
    required String lineKey,
    required int xp,
    required String xpField,
  }) =>
      awardFirstMastery(moduleKey: moduleKey, itemKey: lineKey, xp: xp, xpField: xpField);

  /// Saves an activity level's stars (best score kept). Each NEW star gives
  /// [XpRewards.activityStar]; replaying without beating the best gives the
  /// repeat XP within the daily cap. Returns the XP awarded.
  /// Values above 3 in `progress.<levelId>` are old data (XP that was saved
  /// there by mistake) and count as no stars.
  Future<int> saveActivityStars({
    required String levelId,
    required int stars,
    required String xpField,
  }) async {
    final user = _studentUser;
    if (user == null || levelId.isEmpty) return 0;
    final userRef = _db.collection('users').doc(user.uid);
    final earned = stars.clamp(0, 3);
    try {
      return await OfflineSync.run<int>((tx) async {
        final snap = await tx.get(userRef);
        final data = snap.data() ?? const <String, dynamic>{};
        final progress = data['progress'];
        final raw = progress is Map ? progress[levelId] : null;
        var previous = raw is num ? raw.toInt() : 0;
        if (previous > 3 || previous < 0) previous = 0;
        if (earned <= previous) {
          return earned > 0 ? _awardRepeat(tx, userRef, data, xpField) : 0;
        }
        final newStars = earned - previous;
        final xp = newStars * XpRewards.activityStar;
        tx.set(
          userRef,
          {
            'progress': {levelId: earned},
            'stars': FieldValue.increment(newStars),
            ..._xpFields(xpField, xp),
            'lastActive': FieldValue.serverTimestamp(),
            ..._touchModule(levelId),
          },
          SetOptions(merge: true),
        );
        return xp;
      });
    } catch (e) {
      debugPrint('Error saving activity stars: $e');
      return 0;
    }
  }

  /// XP fields updated together: the module field and the global totals.
  static Map<String, dynamic> _xpFields(String xpField, int xp) => xp <= 0
      ? const {}
      : {
          xpField: FieldValue.increment(xp),
          'xp': FieldValue.increment(xp),
          ...periodXp(xp),
        };

  /// This week's id, e.g. "2026-W46" (ISO weeks: Monday to Sunday).
  static String weekKey([DateTime? when]) {
    final d = DateTime.utc((when ?? DateTime.now()).year, (when ?? DateTime.now()).month, (when ?? DateTime.now()).day);
    final thursday = d.add(Duration(days: 4 - d.weekday)); // the ISO week's year is its Thursday's
    final firstThursday = DateTime.utc(thursday.year, 1, 4);
    final week = 1 + thursday.difference(firstThursday.subtract(Duration(days: firstThursday.weekday - 4))).inDays ~/ 7;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  /// Weekly League field: XP earned this week ("weekXp.2026-W46"). A new
  /// week is a new field, so everyone starts the week at 0 and inactive
  /// students drop off the league by themselves (no reset needed).
  static String weekXpField([DateTime? when]) => 'weekXp.${weekKey(when)}';

  /// This week's XP in a user document (0 if none yet).
  static int weekXpOf(Map<String, dynamic> user) => ((user['weekXp'] as Map?)?[weekKey()] as num?)?.toInt() ?? 0;

  /// Every XP gain also counts for today (daily quests) and this week
  /// (Weekly League). Use in set(..., merge: true) writes.
  static Map<String, dynamic> periodXp(int xp) => xp <= 0
      ? const {}
      : {
          'dailyXp': FieldValue.increment(xp),
          'weeklyXp': FieldValue.increment(xp), // running total (kept for old reports)
          'weekXp': {weekKey(): FieldValue.increment(xp)},
        };

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Repeat XP inside a transaction (or offline batch): [XpRewards.repeat] per repeat, at most
  /// [XpRewards.repeatDailyCap] per category per day. Kept on the user
  /// document as `repeatXp.<xpField> = {date, xp}`.
  int _awardRepeat(SyncTx tx, DocumentReference<Map<String, dynamic>> userRef, Map<String, dynamic> data, String xpField) {
    final today = _today();
    final entry = (data['repeatXp'] as Map?)?[xpField];
    final usedToday = entry is Map && entry['date'] == today ? ((entry['xp'] as num?)?.toInt() ?? 0) : 0;
    final grant = (XpRewards.repeatDailyCap - usedToday).clamp(0, XpRewards.repeat);
    if (grant <= 0) return 0;
    tx.set(
      userRef,
      {
        ..._xpFields(xpField, grant),
        'lastActive': FieldValue.serverTimestamp(),
        'repeatXp': {
          xpField: {'date': today, 'xp': usedToday + grant},
        },
      },
      SetOptions(merge: true),
    );
    return grant;
  }

  /// Mastery key of a sign: lowercase letters / digits only ("Magandang
  /// Umaga" -> "magandangumaga", "A" -> "a", "11" -> "11").
  static String masteryKey(String sign) => sign.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Records that a tutorial sign was mastered (no XP: modules that award
  /// their own XP call this so their tutorial lists can mark the sign).
  Future<void> markTutorialMastered(String moduleKey, String sign) async {
    final user = _studentUser;
    final key = masteryKey(sign);
    if (key.isEmpty) return;
    if (user == null) {
      if (RoleProvider.guestActive) await _saveGuestMastery(moduleKey, key);
      return;
    }
    try {
      await _db.collection('users').doc(user.uid).set({
        'tutorialMastery': {
          moduleKey: {key: FieldValue.serverTimestamp()},
        },
      }, SetOptions(merge: true));
      unawaited(ActivityLog.instance.log('learning.sign_learned',
          category: ActivityCategory.learning,
          title: 'Learned "$sign" in ${ActivityLog.moduleName(moduleKey)}',
          details: {'module': moduleKey, 'sign': sign}));
    } catch (e) {
      debugPrint('Error recording tutorial mastery: $e');
    }
  }

  /// Line keys the user has mastered in a tutorial module (live).
  Stream<Set<String>> masteredTutorialLines(String moduleKey) {
    final user = _studentUser;
    if (user == null) {
      return RoleProvider.guestActive ? _guestMasteryStream(moduleKey) : Stream.value(const {});
    }
    return _db.collection('users').doc(user.uid).snapshots().map((snap) {
      final mastery = (snap.data()?['tutorialMastery'] as Map?)?[moduleKey];
      return mastery is Map ? mastery.keys.map((k) => k.toString()).toSet() : <String>{};
    });
  }

  // ---------------------------------------------------------------------------
  // Guest (Faculty / Parent) mastery: on the device only (SharedPreferences),
  // never in Firestore. Same keys as students' tutorialMastery.<module>.
  // ---------------------------------------------------------------------------

  static String _guestMasteryPref(String moduleKey) => 'guest_mastery_$moduleKey';
  static final StreamController<String> _guestMasteryChanged = StreamController<String>.broadcast();

  Future<void> _saveGuestMastery(String moduleKey, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_guestMasteryPref(moduleKey)) ?? <String>[];
      if (list.contains(key)) return;
      await prefs.setStringList(_guestMasteryPref(moduleKey), [...list, key]);
      _guestMasteryChanged.add(moduleKey);
    } catch (e) {
      debugPrint('Guest mastery not saved: $e');
    }
  }

  static Future<Set<String>> _guestMastery(String moduleKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_guestMasteryPref(moduleKey)) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Stream<Set<String>> _guestMasteryStream(String moduleKey) async* {
    yield await _guestMastery(moduleKey);
    await for (final changed in _guestMasteryChanged.stream) {
      if (changed == moduleKey) yield await _guestMastery(moduleKey);
    }
  }

  /// Stream the user's current progress
  Stream<DocumentSnapshot> getUserProgressStream() {
    User? currentUser = _studentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    return _db.collection('users').doc(currentUser.uid).snapshots();
  }
}