import '/widgets/sign_recording.dart';
import '/widgets/activity_feedback.dart';
import '/widgets/button_3d.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '/leaderboard/arena.dart' show LeaderboardScreen;
import '/module/alphabet/tutorial_practice.dart' show TutorialPractice;
import '/module/civic/civic_tutorial_detail.dart' show CustomVideoPlayer;
import '/module/civic/civic_tutorial_practice.dart' show CivicTutorialPractice;
import '/module/numbers/numbers_tutorial_practice.dart' show NumbersTutorialPractice;
import '/module/phrases/phrase_recognizer.dart' show PhraseRecognizer;
import '/module/phrases/phrase_tutorial_practice.dart' show PhraseTutorialPractice;
import '/module/phrases/phraseAct.dart' show PhraseActivityInterface;
import '/module/phrases/phrase_difficulty_selection.dart' show PhraseDifficultySelectionScreen;
import '/module/phrases/phrase_activity.dart' show ActivityCategoryConfig;
import '/services/frame_gate.dart';
import '/services/handspeak_api_service.dart';
import '/services/holistic_capture.dart';
import '/services/lighting_monitor.dart';
import '/services/performance_monitor.dart';
import '/services/progress_service.dart';
import '/services/published_gesture_models.dart';
import '/services/role_service.dart';
import '/services/xp_rewards.dart';
import '/providers/language_provider.dart';
import '/widgets/practice_feedback.dart';
import '/widgets/practice_success.dart';
import '/widgets/challenge_camera_sign.dart' show ChallengeSignResult;
import '/module/tutorial_session_practice.dart' show TutorialSessionPractice, PracticeSign;
import '/widgets/responsive.dart';

/// A category added in the web app (Firestore `activity_categories/{id}`):
/// label, description, cover image, isActive. The four built-in modules have
/// their own screens; every other active category is listed live on the
/// Modules page and opens [CloudCategoryScreen].
class CloudCategory {
  final String id;
  final String label;
  final String description;
  final String cover;
  final int order;

  const CloudCategory({required this.id, required this.label, required this.description, required this.cover, this.order = 0});

  /// Values stored in activity_questions / tutorial_lessons `category`.
  List<String> get aliases {
    final names = <String>{id, label};
    return {
      for (final n in names.where((n) => n.trim().isNotEmpty)) ...[n, n.toLowerCase(), n.toUpperCase(),
        n[0].toUpperCase() + n.substring(1).toLowerCase()],
    }.take(30).toList();
  }

  String get xpField => '${id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}Xp';

  static const Set<String> _builtIn = {
    'alphabet', 'alphabets', 'numbers', 'number', 'phrase', 'phrases', 'words', 'common words',
    'civic', 'civics', 'civic observances', 'civic_observances',
  };

  static CloudCategory? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    if (d['isActive'] == false) return null;
    final status = (d['status'] ?? '').toString().toLowerCase();
    if (status.isNotEmpty && status != 'approved' && status != 'active' && status != 'published') return null;
    final label = (d['label'] ?? d['name'] ?? d['title'] ?? doc.id).toString().trim();
    if (_builtIn.contains(doc.id.toLowerCase()) || _builtIn.contains(label.toLowerCase())) return null;
    return CloudCategory(
      id: doc.id,
      label: label,
      description: (d['description'] ?? '').toString().trim(),
      cover: (d['coverImageUrl'] ?? d['imgUrl'] ?? d['imageUrl'] ?? d['coverImagePath'] ?? '').toString().trim(),
      order: (d['order'] as num?)?.toInt() ?? 0,
    );
  }

  /// Display name: "PRACTICE" -> "Practice".
  String get title => label == label.toUpperCase() && label.length > 1
      ? label.split(' ').map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()).join(' ')
      : label;
}

/// A category cover (URL, Storage path or base64), for other screens.
class CloudCover extends StatelessWidget {
  final String source;
  final BoxFit fit;
  const CloudCover({super.key, required this.source, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) => _CloudMedia(source: source, fit: fit);
}

/// Image / video from a URL, Firebase Storage path or base64 string.
class _CloudMedia extends StatelessWidget {
  final String source;
  final BoxFit fit;
  const _CloudMedia({super.key, required this.source, this.fit = BoxFit.cover});

  static final Map<String, Future<String>> _urls = {};

  static Future<String> _resolve(String s) {
    if (s.isEmpty || s.startsWith('http') || s.startsWith('data:') || s.startsWith('assets/')) return Future.value(s);
    return _urls[s] ??= (s.startsWith('gs://')
            ? FirebaseStorage.instance.refFromURL(s)
            : FirebaseStorage.instance.ref(s))
        .getDownloadURL()
        .catchError((_) => '');
  }

  static bool isVideo(String s) => RegExp(r'\.(mp4|mov|webm|m4v|3gp|mkv)$', caseSensitive: false)
      .hasMatch(Uri.decodeComponent(s.split('?').first));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = Container(
      color: theme.primaryColor.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Icon(Icons.category_rounded, color: theme.primaryColor, size: 40),
    );
    return FutureBuilder<String>(
      future: _resolve(source.trim()),
      builder: (context, snap) {
        final url = snap.data ?? '';
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
        }
        if (url.isEmpty) return fallback;
        if (isVideo(url)) return ColoredBox(color: Colors.black, child: Center(child: CustomVideoPlayer(videoUrl: url)));
        if (url.startsWith('data:image')) {
          try {
            return Image.memory(base64Decode(url.split(',').last), fit: fit);
          } catch (_) {
            return fallback;
          }
        }
        if (url.startsWith('assets/')) return Image.asset(url, fit: fit, errorBuilder: (_, _, _) => fallback);
        return Image.network(url, fit: fit, errorBuilder: (_, _, _) => fallback);
      },
    );
  }
}

// =============================================================================
// Modules page: live list of the web app's categories
// =============================================================================

