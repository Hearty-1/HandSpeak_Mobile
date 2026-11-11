import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '/widgets/button_3d.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/services/badge_catalog.dart';
import '/services/daily_challenge_service.dart';

// =============================================================================
// MODEL
// =============================================================================

enum BadgeCategory { learning, mastery, consistency, arena, social, quests }

const Map<BadgeCategory, (String, IconData)> badgeCategoryInfo = {
  BadgeCategory.learning: ('Learning', Icons.school_rounded),
  BadgeCategory.mastery: ('Mastery', Icons.workspace_premium_rounded),
  BadgeCategory.consistency: ('Consistency', Icons.local_fire_department_rounded),
  BadgeCategory.arena: ('Arena', Icons.sports_esports_rounded),
  BadgeCategory.social: ('Social', Icons.people_alt_rounded),
  BadgeCategory.quests: ('Daily Quests', Icons.flag_rounded),
};

class BadgeData {
  /// Stable key in users.badges (the built-in title, or the badge document id
  /// for badges added from the web); the title itself can be edited.
  final String key;
  final String title;
  final String description;
  final String? imagePath; // illustration, or null to use [icon]
  final String? imageUrl; // picture set from the web content management
  final IconData icon;
  final int currentProgress;
  final int targetProgress;
  final Color themeColor;
  final BadgeCategory category;

  /// When the badge was first unlocked (users.badges). Once earned, a badge
  /// stays earned even if the number behind it drops (e.g. a streak resets).
  final DateTime? unlockedAt;

  BadgeData({
    String? key,
    required this.title,
    required this.description,
    this.imagePath,
    this.imageUrl,
    this.icon = Icons.emoji_events_rounded,
    required this.currentProgress,
    required this.targetProgress,
    required this.themeColor,
    this.category = BadgeCategory.learning,
    this.unlockedAt,
  }) : key = key ?? title;

  bool get isUnlocked => unlockedAt != null || currentProgress >= targetProgress;
  double get progressPercent => isUnlocked ? 1.0 : (currentProgress / targetProgress).clamp(0.0, 1.0);
  int get shownProgress => isUnlocked && currentProgress < targetProgress ? targetProgress : currentProgress;
}

// =============================================================================
// CATALOG
// =============================================================================

final RegExp _levelKey = RegExp(r'^(alphabet|numbers|phrases|civic)_(easy|medium|hard)_\d+$');

/// A built-in badge: the default that a `badges` document can edit.
class _Def {
  final String title, description, metric;
  final int target;
  final Color color;
  final BadgeCategory category;
  final String? image;
  final IconData icon;
  const _Def(this.title, this.description, this.metric, this.target, this.color, this.category,
      {this.image, this.icon = Icons.emoji_events_rounded});
}

const _l = BadgeCategory.learning, _m = BadgeCategory.mastery, _c = BadgeCategory.consistency;
const _a = BadgeCategory.arena, _s = BadgeCategory.social, _q = BadgeCategory.quests;

