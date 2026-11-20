import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'phrase_tutorial_detail.dart';

import '/services/performance_monitor.dart';
import '/services/progress_service.dart';
import '/providers/language_provider.dart';

class PhraseLesson {
  final String id;
  final String title;
  final String imageUrl;
  final int order;
  final bool isLocked;

  PhraseLesson({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.order,
    this.isLocked = false,
  });
}

/// Phrases tutorial = greetings only. The months (calendar lessons) were
/// removed: the calendar model does not recognise new signers yet
/// (2026-10-14 phone replay: 5 of 27 correct attempts accepted).
class PhraseCategories {
  static const List<String> phraseKeys = ['phrase', 'phrases', 'Phrase', 'Phrases'];

  /// Month names (Filipino and English): month lessons uploaded under the
  /// phrase category are skipped too.
  static const Set<String> _months = {
    'enero', 'pebrero', 'marso', 'abril', 'mayo', 'hunyo', 'hulyo', 'agosto', 'setyembre', 'oktubre',
    'nobyembre', 'disyembre', 'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
    'september', 'october', 'november', 'december',
  };
  static bool isMonth(String title) => _months.contains(title.trim().toLowerCase());
}

class PhraseTutorialInterface extends StatefulWidget {
  const PhraseTutorialInterface({super.key});

  @override
  State<PhraseTutorialInterface> createState() => _PhraseTutorialInterfaceState();
}

class _PhraseTutorialInterfaceState extends State<PhraseTutorialInterface> {
  List<PhraseLesson> _allLessons = [];
  List<PhraseLesson> _filteredLessons = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _query = '';
  // Signs mastered in tutorial practice (green outline on their cards).
  late final Stream<Set<String>> _mastered = ProgressService().masteredTutorialLines('phrases');

  @override
  void initState() {
    super.initState();
    _fetchLessons();
  }

  Future<String> _resolveImage(String rawImagePath) async {
    // Resolve Firebase Storage paths dynamically if not a direct URL or local asset
    if (rawImagePath.isNotEmpty &&
        !rawImagePath.startsWith('http://') &&
        !rawImagePath.startsWith('https://') &&
        !rawImagePath.startsWith('assets/') &&
        !rawImagePath.startsWith('data:image')) {
      try {
        final ref = rawImagePath.startsWith('gs://')
            ? FirebaseStorage.instance.refFromURL(rawImagePath)
            : FirebaseStorage.instance.ref(rawImagePath);
        return await ref.getDownloadURL();
      } catch (e) {
        debugPrint("Cloud Storage resolution error for $rawImagePath: $e");
      }
    }
    return rawImagePath;
  }

  Future<void> _fetchLessons() async {
    final lessons = <PhraseLesson>[];
    bool failed = false;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tutorial_lessons')
          .where('category', whereIn: PhraseCategories.phraseKeys)
          .get();

      final resolved = await Future.wait(snapshot.docs.map((doc) async {
        final data = doc.data();
        final rawImagePath = (data['videoUrl'] ??
                data['video_url'] ??
                data['image_url'] ??
                data['imageUrl'] ??
                data['imageStoragePath'] ??
                data['imagePath'] ??
                '')
            .toString()
            .trim();
        final title = (data['displayTitle'] ??
                data['gestureKey'] ??
                data['symbol'] ??
                data['title'] ??
                data['label'] ??
                data['name'] ??
                L.t('Unknown Phrase', 'Hindi kilalang parirala'))
            .toString();
        if (PhraseCategories.isMonth(title)) return null;
        return PhraseLesson(
          id: doc.id,
          title: title,
          imageUrl: await _resolveImage(rawImagePath),
          order: (data['order'] as num?)?.toInt() ?? 0,
          isLocked: data['isLocked'] ?? (data['status'] == 'locked'),
        );
      }));
      lessons.addAll(resolved.whereType<PhraseLesson>());
    } catch (e) {
      debugPrint("Firestore fetch error: $e");
      failed = true;
    }

