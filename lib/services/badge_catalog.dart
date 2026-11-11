import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Badge definitions managed by faculty from the web content management
/// (Firestore collection `badges`, one document per badge). The app's
/// built-in badges are the defaults; a document overrides the built-in badge
/// with the same id, `active: false` hides it, and a document with a new id
/// adds a badge. Live: changes show in the app without an update.
///
/// badges/{id}  (id = snake_case of the built-in title, e.g. "alphabet_explorer")
///   title        "Alphabet Explorer"
///   description  "Complete 5 Alphabet levels."
///   category     learning | mastery | consistency | arena | social | quests
///   metric       what is counted (see [BadgeCatalog.metrics]), or a
///                category condition ([BadgeCatalog.moduleMetrics]) with
///   module       the category, e.g. "foods" (module_* metrics only)
///   awardKey     stable key of the badge in users.badges (set by the CMS)
///   target       number to reach, e.g. 5
///   color        "#42A5F5"
///   icon         Material icon name from [BadgeCatalog.icons] (when no image)
///   imageUrl     badge picture (https download link), optional
///   order        sort position, optional
///   active       false hides the badge
///
/// Earned badges stay in users/{uid}.badges ({ badge key: unlock time }).
class BadgeCatalog {
  BadgeCatalog._();
  static final BadgeCatalog instance = BadgeCatalog._();

  static const String collection = 'badges';

  /// What a badge can count (the `metric` field), with a description for
  /// the web form.
  static const Map<String, String> metrics = {
    'xp': 'Total XP',
    'stars': 'Total stars',
    'streak': 'Learning streak (days)',
    'alphabet_levels': 'Alphabet levels completed',
    'numbers_levels': 'Numbers levels completed',
    'phrases_levels': 'Greetings levels completed',
    'civic_levels': 'Civic levels completed',
    'categories_tried': 'Categories with a completed level',
    'hard_levels': 'Hard levels completed',
    'three_star_levels': 'Levels finished with 3 stars',
    'perfect_scores': 'Perfect-score lessons',
    'solo_challenges': 'Solo Challenges completed',
    'games_played': 'Arena games played',
    'correct_answers': 'Arena questions answered correctly',
    'following': 'Classmates followed',
    'followers': 'Followers',
    'quests_completed': 'Daily quests completed',
  };

  /// Conditions about one category, used with the badge's `module` field
  /// (a built-in module or a web category id, e.g. "foods").
  static const Map<String, String> moduleMetrics = {
    'module_lessons': 'Tutorial signs learned in the module',
    'module_levels': 'Activity levels completed in the module',
    'module_stars': 'Activity stars earned in the module',
    'module_xp': 'XP earned in the module',
  };

  static bool isModuleMetric(String metric) => moduleMetrics.containsKey(metric);

  /// Icon names the web form can pick from.
  static const Map<String, IconData> icons = {
    'emoji_events': Icons.emoji_events_rounded,
    'school': Icons.school_rounded,
    'star': Icons.star_rounded,
    'stars': Icons.stars_rounded,
    'auto_awesome': Icons.auto_awesome_rounded,
    'workspace_premium': Icons.workspace_premium_rounded,
    'military_tech': Icons.military_tech_rounded,
    'diamond': Icons.diamond_rounded,
    'trending_up': Icons.trending_up_rounded,
    'bolt': Icons.bolt_rounded,
    'whatshot': Icons.whatshot_rounded,
    'local_fire_department': Icons.local_fire_department_rounded,
    'abc': Icons.abc_rounded,
    'pin': Icons.pin_rounded,
    'chat_bubble': Icons.chat_bubble_rounded,
    'flag': Icons.flag_rounded,
    'flag_circle': Icons.flag_circle_rounded,
    'public': Icons.public_rounded,
    'terrain': Icons.terrain_rounded,
    'landscape': Icons.landscape_rounded,
    'sports_esports': Icons.sports_esports_rounded,
    'sports_martial_arts': Icons.sports_martial_arts_rounded,
    'shield': Icons.shield_rounded,
    'gps_fixed': Icons.gps_fixed_rounded,
    'waving_hand': Icons.waving_hand_rounded,
    'groups': Icons.groups_rounded,
    'people_alt': Icons.people_alt_rounded,
    'favorite': Icons.favorite_rounded,
    'celebration': Icons.celebration_rounded,
  };

  /// Latest badge documents by id (empty until loaded / when none exist).
  final ValueNotifier<Map<String, Map<String, dynamic>>> docs = ValueNotifier(const {});
  StreamSubscription? _sub;

  /// Starts listening (once).
  void start() {
    _sub ??= FirebaseFirestore.instance.collection(collection).snapshots().listen(
      (snap) => docs.value = {for (final d in snap.docs) d.id: d.data()},
      onError: (Object e) => debugPrint('badges catalog unavailable: $e'),
    );
  }

  static Color? parseColor(Object? v) {
    final s = '${v ?? ''}'.trim().replaceFirst('#', '');
    if (s.length != 6 && s.length != 8) return null;
    final n = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
    return n == null ? null : Color(n);
  }
}