const List<_Def> _builtIn = [
  // ---- Learning ----------------------------------------------------------
  _Def('First Sign', 'Complete your very first lesson.', 'xp', 50, Colors.blueAccent, _l, image: 'assets/pictures/alphabet1.png'),
  _Def('Alphabet Explorer', 'Complete 5 Alphabet levels.', 'alphabet_levels', 5, Color(0xFF42A5F5), _l, icon: Icons.abc_rounded),
  _Def('Number Navigator', 'Complete 5 Numbers levels.', 'numbers_levels', 5, Color(0xFF26C6DA), _l, icon: Icons.pin_rounded),
  _Def('Phrase Speaker', 'Complete 5 Greetings levels.', 'phrases_levels', 5, Color(0xFF66BB6A), _l, icon: Icons.chat_bubble_rounded),
  _Def('Civic Champion', 'Complete 5 Civic levels.', 'civic_levels', 5, Color(0xFFEF5350), _l, icon: Icons.flag_rounded),
  _Def('Well-Rounded', 'Complete a level in all 4 categories.', 'categories_tried', 4, Color(0xFF7E57C2), _l, icon: Icons.public_rounded),
  _Def('Hard Hitter', 'Complete your first Hard level.', 'hard_levels', 1, Color(0xFFFF7043), _l, icon: Icons.terrain_rounded),
  _Def('Summit Seeker', 'Complete 10 Hard levels.', 'hard_levels', 10, Color(0xFFD84315), _l, icon: Icons.landscape_rounded),
  // ---- Mastery -----------------------------------------------------------
  _Def('Star Scholar', 'Collect 10 total stars from modules.', 'stars', 10, Colors.amber, _m, image: 'assets/pictures/large_star.png'),
  _Def('Star Collector', 'Collect 50 total stars.', 'stars', 50, Color(0xFFFFB300), _m, icon: Icons.stars_rounded),
  _Def('Constellation', 'Collect 150 total stars.', 'stars', 150, Color(0xFFFFA000), _m, icon: Icons.auto_awesome_rounded),
  _Def('Perfectionist', 'Achieve a perfect score on 5 lessons.', 'perfect_scores', 5, Colors.green, _m, image: 'assets/pictures/perfect.png'),
  _Def('Triple Threat', 'Finish 10 levels with 3 stars.', 'three_star_levels', 10, Color(0xFF43A047), _m, icon: Icons.military_tech_rounded),
  _Def('Flawless', 'Finish 25 levels with 3 stars.', 'three_star_levels', 25, Color(0xFF2E7D32), _m, icon: Icons.diamond_rounded),
  _Def('Rising Star', 'Earn 250 XP.', 'xp', 250, Color(0xFFAB47BC), _m, icon: Icons.trending_up_rounded),
  _Def('Sign Master', 'Earn 1,000 XP through lessons and arenas.', 'xp', 1000, Colors.purpleAccent, _m, image: 'assets/pictures/sign1.png'),
  _Def('Grandmaster', 'Earn 5,000 XP.', 'xp', 5000, Color(0xFF6A1B9A), _m, image: 'assets/pictures/Crown.png'),
  // ---- Consistency -------------------------------------------------------
  _Def('Spark', 'Keep a 3-day learning streak.', 'streak', 3, Color(0xFFFFA726), _c, icon: Icons.bolt_rounded),
  _Def('Streak Keeper', 'Maintain a 7-day learning streak.', 'streak', 7, Colors.deepOrange, _c, image: 'assets/pictures/fire.png'),
  _Def('Fortnight Flame', 'Keep a 14-day learning streak.', 'streak', 14, Color(0xFFF4511E), _c, icon: Icons.whatshot_rounded),
  _Def('Unstoppable', 'Keep a 30-day learning streak.', 'streak', 30, Color(0xFFBF360C), _c, icon: Icons.local_fire_department_rounded),
  // ---- Arena -------------------------------------------------------------
  _Def('First Duel', 'Complete your first Solo Challenge.', 'solo_challenges', 1, Color(0xFFE57373), _a, icon: Icons.sports_martial_arts_rounded),
  _Def('Challenger', 'Complete 10 Solo Challenges.', 'solo_challenges', 10, Colors.redAccent, _a, image: 'assets/pictures/sword.png'),
  _Def('Arena Veteran', 'Play 50 Arena games.', 'games_played', 50, Color(0xFFC62828), _a, icon: Icons.shield_rounded),
  _Def('Sharp Eye', 'Answer 100 Arena questions correctly.', 'correct_answers', 100, Color(0xFFEC407A), _a, icon: Icons.gps_fixed_rounded),
  // ---- Social ------------------------------------------------------------
  _Def('Friendly Hand', 'Follow your first classmate.', 'following', 1, Color(0xFF4DB6AC), _s, icon: Icons.waving_hand_rounded),
  _Def('Socialite', 'Connect with 10 other students.', 'followers', 10, Colors.teal, _s, image: 'assets/pictures/people.png'),
  _Def('Community Star', 'Have 25 followers.', 'followers', 25, Color(0xFF00796B), _s, icon: Icons.groups_rounded),
  // ---- Daily quests (the quest-track badges come after this one) ---------
  _Def('Quest Starter', 'Complete your first daily quest.', 'quests_completed', 1, Color(0xFF29B6F6), _q, icon: Icons.flag_circle_rounded),
];