class CloudCategoriesSection extends StatelessWidget {
  final double scale;
  const CloudCategoriesSection({super.key, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final canProgress = context.roles.can(AppFeature.progress);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('activity_categories').snapshots(),
      builder: (context, snap) {
        final cats = [
          for (final d in snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            ?CloudCategory.fromDoc(d),
        ]..sort((a, b) => a.order != b.order ? a.order.compareTo(b.order) : a.title.compareTo(b.title));
        if (cats.isEmpty) return const SizedBox.shrink();
        // The student's progress (tutorialMastery / activity stars).
        return StreamBuilder<DocumentSnapshot>(
          stream: ProgressService().getUserProgressStream(),
          builder: (context, user) {
            final data = (user.data?.data() as Map<String, dynamic>?) ?? const {};
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 16 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L.t('More Categories', 'Iba pang Kategorya'),
                      style: TextStyle(color: textColor, fontSize: 22 * scale, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                  SizedBox(height: 4 * scale),
                  Text(L.t('Added by your teachers', 'Idinagdag ng iyong mga guro'),
                      style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 13 * scale, fontWeight: FontWeight.w500)),
                  SizedBox(height: 14 * scale),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    mainAxisSpacing: 14 * scale,
                    crossAxisSpacing: 14 * scale,
                    childAspectRatio: canProgress ? 0.66 : 0.78,
                    children: [
                      for (final c in cats)
                        ModuleCard(
                          scale: scale,
                          title: c.title,
                          subtitle: c.description,
                          picture: ClipRRect(borderRadius: BorderRadius.circular(14 * scale), child: _CloudMedia(source: c.cover)),
                          source: ModuleSource.cloud(c),
                          userData: data,
                          showProgress: canProgress,
                          onTap: () {
                            ProgressService().trackRecentModule(c.id);
                            Navigator.push(context, MaterialPageRoute(builder: (_) => CloudCategoryScreen(category: c)));
                          },
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Completion of a module: how much of its content the student has done.
/// Signs = tutorial lessons mastered; stars = activity stars earned out of 3
/// per level. [percent] weighs every lesson and every star the same, out of
/// what the module has now (new content raises the totals by itself).
class ModuleProgress {
  final int mastered, lessons, stars, levels;
  const ModuleProgress({required this.mastered, required this.lessons, required this.stars, required this.levels});

  int get maxStars => levels * 3;
  int get total => lessons + maxStars;
  double get percent => total == 0 ? 0 : ((mastered.clamp(0, lessons) + stars.clamp(0, maxStars)) / total).clamp(0.0, 1.0);
  bool get completed => total > 0 && percent >= 1.0;
}

/// Where a module's content and progress live: tutorial_lessons /
/// activity_questions `category` values, and its `tutorialMastery.<key>`.
class ModuleSource {
  final List<String> categories;
  final String masteryKey;
  const ModuleSource({required this.categories, required this.masteryKey});

  static const alphabet = ModuleSource(categories: ['alphabet', 'Alphabet'], masteryKey: 'alphabet');
  static const numbers = ModuleSource(categories: ['numbers', 'Numbers'], masteryKey: 'numbers');
  static const greetings = ModuleSource(categories: ['phrases', 'phrase', 'Phrases'], masteryKey: 'phrases');
  static const civic = ModuleSource(categories: ['civic', 'Civic'], masteryKey: 'civic_lupang_hinirang');
  static ModuleSource cloud(CloudCategory c) => ModuleSource(categories: c.aliases, masteryKey: c.id);

  static final Map<String, Future<({int lessons, List<String> levels})>> _totals = {};

  /// Lessons and activity levels of the module (read once per session).
  Future<({int lessons, List<String> levels})> totals() => _totals[masteryKey] ??= () async {
        final db = FirebaseFirestore.instance;
        final cats = categories.take(30).toList();
        final lessons = await db.collection('tutorial_lessons').where('category', whereIn: cats).get();
        final questions = await db.collection('activity_questions').where('category', whereIn: cats).get();
        final levels = {
          for (final d in questions.docs)
            if ('${d.data()['level'] ?? ''}'.trim().isNotEmpty) '${d.data()['level']}'.trim(),
        }.toList();
        return (lessons: lessons.size, levels: levels);
      }()
          .catchError((Object e) {
        _totals.remove(masteryKey);
        throw e;
      });

  /// The student's completion from users/{uid} [data].
  ModuleProgress progress(Map<String, dynamic> data, ({int lessons, List<String> levels}) t) {
    final m = (data['tutorialMastery'] as Map?)?[masteryKey];
    final progress = data['progress'];
    var stars = 0;
    if (progress is Map) {
      for (final l in t.levels) {
        final v = progress[l];
        if (v is num) stars += v.toInt().clamp(0, 3);
      }
    }
    return ModuleProgress(mastered: m is Map ? m.length : 0, lessons: t.lessons, stars: stars, levels: t.levels.length);
  }
}

/// Top panel of a module page (Alphabet, Numbers, Greetings, Civic and every
/// web app category): the module's completion, the same number as its card
/// on the Modules page, with what makes it up: tutorial signs mastered and
/// activity stars earned. Live (users/{uid}).
class ModuleProgressPanel extends StatefulWidget {
  final ModuleSource source;
  final String title;
  final double scale;

  const ModuleProgressPanel({super.key, required this.source, required this.title, this.scale = 1.0});

  @override
  State<ModuleProgressPanel> createState() => _ModuleProgressPanelState();
}

/// The header (title, % and the big bar) is always shown; tapping it opens
/// or closes the breakdown (tutorials / activities) like a dropdown.
class _ModuleProgressPanelState extends State<ModuleProgressPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final scale = widget.scale;
    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(),
      builder: (context, user) {
        final data = (user.data?.data() as Map<String, dynamic>?) ?? const {};
        return FutureBuilder<({int lessons, List<String> levels})>(
          future: widget.source.totals(),
          builder: (context, t) {
            final p = t.hasData ? widget.source.progress(data, t.data!) : null;
            final done = p?.completed ?? false;
            final accent = done ? Colors.green : theme.primaryColor;
            final pct = ((p?.percent ?? 0) * 100).round();

            Widget row(IconData icon, Color color, String label, String value, double ratio) => Padding(
                  padding: EdgeInsets.only(top: 12 * scale),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(7 * scale),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10 * scale)),
                        child: Icon(icon, size: 16 * scale, color: color),
                      ),
                      SizedBox(width: 10 * scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(label,
                                      style: TextStyle(color: textColor.withValues(alpha: 0.85), fontSize: 13 * scale, fontWeight: FontWeight.w700)),
                                ),
                                Text(value, style: TextStyle(color: textColor, fontSize: 13 * scale, fontWeight: FontWeight.w900)),
                              ],
                            ),
                            SizedBox(height: 5 * scale),
                            ProgressBar3D(value: ratio, color: color, height: 8 * scale),
                          ],
                        ),
                      ),
                    ],
                  ),
                );

            final breakdown = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 6 * scale),
                Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.4)),
                row(Icons.back_hand_rounded, theme.primaryColor, L.t('Tutorials', 'Mga Tutorial'),
                    p == null ? '…' : L.t('${p.mastered.clamp(0, p.lessons)} / ${p.lessons} signs', '${p.mastered.clamp(0, p.lessons)} / ${p.lessons} senyas'),
                    p == null || p.lessons == 0 ? 0 : p.mastered / p.lessons),
                row(Icons.star_rounded, const Color(0xFFFFB300), L.t('Activities', 'Mga Aktibidad'),
                    p == null ? '…' : L.t('${p.stars} / ${p.maxStars} stars', '${p.stars} / ${p.maxStars} bituin'),
                    p == null || p.maxStars == 0 ? 0 : p.stars / p.maxStars),
              ],
            );

            return ClipRRect(
              borderRadius: BorderRadius.circular(22 * scale),
              child: SmartBlur(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(22 * scale),
                    border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 6))],
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: () => setState(() => _open = !_open),
                      child: Padding(
                        padding: EdgeInsets.all(16 * scale),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(L.t('${widget.title} progress', 'Progreso sa ${widget.title}'),
                                      style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                                ),
                                if (done) ...[
                                  Icon(Icons.check_circle_rounded, color: Colors.green, size: 18 * scale),
                                  SizedBox(width: 4 * scale),
                                  Text(L.t('Completed', 'Tapos na'),
                                      style: TextStyle(color: Colors.green, fontSize: 14 * scale, fontWeight: FontWeight.w900)),
                                ] else
                                  Text(p == null ? '…' : '$pct%', style: TextStyle(color: accent, fontSize: 20 * scale, fontWeight: FontWeight.w900)),
                                SizedBox(width: 6 * scale),
                                AnimatedRotation(
                                  turns: _open ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 220),
                                  child: Container(
                                    padding: EdgeInsets.all(2 * scale),
                                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                                    child: Icon(Icons.keyboard_arrow_down_rounded, color: accent, size: 22 * scale),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12 * scale),
                            ProgressBar3D(value: p?.percent ?? 0, color: accent, height: 16 * scale, label: p == null ? null : '$pct%'),
                            AnimatedCrossFade(
                              firstChild: const SizedBox(width: double.infinity),
                              secondChild: breakdown,
                              crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 240),
                              sizeCurve: Curves.easeOut,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Tutorial / Practice card of a module page (every category): picture,
/// title, the button, and for the tutorial the signs learned so far
/// ([progress]: tutorial signs mastered of the module's lessons, live).
class ModuleLearnCard extends StatelessWidget {
  final double scale;
  final String image;
  final String title;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Shows "Signs learned" with its bar (the tutorial card).
  final ModuleSource? progress;

  /// Size of the picture inside its round tile (1 = fills it). The two
  /// pictures have different margins, so each is sized to look the same.
  final double imageScale;

  const ModuleLearnCard({
    super.key,
    required this.scale,
    required this.image,
    required this.title,
    required this.icon,
    required this.label,
    required this.onTap,
    this.progress,
    this.imageScale = 1.0,
  });

  Widget _signs(BuildContext context, ModuleSource source) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(),
      builder: (context, user) {
        final data = (user.data?.data() as Map<String, dynamic>?) ?? const {};
        return FutureBuilder<({int lessons, List<String> levels})>(
          future: source.totals(),
          builder: (context, t) {
            final p = t.hasData ? source.progress(data, t.data!) : null;
            final learned = p == null ? 0 : p.mastered.clamp(0, p.lessons);
            final ratio = p == null || p.lessons == 0 ? 0.0 : learned / p.lessons;
            final done = p != null && p.lessons > 0 && learned >= p.lessons;
            final color = done ? Colors.green : theme.primaryColor;
            return Padding(
              padding: EdgeInsets.only(bottom: 10 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(L.t('Signs learned', 'Natutunang senyas'),
                            style: TextStyle(color: textColor.withValues(alpha: 0.75), fontSize: 12.5 * scale, fontWeight: FontWeight.w700)),
                      ),
                      Text(p == null ? '…' : '$learned / ${p.lessons}',
                          style: TextStyle(color: color, fontSize: 13 * scale, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  SizedBox(height: 5 * scale),
                  ProgressBar3D(value: ratio, color: color, height: 10 * scale),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.primaryColor;
    final textColor = theme.colorScheme.onSurface;
    // Practice has no progress bar: a short line keeps both cards the same height.
    final subtitle = progress == null
        ? L.t('Sign with the camera and get instant feedback.', 'Kumumpas sa camera at alamin agad ang resulta.')
        : null;
    return Container(
      height: 172 * scale,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24 * scale),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.cardColor, Color.lerp(theme.cardColor, accent, 0.08)!],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.22), width: 1.5),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.18), offset: Offset(0, 5 * scale)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: Offset(0, 8 * scale)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(24 * scale),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(14 * scale),
            child: Row(
              children: [
                // Same tile for every picture, whatever its own size / shape.
                Container(
                  width: 124 * scale,
                  height: 124 * scale,
                  padding: EdgeInsets.all(6 * scale),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [accent.withValues(alpha: 0.10), accent.withValues(alpha: 0.26)],
                    ),
                    border: Border.all(color: accent.withValues(alpha: 0.35), width: 2),
                  ),
                  child: ClipOval(child: Transform.scale(scale: imageScale, child: Image.asset(image, fit: BoxFit.contain))),
                ),
                SizedBox(width: 14 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: textColor, fontSize: 22 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1)),
                      SizedBox(height: 6 * scale),
                      if (progress != null)
                        _signs(context, progress!)
                      else
                        Padding(
                          padding: EdgeInsets.only(bottom: 10 * scale),
                          child: Text(subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 12.5 * scale, fontWeight: FontWeight.w600, height: 1.25)),
                        ),
                      SizedBox(
                        height: 38 * scale,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: theme.colorScheme.onPrimary,
                            elevation: 0,
                            shape: Button3DBorder(borderRadius: BorderRadius.circular(20 * scale)),
                            padding: EdgeInsets.symmetric(horizontal: 14 * scale),
                          ),
                          icon: Icon(icon, size: 18 * scale),
                          label: Text(label, style: TextStyle(fontSize: 13.5 * scale, fontWeight: FontWeight.w800)),
                          onPressed: onTap,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A module on the Modules page (the 4 built-in modules and every web app
/// category) as a glass card: its picture, name and completion, the
/// industry-standard progress of a course (Duolingo units, Khan Academy
/// mastery): % complete, signs mastered and activity stars, out of what the
/// module has now. Locked modules are dimmed with a lock; guests (no
/// progress) see an Explore pill. Pushes in when tapped.
class ModuleCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget picture;
  final ModuleSource source;
  final Map<String, dynamic> userData;
  final bool locked;
  final String? lockedHint;
  final bool showProgress;
  final VoidCallback? onTap;
  final double scale;

  const ModuleCard({
    super.key,
    required this.title,
    required this.picture,
    required this.source,
    required this.userData,
    this.subtitle,
    this.locked = false,
    this.lockedHint,
    this.showProgress = true,
    this.onTap,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(22 * scale);
    if (!showProgress) return _card(context, r, null);
    return FutureBuilder<({int lessons, List<String> levels})>(
      future: source.totals(),
      builder: (context, snap) => _card(context, r, snap.hasData ? source.progress(userData, snap.data!) : null),
    );
  }

  Widget _card(BuildContext context, BorderRadius r, ModuleProgress? p) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final done = p?.completed ?? false;
    final accent = done ? Colors.green : theme.primaryColor;
    final pct = ((p?.percent ?? 0) * 100).round();

    Widget stat(IconData icon, Color color, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14 * scale, color: color),
            SizedBox(width: 3 * scale),
            Text(text, style: TextStyle(color: textColor.withValues(alpha: 0.75), fontSize: 11.5 * scale, fontWeight: FontWeight.w800)),
          ],
        );

    return Pressable3D(
      radius: r,
      enabled: !locked,
      child: GestureDetector(
        onTap: locked ? null : onTap,
        child: ClipRRect(
          borderRadius: r,
          child: SmartBlur(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardColor.withValues(alpha: 0.78),
                borderRadius: r,
                border: Border.all(color: (locked ? theme.dividerColor : accent).withValues(alpha: 0.35), width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 6))],
              ),
              child: Opacity(
                opacity: locked ? 0.55 : 1.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Padding(padding: EdgeInsets.all(10 * scale), child: picture),
                          if (locked)
                            Center(
                              child: Container(
                                padding: EdgeInsets.all(12 * scale),
                                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                                child: Icon(Icons.lock_rounded, color: Colors.white, size: 30 * scale),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(12 * scale, 0, 12 * scale, 12 * scale),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.w900, letterSpacing: -0.4, height: 1.1)),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            SizedBox(height: 2 * scale),
                            Text(subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 11.5 * scale, fontWeight: FontWeight.w600)),
                          ],
                          SizedBox(height: 8 * scale),
                          if (showProgress) ...[
                            Wrap(
                              spacing: 10 * scale,
                              runSpacing: 2 * scale,
                              children: [
                                stat(Icons.back_hand_rounded, theme.primaryColor,
                                    p == null ? '…' : '${p.mastered.clamp(0, p.lessons)}/${p.lessons}'),
                                stat(Icons.star_rounded, const Color(0xFFFFC107), p == null ? '…' : '${p.stars}/${p.maxStars}'),
                              ],
                            ),
                            SizedBox(height: 6 * scale),
                            ProgressBar3D(value: p?.percent ?? 0, color: accent, height: 10 * scale),
                            SizedBox(height: 5 * scale),
                            Text(
                              locked
                                  ? (lockedHint ?? L.t('Locked', 'Naka-lock'))
                                  : (p == null
                                      ? L.t('Loading...', 'Kinukuha...')
                                      : (done ? L.t('Completed', 'Tapos na') : L.t('$pct% complete', '$pct% tapos'))),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: done ? Colors.green : textColor.withValues(alpha: 0.55), fontSize: 11 * scale, fontWeight: FontWeight.w700),
                            ),
                          ] else
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 6 * scale),
                              decoration: BoxDecoration(color: theme.primaryColor, borderRadius: BorderRadius.circular(20 * scale)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(L.t('Explore', 'Tuklasin'),
                                      style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 13 * scale, fontWeight: FontWeight.w800)),
                                  SizedBox(width: 4 * scale),
                                  Icon(Icons.arrow_forward_rounded, size: 15 * scale, color: theme.colorScheme.onPrimary),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Category interface: same layout as AlphabetInterface / NumbersInterface /
// PhraseInterface / CivicInterface (progress, Tutorial, Practice, Activity +
// Challenges, stars / challenge XP), with the content read live from Firestore.
// =============================================================================

/// A lesson of a web-app category (tutorial_lessons).
class CloudLesson {
  final String id;
  final String title;
  final String media;

  /// gestureKey / symbol of the lesson (matched with a published model's
  /// classes[].lessonSymbol).
  final String symbol;
  const CloudLesson({required this.id, required this.title, required this.media, this.symbol = ''});

  String get key => ProgressService.masteryKey(title);
}

Stream<List<CloudLesson>> _lessonsOf(CloudCategory c) => FirebaseFirestore.instance
    .collection('tutorial_lessons')
    .where('category', whereIn: c.aliases)
    .snapshots()
    .map((snap) {
  final docs = [...snap.docs]
    ..sort((a, b) => ((a.data()['order'] as num?) ?? 0).compareTo((b.data()['order'] as num?) ?? 0));
  return [
    for (final d in docs)
      CloudLesson(
        id: d.id,
        title: (d.data()['displayTitle'] ?? d.data()['gestureKey'] ?? d.data()['title'] ?? d.data()['label'] ?? 'Lesson')
            .toString(),
        symbol: (d.data()['symbol'] ?? d.data()['gestureKey'] ?? '').toString(),
        media: (d.data()['videoUrl'] ?? d.data()['video_url'] ?? d.data()['image_url'] ?? d.data()['imageUrl'] ??
                d.data()['imageStoragePath'] ?? d.data()['imagePath'] ?? '')
            .toString(),
      ),
  ];
});

