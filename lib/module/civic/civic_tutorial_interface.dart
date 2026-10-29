import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'civic_tutorial_detail.dart';

import '/services/performance_monitor.dart';
import '/services/progress_service.dart';
import '/services/xp_rewards.dart';
import '/providers/language_provider.dart';

class CivicLesson {
  final String id;
  final String title;
  final String videoUrl;
  final String description;
  final int order;
  final bool isLocked;
  final List<Map<String, dynamic>> questions;

  /// Practice category (e.g. 'lupang_hinirang'); empty = use [title].
  final String category;

  /// Lupang Hinirang line: model class index (-1 = not a single line) and the
  /// 1-based number shown to the user.
  final int lineIndex;
  final int lineNumber;

  CivicLesson({
    required this.id,
    required this.title,
    required this.videoUrl,
    this.description = '',
    required this.order,
    this.isLocked = false,
    this.questions = const [],
    this.category = '',
    this.lineIndex = -1,
    this.lineNumber = 0,
  });

  factory CivicLesson.fromJson(Map<String, dynamic> json, String docId) {
    return CivicLesson(
      id: docId,
      title: json['displayTitle'] ?? json['title'] ?? json['symbol'] ?? json['label'] ?? 'Civic Video Lesson',
      videoUrl: json['videoUrl'] ?? json['video_url'] ?? json['mediaUrl'] ?? '',
      description: json['description'] ?? '',
      order: json['order'] ?? json['index'] ?? 0,
      isLocked: json['status'] == 'locked' || json['isLocked'] == true,
      questions: json['questions'] != null
          ? List<Map<String, dynamic>>.from(json['questions'])
          : [],
    );
  }
}

/// The Lupang Hinirang tutorial: one lesson per line of the merged 21-line
/// manifest (assets/civic/labels_lupang_hinirang.json, the class order of the
/// deployed model), each with its own XP reward.
class LupangLines {
  static const String category = 'lupang_hinirang';
  static const String manifestPath = 'assets/civic/labels_lupang_hinirang.json';

  /// Key of the per-line mastery record (ProgressService.awardTutorialLineXp).
  static const String moduleKey = 'civic_lupang_hinirang';
  static int get xpPerLine => XpRewards.civicTutorial; // xp_rewards.dart
  static const String xpField = 'civicXp';

  /// Mastery key of a line = its model class index (stable across reorders).
  static String lineKey(int classIndex) => 'line_$classIndex';