const List<_Def> _builtInLast = [
  _Def('Quest Master', 'Complete 25 daily quests.', 'quests_completed', 25, Color(0xFFFFC107), _q, image: 'assets/pictures/Crown.png'),
  _Def('Quest Legend', 'Complete 50 daily quests.', 'quests_completed', 50, Color(0xFFFF8F00), _q, image: 'assets/pictures/trophy.png'),
];

/// The numbers a badge can count (BadgeCatalog.metrics), from the user document.
Map<String, int> badgeMetrics(Map<String, dynamic> user) {
  int n(String k) => (user[k] as num?)?.toInt() ?? 0;
  // Level progress: progress map keys like alphabet_hard_2 -> stars (1-3).
  final progress = Map<String, dynamic>.from(user['progress'] as Map? ?? const {});
  final perCategory = <String, int>{'alphabet': 0, 'numbers': 0, 'phrases': 0, 'civic': 0};
  int hard = 0, threeStar = 0;
  progress.forEach((k, v) {
    final m = _levelKey.firstMatch(k);
    if (m == null || v is! num || v <= 0) return;
    perCategory[m.group(1)!] = (perCategory[m.group(1)!] ?? 0) + 1;
    if (m.group(2) == 'hard') hard++;
    if (v >= 3) threeStar++;
  });
  int xp = n('xp');
  if (xp == 0) progress.forEach((_, v) => xp += v is num ? v.toInt() : 0);
  return {
    'xp': xp,
    'stars': n('stars'),
    'streak': n('streak'),
    'alphabet_levels': perCategory['alphabet']!,
    'numbers_levels': perCategory['numbers']!,
    'phrases_levels': perCategory['phrases']!,
    'civic_levels': perCategory['civic']!,
    'categories_tried': perCategory.values.where((c) => c > 0).length,
    'hard_levels': hard,
    'three_star_levels': threeStar,
    'perfect_scores': n('perfectScores'),
    'solo_challenges': n('soloChallengesCompleted'),
    'games_played': n('totalGamesPlayed'),
    'correct_answers': n('totalCorrectAnswers'),
    'following': (user['following'] as List?)?.length ?? 0,
    'followers': (user['followers'] as List?)?.length ?? 0,
    'quests_completed': List<String>.from(user['completedDailyChallenges'] ?? const []).length,
  };
}

/// A category ("module") condition of a badge made on the web, e.g.
/// metric "module_lessons" + module "foods" = Foods signs learned.
///   module_lessons  tutorial signs learned (users.tutorialMastery[module])
///   module_levels   activity levels completed (stars > 0)
///   module_stars    activity stars earned (best per level, max 3)
///   module_xp       the module's XP (e.g. foodsXp)
int moduleMetric(Map<String, dynamic> user, String metric, String module) {
  final m = module.trim().toLowerCase();
  if (m.isEmpty) return 0;
  // Built-in modules keep their own keys / fields.
  final masteryKey = switch (m) {
    'greetings' || 'phrase' || 'common phrases' => 'phrases',
    'civic' || 'civic observances' => 'civic_lupang_hinirang',
    _ => m,
  };
  final xpField = switch (m) {
    'alphabet' => 'alphabetXp',
    'numbers' => 'numbersXp',
    'phrases' || 'greetings' || 'phrase' => 'phraseXp',
    'civic' => 'civicXp',
    _ => '${m.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}Xp',
  };
  bool inModule(String levelId) {
    final l = levelId.toLowerCase();
    return l.startsWith('${m}_') || l.startsWith('$masteryKey' '_') || l.startsWith(m);
  }

  final progress = Map<String, dynamic>.from(user['progress'] as Map? ?? const {});
  int levels = 0, stars = 0;
  progress.forEach((k, v) {
    if (v is! num || v <= 0 || v > 3 || !inModule(k)) return;
    levels++;
    stars += v.toInt();
  });
  switch (metric) {
    case 'module_lessons':
      final mastery = (user['tutorialMastery'] as Map?)?[masteryKey];
      return mastery is Map ? mastery.length : 0;
    case 'module_levels':
      return levels;
    case 'module_stars':
      return stars;
    case 'module_xp':
      return (user[xpField] as num?)?.toInt() ?? 0;
  }
  return 0;
}