class CloudCategoryScreen extends StatelessWidget {
  final CloudCategory category;
  final int targetXp;
  const CloudCategoryScreen({super.key, required this.category, this.targetXp = 1000});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final roles = context.roles;
    final canProgress = roles.can(AppFeature.progress);
    final canActivities = roles.can(AppFeature.activities);
    final canPractice = roles.can(AppFeature.practice);
    final canTutorials = roles.can(AppFeature.tutorials);

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(),
      builder: (context, snapshot) {
        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: theme.cardColor.withValues(alpha: 0.4),
            elevation: 0,
            centerTitle: true,
            iconTheme: IconThemeData(color: textColor),
            flexibleSpace: ClipRRect(
              child: SmartBlur(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(color: Colors.transparent)),
            ),
            title: Text(category.title,
                style: TextStyle(color: textColor, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96)),
            actions: [
              Padding(padding: const EdgeInsets.only(right: 16.0), child: Image.asset("assets/pictures/image 66.png", width: 45)),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final double scale = Responsive.scale(constraints.maxWidth);
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: -50, left: -50,
                    child: Container(width: 250, height: 250,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primaryColor.withValues(alpha: 0.3))),
                  ),
                  Positioned(
                    top: 400, right: -100,
                    child: Container(width: 300, height: 300,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.secondary.withValues(alpha: 0.2))),
                  ),
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.only(top: 110 * scale, bottom: 40 * scale, left: 16 * scale, right: 16 * scale),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (canTutorials) ...[
                            ModuleLearnCard(
                              scale: scale,
                              image: "assets/pictures/tutor.png",
                              imageScale: 0.82,
                              progress: canProgress ? ModuleSource.cloud(category) : null,
                              title: 'Tutorial',
                              icon: Icons.play_arrow_rounded,
                              label: 'Start Learn',
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => CloudTutorialListScreen(category: category))),
                            ),
                            SizedBox(height: 16 * scale),
                          ],
                          if (canPractice) ...[
                            ModuleLearnCard(
                              scale: scale,
                              image: "assets/pictures/practice.png",
                              imageScale: 1.3,
                              title: 'Practice',
                              icon: Icons.camera_alt_rounded,
                              label: 'Train Sign',
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => CloudPracticeScreen(category: category))),
                            ),
                            SizedBox(height: 24 * scale),
                          ],
                          if (!canActivities) GuestModuleGuide(scale: scale),
                          if (canActivities) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(children: [
                                    Text('Activity',
                                        style: TextStyle(color: textColor, fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44)),
                                    SizedBox(height: 12 * scale),
                                    GestureDetector(
                                      onTap: () => Navigator.push(context,
                                          MaterialPageRoute(
                                              builder: (_) => PhraseDifficultySelectionScreen(
                                                    config: ActivityCategoryConfig(
                                                      aliases: category.aliases,
                                                      title: category.title,
                                                      categoryId: category.id,
                                                      moduleKey: category.id,
                                                      xpField: category.xpField,
                                                    ),
                                                  ))),
                                      child: PictureButton3D(picture: Image.asset("assets/pictures/actt.png", width: 164 * scale, height: 160 * scale, fit: BoxFit.cover)),
                                    ),
                                  ]),
                                ),
                                SizedBox(width: 16 * scale),
                                Expanded(
                                  child: Column(children: [
                                    Text('Challenges',
                                        style: TextStyle(color: textColor, fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44)),
                                    SizedBox(height: 12 * scale),
                                    GestureDetector(
                                      onTap: () => Navigator.push(context,
                                          MaterialPageRoute(builder: (_) => const LeaderboardScreen(initialTab: 'challenges'))),
                                      child: PictureButton3D(picture: Image.asset("assets/pictures/battle.png", width: 159 * scale, height: 159 * scale, fit: BoxFit.cover)),
                                    ),
                                  ]),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// =============================================================================
// Tutorial list (green outline = mastered) and lesson screen
// =============================================================================

/// Same layout as the built-in tutorial lists (PhraseTutorialInterface):
/// blurred app bar, soft background circles, a search bar and the lesson
/// cards (green outline = mastered).
class CloudTutorialListScreen extends StatefulWidget {
  final CloudCategory category;
  const CloudTutorialListScreen({super.key, required this.category});

  @override
  State<CloudTutorialListScreen> createState() => _CloudTutorialListScreenState();
}

class _CloudTutorialListScreenState extends State<CloudTutorialListScreen> {
  late final Stream<List<CloudLesson>> _lessons = _lessonsOf(widget.category);
  late final Stream<Set<String>> _mastered = ProgressService().masteredTutorialLines(widget.category.id);
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.6),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        flexibleSpace: ClipRRect(
          child: SmartBlur(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1), width: 0.5)),
              ),
            ),
          ),
        ),
        title: Text('${widget.category.title} Tutorial',
            style: TextStyle(color: textColor, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96)),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primaryColor.withValues(alpha: 0.25)),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF4CAF50).withValues(alpha: 0.15)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20.0, 15.0, 20.0, 10.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SmartBlur(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.cardColor.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15), width: 1.5),
                        ),
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            hintText: L.t('Search sign...', 'Maghanap ng senyas...'),
                            hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5), fontWeight: FontWeight.w500),
                            prefixIcon: Icon(Icons.search, color: textColor.withValues(alpha: 0.5)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<CloudLesson>>(
                    stream: _lessons,
                    builder: (context, snap) {
                      if (!snap.hasData) return Center(child: CircularProgressIndicator(color: theme.primaryColor));
                      final all = snap.data!;
                      if (all.isEmpty) {
                        return _EmptyNote(
                            text: L.t('No tutorials yet. Your teachers will add them soon.',
                                'Wala pang tutorial. Idaragdag ito ng iyong mga guro.'));
                      }
                      final shown = [
                        for (var i = 0; i < all.length; i++)
                          if (_query.isEmpty || all[i].title.toLowerCase().contains(_query)) i
                      ];
                      if (shown.isEmpty) {
                        return Center(
                          child: Text(L.t('No signs found.', 'Walang nahanap na senyas.'),
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.6))),
                        );
                      }
                      return StreamBuilder<Set<String>>(
                        stream: _mastered,
                        builder: (context, m) {
                          final mastered = m.data ?? const <String>{};
                          return ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            itemCount: shown.length,
                            itemBuilder: (context, k) {
                              final i = shown[k];
                              return _LessonCard(
                                title: all[i].title,
                                mastered: mastered.contains(all[i].key),
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            CloudLessonScreen(category: widget.category, lessons: all, initialIndex: i))),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final String title;
  final bool mastered;
  final VoidCallback onTap;
  const _LessonCard({required this.title, required this.mastered, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SmartBlur(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                color: theme.cardColor.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: mastered ? Colors.green.withValues(alpha: 0.75) : theme.primaryColor.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, fontFamily: 'Inter', color: textColor, letterSpacing: -1.0)),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.3), blurRadius: 8, spreadRadius: 1)],
                    ),
                    child: Icon(Icons.play_arrow_rounded, color: theme.primaryColor, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_rounded, size: 44, color: textColor.withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: textColor.withValues(alpha: 0.65), fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

/// Same layout and sizes as the built-in tutorial detail screens
/// (PhraseTutorialDetail): sign name, a 299 x 276 media box, the progress
/// bar, Previous / Next and the Practice button, all scaled from a 393-wide
/// screen.
class CloudLessonScreen extends StatefulWidget {
  final CloudCategory category;
  final List<CloudLesson> lessons;
  final int initialIndex;
  const CloudLessonScreen({super.key, required this.category, required this.lessons, required this.initialIndex});

  @override
  State<CloudLessonScreen> createState() => _CloudLessonScreenState();
}

class _CloudLessonScreenState extends State<CloudLessonScreen> {
  late int _i = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final lesson = widget.lessons[_i];
    final n = widget.lessons.length;
    final label = lesson.title;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.cardColor.withValues(alpha: 0.4),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        flexibleSpace: ClipRRect(
          child: SmartBlur(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(color: Colors.transparent)),
        ),
        title: Text('Tutorial', style: TextStyle(color: textColor, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800)),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primaryColor.withValues(alpha: 0.2)),
            ),
          ),
          Positioned(
            bottom: 150,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.secondary.withValues(alpha: 0.15)),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = Responsive.scale(constraints.maxWidth);
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(vertical: 10 * scale),
                  child: Center(
                    child: SizedBox(
                      width: 299 * scale,
                      child: Column(
                        children: [
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: textColor,
                              fontSize: label.length > 22 ? 26 * scale : (label.length > 12 ? 36 * scale : 52 * scale),
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                          SizedBox(height: 18 * scale),
                          Container(
                            width: 299 * scale,
                            height: 276 * scale,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16 * scale),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 15, offset: const Offset(0, 8))],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16 * scale),
                              child: ColoredBox(
                                color: theme.cardColor,
                                child: _CloudMedia(key: ValueKey(lesson.media), source: lesson.media, fit: BoxFit.cover),
                              ),
                            ),
                          ),
                          SizedBox(height: 34 * scale),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(25 * scale),
                            child: SizedBox(
                              width: 295 * scale,
                              child: ProgressBar3D(value: ((_i + 1) / n).toDouble(), color: theme.colorScheme.secondary, height: 14 * scale, trackColor: theme.cardColor.withValues(alpha: 0.4)),
                            ),
                          ),
                          SizedBox(height: 26 * scale),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                onPressed: _i > 0 ? () => setState(() => _i--) : null,
                                icon: Icon(Icons.arrow_back, color: textColor, size: 18 * scale),
                                label: Text(L.t('Previous', 'Nakaraan'),
                                    style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                              ),
                              TextButton(
                                onPressed: _i < n - 1 ? () => setState(() => _i++) : null,
                                child: Row(children: [
                                  Text(L.t('Next', 'Susunod'),
                                      style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                                  SizedBox(width: 8 * scale),
                                  Icon(Icons.arrow_forward, color: textColor, size: 18 * scale),
                                ]),
                              ),
                            ],
                          ),
                          SizedBox(height: 30 * scale),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(25 * scale),
                              boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 5))],
                            ),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primaryColor,
                                foregroundColor: theme.colorScheme.onPrimary,
                                minimumSize: Size(299 * scale, 50 * scale),
                                shape: Button3DBorder(borderRadius: BorderRadius.circular(25 * scale)),
                                elevation: 0,
                              ),
                              onPressed: () => Navigator.push(
                                  context, MaterialPageRoute(builder: (_) => practiceFor(widget.category, lesson))),
                              child: Text(L.t('Practice', 'Pagsasanay'),
                                  style: TextStyle(fontSize: 22 * scale, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Camera practice
// =============================================================================

/// The camera practice for a lesson. A lesson that is a sign the app already
/// recognises uses that recogniser: a letter (A-Z) -> alphabet practice, a
/// number (1-100) -> numbers practice, a greeting -> phrase practice. Any
/// other sign has no trained model yet and gets [CloudMirrorPractice]: the
/// demo next to the camera, hands tracked live, and a self-check.
///
/// When an administrator published a model for the category
/// (published_gesture_models, active) and the lesson is one of its signs,
/// that model checks the sign instead ([_PublishedOrBuiltIn]).
Widget practiceFor(CloudCategory category, CloudLesson lesson, {VoidCallback? onDone, String? progressLabel}) =>
    _PublishedOrBuiltIn(category: category, lesson: lesson, onDone: onDone, progressLabel: progressLabel);

Widget _builtInPracticeFor(CloudCategory category, CloudLesson lesson, {VoidCallback? onDone}) {
  final t = lesson.title.trim();
  if (RegExp(r'^[A-Za-z]$').hasMatch(t)) return TutorialPractice(targetLetter: t.toUpperCase());
  final n = int.tryParse(t);
  if (n != null && n >= 1 && n <= 100) return NumbersTutorialPractice(targetNumber: '$n');
  if (PhraseRecognizer.classIndexFor(t) != -1) return PhraseTutorialPractice(targetPhrase: t, mediaUrl: lesson.media);
  return CloudMirrorPractice(category: category, lesson: lesson, onDone: onDone);
}

/// Looks up the category's published model (cached per session), then opens
/// its practice, or the built-in practice when there is no model, it is
/// inactive, Firestore cannot be read, or the lesson is not one of its signs.
class _PublishedOrBuiltIn extends StatelessWidget {
  final CloudCategory category;
  final CloudLesson lesson;
  final VoidCallback? onDone;
  final String? progressLabel;
  const _PublishedOrBuiltIn({required this.category, required this.lesson, this.onDone, this.progressLabel});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PublishedGestureModel?>(
      future: PublishedGestureModels.forCategory(category.id),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(body: Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)));
        }
        final model = snap.data;
        final target = model?.classForLesson([lesson.symbol, lesson.title]);
        if (model != null && target != null) {
          return CloudModelPractice(
            key: ValueKey('${model.modelId}/${lesson.id}'),
            category: category,
            lesson: lesson,
            model: model,
            target: target,
            onDone: onDone,
            progressLabel: progressLabel,
          );
        }
        final screen = _builtInPracticeFor(category, lesson, onDone: onDone);
        if (onDone == null) return screen;
        if (screen is CloudMirrorPractice) {
          return CloudMirrorPractice(
            key: ValueKey(lesson.id),
            category: category,
            lesson: lesson,
            onDone: onDone,
            progressLabel: progressLabel,
          );
        }
        // A sign with its own recogniser: that practice screen, then the next one.
        return _RecognizerStep(key: ValueKey(lesson.id), screen: screen, lesson: lesson, onNext: onDone!,
            progressLabel: progressLabel ?? '');
      },
    );
  }
}

/// Continuous practice over the category's lessons (like the other modules'
/// "Train Sign"): starts at the first lesson not mastered yet.
class CloudPracticeScreen extends StatelessWidget {
  final CloudCategory category;
  const CloudPracticeScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<CloudLesson>>(
      stream: _lessonsOf(category),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Scaffold(body: Center(child: CircularProgressIndicator(color: theme.primaryColor)));
        }
        final lessons = snap.data!;
        if (lessons.isEmpty) {
          return Scaffold(
            appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
            body: const _EmptyNote(text: 'Nothing to practise yet. Lessons will appear here once added.'),
          );
        }
        return TutorialSessionPractice(
          title: '${category.label} Practice',
          category: category.id,
          categoryName: category.label,
          xpField: category.xpField,
          signs: [for (final l in lessons) PracticeSign(l.title, media: l.media)],
        );
      },
    );
  }
}

