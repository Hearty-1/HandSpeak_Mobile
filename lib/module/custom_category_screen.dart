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
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('activity_categories').snapshots(),
      builder: (context, snap) {
        final cats = [
          for (final d in snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            ?CloudCategory.fromDoc(d),
        ]..sort((a, b) => a.order != b.order ? a.order.compareTo(b.order) : a.title.compareTo(b.title));
        if (cats.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('More Categories',
                  style: TextStyle(color: textColor, fontSize: 22 * scale, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
              SizedBox(height: 4 * scale),
              Text('Added by your teachers',
                  style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 13 * scale, fontWeight: FontWeight.w500)),
              SizedBox(height: 14 * scale),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                mainAxisSpacing: 14 * scale,
                crossAxisSpacing: 14 * scale,
                childAspectRatio: 0.82,
                children: [for (final c in cats) _CategoryCard(category: c, scale: scale)],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final CloudCategory category;
  final double scale;
  const _CategoryCard({required this.category, required this.scale});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    return GestureDetector(
      onTap: () {
        ProgressService().trackRecentModule(category.id);
        Navigator.push(context, MaterialPageRoute(builder: (_) => CloudCategoryScreen(category: category)));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22 * scale),
        child: SmartBlur(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(22 * scale),
              border: Border.all(color: theme.primaryColor.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _CloudMedia(source: category.cover)),
                Padding(
                  padding: EdgeInsets.fromLTRB(12 * scale, 10 * scale, 12 * scale, 12 * scale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                      if (category.description.isNotEmpty) ...[
                        SizedBox(height: 2 * scale),
                        Text(category.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 12 * scale, fontWeight: FontWeight.w600)),
                      ],
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
        int moduleXp = 0, challengeXp = 0, stars = 0;
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        if (data != null) {
          moduleXp = (data[category.xpField] as num?)?.toInt() ?? 0;
          final progress = data['progress'];
          if (progress is Map) {
            challengeXp = (progress['${category.id}_challenge_xp'] as num?)?.toInt() ?? 0;
            progress.forEach((k, v) {
              final key = k.toString().toLowerCase();
              if (key.startsWith('${category.id.toLowerCase()}_') && !key.contains('xp') && !key.contains('challenge') && v is num) {
                stars += v.toInt().clamp(0, 3);
              }
            });
          }
        }
        final total = moduleXp + challengeXp;
        final level = total ~/ targetXp + 1;
        final xpInLevel = total % targetXp;

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
              final double scale = constraints.maxWidth / 393;
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
                          if (canProgress) ...[
                            _MainProgressPanel(scale: scale, level: level, currentXp: xpInLevel, targetXp: targetXp),
                            SizedBox(height: 24 * scale),
                          ],
                          if (canTutorials) ...[
                            _SectionRow(
                              scale: scale,
                              image: "assets/pictures/tutor.png",
                              imageWidth: 130, imageHeight: 110, fit: BoxFit.fill,
                              title: 'Tutorial',
                              icon: Icons.play_arrow_rounded,
                              label: 'Start Learn',
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => CloudTutorialListScreen(category: category))),
                            ),
                            SizedBox(height: 16 * scale),
                          ],
                          if (canPractice) ...[
                            _SectionRow(
                              scale: scale,
                              image: "assets/pictures/practice.png",
                              imageWidth: 135, imageHeight: 135, fit: BoxFit.cover,
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
                                      child: Image.asset("assets/pictures/actt.png", width: 164 * scale, height: 160 * scale, fit: BoxFit.cover),
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
                                      child: Image.asset("assets/pictures/battle.png", width: 159 * scale, height: 159 * scale, fit: BoxFit.cover),
                                    ),
                                  ]),
                                ),
                              ],
                            ),
                            SizedBox(height: 32 * scale),
                            Row(
                              children: [
                                Expanded(
                                  child: _SubMetricPanel(scale: scale, value: '$stars Stars', progress: (stars / 27).clamp(0.0, 1.0),
                                      icon: Icons.star_rounded),
                                ),
                                SizedBox(width: 12 * scale),
                                Expanded(
                                  child: _SubMetricPanel(scale: scale, value: '$challengeXp XP',
                                      progress: (challengeXp / targetXp).clamp(0.0, 1.0), icon: Icons.bolt_rounded),
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

class _SectionRow extends StatelessWidget {
  final double scale;
  final String image;
  final double imageWidth, imageHeight;
  final BoxFit fit;
  final String title;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SectionRow({
    required this.scale, required this.image, required this.imageWidth, required this.imageHeight, required this.fit,
    required this.title, required this.icon, required this.label, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(image, width: imageWidth * scale, height: imageHeight * scale, fit: fit),
        SizedBox(width: 22 * scale),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5)),
              SizedBox(height: 8 * scale),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 4,
                  shadowColor: theme.primaryColor.withValues(alpha: 0.5),
                  padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale)),
                ),
                icon: Icon(icon, size: 18 * scale),
                label: Text(label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 14 * scale)),
                onPressed: onTap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _glassIcon(BuildContext context, double scale, double size, IconData icon, Color color) {
  final theme = Theme.of(context);
  return Container(
    padding: EdgeInsets.all(6 * scale),
    decoration: BoxDecoration(
      color: theme.cardColor.withValues(alpha: 0.8),
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 8, spreadRadius: 1)],
    ),
    child: Icon(icon, color: color, size: size),
  );
}