/// Every achievement: the built-in badges with the faculty's edits from the
/// `badges` collection (BadgeCatalog) on top, plus the badges they added.
List<BadgeData> buildAchievements(Map<String, dynamic> user, {Map<String, Map<String, dynamic>>? catalog}) {
  final docs = catalog ?? BadgeCatalog.instance.docs.value;
  final stored = Map<String, dynamic>.from(user['badges'] as Map? ?? const {});
  DateTime? unlocked(String key) {
    final v = stored[key];
    if (v is Timestamp) return v.toDate();
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(0);
  }

  final metrics = badgeMetrics(user);
  final quests = List<String>.from(user['completedDailyChallenges'] ?? const []);
  final lp = user['learnerProfile'];
  final unexplored = lp is Map && lp['unexplored'] is List ? List<String>.from(lp['unexplored']) : null;
  final tracks = DailyChallengeService.trackProgress(quests, unexplored: unexplored);

  // (badge, sort position): built-ins keep their place unless `order` is set.
  final out = <(BadgeData, num)>[];
  final used = <String>{};
  var pos = 0;

  void add({required String id, required String key, required _Def d, (int, int)? fixed}) {
    // The web content management's stable key (`awardKey`), when it has one.
    final award = '${docs[id]?['awardKey'] ?? ''}'.trim();
    if (award.isNotEmpty) key = award;
    used.add(id);
    final doc = docs[id];
    pos++;
    if (doc != null && doc['active'] == false) return;
    String str(String f, String def) => '${doc?[f] ?? ''}'.trim().isEmpty ? def : '${doc![f]}'.trim();
    final metric = str('metric', d.metric);
    final target = (doc?['target'] as num?)?.toInt() ?? fixed?.$2 ?? d.target;
    final current = fixed != null && metric == d.metric
        ? fixed.$1
        : (BadgeCatalog.isModuleMetric(metric)
            ? moduleMetric(user, metric, '${doc?['module'] ?? ''}')
            : (metrics[metric] ?? 0));
    final category = BadgeCategory.values.where((c) => c.name == '${doc?['category'] ?? ''}').firstOrNull ?? d.category;
    final image = '${doc?['imageUrl'] ?? ''}'.trim();
    out.add((
      BadgeData(
        key: key,
        title: str('title', d.title),
        description: str('description', d.description),
        imagePath: d.image,
        imageUrl: image.startsWith('http') ? image : null,
        icon: BadgeCatalog.icons['${doc?['icon'] ?? ''}'] ?? d.icon,
        currentProgress: current,
        targetProgress: target < 1 ? 1 : target,
        themeColor: BadgeCatalog.parseColor(doc?['color']) ?? d.color,
        category: category,
        unlockedAt: unlocked(key),
      ),
      (doc?['order'] as num?) ?? pos,
    ));
  }

  for (final d in _builtIn) {
    add(id: BadgeArt.keyFor(d.title), key: d.title, d: d);
  }
  for (final e in tracks.entries) {
    final t = questTracks[e.key]!;
    final d = _Def(t.badgeTitle, t.badgeDescription, 'quest_track_${e.key.name}', e.value.$2, t.color, _q,
        image: t.badgeImage, icon: t.icon);
    add(id: BadgeArt.keyFor(t.badgeTitle), key: t.badgeTitle, d: d, fixed: e.value);
  }
  for (final d in _builtInLast) {
    add(id: BadgeArt.keyFor(d.title), key: d.title, d: d);
  }
  // Badges added from the web: any document that is not a built-in badge.
  for (final e in docs.entries) {
    if (used.contains(e.key)) continue;
    final title = '${e.value['title'] ?? ''}'.trim();
    final metric = '${e.value['metric'] ?? ''}';
    if (title.isEmpty) continue;
    if (!BadgeCatalog.metrics.containsKey(metric) && !BadgeCatalog.isModuleMetric(metric)) continue;
    if (BadgeCatalog.isModuleMetric(metric) && '${e.value['module'] ?? ''}'.trim().isEmpty) continue;
    add(id: e.key, key: e.key, d: _Def(title, '', '${e.value['metric']}', 1, const Color(0xFF7E57C2), _l));
  }
  out.sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final e in out) e.$1];
}