class _RecognizerStep extends StatelessWidget {
  final Widget screen;
  final CloudLesson lesson;
  final VoidCallback onNext;
  final String progressLabel;
  const _RecognizerStep({super.key, required this.screen, required this.lesson, required this.onNext, required this.progressLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(progressLabel, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w800)),
        actions: [TextButton(onPressed: onNext, child: const Text('Skip'))],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(lesson.title, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('Practise with the camera'),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
                  onNext();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Camera practice for a sign without a trained model: the lesson demo next
/// to the live front camera; the hands are tracked (hand_landmarker) and the
/// learner can confirm the sign after holding it in view for a moment.
class CloudMirrorPractice extends StatefulWidget {
  final CloudCategory category;
  final CloudLesson lesson;
  final VoidCallback? onDone;
  final String? progressLabel;
  const CloudMirrorPractice({super.key, required this.category, required this.lesson, this.onDone, this.progressLabel});

  @override
  State<CloudMirrorPractice> createState() => _CloudMirrorPracticeState();
}

class _CloudMirrorPracticeState extends State<CloudMirrorPractice> {
  static const int _needHandsMs = 1500;

  CameraController? _camera;
  HandLandmarkerPlugin? _landmarker;
  StreamSubscription<List<Hand>>? _handSub;
  final FrameGate _gate = FrameGate();
  bool _handsVisible = false;
  int _handsMs = 0;
  int? _lastHandFrameMs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      _landmarker = HandLandmarkerPlugin.create(numHands: 2, minHandDetectionConfidence: 0.5, delegate: HandLandmarkerDelegate.gpu);
      _handSub = _landmarker!.landmarkStream.listen(_onHands);
      final cams = await availableCameras();
      final cam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final c = CameraController(cam, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _camera = c);
      await c.startImageStream((img) {
        LightingMonitor.instance.onImage(img); // low-light warning
        if (_landmarker == null || !_gate.tryEnter()) return;
        try {
          _landmarker!.processFrame(img, _rotation(c));
        } catch (_) {
          _gate.done();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera unavailable: $e');
    }
  }

  static int _rotation(CameraController c) {
    final sensor = c.description.sensorOrientation;
    final ccw = switch (c.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    return c.description.lensDirection == CameraLensDirection.front ? (sensor + ccw) % 360 : (sensor - ccw + 360) % 360;
  }

  void _onHands(List<Hand> hands) {
    _gate.done();
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final visible = hands.isNotEmpty;
    if (visible && _lastHandFrameMs != null) _handsMs += (now - _lastHandFrameMs!).clamp(0, 300);
    _lastHandFrameMs = visible ? now : null;
    if (visible != _handsVisible || (visible && _handsMs < _needHandsMs + 300)) {
      setState(() => _handsVisible = visible);
    }
  }

  bool _confirmed = false;

  Future<void> _confirm() async {
    if (_confirmed) return;
    _confirmed = true;
    // Same rewards and feedback as the other categories' practice.
    await practiceSuccessHaptics();
    final xp = await _cloudAwardMastery(widget.category, widget.lesson, continuous: widget.onDone != null);
    if (!mounted) return;
    await showPracticeMasteredDialog(context, signName: widget.lesson.title, xpGained: xp);
    if (!mounted) return;
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _handSub?.cancel();
    _camera?.stopImageStream().catchError((_) {});
    _camera?.dispose();
    _landmarker?.dispose();
    super.dispose();
  }

  // Same look as the built-in tutorial practices (numbers_tutorial_practice):
  // blurred app bar, ambient icons, square demo + camera, PracticeFeedback.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;
    final ready = _handsMs >= _needHandsMs;
    final hold = (_handsMs / _needHandsMs).clamp(0.0, 1.0);
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final paneWidth = MediaQuery.sizeOf(context).width * (landscape ? 0.45 : 1.0);
    final c = _camera;
    final title = widget.lesson.title;

    final Widget cameraPane = Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(width: 4.0, color: ready ? Colors.greenAccent : theme.dividerColor.withValues(alpha: 0.6)),
            boxShadow: [
              if (ready)
                BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.6), blurRadius: 25, spreadRadius: 2)
              else
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: c != null && c.value.isInitialized
                ? _MirrorCameraView(controller: c)
                : Center(
                    child: _error != null
                        ? Padding(padding: const EdgeInsets.all(12), child: Text(_error!, textAlign: TextAlign.center))
                        : CircularProgressIndicator(color: theme.primaryColor),
                  ),
          ),
        ),
        if (c != null && c.value.isInitialized)
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _handsVisible ? Colors.greenAccent.withValues(alpha: 0.9) : Colors.white54,
                  width: _handsVisible ? 4.0 : 3.0,
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SmartBlur(
                    filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: Colors.black45,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_handsVisible) ...[
                            const Icon(Icons.stars_rounded, color: Colors.greenAccent, size: 12),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            ready ? 'Great!' : (_handsVisible ? 'Hold!' : 'Frame Hand'),
                            style: TextStyle(
                              color: _handsVisible ? Colors.greenAccent : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.cardColor.withValues(alpha: 0.4),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: onSurface),
        flexibleSpace: ClipRRect(
          child: SmartBlur(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(color: Colors.transparent)),
        ),
        title: Text(
          widget.progressLabel ?? 'Tutorial Practice',
          style: TextStyle(color: onSurface, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96),
        ),
        actions: [
          if (widget.onDone != null) TextButton(onPressed: widget.onDone, child: const Text('Skip')),
        ],
      ),
      body: Stack(
        children: [
          Positioned(
            top: -20,
            right: -20,
            child: Opacity(
              opacity: 0.12,
              child: Transform.rotate(angle: -0.2, child: Icon(Icons.wb_sunny_rounded, size: 220, color: theme.primaryColor)),
            ),
          ),
          Positioned(
            bottom: 40,
            left: -30,
            child: Opacity(
              opacity: 0.10,
              child: Transform.rotate(angle: 0.3, child: Icon(Icons.auto_awesome_rounded, size: 240, color: theme.colorScheme.secondary)),
            ),
          ),
          SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        children: [
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: onSurface,
                              fontSize: title.length > 18 ? 28 : 42,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Inter',
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: paneWidth * 0.60,
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.grey.shade900 : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: _CloudMedia(source: widget.lesson.media, fit: BoxFit.cover),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (!landscape)
                            SizedBox(width: paneWidth * 0.60, child: AspectRatio(aspectRatio: 1, child: cameraPane)),
                          const SizedBox(height: 16),
                          PracticeFeedback(
                            message: ready
                                ? 'Nice! Compare your sign with the demo, then tap "I signed it".'
                                : (_handsVisible ? 'Keep your hands in view…' : 'Show your hands to the camera and sign along with the demo.'),
                            tone: ready ? FeedbackTone.success : FeedbackTone.info,
                          ),
                          const SizedBox(height: 12),
                          if (!ready && hold > 0) ...[
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.workspace_premium_rounded, color: Colors.green, size: 20),
                                SizedBox(width: 6),
                                Text('Hold steady...', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 18)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SmartBlur(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Container(
                                  width: paneWidth * 0.70,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: theme.colorScheme.surface.withValues(alpha: 0.5), width: 1),
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: hold,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(colors: [Colors.greenAccent, Colors.green]),
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.5), blurRadius: 10)],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          SizedBox(
                            width: paneWidth * 0.70,
                            height: 52,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primaryColor,
                                foregroundColor: theme.colorScheme.onPrimary,
                                disabledBackgroundColor: theme.dividerColor,
                                shape: Button3DBorder(borderRadius: BorderRadius.circular(28)),
                              ),
                              onPressed: ready ? _confirm : null,
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('I signed it', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, fontFamily: 'Inter')),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Watch the demo, sign along, and tap the button when your sign matches.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: onSurface.withValues(alpha: 0.55), fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (landscape)
                  Expanded(
                    flex: 6,
                    child: Padding(padding: const EdgeInsets.fromLTRB(0, 10, 16, 16), child: cameraPane),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Camera preview scaled to cover its box without stretching, with the soft
/// vignette of the other tutorial practices.
class _MirrorCameraView extends StatelessWidget {
  final CameraController controller;
  const _MirrorCameraView({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final size = value.previewSize;
        if (!value.isInitialized || size == null) return const ColoredBox(color: Colors.black);
        final landscape = value.deviceOrientation == DeviceOrientation.landscapeLeft ||
            value.deviceOrientation == DeviceOrientation.landscapeRight;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.05,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.28)],
              stops: const [0.62, 1.0],
            ),
          ),
          child: ColoredBox(
            color: Colors.black,
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: landscape ? size.longestSide : size.shortestSide,
                  height: landscape ? size.shortestSide : size.longestSide,
                  child: CameraPreview(controller),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Activity levels (students)
// =============================================================================

class CloudActivityLevelsScreen extends StatelessWidget {
  final CloudCategory category;
  const CloudActivityLevelsScreen({super.key, required this.category});

  static int _levelNumber(String level) => int.tryParse(RegExp(r'(\d+)(?!.*\d)').firstMatch(level)?.group(1) ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    return RoleGuard(
      feature: AppFeature.activities,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: textColor),
          title: Text('${category.title} Activity',
              style: TextStyle(color: textColor, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96)),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('activity_questions').where('category', whereIn: category.aliases).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return Center(child: CircularProgressIndicator(color: theme.primaryColor));
            final counts = <String, int>{};
            for (final d in snap.data!.docs) {
              final level = (d.data()['level'] ?? '').toString();
              if (level.isNotEmpty) counts[level] = (counts[level] ?? 0) + 1;
            }
            final levels = counts.keys.toList()
              ..sort((a, b) => _levelNumber(a) != _levelNumber(b) ? _levelNumber(a).compareTo(_levelNumber(b)) : a.compareTo(b));
            if (levels.isEmpty) return const _EmptyNote(text: 'No activities yet. Your teachers will add them soon.');
            return ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              itemCount: levels.length,
              itemBuilder: (context, i) {
                final n = _levelNumber(levels[i]) > 0 ? _levelNumber(levels[i]) : i + 1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Material(
                    color: theme.cardColor.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PhraseActivityInterface(
                            levelId: levels[i],
                            title: '${category.title} Activities',
                            category: category.id,
                            moduleKey: category.id,
                            xpField: category.xpField,
                          ),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.45), width: 1.5),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: theme.primaryColor,
                              child: Text('$n', style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900)),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Level $n', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                                  Text('${counts[levels[i]]} question${counts[levels[i]] == 1 ? '' : 's'}',
                                      style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 13)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: theme.primaryColor),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// =============================================================================
// Camera practice with a published model (web content management)
// =============================================================================

/// Practice for a sign of a web-app category whose model an administrator
/// published (published_gesture_models). Body + both hands are tracked
/// natively (fsl_holistic_channel) while the learner records the sign, and
/// the capture is sent to `POST <serviceUrl>/v1/predict_raw/<modelId>`.
class CloudModelPractice extends StatefulWidget {
  final CloudCategory category;
  final CloudLesson lesson;
  final PublishedGestureModel model;
  final PublishedGestureClass target;

  /// Continuous practice: Skip, a "Sign 2 of 12" header, and [onDone] after a
  /// correct sign instead of a dialog.
  final VoidCallback? onDone;
  final String? progressLabel;

  const CloudModelPractice({
    super.key,
    required this.category,
    required this.lesson,
    required this.model,
    required this.target,
    this.onDone,
    this.progressLabel,
  });

  @override
  State<CloudModelPractice> createState() => _CloudModelPracticeState();
}

class _CloudModelPracticeState extends State<CloudModelPractice> with WidgetsBindingObserver {
  // Hands must be gone this long before the recording stops by itself.
  static const int _autoStopAfterMs = 1500;
  // A manual stop drops the reach to the screen.
  static const int _manualStopTrimMs = 600;
  static const Duration _maxRecording = Duration(seconds: 6);
  static const int _maxInFlight = 2;

  CameraController? _camera;
  String? _error;
  bool _disposed = false;

  // Live tracking
  int _inFlight = 0;
  bool _handsVisible = false;
  bool _poseVisible = false;
  int _imageWidth = 0, _imageHeight = 0;
  String _engine = '';

  // Recording
  int _countdown = 0;
  Timer? _countdownTimer;
  Timer? _maxTimer;
  bool _recording = false;
  DateTime? _recordStart;
  bool _evaluating = false;
  bool _done = false;
  int _xpGained = 0; // XP actually awarded (0 when mastered before)
  final List<RawFrame> _frames = [];
  bool _sawHands = false;
  int _lastHandMs = 0;
  int _lastUiMs = 0;

  /// Debug: shape of the last capture (duration, coverage, ...).
  String _clipInfo = '';

  // Result
  String _title = '';
  String _message = '';
  FeedbackTone _tone = FeedbackTone.info;

  PublishedGestureModel get _model => widget.model;
  PublishedGestureClass get _target => widget.target;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => _error = L.t('No camera found on this device.', 'Walang camera sa device na ito.'));
        return;
      }
      final cam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final c = CameraController(cam, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await c.initialize();
      if (_disposed) {
        await c.dispose();
        return;
      }
      setState(() => _camera = c);
      await c.startImageStream(_onImage);
    } catch (e) {
      if (mounted) setState(() => _error = L.t('Camera unavailable: $e', 'Hindi magamit ang camera: $e'));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _camera;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cancelRecording();
      if (c.value.isStreamingImages) unawaited(c.stopImageStream().catchError((_) {}));
    } else if (state == AppLifecycleState.resumed && !c.value.isStreamingImages) {
      unawaited(c.startImageStream(_onImage).catchError((_) {}));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _maxTimer?.cancel();
    final c = _camera;
    _camera = null;
    if (c != null) {
      unawaited(() async {
        try {
          if (c.value.isStreamingImages) await c.stopImageStream();
        } catch (_) {}
        await c.dispose();
      }());
    }
    super.dispose();
  }

  /// A hand fully inside the image: hands resting at the bottom edge are
  /// still detected but cut off, and do not count as signing.
  static bool _handInFrame(List<List<double>>? hand) {
    if (hand == null || hand.isEmpty) return false;
    const m = 0.02;
    for (final p in hand) {
      if (p.length < 2 || p[0] < m || p[0] > 1 - m || p[1] < m || p[1] > 1 - m) return false;
    }
    return true;
  }

  /// One native Pose + Hands pass per camera frame (up to 2 in flight).
  Future<void> _onImage(CameraImage image) async {
    LightingMonitor.instance.onImage(image); // low-light warning
    final c = _camera;
    if (_disposed || _done || _evaluating || c == null || _inFlight >= _maxInFlight) return;
    _inFlight++;
    try {
      final r = await HolisticCapture.process(image, _CloudMirrorPracticeState._rotation(c));
      if (r == null || _disposed || !mounted) return;
      _imageWidth = r.imageWidth;
      _imageHeight = r.imageHeight;
      _engine = r.engine;
      final f = r.frame;
      final changed = f.hasHands != _handsVisible || r.poseVisible != _poseVisible;
      _handsVisible = f.hasHands;
      _poseVisible = r.poseVisible;
      if (!_recording) {
        if (changed) setState(() {});
        return;
      }
      _frames.add(f);
      if (_handInFrame(f.leftHand) || _handInFrame(f.rightHand)) {
        _sawHands = true;
        _lastHandMs = f.timeMs;
      } else if (_sawHands && f.timeMs - _lastHandMs > _autoStopAfterMs) {
        unawaited(_stopAndEvaluate()); // hands lowered: the sign is done
        return;
      }
      if (changed || f.timeMs - _lastUiMs > 250) {
        _lastUiMs = f.timeMs;
        setState(() {});
      }
    } catch (e) {
      debugPrint('Published model capture error: $e');
    } finally {
      _inFlight--;
    }
  }

  // ---- recording ------------------------------------------------------------

  void _toggleRecording() {
    if (_camera == null || _done || _evaluating) return;
    if (_countdown > 0) {
      _cancelRecording();
    } else if (_recording) {
      _stopAndEvaluate(manual: true);
    } else {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdown = 3;
      _title = '';
      _tone = FeedbackTone.info;
      _message = L.t('Lower your hands and get ready...', 'Ibaba ang mga kamay at pumwesto...');
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _disposed) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        _startRecording();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _startRecording() {
    _frames.clear();
    _sawHands = false;
    _lastHandMs = 0;
    setState(() {
      _countdown = 0;
      _recording = true;
      _recordStart = DateTime.now();
      _message = L.t('Sign now! Lower your hands when you are done.', 'Kumpas na! Ibaba ang mga kamay kapag tapos na.');
    });
    _maxTimer?.cancel();
    _maxTimer = Timer(_maxRecording, () => _stopAndEvaluate());
  }

  void _cancelRecording() {
    _countdownTimer?.cancel();
    _maxTimer?.cancel();
    _frames.clear();
    if (!mounted || _disposed) return;
    setState(() {
      _countdown = 0;
      _recording = false;
      _recordStart = null;
      _message = '';
    });
  }

  void _show(String title, String message, FeedbackTone tone) {
    if (!mounted || _disposed) return;
    setState(() {
      _evaluating = false;
      _title = title;
      _message = message;
      _tone = tone;
    });
  }

  // ---- evaluation -------------------------------------------------------------

  Future<void> _stopAndEvaluate({bool manual = false}) async {
    if (!_recording || _disposed) return;
    _recording = false;
    _recordStart = null;
    _maxTimer?.cancel();

    var frames = List<RawFrame>.of(_frames)..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    _frames.clear();
    if (manual && frames.isNotEmpty) {
      final cutoff = frames.last.timeMs - _manualStopTrimMs;
      frames = frames.where((f) => f.timeMs <= cutoff).toList();
    }
    if (!frames.any((f) => f.hasHands)) {
      _show(L.t('No hands detected', 'Walang nakitang kamay'), HolisticCapture.rejectAdvice['NO_HANDS']!, FeedbackTone.problem);
      return;
    }
    // Shape the capture like the web's training clips (see _TrainingClip).
    final all = frames;
    final settings = _target.practice;
    final clip = _TrainingClip.from(all, settings, tight: settings.tightFirst);
    _clipInfo = clip.describe();
    debugPrint('Published model capture: $_clipInfo');
    final problem = clip.problem();
    if (problem != null) {
      _show(problem.title, problem.message + (kDebugMode ? '\n\n[debug] $_clipInfo' : ''), FeedbackTone.problem);
      return;
    }
    frames = clip.frames;

    setState(() {
      _evaluating = true;
      _title = '';
      _tone = FeedbackTone.info;
      _message = L.t('Checking your sign...', 'Sinusuri ang kumpas...');
    });

    try {
      Future<RawPredictResponse> send(List<RawFrame> fs) {
        final s0 = fs.first.timeMs;
        // Upright landmarks + hands assigned to the pose wrists.
        final fixed = CaptureFixer.fix([for (final f in fs) f.toJson(s0)], _imageWidth, _imageHeight,
            reassignHands: !HolisticResult.isHolisticEngine(_engine));
        return HandSpeakApiService().predictRaw(
          modelId: _model.modelId,
          serviceUrl: _model.serviceUrl,
          frames: fixed.frames,
          imageWidth: fixed.imageWidth,
          imageHeight: fixed.imageHeight,
          topK: 10, // every sign's share (see _judge)
        );
      }

      // The capture is sent as the training-shaped clip first. If it does not
      // pass, the same capture is tried in other shapes, stopping at the first
      // that passes; otherwise the answer closest to a pass is used:
      //  - unsmoothed: the server's motion gates (LOW_MOTION, SINGLE_STROKE)
      //    were calibrated on training videos, and smoothing a slow phone
      //    camera's landmarks can push a real sign under them;
      //  - cut the other way (tight = the sign only, without raising /
      //    lowering the hands; or with the margin when tight went first):
      //    some training clips are the sign only (Setyembre: activeS =
      //    durationS = 2.08 s).
      final alt = _TrainingClip.from(all, settings, tight: !settings.tightFirst);
      final tries = <(String, List<RawFrame>)>[
        ('', frames),
        ('unsmoothed', clip.unsmoothed),
        if (alt.problem() == null) (settings.tightFirst ? 'with margin' : 'tight', alt.frames),
        if (alt.problem() == null) ('${settings.tightFirst ? 'with margin' : 'tight'}, unsmoothed', alt.unsmoothed),
      ];
      RawPredictResponse? result;
      var resultRank = -1.0;
      for (final (name, fs) in tries) {
        if (fs.length < 2) continue;
        final r = await send(fs);
        final a = _assess(r);
        debugPrint('Published model try ${name.isEmpty ? 'training clip' : name} (${fs.length} frames): '
            '${r.accepted ? 'accepted' : 'rejected ${r.rejection?.code ?? '-'} ${r.failedChecks}'}'
            '${a.passed ? ' PASS' : ''}, target share ${(a.share * 100).toStringAsFixed(0)}%'
            '${[for (final c in r.checks) if (!c.passed) ' | ${c.label} ${c.text}'].join()}');
        // A model answer beats a gate rejection; then the practised sign's share.
        final rank = (a.passed ? 10.0 : 0.0) + (r.topK.isNotEmpty ? 1.0 : 0.0) + a.share;
        if (rank > resultRank) {
          result = r;
          resultRank = rank;
          if (name.isNotEmpty) _clipInfo = '$name: ${name.startsWith('tight') || name.startsWith('with') ? alt.describe() : clip.describe()}';
        }
        // Other shapes only when the server's gates stopped the clip before the
        // model answered (no sign scores): a model answer is final, retrying it
        // in other cuts only fished for a pass (false positives).
        if (a.passed || r.topK.isNotEmpty || !mounted || _disposed) break;
      }
      if (result == null) return;
      if (!mounted || _disposed) return;
      debugPrint('Published model ${_model.modelId} response: ${result.raw}');
      _judge(result);
    } on ArgumentError catch (e) {
      // Rejected before upload (e.g. no body in most frames).
      debugPrint('Published model capture rejected client-side: ${e.message}');
      _show(
        L.t('Body not detected', 'Hindi makita ang katawan'),
        '${e.message}'.contains('Pose')
            ? L.t('Show your shoulders, body and hands to the camera.', 'Ipakita ang balikat, katawan at mga kamay sa camera.')
            : L.t('Could not send your sign. Try again.', 'Hindi maipadala ang kumpas. Subukang muli.'),
        FeedbackTone.problem,
      );
    } catch (e) {
      debugPrint('Published model prediction error: $e');
      _show(
        L.t('Try again', 'Subukang muli'),
        L.t('The model did not answer. Check your internet connection, then try again.',
            'Hindi sumagot ang model. Tingnan ang koneksyon sa internet, saka subukang muli.'),
        FeedbackTone.problem,
      );
    }
  }

  /// Practice check. On phone captures the model puts much of its weight on
  /// "not recognised" (the invalid class) even for correct signs, while the
  /// right sign still leads the other signs (10 of 12 months, 2026-10-30
  /// phone tests). The sign being practised is known, so it passes when it is
  /// confidently the top answer, or the model's best SIGN with a clear share
  /// of the sign probability and a lead over the next sign.
  /// Whether [result] passes the practice check (as in [_judge]) and the
  /// practised sign's share of the sign probability.
  // The confidence pass also needs the server's own verdict (accepted): its
  // margin vs "not recognised" check is what the web app's test passes on.
  ({bool passed, double share}) _assess(RawPredictResponse result) {
    double pct(Prediction p) => p.confidence > 1.0 ? p.confidence / 100.0 : p.confidence;
    bool isSign(Prediction p) => p.index != _model.invalidIndex && _model.classAt(p.index) != null;
    final signs = [for (final p in result.topK) if (isSign(p)) p];
    final invalid = result.topK.where((p) => !isSign(p)).fold<double>(0, (a, p) => a + pct(p));
    final mass = math.max(1.0 - invalid, 0.05);
    double share(Prediction? p) => p == null ? 0.0 : (pct(p) / mass).clamp(0.0, 1.0);
    final best = signs.isNotEmpty ? signs.first : null;
    final next = signs.length > 1 ? signs[1] : null;
    final target = signs.where((p) => p.index == _target.index).firstOrNull;
    final passed = best != null &&
        best.index == _target.index &&
        ((result.accepted && pct(best) >= _target.practice.minConfidence) ||
            (invalid <= _target.practice.maxInvalid &&
                share(best) >= _target.practice.minSignShare &&
                share(best) - share(next) >= _target.practice.minSignLead));
    return (passed: passed, share: share(target));
  }

  void _judge(RawPredictResponse result) {
    double pct(Prediction p) => p.confidence > 1.0 ? p.confidence / 100.0 : p.confidence;
    bool isSign(Prediction p) => p.index != _model.invalidIndex && _model.classAt(p.index) != null;
    final signs = [for (final p in result.topK) if (isSign(p)) p];
    final invalid = result.topK.where((p) => !isSign(p)).fold<double>(0, (a, p) => a + pct(p));
    final signMass = math.max(1.0 - invalid, 0.05);
    double share(Prediction? p) => p == null ? 0.0 : (pct(p) / signMass).clamp(0.0, 1.0);
    final best = signs.isNotEmpty ? signs.first : null;
    final next = signs.length > 1 ? signs[1] : null;
    final bestCls = best == null ? null : _model.classAt(best.index);
    final lead = share(best) - share(next);
    final passed = best != null &&
        best.index == _target.index &&
        ((result.accepted && pct(best) >= _target.practice.minConfidence) ||
            (invalid <= _target.practice.maxInvalid && share(best) >= _target.practice.minSignShare && lead >= _target.practice.minSignLead));

    var debug = '';
    if (kDebugMode) {
      String fmt(Prediction p) => '${_model.classAt(p.index)?.name ?? 'Not recognised'} ${(pct(p) * 100).toStringAsFixed(0)}%';
      debug = '\n\n[debug] target ${_target.name}\nclip: $_clipInfo\nmodel: ${result.topK.take(4).map(fmt).join(', ')}\n'
          'best sign: ${bestCls?.name ?? '-'} ${(share(best) * 100).toStringAsFixed(0)}% of signs, '
          'lead ${(lead * 100).toStringAsFixed(0)}% -> ${passed ? 'PASS' : 'no'}';
      debugPrint(debug.trim());
    }

    if (passed) {
      _show(L.t('Great job!', 'Mahusay!'), L.t('Correct sign!', 'Tumpak ang kumpas!') + debug, FeedbackTone.success);
      unawaited(_onSuccess());
    } else if (bestCls != null && best!.index == _target.index) {
      _show(
        L.t('Almost! Make it clearer', 'Malapit na! Gawin nang mas malinaw'),
        L.t('Do the whole sign slowly, with your hands in front of your chest.',
                'Gawin nang buo at dahan-dahan ang kumpas, nasa harap ng dibdib ang mga kamay.') +
            debug,
        FeedbackTone.almost,
      );
    } else if (bestCls != null && share(best) >= 0.40 && lead >= _target.practice.minSignLead) {
      _show(
        L.t('That looked like ${bestCls.name}', 'Mukhang ${bestCls.name} ang naisagawa'),
        L.t('Try ${_target.name} again. Follow the example.', 'Subukang muli ang ${_target.name}. Sundan ang halimbawa.') + debug,
        FeedbackTone.tryAgain,
      );
    } else if (result.topK.isEmpty && result.rejection != null) {
      // Stopped by the server's capture checks before the model answered.
      final code = result.rejection!.code;
      final why = '\n${L.t('Reason', 'Dahilan')}: ${result.rejection!.message}';
      final (title, message) = switch (code) {
        'LOW_MOTION' || 'SINGLE_STROKE' => (
            L.t('Move a little more', 'Igalaw nang mas malinaw'),
            L.t('The camera saw too little movement. Do the whole sign with clear, full movements, like the example.',
                'Kaunti lang ang galaw na nakita. Gawin ang buong kumpas nang malinaw at buo ang galaw, gaya ng halimbawa.'),
          ),
        'TOO_SHORT' || 'FRAGMENT_DURATION' => (
            L.t('A little too fast!', 'Medyo mabilis!'),
            L.t('Do the whole sign, at a normal speed.', 'Gawin ang buong kumpas sa normal na bilis.'),
          ),
        'OUT_OF_FRAME' || 'NO_HANDS' || 'LOW_LANDMARKS' => (
            L.t('Keep your hands in view', 'Panatilihing kita ang mga kamay'),
            L.t('Sign in front of your chest, with both hands fully inside the camera.',
                'Gawin ang kumpas sa harap ng dibdib, buo ang mga kamay sa loob ng camera.'),
          ),
        _ => (
            L.t('Try again', 'Subukang muli'),
            L.t('The sign was not recognized. Follow the example and sign it clearly.',
                'Hindi makilala ang kumpas. Sundan ang halimbawa at gawin nang malinaw.'),
          ),
      };
      _show(title, message + (kDebugMode ? why + debug : ''), FeedbackTone.tryAgain);
    } else {
      _show(
        L.t('Try again', 'Subukang muli'),
        L.t('The sign was not recognized. Follow the example and sign it clearly.',
                'Hindi makilala ang kumpas. Sundan ang halimbawa at gawin nang malinaw.') +
            debug,
        FeedbackTone.tryAgain,
      );
    }
  }

  Future<void> _onSuccess() async {
    if (_done) return;
    _done = true;
    // Same rewards and feedback as the Greetings / Numbers / Alphabet practice.
    await practiceSuccessHaptics();
    _xpGained = await _cloudAwardMastery(widget.category, widget.lesson, continuous: widget.onDone != null);
    if (!mounted) return;
    if (widget.onDone != null) {
      // Inline success card (see build), then the next sign.
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) widget.onDone!();
      return;
    }
    await showPracticeMasteredDialog(context, signName: widget.lesson.title, xpGained: _xpGained);
    if (mounted) Navigator.pop(context);
  }

  // ---- UI -----------------------------------------------------------------------
  // Same layout as the phrase / civic tutorial practice: blurred app bar,
  // ambient icons, title, square demo + camera with the "Frame Body" ring,
  // the round record button with its status line, one feedback card.

  String get _guide {
    if (_message.isNotEmpty) return _message;
    if (_camera == null) return L.t('Opening camera…', 'Binubuksan ang camera…');
    return L.t('Step back a little so your shoulders and hands are visible,\nthen tap RECORD.',
        'Lumayo nang kaunti para makita ang balikat at mga kamay,\nsaka pindutin ang RECORD.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final screenWidth = MediaQuery.sizeOf(context).width * (landscape ? 0.45 : 1.0);
    final c = _camera;
    final ready = c != null && c.value.isInitialized;
    final title = widget.lesson.title;
    final success = _tone == FeedbackTone.success;

    final elapsed = (_recording && _recordStart != null) ? DateTime.now().difference(_recordStart!).inMilliseconds / 1000.0 : 0.0;
    final recordProgress = (elapsed / _maxRecording.inSeconds).clamp(0.0, 1.0).toDouble();

    // Theme colour while recording / checking, green when correct, else grey.
    final Color borderColor = (_recording || _evaluating)
        ? theme.colorScheme.primary
        : (success ? Colors.greenAccent : theme.dividerColor.withValues(alpha: 0.6));

    final Widget cameraPane = Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(width: 4.0, color: borderColor),
            boxShadow: [
              if (_recording || success)
                BoxShadow(color: borderColor.withValues(alpha: 0.6), blurRadius: 25, spreadRadius: 2)
              else
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ready
                ? _MirrorCameraView(controller: c)
                : Center(
                    child: _error != null
                        ? Padding(padding: const EdgeInsets.all(12), child: Text(_error!, textAlign: TextAlign.center))
                        : CircularProgressIndicator(color: theme.primaryColor),
                  ),
          ),
        ),
        if (ready && !_done)
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                border: Border.all(color: borderColor.withValues(alpha: 0.9), width: _recording ? 4.0 : 3.0),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SmartBlur(
                    filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: Colors.black45,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_recording) ...[
                            Icon(Icons.fiber_manual_record, color: theme.colorScheme.primary, size: 12),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _recording ? 'Recording' : (_evaluating ? 'Evaluating...' : 'Frame Body'),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.cardColor.withValues(alpha: 0.4),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: onSurface),
        flexibleSpace: ClipRRect(
          child: SmartBlur(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(color: Colors.transparent)),
        ),
        title: Text(
          widget.onDone != null ? 'Continuous Practice' : 'Tutorial Practice',
          style: TextStyle(color: onSurface, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96),
        ),
        actions: [
          if (widget.onDone != null) TextButton(onPressed: widget.onDone, child: Text(L.t('Skip', 'Laktawan'))),
        ],
      ),
      body: Stack(
        children: [
          Positioned(
            top: -20,
            right: -20,
            child: Opacity(
              opacity: 0.12,
              child: Transform.rotate(angle: -0.2, child: Icon(Icons.wb_sunny_rounded, size: 220, color: theme.primaryColor)),
            ),
          ),
          Positioned(
            bottom: 40,
            left: -30,
            child: Opacity(
              opacity: 0.10,
              child: Transform.rotate(angle: 0.3, child: Icon(Icons.auto_awesome_rounded, size: 240, color: theme.colorScheme.secondary)),
            ),
          ),
          SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (widget.progressLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(widget.progressLabel!,
                                  style: TextStyle(color: onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w700)),
                            ),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: onSurface, fontSize: 32, fontWeight: FontWeight.w900, fontFamily: 'Inter'),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: screenWidth * 0.60,
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: _CloudMedia(source: widget.lesson.media, fit: BoxFit.cover),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (!landscape) SizedBox(width: screenWidth * 0.60, child: AspectRatio(aspectRatio: 1, child: cameraPane)),
                          const SizedBox(height: 16),
                          if (widget.onDone != null && _done) ...[
                            const SizedBox(height: 8),
                            ContinuousPracticeSuccess(xpGained: _xpGained, nextLabel: L.t('Next sign...', 'Susunod na kumpas...')),
                          ] else ...[
                            _RecordControls(
                              heroTag: 'cloud_record_button',
                              countdown: _countdown,
                              isRecording: _recording,
                              isEvaluating: _evaluating,
                              elapsed: elapsed,
                              recordProgress: recordProgress,
                              bodyVisible: _poseVisible,
                              showButton: ready && !_done,
                              onRecord: _toggleRecording,
                              width: screenWidth * 0.70,
                            ),
                            const SizedBox(height: 16),
                            // One feedback card: the verdict after an attempt,
                            // else the instruction / status.
                            if (_title.isNotEmpty && !_recording && !_evaluating)
                              PracticeFeedback(title: _title, message: _message, tone: _tone)
                            else
                              PracticeFeedback(message: _guide, tone: _error != null ? FeedbackTone.problem : FeedbackTone.info),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (landscape)
                  Expanded(flex: 6, child: Padding(padding: const EdgeInsets.fromLTRB(0, 10, 16, 16), child: cameraPane)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Record controls under the camera. Kept identical in
/// phrase_tutorial_practice.dart, civic_tutorial_practice.dart and here:
/// one status line (countdown / recording bar / checking bar / body hint)
/// and the round record button, in the same look on every screen.
class _RecordControls extends StatelessWidget {
  final int countdown;
  final bool isRecording;
  final bool isEvaluating;

  /// Seconds recorded so far, and how full the recording bar is (0-1).
  final double elapsed;
  final double recordProgress;

  /// Body / hands in view (shown while idle).
  final bool bodyVisible;

  /// null disables the button.
  final VoidCallback? onRecord;
  final bool showButton;
  final double? width;
  final String heroTag;

  const _RecordControls({
    required this.countdown,
    required this.isRecording,
    required this.isEvaluating,
    required this.elapsed,
    required this.recordProgress,
    required this.bodyVisible,
    required this.onRecord,
    required this.heroTag,
    this.showButton = true,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final barWidth = width ?? MediaQuery.sizeOf(context).width * 0.70;

    // One animation only (extra spinners made the camera lag): a static
    // dot + the bar; the record button is hidden while checking.
    Widget bar(String label, double? value) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle, size: 10, color: primary),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SmartBlur(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  width: barWidth,
                  height: 14,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.surface.withValues(alpha: 0.5), width: 1),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 200),
                      widthFactor: value ?? 0.5,
                      child: Container(
                        decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

    final Widget status;
    if (countdown > 0) {
      status = Text(
        L.t('Lower your hands… $countdown', 'Ibaba ang mga kamay… $countdown'),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFFF08C00)),
      );
    } else if (isRecording) {
      status = bar(L.t('Recording... ${elapsed.toStringAsFixed(1)}s', 'Nagre-record... ${elapsed.toStringAsFixed(1)}s'), recordProgress.clamp(0.0, 1.0));
    } else if (isEvaluating) {
      status = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(L.t('Checking your sign...', 'Sinusuri ang kumpas...'), style: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 10),
          SizedBox(
            width: barWidth,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LinearProgressIndicator(minHeight: 14, color: primary, backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.4)),
            ),
          ),
        ],
      );
    } else {
      status = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(bodyVisible ? Icons.check_circle_rounded : Icons.accessibility_new_rounded,
              size: 18, color: bodyVisible ? const Color(0xFF2E9E4F) : const Color(0xFFF08C00)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              bodyVisible ? L.t('Body in view. Tap RECORD', 'Nakikita ang katawan. Pindutin ang RECORD') : L.t('Step back a little so your shoulders and hands are visible', 'Lumayo nang kaunti para makita ang balikat at mga kamay'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: bodyVisible ? const Color(0xFF2E9E4F) : const Color(0xFFF08C00),
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        status,
        if (showButton && !isEvaluating) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 64,
            width: 64,
            child: FloatingActionButton(
              heroTag: heroTag,
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              disabledElevation: 0,
              elevation: 8,
              onPressed: onRecord,
              child: Icon(countdown > 0 ? Icons.close : (isRecording ? Icons.stop : Icons.fiber_manual_record), size: 32),
            ),
          ),
        ],
      ],
    );
  }
}