Widget _bar(BuildContext context, double scale, double height, double ratio) {
  final theme = Theme.of(context);
  return Stack(
    alignment: Alignment.centerLeft,
    children: [
      Container(height: height * scale, decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(25 * scale))),
      FractionallySizedBox(
        widthFactor: ratio,
        child: Container(
          height: height * scale,
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            borderRadius: BorderRadius.circular(25 * scale),
            boxShadow: [BoxShadow(color: theme.colorScheme.secondary.withValues(alpha: 0.5), blurRadius: 4)],
          ),
        ),
      ),
    ],
  );
}

BoxDecoration _glassBox(BuildContext context, double scale) {
  final theme = Theme.of(context);
  return BoxDecoration(
    color: theme.cardColor.withValues(alpha: 0.65),
    borderRadius: BorderRadius.circular(16 * scale),
    border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))],
  );
}

class _MainProgressPanel extends StatelessWidget {
  final double scale;
  final int level, currentXp, targetXp;
  const _MainProgressPanel({required this.scale, required this.level, required this.currentXp, required this.targetXp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16 * scale),
      child: SmartBlur(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
          decoration: _glassBox(context, scale),
          child: Row(
            children: [
              _glassIcon(context, scale, 24 * scale, Icons.bolt_rounded, Colors.amber.shade500),
              SizedBox(width: 16 * scale),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Category Level $level',
                      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.w700)),
                  Text('$currentXp / $targetXp XP',
                      style: TextStyle(color: theme.primaryColor, fontSize: 15 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400)),
                ],
              ),
              SizedBox(width: 16 * scale),
              Expanded(child: _bar(context, scale, 8, (currentXp / targetXp).clamp(0.0, 1.0))),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubMetricPanel extends StatelessWidget {
  final double scale;
  final String value;
  final double progress;
  final IconData icon;
  const _SubMetricPanel({required this.scale, required this.value, required this.progress, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16 * scale),
      child: SmartBlur(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(12 * scale),
          decoration: _glassBox(context, scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _glassIcon(context, scale, 18 * scale, icon, Colors.amber.shade500),
                SizedBox(width: 8 * scale),
                Expanded(
                  child: Text(value,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.primaryColor, fontSize: 13 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400)),
                ),
              ]),
              SizedBox(height: 12 * scale),
              _bar(context, scale, 6, progress),
            ],
          ),
        ),
      ),
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
                final scale = (constraints.maxWidth / 393).clamp(0.6, 1.4).toDouble();
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
                              child: LinearProgressIndicator(
                                value: (_i + 1) / n,
                                minHeight: 14 * scale,
                                color: theme.colorScheme.secondary,
                                backgroundColor: theme.cardColor.withValues(alpha: 0.4),
                              ),
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
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)),
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
  const _PublishedOrBuiltIn({super.key, required this.category, required this.lesson, this.onDone, this.progressLabel});

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
        return _ContinuousPractice(category: category, lessons: lessons);
      },
    );
  }
}

class _ContinuousPractice extends StatefulWidget {
  final CloudCategory category;
  final List<CloudLesson> lessons;
  const _ContinuousPractice({required this.category, required this.lessons});

  @override
  State<_ContinuousPractice> createState() => _ContinuousPracticeState();
}

class _ContinuousPracticeState extends State<_ContinuousPractice> {
  int _i = 0;

  @override
  void initState() {
    super.initState();
    ProgressService().masteredTutorialLines(widget.category.id).first.then((mastered) {
      final first = widget.lessons.indexWhere((l) => !mastered.contains(l.key));
      if (mounted && first > 0) setState(() => _i = first);
    });
  }

