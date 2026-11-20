import 'dart:math';

import '/services/tutorial_session_recorder.dart' show TutorialSessionRecorder;
import '/services/live.dart';
import 'quest_catalog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'progress_service.dart';
import 'offline_sync.dart';

// =============================================================================
// CATALOG
// =============================================================================

/// Challenge tracks. A student gets quests from the track matching their pace
/// plus targeted (skill / explorer) and consistency quests. Each challenge can
/// be completed ONCE; finishing every challenge of a track unlocks its badge.
enum QuestTrack { starter, steady, fast, skill, explorer, consistency }

class QuestTrackInfo {
  final String name;
  final String badgeTitle;
  final String badgeDescription;
  final String badgeImage;
  final IconData icon;
  final Color color;
  const QuestTrackInfo(this.name, this.badgeTitle, this.badgeDescription, this.badgeImage, this.icon, this.color);
}

const Map<QuestTrack, QuestTrackInfo> questTracks = {
  QuestTrack.starter: QuestTrackInfo('Starter', 'First Steps', 'Complete every Starter daily quest.',
      'assets/pictures/star.png', Icons.rocket_launch_rounded, Color(0xFF29B6F6)),
  QuestTrack.steady: QuestTrackInfo('Steady Pace', 'Steady Climber', 'Complete every Steady Pace daily quest.',
      'assets/pictures/practice.png', Icons.spa_rounded, Color(0xFF66BB6A)),
  QuestTrack.fast: QuestTrackInfo('Fast Track', 'Fast Tracker', 'Complete every Fast Track daily quest.',
      'assets/pictures/battle.png', Icons.bolt_rounded, Color(0xFFFF7043)),
  QuestTrack.skill: QuestTrackInfo('Skill Builder', 'Skill Builder', 'Complete every Skill Builder daily quest.',
      'assets/pictures/tutor.png', Icons.fitness_center_rounded, Color(0xFFAB47BC)),
  QuestTrack.explorer: QuestTrackInfo('Explorer', 'Explorer', 'Complete every Explorer daily quest.',
      'assets/pictures/civic.png', Icons.explore_rounded, Color(0xFF26A69A)),
  QuestTrack.consistency: QuestTrackInfo('Consistency', 'Consistency Champ', 'Complete every Consistency daily quest.',
      'assets/pictures/fire.png', Icons.calendar_month_rounded, Color(0xFFFFB300)),
};

/// What a quest counts (computed for TODAY by [DailyChallengeService.todayProgress]).
enum QuestMetric {
  lessons, // tutorial lessons completed (users.completedLessons)
  activities, // activity levels completed
  activitiesInCategory, // activity levels completed in [category]
  categoriesToday, // distinct categories with a completed level
  hardLevels, // hard levels completed
  threeStarLevels, // levels finished with 3 stars
  twoStarLevel, // best stars on a level >= 2 (target 1)
  retriedLevel, // a level completed today that was failed before
  dailyXp,
  correctSigns, // correct camera-sign attempts
  correctSignsInCategory,
  signAccuracy, // % correct signs today (needs >= 10 attempts)
  soloChallenges, // solo arena challenges played
  sessions, // separate study sessions (gap >= 30 min)
  earlyBird, // a level completed before 9 AM (target 1)
  streak, // current day streak
  firstLevelInCategory, // first ever completed level in [category] (target 1)
}

class QuestDef {
  final String id;
  final QuestTrack track;
  final String title;
  final String description;
  final QuestMetric metric;
  final int target;
  final int reward;
  final IconData icon;
  final String? category; // alphabet | numbers | phrases | civic
  const QuestDef(this.id, this.track, this.title, this.description, this.metric, this.target, this.reward, this.icon,
      {this.category});

  QuestTrackInfo get info => questTracks[track]!;
}

const List<String> questCategories = ['alphabet', 'numbers', 'phrases', 'civic'];
const Map<String, String> questCategoryNames = {
  'alphabet': 'Alphabet',
  'numbers': 'Numbers',
  'phrases': 'Greetings',
  'civic': 'Civic',
};