/// A practice capture shaped like the web's training clips
/// (gesture_training_samples, validated by the web pipeline). The server
/// resamples the whole clip to 32 steps, so the sign must fill the same share
/// of the clip as in training: the capture is cut to the training clip length
/// of the sign (PracticeSettings.clipS, e.g. ~1.8 s for Calendar, ~4 s for
/// Drinks) centred on the moving part; without it, to the moving part plus
/// a short margin.
class _TrainingClip {
  final List<RawFrame> frames;
  final double durationS;
  final double activeS;
  final double handCoverage;
  final double poseCoverage;
  final double outOfFrame;

  /// Limits: the web's validation thresholds, per model / sign.
  final PracticeSettings settings;

  /// The same frames without smoothing (sent when the smoothed clip is
  /// stopped by the server's motion gates).
  final List<RawFrame> unsmoothed;

  const _TrainingClip(this.frames, this.durationS, this.activeS, this.handCoverage, this.poseCoverage, this.outOfFrame, this.settings,
      [this.unsmoothed = const []]);

  /// Hand moved: mean |dx| + |dy| of its 21 points over [_windowMs] above
  /// this share of the image (handshape changes count too). Measured over a
  /// fixed time, not between frames, so it does not depend on the camera's
  /// frame rate (the same threshold per frame missed slow, small signs such
  /// as Cold at 30-60 fps).
  static const double _motion = 0.016;
  static const int _windowMs = 100;