/// The three badges worth showing on the profile: newest unlocks first,
/// then the ones closest to unlocking.
List<BadgeData> highlightBadges(List<BadgeData> all, {int count = 3}) {
  final unlocked = all.where((b) => b.isUnlocked).toList()
    ..sort((a, b) => (b.unlockedAt ?? DateTime(2100)).compareTo(a.unlockedAt ?? DateTime(2100)));
  final inProgress = all.where((b) => !b.isUnlocked).toList()
    ..sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
  return [...unlocked, ...inProgress].take(count).toList();
}

// =============================================================================
// WIDGETS
// =============================================================================

/// Badge artwork uploaded to Firebase Storage: `badges/<snake_case title>.png`
/// ("Alphabet Explorer" -> badges/alphabet_explorer.png), or a picture set
/// from the web content management (badges.imageUrl). Fast after the first
/// time:
/// - the download links are remembered on the phone (no Storage lookups on
///   the next launches; a badge without a picture is checked again daily);
/// - the pictures themselves are saved on the phone (30 days) and shown from
///   there, also offline;
/// - [prefetch] loads every badge's picture at once (in parallel).
/// A badge without an uploaded picture keeps its bundled illustration / icon.
class BadgeArt {
  static final Map<String, Future<String?>> _urls = {};
  static final Map<String, String?> _resolved = {};
  static final Map<String, Future<File?>> _files = {};
  static final Map<String, File> _ready = {};

  static final CacheManager _cache =
      CacheManager(Config('handspeak_badge_art', stalePeriod: const Duration(days: 30), maxNrOfCacheObjects: 200));

  /// Links remembered between launches: key -> url ('' = none uploaded).
  static const String _prefKey = 'badge_art_urls_v1';
  static const Duration _recheckMissing = Duration(days: 1);
  static Future<Map<String, dynamic>>? _saved;

  /// Uploaded files whose names differ from the badge title.
  static const Map<String, List<String>> _aliases = {
    'civic_champion': ['civic_companion'],
  };

  static String keyFor(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');

  /// Already resolved URL (null = none uploaded or not resolved yet).
  static String? cachedUrl(String title) => _resolved[keyFor(title)];

  /// The picture already saved on the phone for [url] (shown at once).
  static File? readyFile(String url) => _ready[url];

  static Future<Map<String, dynamic>> _savedLinks() => _saved ??= () async {
        try {
          final raw = (await SharedPreferences.getInstance()).getString(_prefKey);
          return raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
        } catch (_) {
          return <String, dynamic>{};
        }
      }();

  static Future<void> _remember(String key, String url) async {
    final saved = await _savedLinks();
    saved[key] = {'url': url, 'at': DateTime.now().millisecondsSinceEpoch};
    try {
      await (await SharedPreferences.getInstance()).setString(_prefKey, jsonEncode(saved));
    } catch (_) {}
  }

  static Future<String?> urlFor(String title) {
    final key = keyFor(title);
    return _urls.putIfAbsent(key, () async {
      // Remembered from an earlier launch: no Storage lookup.
      final known = (await _savedLinks())[key];
      if (known is Map) {
        final url = '${known['url'] ?? ''}';
        final at = DateTime.fromMillisecondsSinceEpoch((known['at'] as num?)?.toInt() ?? 0);
        if (url.isNotEmpty || DateTime.now().difference(at) < _recheckMissing) {
          _resolved[key] = url.isEmpty ? null : url;
          return _resolved[key];
        }
      }
      for (final name in [key, ...?_aliases[key]]) {
        try {
          final url = await FirebaseStorage.instance.ref('badges/$name.png').getDownloadURL();
          _resolved[key] = url;
          unawaited(_remember(key, url));
          return url;
        } catch (_) {
          // Not uploaded under this name: try the next one.
        }
      }
      _resolved[key] = null;
      unawaited(_remember(key, ''));
      return null;
    });
  }

  /// The picture of [url] saved on the phone (downloaded the first time).
  static Future<File?> fileFor(String url) => _files.putIfAbsent(url, () async {
        try {
          final f = await _cache.getSingleFile(url);
          _ready[url] = f;
          return f;
        } catch (_) {
          _files.remove(url); // offline: try again later
          return null;
        }
      });

  /// Every badge's picture at once (profile / achievements open).
  static void prefetch(Iterable<BadgeData> badges) {
    for (final b in badges) {
      final web = b.imageUrl;
      if (web != null) {
        fileFor(web);
      } else {
        urlFor(b.key).then((url) {
          if (url != null) fileFor(url);
        });
      }
    }
  }
}

/// Badge artwork: the uploaded badge image (Firebase Storage), else the
/// bundled illustration, else a glowing gradient medallion with the badge's
/// icon. Greyed out while locked.
class BadgeMedallion extends StatelessWidget {
  final BadgeData badge;
  final double size;
  const BadgeMedallion({super.key, required this.badge, required this.size});