/// Every daily challenge in the app (34). See the summary in the README /
/// the chat for who receives which.
/// The built-in quests (the defaults). The web can edit, switch off or add
/// quests in Firestore `daily_challenges` (services/quest_catalog.dart), so
/// use [questCatalog], which applies those edits.
final List<QuestDef> builtInQuests = [
  // --- Starter: brand-new learners (fewer than 3 completed levels) ---------
  const QuestDef('starter_first_lesson', QuestTrack.starter, 'Your First Lesson',
      'Complete 1 tutorial lesson.', QuestMetric.lessons, 1, 20, Icons.menu_book_rounded),
  const QuestDef('starter_first_level', QuestTrack.starter, 'First Activity',
      'Finish any activity level.', QuestMetric.activities, 1, 30, Icons.flag_rounded),
  const QuestDef('starter_first_signs', QuestTrack.starter, 'Hello, Camera!',
      'Sign 3 gestures correctly in front of the camera.', QuestMetric.correctSigns, 3, 30, Icons.videocam_rounded),
  const QuestDef('starter_two_categories', QuestTrack.starter, 'Look Around',
      'Complete levels in 2 different categories today.', QuestMetric.categoriesToday, 2, 40, Icons.grid_view_rounded),
  const QuestDef('starter_xp_30', QuestTrack.starter, 'Warm Up',
      'Earn 30 XP today.', QuestMetric.dailyXp, 30, 25, Icons.local_fire_department_rounded),

  // --- Steady Pace: slower learners (few levels per day / low completion) --
  const QuestDef('steady_one_level', QuestTrack.steady, 'One Step Today',
      'Finish 1 activity level.', QuestMetric.activities, 1, 25, Icons.directions_walk_rounded),
  const QuestDef('steady_two_lessons', QuestTrack.steady, 'Review Time',
      'Complete 2 tutorial lessons.', QuestMetric.lessons, 2, 30, Icons.auto_stories_rounded),
  const QuestDef('steady_retry', QuestTrack.steady, 'Try Again',
      'Complete a level you did not finish before.', QuestMetric.retriedLevel, 1, 45, Icons.replay_rounded),
  const QuestDef('steady_two_stars', QuestTrack.steady, 'Getting Better',
      'Earn at least 2 stars on a level.', QuestMetric.twoStarLevel, 1, 35, Icons.star_half_rounded),
  const QuestDef('steady_xp_50', QuestTrack.steady, 'Little by Little',
      'Earn 50 XP today.', QuestMetric.dailyXp, 50, 30, Icons.trending_up_rounded),
  const QuestDef('steady_five_signs', QuestTrack.steady, 'Practice Makes Perfect',
      'Sign 5 gestures correctly.', QuestMetric.correctSigns, 5, 35, Icons.back_hand_rounded),
  const QuestDef('steady_two_sessions', QuestTrack.steady, 'Come Back Later',
      'Study in 2 separate sessions today (30+ min apart).', QuestMetric.sessions, 2, 40, Icons.schedule_rounded),

  // --- Fast Track: fast learners (many levels per day, high completion) ----
  const QuestDef('fast_hard_level', QuestTrack.fast, 'Up the Difficulty',
      'Complete a Hard level.', QuestMetric.hardLevels, 1, 80, Icons.terrain_rounded),
  const QuestDef('fast_two_hard', QuestTrack.fast, 'Hard Mode',
      'Complete 2 Hard levels today.', QuestMetric.hardLevels, 2, 120, Icons.landscape_rounded),
  const QuestDef('fast_three_stars', QuestTrack.fast, 'Flawless',
      'Finish 2 levels with 3 stars.', QuestMetric.threeStarLevels, 2, 90, Icons.stars_rounded),
  const QuestDef('fast_five_levels', QuestTrack.fast, 'Marathon',
      'Complete 5 activity levels today.', QuestMetric.activities, 5, 80, Icons.directions_run_rounded),
  const QuestDef('fast_xp_300', QuestTrack.fast, 'XP Rush',
      'Earn 300 XP today.', QuestMetric.dailyXp, 300, 100, Icons.bolt_rounded),
  const QuestDef('fast_fifteen_signs', QuestTrack.fast, 'Sign Sprint',
      'Sign 15 gestures correctly.', QuestMetric.correctSigns, 15, 80, Icons.sign_language_rounded),
  const QuestDef('fast_accuracy_90', QuestTrack.fast, 'Sharp Shooter',
      'Reach 90% sign accuracy today (at least 10 signs).', QuestMetric.signAccuracy, 90, 110, Icons.gps_fixed_rounded),
  const QuestDef('fast_solo_two', QuestTrack.fast, 'Arena Ready',
      'Play 2 Solo Challenges in the Arena.', QuestMetric.soloChallenges, 2, 90, Icons.sports_esports_rounded),

  // --- Skill Builder: the student's weakest category ----------------------
  for (final c in questCategories)
    QuestDef('skill_levels_$c', QuestTrack.skill, 'Strengthen ${questCategoryNames[c]}',
        'Complete 2 ${questCategoryNames[c]} levels today.', QuestMetric.activitiesInCategory, 2, 60,
        Icons.fitness_center_rounded, category: c),
  for (final c in const ['alphabet', 'numbers'])
    QuestDef('skill_signs_$c', QuestTrack.skill, '${questCategoryNames[c]} Signs',
        'Sign 5 ${questCategoryNames[c]} gestures correctly.', QuestMetric.correctSignsInCategory, 5, 60,
        Icons.back_hand_rounded, category: c),

  // --- Explorer: categories the student has not tried yet ----------------
  for (final c in questCategories)
    QuestDef('explore_$c', QuestTrack.explorer, 'Discover ${questCategoryNames[c]}',
        'Complete your first ${questCategoryNames[c]} level.', QuestMetric.firstLevelInCategory, 1, 50,
        Icons.explore_rounded, category: c),

  // --- Consistency: everyone -----------------------------------------------
  const QuestDef('consist_streak_3', QuestTrack.consistency, 'Three in a Row',
      'Reach a 3-day learning streak.', QuestMetric.streak, 3, 50, Icons.local_fire_department_rounded),
  const QuestDef('consist_streak_7', QuestTrack.consistency, 'Week Warrior',
      'Reach a 7-day learning streak.', QuestMetric.streak, 7, 100, Icons.whatshot_rounded),
  const QuestDef('consist_early_bird', QuestTrack.consistency, 'Early Bird',
      'Complete a level before 9:00 AM.', QuestMetric.earlyBird, 1, 40, Icons.wb_twilight_rounded),
  const QuestDef('consist_all_four', QuestTrack.consistency, 'Full Tour',
      'Complete a level in all 4 categories today.', QuestMetric.categoriesToday, 4, 120, Icons.public_rounded),
];

/// The quests students can get now: [builtInQuests] with the web's edits
/// (daily_challenges), switched-off ones left out.
List<QuestDef> get questCatalog => QuestCatalog.instance.apply(builtInQuests);

QuestDef? questById(String id) {
  // Also a switched-off quest (it may have been given today already).
  for (final q in QuestCatalog.instance.apply(builtInQuests, includeInactive: true)) {
    if (q.id == id) return q;
  }
  return null;
}

// =============================================================================
// LEARNER PROFILE
// =============================================================================

enum LearnerPace { starter, steady, balanced, fast }

class LearnerProfile {
  final LearnerPace pace;
  final int activeDays; // of the last 14
  final double levelsPerActiveDay;
  final double levelsPerHour; // within study sessions
  final double completionRate; // completed / attempted levels
  final double? signAccuracy; // last 100 camera signs, 0..1
  final String? weakestCategory;
  final List<String> unexplored;
  final int streak;
  final int totalCompleted;

