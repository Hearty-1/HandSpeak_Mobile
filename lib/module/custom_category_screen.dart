import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
import '/services/frame_gate.dart';
import '/services/lighting_monitor.dart';
import '/services/performance_monitor.dart';
import '/services/progress_service.dart';
import '/services/role_service.dart';
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
        if (url.startsWith('assets/')) return Image.asset(url, fit: fit, errorBuilder: (_, __, ___) => fallback);
        return Image.network(url, fit: fit, errorBuilder: (_, __, ___) => fallback);
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
            if (CloudCategory.fromDoc(d) case final c?) c,
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
  const CloudLesson({required this.id, required this.title, required this.media});

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
                                          MaterialPageRoute(builder: (_) => CloudActivityLevelsScreen(category: category))),
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

class CloudTutorialListScreen extends StatelessWidget {
  final CloudCategory category;
  const CloudTutorialListScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        title: Text('${category.title} Tutorial',
            style: TextStyle(color: textColor, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96)),
      ),
      body: StreamBuilder<List<CloudLesson>>(
        stream: _lessonsOf(category),
        builder: (context, snap) {
          if (!snap.hasData) return Center(child: CircularProgressIndicator(color: theme.primaryColor));
          final lessons = snap.data!;
          if (lessons.isEmpty) return const _EmptyNote(text: 'No tutorials yet. Your teachers will add them soon.');
          return StreamBuilder<Set<String>>(
            stream: ProgressService().masteredTutorialLines(category.id),
            builder: (context, m) {
              final mastered = m.data ?? const <String>{};
              return ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                itemCount: lessons.length,
                itemBuilder: (context, i) => _LessonCard(
                  title: lessons[i].title,
                  mastered: mastered.contains(lessons[i].key),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => CloudLessonScreen(category: category, lessons: lessons, initialIndex: i))),
                ),
              );
            },
          );
        },
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
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        title: Text('Tutorial', style: TextStyle(color: textColor, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              Text(lesson.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textColor, fontSize: lesson.title.length > 18 ? 28 : 44, fontWeight: FontWeight.w900, fontFamily: 'Inter')),
              const SizedBox(height: 18),
              AspectRatio(
                aspectRatio: 1.08,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: _CloudMedia(key: ValueKey(lesson.media), source: lesson.media, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(value: (_i + 1) / n, minHeight: 12, color: theme.colorScheme.secondary,
                    backgroundColor: theme.cardColor),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _i > 0 ? () => setState(() => _i--) : null,
                    icon: Icon(Icons.arrow_back, color: textColor),
                    label: Text('Previous', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: _i < n - 1 ? () => setState(() => _i++) : null,
                    child: Row(children: [
                      Text('Next', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward, color: textColor),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => practiceFor(widget.category, lesson))),
                  child: const Text('Practice', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
                ),
              ),
            ],
          ),
        ),
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
Widget practiceFor(CloudCategory category, CloudLesson lesson, {VoidCallback? onDone}) {
  final t = lesson.title.trim();
  if (RegExp(r'^[A-Za-z]$').hasMatch(t)) return TutorialPractice(targetLetter: t.toUpperCase());
  final n = int.tryParse(t);
  if (n != null && n >= 1 && n <= 100) return NumbersTutorialPractice(targetNumber: '$n');
  if (PhraseRecognizer.classIndexFor(t) != -1) return PhraseTutorialPractice(targetPhrase: t, mediaUrl: lesson.media);
  return CloudMirrorPractice(category: category, lesson: lesson, onDone: onDone);
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
    final screen = practiceFor(widget.category, lesson, onDone: _next);
    if (screen is CloudMirrorPractice) {
      return CloudMirrorPractice(
        key: ValueKey(lesson.id),
        category: widget.category,
        lesson: lesson,
        onDone: _next,
        progressLabel: 'Sign ${_i + 1} of ${widget.lessons.length}',
      );
    }
    // A sign with its own recogniser: that practice screen, then the next one.
    return _RecognizerStep(key: ValueKey(lesson.id), screen: screen, lesson: lesson, onNext: _next,
        progressLabel: 'Sign ${_i + 1} of ${widget.lessons.length}');
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