  /// First and last index of the moving part, or (-1, -1).
  static (int, int) _activeSpan(List<RawFrame> fs) {
    var first = -1, last = -1, j = 0;
    for (var i = 1; i < fs.length; i++) {
      while (j < i - 1 && fs[i].timeMs - fs[j + 1].timeMs >= _windowMs) {
        j++;
      }
      if (_moved(fs[j], fs[i]) > _motion) {
        if (first == -1) first = j;
        last = i;
      }
    }
    return (first, last);
  }


  static bool _inFrame(List<List<double>>? hand) {
    if (hand == null || hand.isEmpty) return false;
    const m = 0.02;
    for (final p in hand) {
      if (p.length < 2 || p[0] < m || p[0] > 1 - m || p[1] < m || p[1] > 1 - m) return false;
    }
    return true;
  }

  static double _moved(RawFrame a, RawFrame b) {
    var best = 0.0;
    for (final pair in [(a.leftHand, b.leftHand), (a.rightHand, b.rightHand)]) {
      final x = pair.$1, y = pair.$2;
      if (x == null || y == null || x.length != y.length) continue;
      var sum = 0.0;
      for (var i = 0; i < x.length; i++) {
        sum += (x[i][0] - y[i][0]).abs() + (x[i][1] - y[i][1]).abs();
      }
      best = math.max(best, sum / (2 * x.length));
    }
    return best;
  }