  const LearnerProfile({
    required this.pace,
    required this.activeDays,
    required this.levelsPerActiveDay,
    required this.levelsPerHour,
    required this.completionRate,
    required this.signAccuracy,
    required this.weakestCategory,
    required this.unexplored,
    required this.streak,
    required this.totalCompleted,
  });

  String get paceLabel => const {
        LearnerPace.starter: 'Getting Started',
        LearnerPace.steady: 'Steady Pace',
        LearnerPace.balanced: 'Balanced',
        LearnerPace.fast: 'Fast Track',
      }[pace]!;

  String get paceReason {
    switch (pace) {
      case LearnerPace.starter:
        return 'You are just beginning, so today\'s quests help you explore HandSpeak.';
      case LearnerPace.steady:
        return 'You learn at a calm pace. These quests build strong habits one step at a time.';
      case LearnerPace.fast:
        return 'You finish levels quickly and accurately. These quests push you further.';
      case LearnerPace.balanced:
        return 'You keep a good rhythm. Today mixes steady practice with a stretch goal.';
    }
  }

  Map<String, dynamic> toMap() => {
        'pace': pace.name,
        'activeDays14': activeDays,
        'levelsPerActiveDay': double.parse(levelsPerActiveDay.toStringAsFixed(2)),
        'levelsPerHour': double.parse(levelsPerHour.toStringAsFixed(2)),
        'completionRate': double.parse(completionRate.toStringAsFixed(3)),
        'signAccuracy': signAccuracy == null ? null : double.parse(signAccuracy!.toStringAsFixed(3)),
        'weakestCategory': weakestCategory,
        'unexplored': unexplored,
        'streak': streak,
        'totalCompleted': totalCompleted,
        'computedAt': FieldValue.serverTimestamp(),
      };

  factory LearnerProfile.fromMap(Map<String, dynamic> m) => LearnerProfile(
        pace: LearnerPace.values.firstWhere((p) => p.name == m['pace'], orElse: () => LearnerPace.balanced),
        activeDays: (m['activeDays14'] as num?)?.toInt() ?? 0,
        levelsPerActiveDay: (m['levelsPerActiveDay'] as num?)?.toDouble() ?? 0,
        levelsPerHour: (m['levelsPerHour'] as num?)?.toDouble() ?? 0,
        completionRate: (m['completionRate'] as num?)?.toDouble() ?? 0,
        signAccuracy: (m['signAccuracy'] as num?)?.toDouble(),
        weakestCategory: m['weakestCategory'] as String?,
        unexplored: List<String>.from(m['unexplored'] ?? const []),
        streak: (m['streak'] as num?)?.toInt() ?? 0,
        totalCompleted: (m['totalCompleted'] as num?)?.toInt() ?? 0,
      );
}

// =============================================================================
// SERVICE
// =============================================================================

class _Attempt {
  final DateTime time;
  final String category;
  final String levelId;
  final bool completed;
  final int stars;

  /// The category as stored (also web categories, e.g. "foods").
  final String rawCategory;
  _Attempt(this.time, this.category, this.levelId, this.completed, this.stars, [this.rawCategory = '']);
  bool get isHard => levelId.contains('hard');
}

/// Camera checks of one record (session) for teacher quests.
class _SignRecord {
  final DateTime time;
  final String rawCategory;
  final Map<String, int> perSign; // SIGN -> correct
  final int correct;
  _SignRecord(this.time, this.rawCategory, this.perSign, this.correct);
}

class _RawData {
  final List<_SignRecord> signs;
  final List<_Attempt> activities;
  _RawData(this.signs, this.activities);
}

class _Sign {
  final DateTime time;
  final String category;
  final bool correct;
  _Sign(this.time, this.category, this.correct);
}

