import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'phrase_tutorial_practice.dart' show CalendarSigns;
import 'phrase_tutorial_detail.dart';

import '/services/performance_monitor.dart';

class PhraseLesson {
  final String id;
  final String title;
  final String imageUrl;
  final int order;
  final bool isLocked;
  final String category; // PhraseCategories.greetings | PhraseCategories.calendar

  PhraseLesson({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.order,
    this.isLocked = false,
    this.category = PhraseCategories.greetings,
  });
}

class PhraseCategories {
  static const String greetings = 'greetings';
  static const String calendar = 'calendar';

  static const List<String> phraseKeys = ['phrase', 'phrases', 'Phrase', 'Phrases'];
  static const List<String> calendarKeys = [
    'calendar', 'Calendar', 'calendar_phrases', 'month', 'months', 'Months', 'buwan', 'Buwan',
  ];

  static const Map<String, String> titles = {
    greetings: 'Pagbati at Parirala',
    calendar: 'Kalendaryo (Mga Buwan)',
  };
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

  @override
  void initState() {
    super.initState();
    _fetchLessons();
  }

  /// Built-in month lessons, used for any month that has no Firestore lesson
  /// (category "calendar") yet. Firestore lessons always take precedence.
  List<PhraseLesson> _builtInMonths(Set<int> present) => [
        for (int i = 0; i < 12; i++)
          if (!present.contains(i))
            PhraseLesson(
              id: 'builtin_month_$i',
              title: CalendarSigns.displayLabels[i],
              imageUrl: '',
              order: 1000 + i,
              category: PhraseCategories.calendar,
            ),
      ];

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
          .where('category', whereIn: [...PhraseCategories.phraseKeys, ...PhraseCategories.calendarKeys])
          .get();

      final resolved = await Future.wait(snapshot.docs.map((doc) async {
        final data = doc.data();
        final rawImagePath = (data['image_url'] ??
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
                'Unknown Phrase')
            .toString();
        final isCalendar = PhraseCategories.calendarKeys.contains(data['category']) ||
            CalendarSigns.isMonth(title);
        return PhraseLesson(
          id: doc.id,
          title: title,
          imageUrl: await _resolveImage(rawImagePath),
          order: (data['order'] as num?)?.toInt() ?? 0,
          isLocked: data['isLocked'] ?? (data['status'] == 'locked'),
          category: isCalendar ? PhraseCategories.calendar : PhraseCategories.greetings,
        );
      }));
      lessons.addAll(resolved);
    } catch (e) {
      debugPrint("Firestore fetch error: $e");
      failed = true;
    }

    final presentMonths = {
      for (final l in lessons)
        if (l.category == PhraseCategories.calendar) CalendarSigns.indexFor(l.title),
    };
    lessons.addAll(_builtInMonths(presentMonths));
    lessons.sort((a, b) {
      if (a.category != b.category) return a.category == PhraseCategories.greetings ? -1 : 1;
      return a.order.compareTo(b.order);
    });

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
    return lessons.where((l) {
      if (l.title.toLowerCase().contains(k)) return true;
      final m = CalendarSigns.indexFor(l.title); // "march" finds Marso
      return m != -1 && CalendarSigns.classNames[m].toLowerCase().contains(k);
    }).toList();
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
          content: Text("Complete previous phrases to unlock ${lesson.title}!"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    // Next / Previous in the detail screen stay within the lesson's section.
    final section = _allLessons.where((l) => l.category == lesson.category).toList();
    final index = section.indexWhere((l) => l.id == lesson.id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhraseTutorialDetail(
          dynamicLessons: section
              .map((l) => <String, dynamic>{
                    'title': l.title,
                    'gestureKey': l.title, // the title is the gesture target for phrases
                    'imageUrl': l.imageUrl,
                    'category': l.category,
                  })
              .toList(),
          initialIndex: index == -1 ? 0 : index,
        ),
      ),
    );
  }

  Widget _sectionHeader(String category, int count, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12, left: 4),
      child: Row(
        children: [
          Icon(
            category == PhraseCategories.calendar ? Icons.calendar_month_rounded : Icons.waving_hand_rounded,
            size: 20,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              PhraseCategories.titles[category] ?? category,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFamily: 'Inter', color: textColor),
            ),
          ),
          Text('$count', style: TextStyle(fontWeight: FontWeight.w700, color: textColor.withOpacity(0.5))),
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
          'Phrases Tutorial',
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
                            hintText: 'Search phrase...',
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

    if (_hasError && _allLessons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: textColor.withOpacity(0.6)),
            const SizedBox(height: 16),
            Text(
              "Failed to load phrases.", 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor.withOpacity(0.8)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() => _isLoading = true);
                _fetchLessons();
              }, 
              child: const Text("Tap to retry"),
            )
          ],
        ),
      );
    }

    if (_filteredLessons.isEmpty) {
      return Center(
        child: Text(
          "No phrases found.", 
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor.withOpacity(0.6)),
        ),
      );
    }

    final rows = <Widget>[
      if (_hasError)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Icon(Icons.cloud_off_rounded, size: 18, color: textColor.withOpacity(0.6)),
              const SizedBox(width: 8),
              Expanded(
                child: Text("Hindi ma-load ang ibang aralin mula sa server.",
                    style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.7))),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _fetchLessons();
                },
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
    ];
    for (final category in [PhraseCategories.greetings, PhraseCategories.calendar]) {
      final section = _filteredLessons.where((l) => l.category == category).toList();
      if (section.isEmpty) continue;
      rows.add(_sectionHeader(category, section.length, textColor));
      for (final lesson in section) {
        rows.add(PhraseCard(
          title: lesson.title,
          isLocked: lesson.isLocked,
          onTap: () => _openLesson(lesson),
        ));
      }
      rows.add(const SizedBox(height: 8));
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      children: rows,
    );
  }
}

class PhraseCard extends StatelessWidget {
  final String title;
  final bool isLocked;
  final VoidCallback onTap;

  const PhraseCard({
    super.key,
    required this.title,
    required this.isLocked,
    required this.onTap,
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
                    color: isLocked ? theme.dividerColor.withOpacity(0.2) : theme.primaryColor.withOpacity(0.5), 
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
                        color: isLocked ? textColor.withOpacity(0.4) : textColor,
                        letterSpacing: -1.0,
                      ),
                    ),
                    isLocked
                        ? Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: textColor.withOpacity(0.08), 
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.lock_outline, color: textColor.withOpacity(0.4), size: 22),
                          )
                        : Container(
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