  static const ColorFilter _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 0.45, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final c = badge.themeColor;
    final Widget localArt = badge.imagePath != null
        ? Image.asset(
            badge.imagePath!,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _iconMedal(c),
          )
        : _iconMedal(c);
    // The picture saved on the phone (downloaded once); the bundled art
    // shows until it is there.
    Widget fromFile(File f) => Image.file(
          f,
          width: size,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => localArt,
        );
    Widget remote(String url) {
      final ready = BadgeArt.readyFile(url);
      if (ready != null) return fromFile(ready);
      return FutureBuilder<File?>(
        future: BadgeArt.fileFor(url),
        builder: (_, snap) => snap.data != null ? fromFile(snap.data!) : localArt,
      );
    }
    final cached = badge.imageUrl ?? BadgeArt.cachedUrl(badge.key);
    final Widget art = cached != null
        ? remote(cached)
        : FutureBuilder<String?>(
            future: BadgeArt.urlFor(badge.key),
            builder: (_, snap) => snap.data != null ? remote(snap.data!) : localArt,
          );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        if (badge.isUnlocked)
          Container(
            width: size * 0.9,
            height: size * 0.9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: size * 0.22, spreadRadius: 1)],
            ),
          ),
        badge.isUnlocked ? art : ColorFiltered(colorFilter: _grey, child: art),
      ]),
    );
  }

  Widget _iconMedal(Color c) => Container(
        width: size * 0.86,
        height: size * 0.86,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Color.lerp(c, Colors.white, 0.35)!, c, Color.lerp(c, Colors.black, 0.25)!]),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: size * 0.04),
        ),
        child: Icon(badge.icon, color: Colors.white, size: size * 0.42),
      );
}

/// One grid cell: medallion, title, progress / UNLOCKED.
class BadgeTile extends StatelessWidget {
  final BadgeData badge;
  final double scale;
  final VoidCallback onTap;
  const BadgeTile({super.key, required this.badge, required this.scale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Expanded(
          child: LayoutBuilder(
            builder: (_, c) => Stack(alignment: Alignment.center, children: [
              BadgeMedallion(badge: badge, size: c.biggest.shortestSide),
              if (!badge.isUnlocked)
                Positioned(
                  bottom: 0,
                  right: c.maxWidth / 2 - c.biggest.shortestSide / 2,
                  child: Container(
                    padding: EdgeInsets.all(4 * scale),
                    decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, shape: BoxShape.circle),
                    child: Icon(Icons.lock_rounded, size: 13 * scale, color: textColor.withValues(alpha: 0.6)),
                  ),
                ),
            ]),
          ),
        ),
        SizedBox(height: 6 * scale),
        Text(
          badge.title,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: badge.isUnlocked ? textColor : textColor.withValues(alpha: 0.5),
            fontSize: 12 * scale,
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
          ),
        ),
        SizedBox(height: 4 * scale),
        if (badge.isUnlocked)
          Text('UNLOCKED',
              style: TextStyle(color: badge.themeColor, fontSize: 9 * scale, fontWeight: FontWeight.w900, letterSpacing: 0.5))
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(4 * scale),
            child: ProgressBar3D(value: (badge.progressPercent).toDouble(), color: badge.themeColor.withValues(alpha: 0.75), height: 4 * scale, trackColor: textColor.withValues(alpha: 0.1)),
          ),
      ]),
    );
  }
}

enum _Filter { all, unlocked, inProgress, locked }

/// Full achievements browser: overall progress, filters, and every badge
/// grouped by category. Scales to any number of badges.
class AchievementsSheet extends StatefulWidget {
  final List<BadgeData> badges;
  final double scale;
  final void Function(BadgeData) onBadgeTap;
  const AchievementsSheet({super.key, required this.badges, required this.scale, required this.onBadgeTap});