String _categoryOf(String raw) {
  final k = raw.toLowerCase();
  if (k.contains('number')) return 'numbers';
  if (k.contains('phrase') || k.contains('word') || k.contains('common')) return 'phrases';
  if (k.contains('civic')) return 'civic';
  return 'alphabet';
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class DailyChallengeService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String get _uid {
    final u = FirebaseAuth.instance.currentUser;
    return u == null || u.isAnonymous ? '' : u.uid; // guests have no quests
  }
  DocumentReference<Map<String, dynamic>> get _userRef => _db.collection('users').doc(_uid);

  static const int questsPerDay = 3;
  static const Duration _sessionGap = Duration(minutes: 30);

  // ---------------------------------------------------------------- data ---
  /// Activity plays: activity_sessions (current records), plus the older
  /// activity_attempts for earlier history. A play saved in both (while both
  /// were written) counts once.
  // The student's play / camera records change only while they play, not when
  // a quest is claimed. Every refresh used to download and parse ALL of them
  // on the main thread (the app froze ~5 s on a claim: "Skipped 306 frames",
  // ANR). Now each list is read once and reused for [_recordsFor], shared by
  // the daily quests and the teacher quests. [forget] starts fresh (screen
  // opened again).
  static const Duration _recordsFor = Duration(minutes: 2);
  static final Map<String, (DateTime, Future<Object>)> _records = {};

  Future<T> _cached<T extends Object>(String name, Future<T> Function() read) {
    final key = '$_uid|$name';
    final hit = _records[key];
    if (hit != null && DateTime.now().difference(hit.$1) < _recordsFor) return hit.$2.then((v) => v as T);
    final f = read();
    _records[key] = (DateTime.now(), f);
    // A failed read is forgotten (read again next time). The error itself
    // goes to the caller through [f]; this listener must not pass it on (it
    // did: "Uncaught error: PERMISSION_DENIED" stopped the app on Arena).
    f.then<void>((_) {}, onError: (Object _) => _records.remove(key));
    return f;
  }

  /// Read the records again on the next refresh (e.g. Daily Quests opened).
  static void forget() {
    _records.clear();
    _raw = null;
  }

  Future<List<_Attempt>> _activityAttempts() => _cached('activities', _readActivityAttempts);
  Future<List<_Sign>> _signAttempts() => _cached('signs', _readSignAttempts);

  Future<List<_Attempt>> _readActivityAttempts() async {
    final out = <_Attempt>[];
    final seen = <String>{};
    for (final col in ['activity_sessions', 'activity_attempts']) {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _db.collection(col).where('userId', isEqualTo: _uid).get();
      } catch (e) {
        debugPrint('Daily quests: $col unavailable: $e');
        continue;
      }
      for (final d in snap.docs) {
        final m = d.data();
        final ts = m['timestamp'];
        if (ts is! Timestamp) continue;
        final level = '${m['levelId'] ?? ''}';
        // Same level within a minute = the same play.
        final id = '$level|${ts.toDate().millisecondsSinceEpoch ~/ 60000}';
        if (!seen.add(id)) continue;
        out.add(_Attempt(ts.toDate(), _categoryOf('${m['category'] ?? level}'), level, m['isCompleted'] == true,
            (m['starsEarned'] as num?)?.toInt() ?? 0, '${m['category'] ?? level}'));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  /// Camera-sign attempts from `gesture_attempts`: session reports (level,
  /// results.attempts / correct, session.endedAt) and older flat attempt
  /// documents (isCorrect, timestamp). One query by `userId`, the field the
  /// rules check (a query by `student.userId` was refused: PERMISSION_DENIED).
  Future<List<_Sign>> _readSignAttempts() async {
    final out = <_Sign>[];
    final docs = await _db.collection('gesture_attempts').where('userId', isEqualTo: _uid).get();
    for (final d in docs.docs) {
      final m = d.data();
      final session = m['session'], results = m['results'], level = m['level'];
      if (session is Map && results is Map) {
        final ts = session['endedAt'] ?? session['startedAt'];
        if (ts is! Timestamp) continue;
        final cat = _categoryOf('${level is Map ? level['category'] ?? level['levelId'] : ''}');
        final attempts = (results['attempts'] as num?)?.toInt() ?? 0;
        final correct = (results['correct'] as num?)?.toInt() ?? 0;
        for (int i = 0; i < attempts; i++) {
          out.add(_Sign(ts.toDate(), cat, i < correct));
        }
        continue;
      }
      final type = m['recordType'];
      if (type != null && type != 'attempt') continue;
      final ts = m['timestamp'];
      if (ts is! Timestamp) continue;
      out.add(_Sign(ts.toDate(), _categoryOf('${m['category'] ?? m['levelId'] ?? ''}'), m['isCorrect'] == true));
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  /// Solo games since [start]: the root solo_challenges records, plus older
  /// games kept in users/{uid}/progress_history (written before 2026-11-11).
  Future<int> _soloChallengesToday(DateTime start) async {
    int count(Iterable<Map<String, dynamic>> docs) => docs.where((d) {
          final ts = d['completedAt'];
          return ts is Timestamp && !ts.toDate().isBefore(start);
        }).length;
    var n = 0;
    try {
      final snap = await _db.collection('solo_challenges').where('userId', isEqualTo: _uid).get();
      n += count(snap.docs.map((d) => d.data()));
    } catch (_) {}
    try {
      final snap = await _userRef.collection('progress_history').where('mode', isEqualTo: 'solo_challenge').get();
      n += count(snap.docs.map((d) => d.data()));
    } catch (_) {}
    return n;
  }

  static int _sessionsIn(List<DateTime> times) {
    if (times.isEmpty) return 0;
    int n = 1;
    for (int i = 1; i < times.length; i++) {
      if (times[i].difference(times[i - 1]) >= _sessionGap) n++;
    }
    return n;
  }

  // ------------------------------------------------------------- profile ---
  /// Profiles the learner from the last 14 days of activity.
  Future<LearnerProfile> analyze(Map<String, dynamic> user) async {
    final attempts = await _activityAttempts();
    List<_Sign> signs = const [];
    try {
      signs = await _signAttempts();
    } catch (_) {}
    final now = DateTime.now();
    final since = now.subtract(const Duration(days: 14));
    final recent = attempts.where((a) => a.time.isAfter(since)).toList();
    final completedAll = attempts.where((a) => a.completed).toList();
    final completedRecent = recent.where((a) => a.completed).toList();

    final activeDays = {for (final a in recent) dayKey(a.time)}.length;
    final perDay = activeDays == 0 ? 0.0 : completedRecent.length / activeDays;
    final completion = recent.isEmpty ? 0.0 : completedRecent.length / recent.length;

    // Levels per hour inside study sessions (each level ~ counts its gap).
    double studyHours = 0;
    int counted = 0;
    for (int i = 1; i < recent.length; i++) {
      final gap = recent[i].time.difference(recent[i - 1].time);
      if (gap < _sessionGap) {
        studyHours += gap.inSeconds / 3600.0;
        if (recent[i].completed) counted++;
      }
    }
    final perHour = studyHours < 0.05 ? 0.0 : counted / studyHours;

    // Sign accuracy: last 100 camera attempts.
    final lastSigns = signs.length > 100 ? signs.sublist(signs.length - 100) : signs;
    final accuracy = lastSigns.length < 5 ? null : lastSigns.where((s) => s.correct).length / lastSigns.length;

    // Category strength: completion rate + sign accuracy per category.
    final explored = <String>{
      for (final a in completedAll) a.category,
      ...((user['progress'] as Map?)?.keys.map((k) => _categoryOf('$k')) ?? const <String>[]),
    };
    final unexplored = [for (final c in questCategories) if (!explored.contains(c)) c];
    String? weakest;
    double weakestScore = 2;
    for (final c in explored) {
      final cat = attempts.where((a) => a.category == c).toList();
      if (cat.isEmpty) continue;
      final comp = cat.where((a) => a.completed).length / cat.length;
      final stars = cat.where((a) => a.completed).fold<int>(0, (s, a) => s + a.stars) /
          max(1, cat.where((a) => a.completed).length) / 3.0;
      final cs = signs.where((s) => s.category == c).toList();
      final acc = cs.length < 5 ? null : cs.where((s) => s.correct).length / cs.length;
      final score = acc == null ? (comp + stars) / 2 : (comp + stars + acc) / 3;
      if (score < weakestScore) {
        weakestScore = score;
        weakest = c;
      }
    }

    final streak = (user['streak'] as num?)?.toInt() ?? 0;
    final LearnerPace pace;
    if (completedAll.length < 3) {
      pace = LearnerPace.starter;
    } else if (perDay >= 5 || (perHour >= 6 && completion >= 0.75) || (perDay >= 3.5 && completion >= 0.85)) {
      pace = LearnerPace.fast;
    } else if (perDay < 2 || completion < 0.6) {
      pace = LearnerPace.steady;
    } else {
      pace = LearnerPace.balanced;
    }

    return LearnerProfile(
      pace: pace,
      activeDays: activeDays,
      levelsPerActiveDay: perDay,
      levelsPerHour: perHour,
      completionRate: completion,
      signAccuracy: accuracy,
      weakestCategory: weakest,
      unexplored: unexplored,
      streak: streak,
      totalCompleted: completedAll.length,
    );
  }

  // ----------------------------------------------------------- selection ---
  /// Picks today's quests: one for the learner's pace, one targeted at their
  /// weakest / untried category, one bonus. Already-completed quests are
  /// never offered again. Deterministic for the day (stable on reopen).
  static List<QuestDef> select(LearnerProfile p, Set<String> completed, DateTime day, String uid) {
    final rng = Random(dayKey(day).hashCode ^ uid.hashCode);
    List<QuestDef> pool(bool Function(QuestDef q) test) =>
        (questCatalog.where((q) => !completed.contains(q.id) && test(q)).toList()..shuffle(rng));

    bool eligible(QuestDef q) {
      switch (q.metric) {
        case QuestMetric.firstLevelInCategory:
          return p.unexplored.contains(q.category);
        default:
          return true;
      }
    }

    final picked = <QuestDef>[];
    void take(List<QuestDef> from) {
      for (final q in from) {
        if (picked.length >= questsPerDay) return;
        if (!picked.any((x) => x.id == q.id) && eligible(q)) {
          picked.add(q);
          return;
        }
      }
    }

    final paceTracks = switch (p.pace) {
      LearnerPace.starter => [QuestTrack.starter],
      LearnerPace.steady => [QuestTrack.steady],
      LearnerPace.fast => [QuestTrack.fast],
      LearnerPace.balanced => rng.nextBool() ? [QuestTrack.steady, QuestTrack.fast] : [QuestTrack.fast, QuestTrack.steady],
    };

    // 1. Pace quest.
    take(pool((q) => q.track == paceTracks.first));
    // 2. Targeted: untried category (explorer) or weakest category (skill).
    final explorer = pool((q) => q.track == QuestTrack.explorer);
    final skill = pool((q) => q.track == QuestTrack.skill && q.category == p.weakestCategory);
    if (explorer.isNotEmpty && (skill.isEmpty || rng.nextBool())) {
      take(explorer);
    } else {
      take(skill);
    }
    // 3. Bonus: newer learners finish the Starter set first (so its badge stays
    //    reachable); balanced -> the other pace track; else consistency / pace.
    if (p.pace != LearnerPace.starter && p.totalCompleted < 15) take(pool((q) => q.track == QuestTrack.starter));
    if (p.pace == LearnerPace.balanced) take(pool((q) => q.track == paceTracks.last));
    take(rng.nextBool() ? pool((q) => q.track == QuestTrack.consistency) : pool((q) => q.track == paceTracks.first));
    // Fill from anything suitable still left.
    while (picked.length < questsPerDay) {
      final before = picked.length;
      take(pool((q) => q.track == paceTracks.first));
      take(pool((q) => q.track == QuestTrack.consistency || q.track == QuestTrack.skill));
      take(pool((q) => q.track != QuestTrack.starter || p.pace == LearnerPace.starter));
      if (picked.length == before) break; // catalog exhausted for this learner
    }
    return picked;
  }

  /// Ensures today's personalised quests exist on the user document
  /// (`dailyChallenges`, `dailyChallengesDate`, `learnerProfile`).
  Future<void> ensureTodayQuests({bool force = false}) async {
    if (_uid.isEmpty) return;
    final snap = await _userRef.get();
    final user = snap.data() ?? {};
    final today = DateTime.now();
    if (!force && user['dailyChallengesDate'] == dayKey(today) && user['dailyChallenges'] is List) return;

    final profile = await analyze(user);
    final completed = Set<String>.from(user['completedDailyChallenges'] ?? const []);
    final quests = select(profile, completed, today, _uid);
    await _userRef.set({
      'dailyChallengesDate': dayKey(today),
      'dailyChallenges': [
        for (final q in quests)
          {
            'id': q.id,
            'title': q.title,
            'description': q.description,
            'track': q.track.name,
            'target': q.target,
            'reward': q.reward,
          }
      ],
      'learnerProfile': profile.toMap(),
    }, SetOptions(merge: true));
  }

  // ------------------------------------------------------------ progress ---
  /// Today's value for every metric.
  Future<Map<QuestMetric, int>> todayProgress(Map<String, dynamic> user, {Set<String> categoriesFor = const {}}) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final attempts = await _activityAttempts();
    List<_Sign> signs = const [];
    try {
      signs = await _signAttempts();
    } catch (_) {}
    final today = attempts.where((a) => !a.time.isBefore(start)).toList();
    final done = today.where((a) => a.completed).toList();
    final signsToday = signs.where((s) => !s.time.isBefore(start)).toList();

    final failedBefore = {for (final a in attempts) if (!a.completed && a.time.isBefore(start)) a.levelId};
    final completedBeforeToday = {for (final a in attempts) if (a.completed && a.time.isBefore(start)) a.category};

    final m = <QuestMetric, int>{
      QuestMetric.lessons: (user['completedLessons'] as num?)?.toInt() ?? 0,
      QuestMetric.activities: done.length,
      QuestMetric.categoriesToday: {for (final a in done) a.category}.length,
      QuestMetric.hardLevels: done.where((a) => a.isHard).length,
      QuestMetric.threeStarLevels: {for (final a in done) if (a.stars >= 3) a.levelId}.length,
      QuestMetric.twoStarLevel: done.any((a) => a.stars >= 2) ? 1 : 0,
      QuestMetric.retriedLevel: done.any((a) => failedBefore.contains(a.levelId) ||
              today.any((b) => !b.completed && b.levelId == a.levelId && b.time.isBefore(a.time)))
          ? 1
          : 0,
      QuestMetric.dailyXp: (user['dailyXp'] as num?)?.toInt() ?? 0,
      QuestMetric.correctSigns: signsToday.where((s) => s.correct).length,
      QuestMetric.signAccuracy: signsToday.length < 10
          ? 0
          : (signsToday.where((s) => s.correct).length * 100 ~/ signsToday.length),
      QuestMetric.soloChallenges: await _soloChallengesToday(start),
      QuestMetric.sessions: _sessionsIn([for (final a in today) a.time]),
      QuestMetric.earlyBird: done.any((a) => a.time.hour < 9) ? 1 : 0,
      QuestMetric.streak: (user['streak'] as num?)?.toInt() ?? 0,
    };
    // Category-specific metrics are keyed per quest via [progressFor].
    _categoryDone = {for (final c in questCategories) c: done.where((a) => a.category == c).length};
    _categorySigns = {for (final c in questCategories) c: signsToday.where((s) => s.correct && s.category == c).length};
    _firstInCategory = {
      for (final c in questCategories) c: (!completedBeforeToday.contains(c) && done.any((a) => a.category == c)) ? 1 : 0
    };
    return m;
  }

  Map<String, int> _categoryDone = {};
  Map<String, int> _categorySigns = {};
  Map<String, int> _firstInCategory = {};

  /// Current value of [q]'s metric (call after [todayProgress]).
  int progressFor(QuestDef q, Map<QuestMetric, int> m) {
    switch (q.metric) {
      case QuestMetric.activitiesInCategory:
        return _categoryDone[q.category] ?? 0;
      case QuestMetric.correctSignsInCategory:
        return _categorySigns[q.category] ?? 0;
      case QuestMetric.firstLevelInCategory:
        return _firstInCategory[q.category] ?? 0;
      default:
        return m[q.metric] ?? 0;
    }
  }

  // ------------------------------------------------------------ analytics ---
  /// Web dashboard analytics: one document per student per day,
  /// `daily_quest_sessions/{uid}_{day}`:
  ///
  ///   userId, sectionId, day ("2026-11-20"), learnerPace,
  ///   quests: [{ id, title, track, category, metric, target, progress,
  ///              percent, completed (progress >= target), claimed, reward }],
  ///   assignedCount, completedCount, claimedCount, xpEarned,
  ///   allClaimed, updatedAt, expireAt (+365 days, Firestore TTL)
  ///
  /// Written when the day's quests are shown and again only when something
  /// changed (progress, completion, claim), so it costs a few writes a day.
  static const String sessionsCollection = 'daily_quest_sessions';
  static String? _lastRecorded;

  Future<void> recordDay({
    required List<QuestDef> quests,
    required Map<QuestMetric, int>? metrics,
    required Set<String> claimedIds,
    required Map<String, dynamic> user,
  }) async {
    if (_uid.isEmpty || quests.isEmpty) return;
    final day = dayKey(DateTime.now());
    final rows = [
      for (final q in quests)
        () {
          final progress = metrics == null ? 0 : progressFor(q, metrics).clamp(0, 1 << 30);
          final done = progress >= q.target;
          return <String, dynamic>{
            'id': q.id,
            'title': q.title,
            'track': q.track.name,
            if (q.category != null) 'category': q.category,
            'metric': q.metric.name,
            'target': q.target,
            'progress': progress > q.target ? q.target : progress,
            'percent': q.target <= 0 ? 0 : ((progress > q.target ? q.target : progress) * 100 ~/ q.target),
            'completed': done,
            'claimed': claimedIds.contains(q.id),
            'reward': q.reward,
          };
        }(),
    ];
    // Only when something changed (no write for the same numbers).
    final signature = '$_uid|$day|${[for (final r in rows) '${r['id']}:${r['progress']}:${r['claimed']}'].join(',')}';
    if (signature == _lastRecorded) return;
    _lastRecorded = signature;
    final claimed = rows.where((r) => r['claimed'] == true).toList();
    final section = (user['section'] ?? user['sectionId'] ?? '').toString().trim();
    final pace = (user['learnerProfile'] is Map) ? (user['learnerProfile'] as Map)['pace'] : null;
    try {
      await FirebaseFirestore.instance.collection(sessionsCollection).doc('${_uid}_$day').set({
        'userId': _uid,
        if (section.isNotEmpty) 'sectionId': section,
        'day': day,
        'learnerPace': ?pace,
        'quests': rows,
        'assignedCount': rows.length,
        'completedCount': rows.where((r) => r['completed'] == true).length,
        'claimedCount': claimed.length,
        'xpEarned': claimed.fold<int>(0, (total, r) => total + (r['reward'] as int)),
        'allClaimed': claimed.length == rows.length,
        'updatedAt': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 365))),
      }, SetOptions(merge: true));
    } catch (e) {
      _lastRecorded = null; // try again next time
      debugPrint('$sessionsCollection: not saved: $e');
    }
  }

  // ------------------------------------------------------- teacher quests ---
  // Quests a teacher sends from the web: users/{uid}/assigned_quests/{id}
  // (spec: docs/teacher-assigned-quests.md in the web repo). Extra to the
  // student's 3 daily quests (select() is not involved), at most 3 shown,
  // counted from assignedAt (a quest can last up to 7 days), never from the
  // title / description. On claim only status + completedAt change on the
  // quest (the rules reject anything else).

  static const String teacherCollection = 'assigned_quests';
  static const int maxTeacherQuests = 3;

  /// Metrics a teacher quest may use; any other metric hides the quest.
  static const Set<String> teacherMetrics = {
    'correctSignsOfSign',
    'levelPassed',
    'correctSignsInCategory',
    'activitiesInCategory',
    'activities',
    'retriedLevel',
    'twoStarLevel',
    'lessons',
    'sessions',
  };

  /// The live active teacher quests (status == 'active').
  Stream<QuerySnapshot<Map<String, dynamic>>> teacherQuests() =>
      Live.query(_userRef.collection(teacherCollection).where('status', isEqualTo: 'active'));

  /// Still open today: expiresDay (YYYY-MM-DD, Manila time) is today or later,
  /// and the metric is one the app can count.
  static bool teacherQuestOpen(Map<String, dynamic> q) {
    if (!teacherMetrics.contains('${q['metric'] ?? ''}')) return false;
    final expires = '${q['expiresDay'] ?? ''}'.trim();
    if (expires.isEmpty) return true;
    return expires.compareTo(_manilaToday()) >= 0; // YYYY-MM-DD compares as text
  }

  static String _manilaToday() => dayKey(DateTime.now().toUtc().add(const Duration(hours: 8)));

  /// The quest as a card (the same card as the daily quests).
  static QuestDef teacherQuestDef(String id, Map<String, dynamic> q) {
    final target = (q['target'] as num?)?.toInt() ?? 1;
    final metric = '${q['metric'] ?? ''}';
    return QuestDef(
      id,
      QuestTrack.skill,
      '${q['title'] ?? 'Teacher quest'}',
      '${q['description'] ?? ''}',
      // Only for the card's display (percent or count); progress comes from
      // [teacherProgress].
      QuestMetric.correctSigns,
      target <= 0 ? 1 : target,
      (q['reward'] as num?)?.toInt() ?? 0,
      metric == 'levelPassed' ? Icons.replay_rounded : Icons.school_rounded,
      category: (q['category'] as String?)?.trim().isEmpty ?? true ? null : '${q['category']}'.trim(),
    );
  }

  // Raw records (read at most once a minute while quests are shown).
  static DateTime _rawAt = DateTime(2000);
  static Future<_RawData>? _raw;

  Future<_RawData> _rawData() {
    if (_raw == null || DateTime.now().difference(_rawAt) > _recordsFor) {
      _rawAt = DateTime.now();
      _raw = _readRaw().catchError((Object e) {
        _raw = null;
        throw e;
      });
    }
    return _raw!;
  }

  Future<_RawData> _readRaw() async {
    final signs = <_SignRecord>[];
    Future<void> read(Query<Map<String, dynamic>> q, {required bool session}) async {
      try {
        for (final d in (await q.get()).docs) {
          final m = d.data();
          final s = m['session'];
          final ts = (s is Map ? s['endedAt'] ?? s['startedAt'] : null) ?? m['updatedAt'] ?? m['timestamp'];
          if (ts is! Timestamp) continue;
          final level = m['level'];
          final rawCat = '${level is Map ? level['category'] ?? level['levelId'] ?? '' : m['category'] ?? ''}';
          final perSign = <String, int>{};
          final rows = m['signs'];
          if (rows is Map) {
            rows.forEach((k, v) {
              if (v is Map) perSign['$k'.toUpperCase()] = (v['correct'] as num?)?.toInt() ?? 0;
            });
          }
          final results = m['results'];
          final correct = results is Map
              ? (results['correct'] as num?)?.toInt() ?? 0
              : (m['isCorrect'] == true ? 1 : perSign.values.fold<int>(0, (a, b) => a + b));
          if (!session && m['isCorrect'] == true && m['sign'] != null) {
            perSign['${m['sign']}'.toUpperCase()] = (perSign['${m['sign']}'.toUpperCase()] ?? 0) + 1;
          }
          signs.add(_SignRecord(ts.toDate(), rawCat, perSign, correct));
        }
      } catch (e) {
        debugPrint('Teacher quests: records unavailable: $e');
      }
    }

    // Camera checks: activity camera levels, Practice Sessions, Tutorial Practice.
    await Future.wait([
      read(_db.collection('gesture_attempts').where('userId', isEqualTo: _uid), session: true),
      read(_db.collection('tutorial_sessions').where('userId', isEqualTo: _uid), session: true),
      read(_db.collection('tutorial_practice_sessions').where('userId', isEqualTo: _uid), session: true),
    ]);
    return _RawData(signs, await _activityAttempts());
  }

  static String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
  static bool _sameCategory(String raw, String? quest) {
    if (quest == null || quest.trim().isEmpty) return true;
    final a = _norm(raw), b = _norm(quest);
    return a.isNotEmpty && (a == b || a.contains(b) || b.contains(a));
  }

  /// Progress of a teacher quest: actions at or after assignedAt only.
  /// null when the metric is unknown.
  Future<int?> teacherProgress(Map<String, dynamic> q, Map<String, dynamic> user) async {
    final metric = '${q['metric'] ?? ''}';
    if (!teacherMetrics.contains(metric)) return null;
    final at = q['assignedAt'];
    final since = at is Timestamp ? at.toDate() : DateTime.now();
    final category = (q['category'] as String?)?.trim();
    final data = await _rawData();
    final signs = data.signs.where((r) => !r.time.isBefore(since)).toList();
    final acts = data.activities.where((a) => !a.time.isBefore(since)).toList();
    final done = acts.where((a) => a.completed).toList();

    switch (metric) {
      case 'correctSignsOfSign':
        final key = TutorialSessionRecorder.signKey('${q['sign'] ?? ''}');
        if (key.isEmpty) return 0;
        return signs.where((r) => _sameCategory(r.rawCategory, category)).fold<int>(0, (n, r) => n + (r.perSign[key] ?? 0));
      case 'levelPassed':
        final level = '${q['levelId'] ?? ''}'.trim().toLowerCase();
        return done.any((a) => a.levelId.trim().toLowerCase() == level) ? 1 : 0;
      case 'correctSignsInCategory':
        return signs.where((r) => _sameCategory(r.rawCategory, category)).fold<int>(0, (n, r) => n + r.correct);
      case 'activitiesInCategory':
        return done.where((a) => _sameCategory(a.rawCategory, category)).length;
      case 'activities':
        return done.length;
      case 'retriedLevel':
        // Levels passed (since assignedAt) that were failed before, at any time.
        final all = data.activities;
        return {
          for (final a in done)
            if (all.any((b) => !b.completed && b.levelId == a.levelId && b.time.isBefore(a.time))) a.levelId,
        }.length;
      case 'twoStarLevel':
        return {for (final a in done) if (a.stars >= 2) a.levelId}.length;
      case 'lessons':
        // Lessons mastered after assignedAt (tutorialMastery.<module>.<sign> = time).
        var n = 0;
        final mastery = user['tutorialMastery'];
        if (mastery is Map) {
          for (final module in mastery.values) {
            if (module is! Map) continue;
            for (final t in module.values) {
              if (t is Timestamp && !t.toDate().isBefore(since)) n++;
            }
          }
        }
        return n;
      case 'sessions':
        return _sessionsIn([for (final a in acts) a.time, for (final r in signs) r.time]);
    }
    return null;
  }

  /// Claims a finished teacher quest: the quest gets ONLY status + completedAt
  /// (the rules reject anything else), the history gets an entry like a normal
  /// quest (+ source 'teacher', rxKey), and the reward XP is added like a
  /// normal quest. Not added to completedDailyChallenges / track badges.
  Future<bool> claimTeacherQuest(DocumentReference<Map<String, dynamic>> questRef, Map<String, dynamic> q) async {
    if (_uid.isEmpty) return false;
    final historyRef = _userRef.collection('daily_challenge_history').doc(questRef.id);
    final reward = (q['reward'] as num?)?.toInt() ?? 0;
    final category = (q['category'] as String?)?.trim();
    try {
      return await OfflineSync.run<bool>((tx) async {
        final existing = await tx.get(historyRef);
        if (existing.exists) return false; // claimed once
        final userSnap = await tx.get(_userRef);
        final moduleField = ProgressService.moduleXpField(category).isNotEmpty
            ? ProgressService.moduleXpField(category)
            : ProgressService.currentModuleXpField(userSnap.data());
        tx.update(questRef, {'status': 'completed', 'completedAt': FieldValue.serverTimestamp()});
        tx.set(historyRef, {
          'challengeId': questRef.id,
          'title': q['title'],
          'description': q['description'],
          'track': 'teacher',
          'category': category,
          'target': q['target'],
          'reward': reward,
          'day': dayKey(DateTime.now()),
          'source': 'teacher',
          'rxKey': q['rxKey'],
          'completedAt': FieldValue.serverTimestamp(),
        });
        if (reward > 0) {
          tx.set(
              _userRef,
              {
                'xp': FieldValue.increment(reward),
                ...ProgressService.periodXp(reward),
                moduleField: FieldValue.increment(reward),
                'lastActive': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
        }
        return true;
      });
    } catch (e) {
      debugPrint('Teacher quest claim failed: $e');
      return false;
    }
  }

  // --------------------------------------------------------------- claim ---
  /// Records a completed quest once: history entry + reward XP.
  Future<bool> claim(QuestDef q, {LearnerProfile? profile}) async {
    if (_uid.isEmpty) return false;
    final historyRef = _userRef.collection('daily_challenge_history').doc(q.id);
    try {
      return await OfflineSync.run<bool>((tx) async {
        final existing = await tx.get(historyRef);
        if (existing.exists) return false; // each quest counts once
        // Module XP: a category quest feeds its category; a general quest feeds
        // the module being worked toward, so quests help unlock the next one.
        final userSnap = await tx.get(_userRef);
        final moduleField = ProgressService.moduleXpField(q.category).isNotEmpty
            ? ProgressService.moduleXpField(q.category)
            : ProgressService.currentModuleXpField(userSnap.data());
        tx.set(historyRef, {
          'challengeId': q.id,
          'title': q.title,
          'description': q.description,
          'track': q.track.name,
          'category': q.category,
          'target': q.target,
          'reward': q.reward,
          'day': dayKey(DateTime.now()),
          'learnerPace': profile?.pace.name,
          'completedAt': FieldValue.serverTimestamp(),
        });
        tx.set(
            _userRef,
            {
              'completedDailyChallenges': FieldValue.arrayUnion([q.id]),
              'dailyChallengesCompletedCount': FieldValue.increment(1),
              'xp': FieldValue.increment(q.reward),
              ...ProgressService.periodXp(q.reward),
              moduleField: FieldValue.increment(q.reward),
              // The Weekly League reads this week's active students.
              'lastActive': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
        return true;
      });
    } catch (e) {
      debugPrint('Daily quest claim failed: $e');
      return false;
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> historyStream() =>
      _userRef.collection('daily_challenge_history').orderBy('completedAt', descending: true).snapshots();

  /// Completed / total quests per track (for badges). Explorer quests are
  /// only offered for untried categories, so a category the student already
  /// explored on their own also counts as done ([unexplored] = the
  /// learnerProfile's list; null = unknown, count only claimed quests).
  static Map<QuestTrack, (int, int)> trackProgress(Iterable<String> completedIds, {List<String>? unexplored}) {
    final done = completedIds.toSet();
    bool isDone(QuestDef q) =>
        done.contains(q.id) ||
        (q.track == QuestTrack.explorer && unexplored != null && !unexplored.contains(q.category));
    return {
      for (final t in QuestTrack.values)
        t: (
          questCatalog.where((q) => q.track == t && isDone(q)).length,
          questCatalog.where((q) => q.track == t).length,
        )
    };
  }
}
