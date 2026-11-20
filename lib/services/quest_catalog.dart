import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'daily_challenge_service.dart';

/// Daily quest definitions ("conditions") managed from the web, exactly like
/// badges (Firestore collection `daily_challenges`, one document per quest;
/// see BadgeCatalog). The app's built-in quests are the defaults; a document
/// overrides the built-in quest with the same id, `active: false` takes it
/// out of the daily picks, and a document with a new id and a known metric
/// adds a quest. Live: changes reach the app without an update.
///
/// daily_challenges/{id}  (id = the built-in quest id, e.g. "starter_first_lesson")
///   title        "Your First Lesson"
///   description  "Complete 1 tutorial lesson."
///   track        starter | steady | fast | skill | explorer | consistency
///   metric       what is counted (see [QuestCatalog.metrics])
///   target       number to reach, e.g. 1
///   reward       XP when claimed, e.g. 20
///   category     alphabet | numbers | phrases | civic (category quests only)
///   order        sort position, optional
///   active       false: not given to students any more
///
/// Uploaded first from the app's built-in list with
/// tools/seed_daily_challenges.py (the rules let only the Admin SDK write).
class QuestCatalog {
  QuestCatalog._();
  static final QuestCatalog instance = QuestCatalog._();

  static const String collection = 'daily_challenges';

  /// What a quest can count (the `metric` field), with a description for
  /// the web form. Computed for TODAY by DailyChallengeService.todayProgress.
  static const Map<String, String> metrics = {
    'lessons': 'Tutorial lessons completed (in total)',
    'activities': 'Activity levels completed today',
    'activitiesInCategory': 'Activity levels completed today in the category',
    'categoriesToday': 'Different categories with a completed level today',
    'hardLevels': 'Hard levels completed today',
    'threeStarLevels': 'Levels finished with 3 stars today',
    'twoStarLevel': 'A level finished with 2+ stars today (target 1)',
    'retriedLevel': 'A level completed today that was failed before (target 1)',
    'dailyXp': 'XP earned today',
    'correctSigns': 'Correct camera signs today',
    'correctSignsInCategory': 'Correct camera signs today in the category',
    'signAccuracy': '% of camera signs correct today (needs 10+ signs)',
    'soloChallenges': 'Solo Challenges played today',
    'sessions': 'Separate study sessions today (30+ min apart)',
    'earlyBird': 'A level completed before 9:00 AM (target 1)',
    'streak': 'Current learning streak (days)',
    'firstLevelInCategory': 'First ever completed level in the category (target 1)',
  };

  /// Latest quest documents by id (empty until loaded / when none exist).
  final ValueNotifier<Map<String, Map<String, dynamic>>> docs = ValueNotifier(const {});
  StreamSubscription? _sub;

  /// Starts listening (once).
  void start() {
    _sub ??= FirebaseFirestore.instance.collection(collection).snapshots().listen(
      (snap) => docs.value = {for (final d in snap.docs) d.id: d.data()},
      onError: (Object e) => debugPrint('daily_challenges catalog unavailable: $e'),
    );
  }

  /// The quests with the web's edits applied. [includeInactive]: also the
  /// switched-off ones (to show a quest already given today).
  List<QuestDef> apply(List<QuestDef> builtIn, {bool includeInactive = false}) {
    final d = docs.value;
    final out = <(QuestDef, num)>[];
    var pos = 0;
    for (final q in builtIn) {
      pos++;
      final doc = d[q.id];
      if (doc == null) {
        out.add((q, pos));
        continue;
      }
      if (doc['active'] == false && !includeInactive) continue;
      out.add((_merge(q, doc), (doc['order'] as num?) ?? pos));
    }
    // Quests added on the web (a new id with a known metric and track).
    for (final e in d.entries) {
      if (builtIn.any((q) => q.id == e.key)) continue;
      if (e.value['active'] == false && !includeInactive) continue;
      final added = _fromDoc(e.key, e.value);
      if (added != null) out.add((added, (e.value['order'] as num?) ?? ++pos));
    }
    out.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final e in out) e.$1];
  }

  static QuestMetric? _metric(Object? v) => QuestMetric.values.where((m) => m.name == '${v ?? ''}'.trim()).firstOrNull;
  static QuestTrack? _track(Object? v) => QuestTrack.values.where((t) => t.name == '${v ?? ''}'.trim()).firstOrNull;
  static int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());
  static String? _text(Object? v) => '${v ?? ''}'.trim().isEmpty ? null : '$v'.trim();

  static QuestDef _merge(QuestDef q, Map<String, dynamic> doc) {
    final target = _int(doc['target']);
    final reward = _int(doc['reward']);
    final category = _text(doc['category']);
    return QuestDef(
      q.id,
      _track(doc['track']) ?? q.track,
      _text(doc['title']) ?? q.title,
      _text(doc['description']) ?? q.description,
      _metric(doc['metric']) ?? q.metric,
      target != null && target > 0 ? target : q.target,
      reward != null && reward >= 0 ? reward : q.reward,
      q.icon,
      category: category ?? q.category,
    );
  }

  static QuestDef? _fromDoc(String id, Map<String, dynamic> doc) {
    final metric = _metric(doc['metric']), track = _track(doc['track']);
    final target = _int(doc['target']);
    final title = _text(doc['title']);
    if (metric == null || track == null || title == null || target == null || target <= 0) return null;
    return QuestDef(
      id,
      track,
      title,
      _text(doc['description']) ?? title,
      metric,
      target,
      _int(doc['reward']) ?? 20,
      Icons.flag_rounded,
      category: _text(doc['category']),
    );
  }
}