    lessons.sort((a, b) => a.order.compareTo(b.order));

    if (mounted) {
      setState(() {
        _allLessons = lessons;
        _filteredLessons = _applyFilter(lessons, _query);
        _isLoading = false;
        _hasError = failed;
      });
    }
  }

  List<PhraseLesson> _applyFilter(List<PhraseLesson> lessons, String keyword) {
    if (keyword.isEmpty) return lessons;
    final k = keyword.toLowerCase();
    return lessons.where((l) => l.title.toLowerCase().contains(k)).toList();
  }

  void _runFilter(String enteredKeyword) {
    setState(() {
      _query = enteredKeyword;
      _filteredLessons = _applyFilter(_allLessons, enteredKeyword);
    });
  }

  void _openLesson(PhraseLesson lesson) {
    if (lesson.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L.t('Complete previous phrases to unlock ${lesson.title}!', 'Tapusin ang mga naunang parirala para mabuksan ang ${lesson.title}!')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final index = _allLessons.indexWhere((l) => l.id == lesson.id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhraseTutorialDetail(
          dynamicLessons: _allLessons
              .map((l) => <String, dynamic>{
                    'title': l.title,
                    'gestureKey': l.title, // the title is the gesture target for phrases
                    'imageUrl': l.imageUrl,
                  })
              .toList(),
          initialIndex: index == -1 ? 0 : index,
        ),
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
        backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.6), 
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
                    color: theme.dividerColor.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          L.t('Phrases Tutorial', 'Tutorial ng mga Parirala'),
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
                color: theme.primaryColor.withValues(alpha: 0.25),
              ),
            ),
          ),
          Positioned(
            bottom: 100, right: -80,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle, 
                color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
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
                          color: theme.cardColor.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15), width: 1.5),
                        ),
                        child: TextField(
                          onChanged: (value) => _runFilter(value), 
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            hintText: L.t('Search phrase...', 'Maghanap ng parirala...'),
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

    if (_hasError && _allLessons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: textColor.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(
              L.t('Failed to load phrases.', 'Hindi ma-load ang mga parirala.'), 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.8)),
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

    if (_filteredLessons.isEmpty) {
      return Center(
        child: Text(
          L.t('No phrases found.', 'Walang nahanap na parirala.'), 
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.6)),
        ),
      );
    }

    return StreamBuilder<Set<String>>(
      stream: _mastered,
      builder: (context, masteredSnap) {
        final mastered = masteredSnap.data ?? const <String>{};
        final rows = <Widget>[
          if (_hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_rounded, size: 18, color: textColor.withValues(alpha: 0.6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(L.t('Some lessons could not be loaded from the server.', 'Hindi ma-load ang ibang aralin mula sa server.'),
                        style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.7))),
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
        ];
        for (final lesson in _filteredLessons) {
          rows.add(PhraseCard(
            title: lesson.title,
            isLocked: lesson.isLocked,
            isMastered: mastered.contains(ProgressService.masteryKey(lesson.title)),
            onTap: () => _openLesson(lesson),
          ));
        }

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: rows,
        );
      },
    );
  }
}

class PhraseCard extends StatelessWidget {
  final String title;
  final bool isLocked;
  final bool isMastered;
  final VoidCallback onTap;

  const PhraseCard({
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
                  color: theme.cardColor.withValues(alpha: isLocked ? 0.4 : 0.75),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLocked
                        ? theme.dividerColor.withValues(alpha: 0.2)
                        : (isMastered ? Colors.green.withValues(alpha: 0.75) : theme.primaryColor.withValues(alpha: 0.5)),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 22, 
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Inter',
                        color: isLocked ? textColor.withValues(alpha: 0.4) : textColor,
                        letterSpacing: -1.0,
                      ),
                    ),
                    isLocked
                        ? Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: textColor.withValues(alpha: 0.08), 
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.lock_outline, color: textColor.withValues(alpha: 0.4), size: 22),
                          )
                        : Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.primaryColor.withValues(alpha: 0.3), 
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