  static String compact(String s) => s
      .toLowerCase()
      .replaceFirst(RegExp(r'^\s*\d+[_\s-]+'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Manifest phrases sorted by class index.
  static Future<List<Map<String, dynamic>>> loadPhrases() async {
    final manifest = jsonDecode(await rootBundle.loadString(manifestPath));
    return List<Map<String, dynamic>>.from(manifest['phrases'])
      ..sort((a, b) => ((a['index'] as num?) ?? 0).compareTo((b['index'] as num?) ?? 0));
  }
}

class CivicTutorialInterface extends StatefulWidget {
  const CivicTutorialInterface({super.key});

  @override
  State<CivicTutorialInterface> createState() => _CivicTutorialInterfaceState();
}

class _CivicTutorialInterfaceState extends State<CivicTutorialInterface> {
  List<CivicLesson> _allLessons = [];
  List<CivicLesson> _filteredLessons = [];
  bool _isLoading = true;
  bool _hasError = false; // the line list itself could not be built
  bool _videosUnavailable = false; // Firestore (videos) failed; lines still work
  String _query = '';
  late final Stream<Set<String>> _mastered = ProgressService().masteredTutorialLines(LupangLines.moduleKey);

  @override
  void initState() {
    super.initState();
    _fetchLessons();
  }

  /// Firestore civic lessons, used only for videos: a lesson whose title is a
  /// line, a question of the Lupang Hinirang lesson that carries a video, or
  /// the whole-anthem video as the fallback for every line.
  Future<List<Map<String, dynamic>>> _fetchFirestoreLessons() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('tutorial_lessons')
        .where('category', whereIn: ['civic', 'Civic', 'civics'])
        .get();
    return [for (final doc in snapshot.docs) doc.data()];
  }

  static String _video(Map m) {
    final v = (m['videoUrl'] ?? m['video_url'] ?? m['mediaUrl'] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
    // The web dashboard's "Add Sign" form saves an uploaded video in
    // imageUrl too; use it when the file is a video.
    final img = (m['imageUrl'] ?? m['image_url'] ?? '').toString().trim();
    return _isVideoFile(img) ? img : '';
  }

  /// mp4 / mov / webm / m4v, also inside a Firebase Storage download link
  /// (".../o/folder%2Fclip.mp4?alt=media&token=...").
  static bool _isVideoFile(String url) {
    if (url.isEmpty) return false;
    final path = Uri.decodeComponent(url.split('?').first).toLowerCase();
    return RegExp(r'\.(mp4|mov|webm|m4v|3gp)$').hasMatch(path);
  }

  Future<void> _fetchLessons() async {
    List<Map<String, dynamic>> phrases;
    try {
      phrases = await LupangLines.loadPhrases();
    } catch (e) {
      debugPrint("Lupang Hinirang manifest error: $e");
      if (mounted) setState(() {
        _isLoading = false;
        _hasError = true;
      });
      return;
    }

    var docs = <Map<String, dynamic>>[];
    bool videosFailed = false;
    try {
      docs = await _fetchFirestoreLessons();
    } catch (e) {
      debugPrint("Firestore civic lessons unavailable: $e");
      videosFailed = true;
    }

    final videoByLine = <String, String>{};
    String anthemVideo = '';
    for (final d in docs) {
      final title = (d['displayTitle'] ?? d['title'] ?? d['label'] ?? '').toString();
      final key = LupangLines.compact(title);
      if (_video(d).isNotEmpty) videoByLine.putIfAbsent(key, () => _video(d));
      final isAnthem = key.contains('lupang') && key.contains('hinirang') && key.length <= 'lupanghinirang'.length + 12;
      if (isAnthem && anthemVideo.isEmpty) anthemVideo = _video(d);
      for (final q in (d['questions'] as List?) ?? const []) {
        if (q is! Map || _video(q).isEmpty) continue;
        for (final f in ['folder_code', 'label', 'question', 'title', 'id']) {
          final k = LupangLines.compact('${q[f] ?? ''}');
          if (k.isNotEmpty) videoByLine.putIfAbsent(k, () => _video(q));
        }
      }
    }

    final lessons = <CivicLesson>[];
    for (int i = 0; i < phrases.length; i++) {
      final p = phrases[i];
      final index = ((p['index'] as num?) ?? i).toInt();
      final label = '${p['label']}';
      final lineVideo = videoByLine[LupangLines.compact(label)] ??
          videoByLine[LupangLines.compact('${p['folder_code'] ?? ''}')] ??
          anthemVideo;
      lessons.add(CivicLesson(
        id: 'lupang_line_$index',
        title: label,
        videoUrl: lineVideo,
        description: '${p['instruction'] ?? ''}',
        order: i,
        category: LupangLines.category,
        lineIndex: index,
        lineNumber: i + 1,
        questions: [
          {
            'id': label,
            'question': label,
            'label': label,
            'instruction': p['instruction'] ?? '',
            'folder_code': p['folder_code'] ?? '',
            'index': index,
            'line_number': i + 1,
            'videoUrl': lineVideo, // demo video in the practice screen
          }
        ],
      ));
    }

    if (mounted) {
      setState(() {
        _allLessons = lessons;
        _filteredLessons = _applyFilter(lessons, _query);
        _isLoading = false;
        _hasError = false;
        _videosUnavailable = videosFailed;
      });
    }
  }

  List<CivicLesson> _applyFilter(List<CivicLesson> lessons, String keyword) {
    final k = keyword.trim().toLowerCase();
    if (k.isEmpty) return lessons;
    return lessons
        .where((l) => l.title.toLowerCase().contains(k) || '${l.lineNumber}' == k || L.t('line ${l.lineNumber}', 'linya ${l.lineNumber}').contains(k))
        .toList();
  }

  void _runFilter(String enteredKeyword) {
    setState(() {
      _query = enteredKeyword;
      _filteredLessons = _applyFilter(_allLessons, enteredKeyword);
    });
  }

  void _openLesson(CivicLesson lesson) {
    final index = _allLessons.indexWhere((l) => l.id == lesson.id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CivicTutorialDetail(
          civicList: _allLessons,
          initialIndex: index == -1 ? 0 : index,
        ),
      ),
    );
  }

  Widget _sectionHeader(int mastered, int total, Color textColor) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 14, left: 4, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 20, color: theme.primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lupang Hinirang',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFamily: 'Inter', color: textColor),
                ),
              ),
              Text(L.t('$mastered / $total lines', '$mastered / $total linya'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: textColor.withOpacity(0.6))),
            ],
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,

      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.6),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        flexibleSpace: ClipRRect(
          child: SmartBlur(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withOpacity(0.1),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          L.t('Civic Tutorial', 'Tutorial na Pansibiko'),
          style: TextStyle(
            color: textColor, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96
          ),
        ),
      ),

      body: Stack(
        children: [
          Positioned(
            top: -50, left: -50,
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.primaryColor.withOpacity(0.25),
              ),
            ),
          ),
          Positioned(
            bottom: 100, right: -80,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4CAF50).withOpacity(0.15),
              ),
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
                          color: theme.cardColor.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: theme.dividerColor.withOpacity(0.15), width: 1.5),
                        ),
                        child: TextField(
                          onChanged: (value) => _runFilter(value),
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            hintText: L.t('Search line...', 'Maghanap ng linya...'),
                            hintStyle: TextStyle(color: textColor.withOpacity(0.5), fontWeight: FontWeight.w500),
                            prefixIcon: Icon(Icons.search, color: textColor.withOpacity(0.5)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: _buildBodyContent(textColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyContent(Color textColor) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor));
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: textColor.withOpacity(0.6)),
            const SizedBox(height: 16),
            Text(
              L.t('Failed to load the lines.', 'Hindi ma-load ang mga linya.'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor.withOpacity(0.8)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() => _isLoading = true);
                _fetchLessons();
              },
              child: Text(L.t('Tap to retry', 'Pindutin para subukang muli')),
            )
          ],
        ),
      );
    }

    return StreamBuilder<Set<String>>(
      stream: _mastered,
      builder: (context, snapshot) {
        final mastered = snapshot.data ?? const <String>{};
        final masteredCount =
            _allLessons.where((l) => mastered.contains(LupangLines.lineKey(l.lineIndex))).length;

        final rows = <Widget>[
          if (_videosUnavailable)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_rounded, size: 18, color: textColor.withOpacity(0.6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(L.t('The videos could not be loaded from the server.', 'Hindi ma-load ang mga video mula sa server.'),
                        style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.7))),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _isLoading = true);
                      _fetchLessons();
                    },
                    child: Text(L.t('Retry', 'Subukang muli')),
                  ),
                ],
              ),
            ),
          _sectionHeader(masteredCount, _allLessons.length, textColor),
          if (_filteredLessons.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  L.t('No lines found.', 'Walang nahanap na linya.'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor.withOpacity(0.6)),
                ),
              ),
            ),
          for (final lesson in _filteredLessons)
            CivicCard(
              title: lesson.title,
              isLocked: lesson.isLocked,
              isMastered: mastered.contains(LupangLines.lineKey(lesson.lineIndex)),
              onTap: () => _openLesson(lesson),
            ),
        ];

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: rows,
        );
      },
    );
  }
}

class CivicCard extends StatelessWidget {
  final String title;
  final bool isLocked;
  final bool isMastered;
  final VoidCallback onTap;

  const CivicCard({
    super.key,
    required this.title,
    required this.isLocked,
    required this.onTap,
    this.isMastered = false,
  });

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
          child: Opacity(
            opacity: isLocked ? 0.6 : 1.0,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                decoration: BoxDecoration(
                  color: theme.cardColor.withOpacity(isLocked ? 0.4 : 0.75),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLocked
                        ? theme.dividerColor.withOpacity(0.2)
                        : (isMastered ? Colors.green.withOpacity(0.6) : theme.primaryColor.withOpacity(0.5)),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Inter',
                          color: isLocked ? textColor.withOpacity(0.4) : textColor,
                          letterSpacing: -0.6,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (isLocked)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: textColor.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.lock_outline, color: textColor.withOpacity(0.4), size: 22),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: theme.primaryColor.withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Icon(Icons.play_arrow_rounded, color: theme.primaryColor, size: 22),
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