  /// [all]: the whole recording, sorted by time.
  /// [tight]: the sign only, without margin and without the frames where the
  /// hands are still rising into / leaving the image.
  factory _TrainingClip.from(List<RawFrame> all, PracticeSettings settings, {bool tight = false}) {
    var frames = all;
    final firstHand = frames.indexWhere((f) => f.hasHands);
    if (firstHand == -1) return _TrainingClip(const [], 0, 0, 0, 0, 0, settings);
    frames = frames.sublist(firstHand, frames.lastIndexWhere((f) => f.hasHands) + 1);
    if (tight) {
      bool full(RawFrame f) => _inFrame(f.leftHand) || _inFrame(f.rightHand);
      final a = frames.indexWhere(full), b = frames.lastIndexWhere(full);
      if (a != -1 && b > a) frames = frames.sublist(a, b + 1);
    }
    final margin = tight ? 0 : settings.marginMs;

    final (first, last) = _activeSpan(frames);
    var activeS = 0.0;
    if (first != -1) {
      final a = frames[first].timeMs, b = frames[last].timeMs;
      activeS = (b - a) / 1000.0;
      final clipMs = (settings.clipS * 1000).round();
      if (!tight && clipMs > b - a) {
        // The training clip length, centred on the sign and kept inside the
        // recording. Like the training clips, this keeps the rest before and
        // after the sign, frames without hands included.
        final start = all.first.timeMs, end = all.last.timeMs;
        final from = ((a + b - clipMs) / 2).round().clamp(start, math.max(start, end - clipMs));
        frames = all.where((f) => f.timeMs >= from && f.timeMs <= from + clipMs).toList();
      } else {
        // The moving part, plus a short margin.
        frames = frames.where((f) => f.timeMs >= a - margin && f.timeMs <= b + margin).toList();
      }
    }

    final n = frames.isEmpty ? 1 : frames.length;
    final withHands = frames.where((f) => f.hasHands).length;
    final withPose = frames.where((f) => f.pose != null).length;
    final cutOff = frames.where((f) => (f.leftHand != null && !_inFrame(f.leftHand)) || (f.rightHand != null && !_inFrame(f.rightHand))).length;
    final duration = frames.length < 2 ? 0.0 : (frames.last.timeMs - frames.first.timeMs) / 1000.0;
    return _TrainingClip(_smooth(frames), duration, activeS, withHands / n, withPose / n, cutOff / n, settings, frames);
  }

  /// Training ran MediaPipe Holistic with smooth_landmarks=true; the phone's
  /// landmarks are raw. A light running average per point (restarted when a
  /// hand / the body was not detected) removes the frame-to-frame jitter.
  /// [_keep] is the share of the previous value 50 ms earlier; with fewer
  /// frames per second it shrinks (0.4 at 20 fps, ~0.1 at 8 fps), so a slow
  /// phone camera does not flatten the movement (and the server's motion
  /// energy, LOW_MOTION) as well.
  static const double _keep = 0.4;

  static List<RawFrame> _smooth(List<RawFrame> frames) {
    List<List<double>>? prevPose, prevLeft, prevRight;
    var keep = _keep;
    List<List<double>>? step(List<List<double>>? now, List<List<double>>? prev) {
      if (now == null) return null;
      if (prev == null || prev.length != now.length) return now;
      return [
        for (var i = 0; i < now.length; i++)
          [
            for (var k = 0; k < now[i].length; k++)
              k < 3 && k < prev[i].length ? keep * prev[i][k] + (1 - keep) * now[i][k] : now[i][k]
          ]
      ];
    }

    int? lastMs;
    return [
      for (final f in frames)
        () {
          final dt = lastMs == null ? 50 : (f.timeMs - lastMs!).clamp(1, 1000);
          lastMs = f.timeMs;
          keep = math.pow(_keep, dt / 50).toDouble();
          prevPose = step(f.pose, prevPose);
          prevLeft = step(f.leftHand, prevLeft);
          prevRight = step(f.rightHand, prevRight);
          return RawFrame(pose: prevPose, leftHand: prevLeft, rightHand: prevRight, timeMs: f.timeMs);
        }(),
    ];
  }

  /// What to fix before the capture is worth sending, or null.
  ({String title, String message})? problem() {
    if (frames.isEmpty) {
      return (title: L.t('No hands detected', 'Walang nakitang kamay'), message: HolisticCapture.rejectAdvice['NO_HANDS']!);
    }
    if (poseCoverage < settings.minPoseCoverage) {
      return (
        title: L.t('Show your body', 'Ipakita ang katawan'),
        message: L.t('Hold the phone at chest height, an arm\'s length away, so your head and shoulders stay in view.',
            'Hawakan ang phone sa taas ng dibdib, isang braso ang layo, para makita ang ulo at balikat.'),
      );
    }
    if (handCoverage < settings.minHandCoverage || outOfFrame > settings.maxOutOfFrame) {
      return (
        title: L.t('Keep your hands in view', 'Panatilihing kita ang mga kamay'),
        message: L.t('Sign in front of your chest, with both hands fully inside the camera.',
            'Gawin ang kumpas sa harap ng dibdib, buo ang mga kamay sa loob ng camera.'),
      );
    }
    // The web measures motion its own way; the phone's estimate only stops
    // captures with clearly too little signing, the model judges the rest.
    if (activeS < settings.minActiveS * 0.5) {
      return (
        title: L.t('A little too fast!', 'Medyo mabilis!'),
        message: L.t('Do the whole sign, at a normal speed.', 'Gawin ang buong kumpas sa normal na bilis.'),
      );
    }
    return null;
  }

  String describe() {
    String pc(double v) => '${(v * 100).toStringAsFixed(0)}%';
    final fps = durationS > 0 ? (frames.length - 1) / durationS : 0;
    return '${frames.length} frames, ${durationS.toStringAsFixed(1)} s (signing ${activeS.toStringAsFixed(1)} s), '
        '${fps.toStringAsFixed(0)} fps, hands ${pc(handCoverage)}, body ${pc(poseCoverage)}, cut off ${pc(outOfFrame)}';
  }
}

/// Marks [lesson] mastered and awards its XP like every other category
/// (XpRewards: 20 XP for a tutorial sign, 10 for a continuous practice sign,
/// first time only, then the capped repeat XP), into the category's module
/// XP field. Returns the XP actually awarded.
Future<int> _cloudAwardMastery(CloudCategory category, CloudLesson lesson, {required bool continuous}) async {
  final module = category.id;
  // XP first: awardFirstMastery gives the first-time XP only while the sign is
  // not yet marked mastered, and marks it itself (as Alphabet / Numbers do).
  // Marking it before (as this did) made every first time count as a repeat.
  final xp = await ProgressService().awardFirstMastery(
    moduleKey: continuous ? XpRewards.practiceKey(module) : module,
    itemKey: ProgressService.masteryKey(lesson.title),
    xp: continuous ? XpRewards.practiceSign : XpRewards.tutorialSign,
    xpField: category.xpField,
    countsAsLesson: !continuous,
  );
  // Practice also counts the sign as learned in the tutorial list.
  if (continuous) await ProgressService().markTutorialMastered(module, lesson.title);
  return xp;
}

// =============================================================================
// Camera question checked by a category's published model (activities and
// challenges)
// =============================================================================

/// Normalised id of the activity_categories / published_gesture_models
/// category for a challenge or activity category name.
String publishedCategoryId(String category) {
  final k = category.trim().toLowerCase();
  if (k.contains('phrase') || k.contains('greeting') || k.contains('word')) return 'phrases';
  if (k.contains('civic')) return 'civic';
  return category.trim();
}

/// A camera question for a sign of a category with a model trained on the
/// web (published_gesture_models: Calendar, Drinks, Greetings, Civic and any
/// category added later): RECORD SIGN -> 3-2-1 -> sign (stops by itself when
/// the hands are lowered, or STOP) -> the capture is shaped like the model's
/// training clips and checked by the model, exactly as in the tutorial
/// practice (CloudModelPractice). When the category has no published model
/// for the sign yet, it says so and offers SKIP (a skipped result).
class PublishedCameraSign extends StatefulWidget {
  final String category;
  final String sign;
  final bool enabled;
  final ValueChanged<ChallengeSignResult> onResult;

  /// The main button goes to the activity's bottom bar (as in the Alphabet /
  /// Numbers camera levels); without it, the button is shown here.
  final CameraButtonBridge? bridge;

  /// A new value starts a new try of the same sign with the same camera
  /// (practice TRY AGAIN).
  final int attempt;

  /// Seconds of "get ready" before recording (0 in the timed challenges).
  final int countdown;

  const PublishedCameraSign({super.key, required this.category, required this.sign, required this.onResult, this.enabled = true, this.bridge, this.attempt = 0, this.countdown = 3});

  @override
  State<PublishedCameraSign> createState() => _PublishedCameraSignState();
}

class _PublishedCameraSignState extends State<PublishedCameraSign> {
  static const int _autoStopAfterMs = 1500;
  static const int _manualStopTrimMs = 600;
  static const Duration _maxRecording = Duration(seconds: 6);

  PublishedGestureModel? _model;
  PublishedGestureClass? _target;
  bool _lookedUp = false;

  CameraController? _camera;
  bool _disposed = false;
  int _inFlight = 0;
  bool _handsVisible = false;
  int _imageWidth = 0, _imageHeight = 0;
  String _engine = '';

  int _countdown = 0;
  Timer? _countdownTimer;
  Timer? _maxTimer;
  bool _recording = false;
  bool _evaluating = false;
  bool _answered = false;
  DateTime? _recStart;
  Timer? _tick;
  final List<RawFrame> _frames = [];
  bool _sawHands = false;
  int _lastHandMs = 0;
  String _note = '';

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void didUpdateWidget(covariant PublishedCameraSign old) {
    super.didUpdateWidget(old);
    if (old.sign != widget.sign || old.category != widget.category || old.attempt != widget.attempt) {
      _cancel();
      _answered = false;
      _note = '';
      _lookup();
    }
  }

