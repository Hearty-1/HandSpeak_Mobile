import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

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
  final String title; // also the key in users.badges (keep stable)
  final String description;
  final String? imagePath; // illustration, or null to use [icon]
  final IconData icon;
  final int currentProgress;
  final int targetProgress;
  final Color themeColor;
  final BadgeCategory category;

  /// When the badge was first unlocked (users.badges). Once earned, a badge
  /// stays earned even if the number behind it drops (e.g. a streak resets).
  final DateTime? unlockedAt;

  BadgeData({
    required this.title,
    required this.description,
    this.imagePath,
    this.icon = Icons.emoji_events_rounded,
    required this.currentProgress,
    required this.targetProgress,
    required this.themeColor,
    this.category = BadgeCategory.learning,
    this.unlockedAt,
  });

  bool get isUnlocked => unlockedAt != null || currentProgress >= targetProgress;
  double get progressPercent => isUnlocked ? 1.0 : (currentProgress / targetProgress).clamp(0.0, 1.0);
  int get shownProgress => isUnlocked && currentProgress < targetProgress ? targetProgress : currentProgress;
}

// =============================================================================
// CATALOG
// =============================================================================

final RegExp _levelKey = RegExp(r'^(alphabet|numbers|phrases|civic)_(easy|medium|hard)_\d+$');