  static Future<void> show(BuildContext context,
      {required List<BadgeData> badges, required double scale, required void Function(BadgeData) onBadgeTap}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AchievementsSheet(badges: badges, scale: scale, onBadgeTap: onBadgeTap),
    );
  }

  @override
  State<AchievementsSheet> createState() => _AchievementsSheetState();
}

class _AchievementsSheetState extends State<AchievementsSheet> {
  _Filter _filter = _Filter.all;
  double get s => widget.scale;

  bool _matches(BadgeData b) => switch (_filter) {
        _Filter.all => true,
        _Filter.unlocked => b.isUnlocked,
        _Filter.inProgress => !b.isUnlocked && b.currentProgress > 0,
        _Filter.locked => !b.isUnlocked && b.currentProgress == 0,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final total = widget.badges.length;
    final unlocked = widget.badges.where((b) => b.isUnlocked).length;
    final width = MediaQuery.of(context).size.width;
    final columns = width >= 600 ? 5 : (width >= 420 ? 4 : 3);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: CustomScrollView(
          controller: controller,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20 * s, 12 * s, 20 * s, 8 * s),
                child: Column(children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: textColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                  ),
                  SizedBox(height: 18 * s),
                  Row(children: [
                    SizedBox(
                      width: 64 * s,
                      height: 64 * s,
                      child: Stack(alignment: Alignment.center, children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: total == 0 ? 0 : unlocked / total,
                            strokeWidth: 6 * s,
                            backgroundColor: textColor.withValues(alpha: 0.08),
                            valueColor: AlwaysStoppedAnimation(theme.primaryColor),
                          ),
                        ),
                        Text('${total == 0 ? 0 : (unlocked * 100 / total).round()}%',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15 * s, color: textColor)),
                      ]),
                    ),
                    SizedBox(width: 16 * s),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Achievements',
                            style: TextStyle(fontSize: 22 * s, fontWeight: FontWeight.w900, color: textColor, fontFamily: 'Inter')),
                        SizedBox(height: 2 * s),
                        Text('$unlocked of $total badges unlocked',
                            style: TextStyle(fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.6))),
                      ]),
                    ),
                  ]),
                  SizedBox(height: 16 * s),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final f in _Filter.values)
                        Padding(
                          padding: EdgeInsets.only(right: 8 * s),
                          child: ChoiceChip(
                            label: Text(const {
                              _Filter.all: 'All',
                              _Filter.unlocked: 'Unlocked',
                              _Filter.inProgress: 'In progress',
                              _Filter.locked: 'Locked',
                            }[f]!),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                            selectedColor: theme.primaryColor.withValues(alpha: 0.25),
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _filter == f ? theme.primaryColor : textColor.withValues(alpha: 0.7),
                            ),
                            showCheckmark: false,
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
            for (final cat in BadgeCategory.values) ..._section(cat, columns, textColor),
            SliverToBoxAdapter(child: SizedBox(height: 24 * s + MediaQuery.of(context).padding.bottom)),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(BadgeCategory cat, int columns, Color textColor) {
    final inCat = widget.badges.where((b) => b.category == cat).toList();
    final shown = inCat.where(_matches).toList();
    if (shown.isEmpty) return const [];
    final (name, icon) = badgeCategoryInfo[cat]!;
    final done = inCat.where((b) => b.isUnlocked).length;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20 * s, 18 * s, 20 * s, 12 * s),
          child: Row(children: [
            Icon(icon, size: 18 * s, color: textColor.withValues(alpha: 0.7)),
            SizedBox(width: 8 * s),
            Text(name, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16 * s, color: textColor)),
            const Spacer(),
            Text('$done / ${inCat.length}',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13 * s, color: textColor.withValues(alpha: 0.55))),
          ]),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: 20 * s),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 18 * s,
            crossAxisSpacing: 14 * s,
            childAspectRatio: 0.74,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => BadgeTile(badge: shown[i], scale: s, onTap: () => widget.onBadgeTap(shown[i])),
            childCount: shown.length,
          ),
        ),
      ),
    ];
  }
}