  Future<void> _lookup() async {
    setState(() => _lookedUp = false);
    final m = await PublishedGestureModels.forCategory(publishedCategoryId(widget.category));
    final t = m?.classForLesson([widget.sign]);
    if (!mounted) return;
    setState(() {
      _model = t == null ? null : m;
      _target = t;
      _lookedUp = true;
    });
    if (t != null && _camera == null) _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty || _disposed) return;
      final cam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final c = CameraController(cam, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await c.initialize();
      if (_disposed) {
        await c.dispose();
        return;
      }
      setState(() => _camera = c);
      await c.startImageStream(_onImage);
    } catch (e) {
      debugPrint('Published camera sign: camera unavailable: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _countdownTimer?.cancel();
    _maxTimer?.cancel();
    _tick?.cancel();
    final c = _camera;
    _camera = null;
    if (c != null) {
      unawaited(() async {
        try {
          if (c.value.isStreamingImages) await c.stopImageStream();
        } catch (_) {}
        await c.dispose();
      }());
    }
    super.dispose();
  }

  static bool _inFrame(List<List<double>>? hand) {
    if (hand == null || hand.isEmpty) return false;
    const m = 0.02;
    for (final p in hand) {
      if (p.length < 2 || p[0] < m || p[0] > 1 - m || p[1] < m || p[1] > 1 - m) return false;
    }
    return true;
  }

  Future<void> _onImage(CameraImage image) async {
    LightingMonitor.instance.onImage(image);
    final c = _camera;
    if (_disposed || _answered || _evaluating || c == null || _inFlight >= 2) return;
    _inFlight++;
    try {
      final r = await HolisticCapture.process(image, _CloudMirrorPracticeState._rotation(c));
      if (r == null || _disposed || !mounted) return;
      _imageWidth = r.imageWidth;
      _imageHeight = r.imageHeight;
      _engine = r.engine;
      final f = r.frame;
      final changed = f.hasHands != _handsVisible;
      _handsVisible = f.hasHands;
      if (!_recording) {
        if (changed) setState(() {});
        return;
      }
      _frames.add(f);
      if (_inFrame(f.leftHand) || _inFrame(f.rightHand)) {
        _sawHands = true;
        _lastHandMs = f.timeMs;
      } else if (_sawHands && f.timeMs - _lastHandMs > _autoStopAfterMs) {
        unawaited(_stopAndEvaluate());
        return;
      }
      if (changed) setState(() {});
    } catch (e) {
      debugPrint('Published camera sign capture error: $e');
    } finally {
      _inFlight--;
    }
  }

  void _onButton() {
    if (!widget.enabled || _answered || _evaluating || _camera == null) return;
    if (_countdown > 0) {
      _cancel();
    } else if (_recording) {
      _stopAndEvaluate(manual: true);
    } else {
      HapticFeedback.selectionClick();
      void begin() {
          _frames.clear();
          _sawHands = false;
          _recStart = DateTime.now();
          _tick?.cancel();
          _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
            if (!mounted || !_recording) return _tick?.cancel();
            setState(() {});
          });
          setState(() {
            _countdown = 0;
            _recording = true;
            _note = L.t('Sign now! Lower your hands when you are done.', 'Kumpas na! Ibaba ang mga kamay kapag tapos na.');
          });
          _maxTimer = Timer(_maxRecording, () => _stopAndEvaluate());
      }
      // No countdown (timed challenges): record at once.
      if (widget.countdown <= 0) {
        begin();
        return;
      }
      setState(() {
        _countdown = widget.countdown;
        _note = L.t('Lower your hands and get ready...', 'Ibaba ang mga kamay at pumwesto...');
      });
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _disposed) return t.cancel();
        if (_countdown <= 1) {
          t.cancel();
          begin();
        } else {
          setState(() => _countdown--);
        }
      });
    }
  }

  void _cancel() {
    _countdownTimer?.cancel();
    _maxTimer?.cancel();
    _frames.clear();
    if (!mounted) return;
    setState(() {
      _countdown = 0;
      _recording = false;
    });
  }

  void _finish(ChallengeSignResult r) {
    if (_answered) return;
    _answered = true;
    if (mounted) setState(() => _evaluating = false);
    widget.onResult(r);
  }

  /// Same pass rule as CloudModelPractice._assess.
  ({bool passed, double share, Prediction? best}) _assess(RawPredictResponse result) {
    final model = _model!, target = _target!;
    double pct(Prediction p) => p.confidence > 1.0 ? p.confidence / 100.0 : p.confidence;
    bool isSign(Prediction p) => p.index != model.invalidIndex && model.classAt(p.index) != null;
    final signs = [for (final p in result.topK) if (isSign(p)) p];
    final invalid = result.topK.where((p) => !isSign(p)).fold<double>(0, (a, p) => a + pct(p));
    final mass = math.max(1.0 - invalid, 0.05);
    double share(Prediction? p) => p == null ? 0.0 : (pct(p) / mass).clamp(0.0, 1.0);
    final best = signs.isNotEmpty ? signs.first : null;
    final next = signs.length > 1 ? signs[1] : null;
    final t = signs.where((p) => p.index == target.index).firstOrNull;
    final passed = best != null &&
        best.index == target.index &&
        ((result.accepted && pct(best) >= target.practice.minConfidence) ||
            (invalid <= target.practice.maxInvalid &&
                share(best) >= target.practice.minSignShare &&
                share(best) - share(next) >= target.practice.minSignLead));
    return (passed: passed, share: share(t), best: best);
  }

  Future<void> _stopAndEvaluate({bool manual = false}) async {
    if (!_recording || _disposed) return;
    _maxTimer?.cancel();
    var frames = List<RawFrame>.of(_frames)..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    _frames.clear();
    setState(() => _recording = false);
    if (manual && frames.isNotEmpty) {
      final cutoff = frames.last.timeMs - _manualStopTrimMs;
      frames = frames.where((f) => f.timeMs <= cutoff).toList();
    }
    if (!frames.any((f) => f.hasHands)) {
      setState(() => _note = L.t('No hands were seen. Keep your hands in view and record again.',
          'Walang nakitang kamay. Panatilihing kita ang mga kamay at i-record muli.'));
      return;
    }
    final model = _model!, target = _target!;
    final settings = target.practice;
    final clip = _TrainingClip.from(frames, settings, tight: settings.tightFirst);
    final problem = clip.problem();
    if (problem != null) {
      // Not worth sending: say what to fix, record again (not a wrong answer).
      setState(() => _note = '${problem.title}. ${problem.message}');
      return;
    }
    setState(() {
      _evaluating = true;
      _note = L.t('Checking your sign...', 'Sinusuri ang kumpas...');
    });
    try {
      Future<RawPredictResponse> send(List<RawFrame> fs) {
        final s0 = fs.first.timeMs;
        final fixed = CaptureFixer.fix([for (final f in fs) f.toJson(s0)], _imageWidth, _imageHeight,
            reassignHands: !HolisticResult.isHolisticEngine(_engine));
        return HandSpeakApiService().predictRaw(
          modelId: model.modelId,
          serviceUrl: model.serviceUrl,
          frames: fixed.frames,
          imageWidth: fixed.imageWidth,
          imageHeight: fixed.imageHeight,
          topK: 10,
        );
      }

      final alt = _TrainingClip.from(frames, settings, tight: !settings.tightFirst);
      final tries = <List<RawFrame>>[
        clip.frames,
        clip.unsmoothed,
        if (alt.problem() == null) alt.frames,
        if (alt.problem() == null) alt.unsmoothed,
      ];
      RawPredictResponse? result;
      ({bool passed, double share, Prediction? best})? verdict;
      var rank = -1.0;
      for (final fs in tries) {
        if (fs.length < 2) continue;
        final r = await send(fs);
        final a = _assess(r);
        final k = (a.passed ? 10.0 : 0.0) + (r.topK.isNotEmpty ? 1.0 : 0.0) + a.share;
        if (k > rank) {
          rank = k;
          result = r;
          verdict = a;
        }
        // Other shapes only when the server's gates stopped the clip before the
        // model answered (no sign scores): a model answer is final, retrying it
        // in other cuts only fished for a pass (false positives).
        if (a.passed || r.topK.isNotEmpty || !mounted || _disposed) break;
      }
      if (result == null || verdict == null || !mounted) return;
      double pct(Prediction p) => p.confidence > 1.0 ? p.confidence / 100.0 : p.confidence;
      final best = verdict.best;
      _finish(ChallengeSignResult(
        correct: verdict.passed,
        score: verdict.share * 100,
        isDynamic: true,
        model: model.modelId,
        predicted: best == null ? null : model.classAt(best.index)?.name,
        confidence: best == null ? null : pct(best),
        frames: frames.length,
      ));
    } catch (e) {
      debugPrint('Published camera sign: prediction error: $e');
      if (mounted) {
        setState(() {
          _evaluating = false;
          _note = L.t('The model did not answer. Check your internet connection, then record again.',
              'Hindi sumagot ang model. Tingnan ang koneksyon sa internet, saka i-record muli.');
        });
      }
    }
  }

  // ---- built-in Cloud Run models (Greetings, Lupang Hinirang) --------------

  /// Greetings and Civic (Lupang Hinirang) are checked by the app's own
  /// Cloud Run models (/v1/predict/greetings, /v1/predict_raw/lupang_hinirang),
  /// through their tutorial practice screens in check mode: the screen opens
  /// for this sign, and passing it answers the question. Null when neither
  /// fits (the sign is not one of their signs).
  Widget Function(VoidCallback onPassed)? get _builtIn {
    final cat = publishedCategoryId(widget.category);
    final sign = widget.sign.trim();
    // Embedded: their own camera, recording and model check, right here in
    // the question (no other screen opens).
    if (cat == 'phrases' && PhraseRecognizer.classIndexFor(sign) != -1) {
      return (onPassed) => PhraseTutorialPractice(
            key: ValueKey('greet_${sign}_${widget.attempt}'),
            targetPhrase: sign,
            onPassed: onPassed,
            onFailed: _builtInFailed,
            embedded: true,
            bridge: widget.bridge,
          );
    }
    if (cat == 'civic') {
      return (onPassed) => CivicTutorialPractice(
            key: ValueKey('civic_${sign}_${widget.attempt}'),
            questions: [{'question': sign, 'label': sign}],
            onPassed: onPassed,
            onFailed: _builtInFailed,
            embedded: true,
            bridge: widget.bridge,
          );
    }
    return null;
  }

  /// The embedded built-in check answered a wrong sign: the question is
  /// answered wrong (as in the Numbers camera levels).
  void _builtInFailed() {
    if (_answered) return;
    _finish(ChallengeSignResult(
      correct: false,
      score: 0,
      isDynamic: true,
      model: publishedCategoryId(widget.category) == 'civic' ? 'lupang_hinirang' : 'greetings',
    ));
  }

  /// The embedded built-in check passed: the question is answered right.
  void _builtInPassed() {
    if (_answered) return;
    _finish(ChallengeSignResult(
      correct: true,
      score: 100,
      isDynamic: true,
      model: publishedCategoryId(widget.category) == 'civic' ? 'lupang_hinirang' : 'greetings',
    ));
  }

  /// The live square camera, as in the Alphabet / Numbers camera levels:
  /// 60% of the screen width, a 4 px border that glows while hands are seen
  /// (red while recording).
  Widget _cameraBox(ThemeData theme) {
    final c = _camera;
    final side = math.min(MediaQuery.sizeOf(context).width * 0.60, 320.0);
    return Center(
            child: Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(width: 4, color: _recording || _handsVisible ? theme.primaryColor : theme.dividerColor.withValues(alpha: 0.6)),
                boxShadow: [
                  if (_handsVisible || _recording)
                    BoxShadow(color: theme.primaryColor.withValues(alpha: 0.3), blurRadius: 15, spreadRadius: 1),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: c == null || !c.value.isInitialized
                    ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                    : FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: c.value.previewSize?.shortestSide ?? 1,
                          height: c.value.previewSize?.longestSide ?? 1,
                          child: CameraPreview(c),
                        ),
                      ),
              ),
            ),
          );
  }

  /// Greetings / Civic (built-in Cloud Run models): their own practice check
  /// embedded here (the live square camera, RECORD, the model's check and
  /// feedback), like the Alphabet / Numbers camera levels; nothing navigates.
  Widget _buildBuiltIn(ThemeData theme) {
    return IgnorePointer(ignoring: !widget.enabled || _answered, child: _builtIn!(_builtInPassed));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    if (!_lookedUp) return Center(child: CircularProgressIndicator(color: theme.primaryColor));
    if (_target == null && _builtIn != null) return _buildBuiltIn(theme);
    if (_target == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_rounded, size: 48, color: onSurface.withValues(alpha: 0.4)),
          const SizedBox(height: 10),
          Text(
            L.t('Camera checking for "${widget.sign}" is coming soon.', 'Malapit nang masuri ng camera ang "${widget.sign}".'),
            textAlign: TextAlign.center,
            style: TextStyle(color: onSurface, fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: widget.enabled
                  ? () => _finish(const ChallengeSignResult(correct: false, score: 0, isDynamic: true, model: 'none', skipped: true))
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor),
              child: Text(L.t('SKIP', 'LAKTAWAN'), style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      );
    }
    final c = _camera;
    final buttonState = CameraButtonState(
      label: cameraButtonLabel(checking: _evaluating, countdown: _countdown, recording: _recording),
      recording: _recording,
      onPressed: widget.enabled && !_answered && !_evaluating && c != null ? _onButton : null,
    );
    widget.bridge?.publish(buttonState);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _cameraBox(theme),
          const SizedBox(height: 20),
          // Exactly the Numbers moving-sign status.
          SignRecordingStatus.view(
            theme,
            countdown: _countdown,
            recording: _recording,
            progress: _recStart == null ? 0 : DateTime.now().difference(_recStart!).inMilliseconds / _maxRecording.inMilliseconds,
            sign: widget.sign,
            checking: _evaluating,
            handsVisible: _handsVisible,
            message: _note,
          ),
          if (widget.bridge == null) ...[
            const SizedBox(height: 16),
            cameraLevelButton(theme, label: buttonState.label, recording: _recording, onPressed: buttonState.onPressed),
          ],
        ],
      ),
    );
  }
}