/// Every achievement, computed from the user document.
List<BadgeData> buildAchievements(Map<String, dynamic> user) {
  int n(String k) => (user[k] as num?)?.toInt() ?? 0;
  final stored = Map<String, dynamic>.from(user['badges'] as Map? ?? const {});
  DateTime? unlocked(String title) {
    final v = stored[title];
    if (v is Timestamp) return v.toDate();
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(0);
  }

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
  final categoriesTried = perCategory.values.where((c) => c > 0).length;

  int xp = n('xp');
  if (xp == 0) progress.forEach((_, v) => xp += v is num ? v.toInt() : 0);
  final stars = n('stars');
  final streak = n('streak');
  final followers = (user['followers'] as List?)?.length ?? 0;
  final following = (user['following'] as List?)?.length ?? 0;
  final quests = List<String>.from(user['completedDailyChallenges'] ?? const []);
  final lp = user['learnerProfile'];
  final unexplored = lp is Map && lp['unexplored'] is List ? List<String>.from(lp['unexplored']) : null;

  BadgeData b(String title, String desc, int cur, int target, Color color, BadgeCategory cat,
          {String? image, IconData icon = Icons.emoji_events_rounded}) =>
      BadgeData(
        title: title,
        description: desc,
        imagePath: image,
        icon: icon,
        currentProgress: cur,
        targetProgress: target,
        themeColor: color,
        category: cat,
        unlockedAt: unlocked(title),
      );

  const L = BadgeCategory.learning, M = BadgeCategory.mastery, C = BadgeCategory.consistency;
  const A = BadgeCategory.arena, S = BadgeCategory.social, Q = BadgeCategory.quests;

  return [
    // ---- Learning ----------------------------------------------------------
    b('First Sign', 'Complete your very first lesson.', xp, 50, Colors.blueAccent, L, image: 'assets/pictures/alphabet1.png'),
    b('Alphabet Explorer', 'Complete 5 Alphabet levels.', perCategory['alphabet']!, 5, const Color(0xFF42A5F5), L, icon: Icons.abc_rounded),
    b('Number Navigator', 'Complete 5 Numbers levels.', perCategory['numbers']!, 5, const Color(0xFF26C6DA), L, icon: Icons.pin_rounded),
    b('Phrase Speaker', 'Complete 5 Words & Phrases levels.', perCategory['phrases']!, 5, const Color(0xFF66BB6A), L, icon: Icons.chat_bubble_rounded),
    b('Civic Champion', 'Complete 5 Civic levels.', perCategory['civic']!, 5, const Color(0xFFEF5350), L, icon: Icons.flag_rounded),
    b('Well-Rounded', 'Complete a level in all 4 categories.', categoriesTried, 4, const Color(0xFF7E57C2), L, icon: Icons.public_rounded),
    b('Hard Hitter', 'Complete your first Hard level.', hard, 1, const Color(0xFFFF7043), L, icon: Icons.terrain_rounded),
    b('Summit Seeker', 'Complete 10 Hard levels.', hard, 10, const Color(0xFFD84315), L, icon: Icons.landscape_rounded),

    // ---- Mastery -----------------------------------------------------------
    b('Star Scholar', 'Collect 10 total stars from modules.', stars, 10, Colors.amber, M, image: 'assets/pictures/large_star.png'),
    b('Star Collector', 'Collect 50 total stars.', stars, 50, const Color(0xFFFFB300), M, icon: Icons.stars_rounded),
    b('Constellation', 'Collect 150 total stars.', stars, 150, const Color(0xFFFFA000), M, icon: Icons.auto_awesome_rounded),
    b('Perfectionist', 'Achieve a perfect score on 5 lessons.', n('perfectScores'), 5, Colors.green, M, image: 'assets/pictures/perfect.png'),
    b('Triple Threat', 'Finish 10 levels with 3 stars.', threeStar, 10, const Color(0xFF43A047), M, icon: Icons.military_tech_rounded),
    b('Flawless', 'Finish 25 levels with 3 stars.', threeStar, 25, const Color(0xFF2E7D32), M, icon: Icons.diamond_rounded),
    b('Rising Star', 'Earn 250 XP.', xp, 250, const Color(0xFFAB47BC), M, icon: Icons.trending_up_rounded),
    b('Sign Master', 'Earn 1,000 XP through lessons and arenas.', xp, 1000, Colors.purpleAccent, M, image: 'assets/pictures/sign1.png'),
    b('Grandmaster', 'Earn 5,000 XP.', xp, 5000, const Color(0xFF6A1B9A), M, image: 'assets/pictures/Crown.png'),

    // ---- Consistency -------------------------------------------------------
    b('Spark', 'Keep a 3-day learning streak.', streak, 3, const Color(0xFFFFA726), C, icon: Icons.bolt_rounded),
    b('Streak Keeper', 'Maintain a 7-day learning streak.', streak, 7, Colors.deepOrange, C, image: 'assets/pictures/fire.png'),
    b('Fortnight Flame', 'Keep a 14-day learning streak.', streak, 14, const Color(0xFFF4511E), C, icon: Icons.whatshot_rounded),
    b('Unstoppable', 'Keep a 30-day learning streak.', streak, 30, const Color(0xFFBF360C), C, icon: Icons.local_fire_department_rounded),

    // ---- Arena -------------------------------------------------------------
    b('First Duel', 'Complete your first Solo Challenge.', n('soloChallengesCompleted'), 1, const Color(0xFFE57373), A, icon: Icons.sports_martial_arts_rounded),
    b('Challenger', 'Complete 10 Solo Challenges.', n('soloChallengesCompleted'), 10, Colors.redAccent, A, image: 'assets/pictures/sword.png'),
    b('Arena Veteran', 'Play 50 Arena games.', n('totalGamesPlayed'), 50, const Color(0xFFC62828), A, icon: Icons.shield_rounded),
    b('Sharp Eye', 'Answer 100 Arena questions correctly.', n('totalCorrectAnswers'), 100, const Color(0xFFEC407A), A, icon: Icons.gps_fixed_rounded),

    // ---- Social ------------------------------------------------------------
    b('Friendly Hand', 'Follow your first classmate.', following, 1, const Color(0xFF4DB6AC), S, icon: Icons.waving_hand_rounded),
    b('Socialite', 'Connect with 10 other students.', followers, 10, Colors.teal, S, image: 'assets/pictures/people.png'),
    b('Community Star', 'Have 25 followers.', followers, 25, const Color(0xFF00796B), S, icon: Icons.groups_rounded),

    // ---- Daily quests ------------------------------------------------------
    b('Quest Starter', 'Complete your first daily quest.', quests.length, 1, const Color(0xFF29B6F6), Q, icon: Icons.flag_circle_rounded),
    for (final e in DailyChallengeService.trackProgress(quests, unexplored: unexplored).entries)
      b(questTracks[e.key]!.badgeTitle, questTracks[e.key]!.badgeDescription, e.value.$1, e.value.$2,
          questTracks[e.key]!.color, Q,
          image: questTracks[e.key]!.badgeImage, icon: questTracks[e.key]!.icon),
    b('Quest Master', 'Complete 25 daily quests.', quests.length, 25, const Color(0xFFFFC107), Q, image: 'assets/pictures/Crown.png'),
    b('Quest Legend', 'Complete 50 daily quests.', quests.length, 50, const Color(0xFFFF8F00), Q, image: 'assets/pictures/trophy.png'),
  ];
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

/// Badge artwork uploaded to Firebase Storage: badges/<snake_case title>.png
/// ("Alphabet Explorer" -> badges/alphabet_explorer.png). Download URLs are
/// resolved once per badge and cached for the session; a badge without an
/// uploaded file keeps its bundled illustration / icon.
class BadgeArt {
  static final Map<String, Future<String?>> _urls = {};
  static final Map<String, String?> _resolved = {};

  /// Uploaded files whose names differ from the badge title.
  static const Map<String, List<String>> _aliases = {
    'civic_champion': ['civic_companion'],
  };

  static String keyFor(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');

  /// Already resolved URL (null = none uploaded or not resolved yet).
  static String? cachedUrl(String title) => _resolved[keyFor(title)];

  static Future<String?> urlFor(String title) {
    final key = keyFor(title);
    return _urls.putIfAbsent(key, () async {
      for (final name in [key, ...?_aliases[key]]) {
        try {
          final url = await FirebaseStorage.instance.ref('badges/$name.png').getDownloadURL();
          _resolved[key] = url;
          return url;
        } catch (_) {
          // Not uploaded under this name: try the next one.
        }
      }
      _resolved[key] = null;
      return null;
    });
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
            errorBuilder: (_, __, ___) => _iconMedal(c),
          )
        : _iconMedal(c);
    Widget remote(String url) => Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.contain,
          // Bundled art until the download finishes (or if it fails).
          frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : localArt,
          errorBuilder: (_, __, ___) => localArt,
        );
    final cached = BadgeArt.cachedUrl(badge.title);
    final Widget art = cached != null
        ? remote(cached)
        : FutureBuilder<String?>(
            future: BadgeArt.urlFor(badge.title),
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
            child: LinearProgressIndicator(
              value: badge.progressPercent,
              minHeight: 4 * scale,
              backgroundColor: textColor.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(badge.themeColor.withValues(alpha: 0.75)),
            ),
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