  void _next() => setState(() => _i = (_i + 1) % widget.lessons.length);

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lessons[_i];
    return _PublishedOrBuiltIn(
      key: ValueKey('step/${lesson.id}'),
      category: widget.category,
      lesson: lesson,
      onDone: _next,
      progressLabel: 'Sign ${_i + 1} of ${widget.lessons.length}',
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

  Future<void> _confirm() async {
    await ProgressService().markTutorialMastered(widget.category.id, widget.lesson.title);
    if (!mounted) return;
    final theme = Theme.of(context);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 56),
        title: const Text('Great signing!', textAlign: TextAlign.center),
        content: Text('"${widget.lesson.title}" is marked as practised.', textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.onDone != null ? 'Next sign' : 'Done')),
        ],
      ),
    );
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
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
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
                            title: '${category.title} · Level $n',
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

      var result = await send(frames);
      // Some training clips are the sign only, start to end, with no rest
      // around it (e.g. the Setyembre samples: activeS = durationS = 2.08 s).
      // If the first clip does not pass, the same capture is sent once more
      // cut the other way (tight = the sign only, without raising / lowering
      // the hands; or with the margin when tight went first), and the better
      // answer for the practised sign is used.
      if (!_assess(result).passed) {
        final tight = _TrainingClip.from(all, settings, tight: !settings.tightFirst);
        if (tight.frames.length >= 8 && tight.frames.length != frames.length && tight.problem() == null) {
          final second = await send(tight.frames);
          debugPrint('Published model tight clip (${tight.describe()}): ${second.raw}');
          if (_assess(second).passed || _assess(second).share > _assess(result).share) {
            result = second;
            _clipInfo = '${settings.tightFirst ? 'with margin' : 'tight'}: ${tight.describe()}';
          }
        }
      }
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
        (pct(best) >= _target.practice.minConfidence ||
            (share(best) >= _target.practice.minSignShare && share(best) - share(next) >= _target.practice.minSignLead));
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
        (pct(best) >= _target.practice.minConfidence ||
            (share(best) >= _target.practice.minSignShare && lead >= _target.practice.minSignLead));

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
    HapticFeedback.heavyImpact();
    final continuous = widget.onDone != null;
    final module = widget.category.id;
    await ProgressService().markTutorialMastered(module, widget.lesson.title);
    await ProgressService().awardFirstMastery(
      moduleKey: continuous ? XpRewards.practiceKey(module) : module,
      itemKey: ProgressService.masteryKey(widget.lesson.title),
      xp: continuous ? XpRewards.practiceSign : XpRewards.tutorialSign,
      xpField: widget.category.xpField,
      countsAsLesson: !continuous,
    );
    if (!mounted) return;
    if (continuous) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) widget.onDone!();
      return;
    }
    final theme = Theme.of(context);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 56),
        title: Text(L.t('Great signing!', 'Mahusay!'), textAlign: TextAlign.center),
        content: Text(L.t('"${widget.lesson.title}" is mastered.', 'Natutunan mo na ang "${widget.lesson.title}".'),
            textAlign: TextAlign.center),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(L.t('Done', 'Tapos')))],
      ),
    );
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
/// (gesture_training_samples, validated by the web pipeline): the sign
/// itself with a short margin (training: ~1.0 s of signing in a ~1.8 s clip),
/// body and hands in view in every frame, no hand cut off at the edge. The
/// server resamples the whole clip to 32 steps, so a phone capture with
/// seconds of waiting around the sign squeezes the sign into a few steps.
class _TrainingClip {
  final List<RawFrame> frames;
  final double durationS;
  final double activeS;
  final double handCoverage;
  final double poseCoverage;
  final double outOfFrame;

  /// Limits: the web's validation thresholds, per model / sign.
  final PracticeSettings settings;

  const _TrainingClip(this.frames, this.durationS, this.activeS, this.handCoverage, this.poseCoverage, this.outOfFrame, this.settings);

  /// Hand moved between two frames: mean |dx| + |dy| of its 21 points
  /// above this share of the image (handshape changes count too).
  static const double _motion = 0.008;


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

    // The moving part, plus a short margin like the training clips.
    var first = -1, last = -1;
    for (var i = 1; i < frames.length; i++) {
      if (_moved(frames[i - 1], frames[i]) > _motion) {
        if (first == -1) first = i - 1;
        last = i;
      }
    }
    var activeS = 0.0;
    if (first != -1) {
      activeS = (frames[last].timeMs - frames[first].timeMs) / 1000.0;
      final from = frames[first].timeMs - margin, to = frames[last].timeMs + margin;
      frames = frames.where((f) => f.timeMs >= from && f.timeMs <= to).toList();
    }

    final n = frames.isEmpty ? 1 : frames.length;
    final withHands = frames.where((f) => f.hasHands).length;
    final withPose = frames.where((f) => f.pose != null).length;
    final cutOff = frames.where((f) => (f.leftHand != null && !_inFrame(f.leftHand)) || (f.rightHand != null && !_inFrame(f.rightHand))).length;
    final duration = frames.length < 2 ? 0.0 : (frames.last.timeMs - frames.first.timeMs) / 1000.0;
    return _TrainingClip(_smooth(frames), duration, activeS, withHands / n, withPose / n, cutOff / n, settings);
  }

  /// Training ran MediaPipe Holistic with smooth_landmarks=true; the phone's
  /// landmarks are raw. A light running average per point (restarted when a
  /// hand / the body was not detected) removes the frame-to-frame jitter.
  static const double _keep = 0.4; // share of the previous smoothed value

  static List<RawFrame> _smooth(List<RawFrame> frames) {
    List<List<double>>? prevPose, prevLeft, prevRight;
    List<List<double>>? step(List<List<double>>? now, List<List<double>>? prev) {
      if (now == null) return null;
      if (prev == null || prev.length != now.length) return now;
      return [
        for (var i = 0; i < now.length; i++)
          [
            for (var k = 0; k < now[i].length; k++)
              k < 3 && k < prev[i].length ? _keep * prev[i][k] + (1 - _keep) * now[i][k] : now[i][k]
          ]
      ];
    }

    return [
      for (final f in frames)
        () {
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
    if (activeS < settings.minActiveS) {
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
