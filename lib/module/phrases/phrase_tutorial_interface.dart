import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'phrase_tutorial_detail.dart';

// --- DATA MODEL ---
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

  factory PhraseLesson.fromJson(Map<String, dynamic> json, String docId) {
    return PhraseLesson(
      id: docId,
      title: json['title'] ?? json['label'] ?? 'Unknown Phrase',
      imageUrl: json['image_url'] ?? json['imagePath'] ?? '',
      order: json['order'] ?? 0,
      isLocked: json['status'] == 'locked',
    );
  }
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

  // --- HYBRID FALLBACK DATA ---
  // If Firestore fails or is empty, the app will load these original local assets.
  final List<PhraseLesson> _localLessons = [
    PhraseLesson(id: 'local_1', title: 'GoodAfternoon', imageUrl: 'assets/pictures/good_afternoon.jpg', order: 1),
    PhraseLesson(id: 'local_2', title: 'GoodEvening', imageUrl: 'assets/pictures/good_evening.jpg', order: 2),
    PhraseLesson(id: 'local_3', title: 'GoodMorning', imageUrl: 'assets/pictures/good_morning.jpg', order: 3),
    PhraseLesson(id: 'local_4', title: 'Hello', imageUrl: 'assets/pictures/hello.jpg', order: 4),
    PhraseLesson(id: 'local_5', title: 'HowAreYou', imageUrl: 'assets/pictures/how_are_you.jpg', order: 5),
    PhraseLesson(id: 'local_6', title: 'ImFine', imageUrl: 'assets/pictures/im_fine.jpg', order: 6),
    PhraseLesson(id: 'local_7', title: 'NiceToMeetYou', imageUrl: 'assets/pictures/nice_to_meet_you.jpg', order: 7),
    PhraseLesson(id: 'local_8', title: 'SeeYouTom', imageUrl: 'assets/pictures/see_you_tom.jpg', order: 8),
    PhraseLesson(id: 'local_9', title: 'ThankYou', imageUrl: 'assets/pictures/thank_you.jpg', order: 9),
    PhraseLesson(id: 'local_10', title: 'You\'reWelcome', imageUrl: 'assets/pictures/youre_welcome.jpg', order: 10),
  ];

  @override
  void initState() {
    super.initState();
    _fetchLessons();
  }

  Future<void> _fetchLessons() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tutorials')
          .where('category', isEqualTo: 'phrase')
          .get();

      if (snapshot.docs.isNotEmpty) {
        List<PhraseLesson> lessons = snapshot.docs
            .map((doc) => PhraseLesson.fromJson(doc.data(), doc.id))
            .toList();

        // Sort by order so they appear sequentially
        lessons.sort((a, b) => a.order.compareTo(b.order));

        if (mounted) {
          setState(() {
            _allLessons = lessons;
            _filteredLessons = lessons;
            _isLoading = false;
          });
        }
      } else {
        // If the collection exists but is empty, fallback to local
        _loadLocalFallback();
      }
    } catch (e) {
      // If there's no internet or a Firestore error, fallback to local
      debugPrint("Firestore fetch failed: $e. Loading local fallback.");
      _loadLocalFallback();
    }
  }

  void _loadLocalFallback() {
    if (mounted) {
      setState(() {
        _allLessons = _localLessons;
        _filteredLessons = _localLessons;
        _isLoading = false;
      });
    }
  }

  void _runFilter(String enteredKeyword) {
    List<PhraseLesson> results = [];
    if (enteredKeyword.isEmpty) {
      results = _allLessons;
    } else {
      results = _allLessons
          .where((lesson) =>
              lesson.title.toLowerCase().contains(enteredKeyword.toLowerCase()))
          .toList();
    }

    setState(() {
      _filteredLessons = results;
    });
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
          child: BackdropFilter(
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
          // Background Decorations
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
                    child: BackdropFilter(
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

    if (_filteredLessons.isEmpty) {
      return Center(
        child: Text(
          "No phrases found.", 
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor.withOpacity(0.6)),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _filteredLessons.length, 
      itemBuilder: (context, index) {
        final lesson = _filteredLessons[index];
        
        return PhraseCard(
          title: lesson.title,
          isLocked: lesson.isLocked,
          onTap: () {
            if (!lesson.isLocked) {
              final originalIndex = _allLessons.indexWhere((l) => l.id == lesson.id);
              
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PhraseTutorialDetail(
                    phraseList: _allLessons, 
                    initialIndex: originalIndex == -1 ? 0 : originalIndex,
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Complete previous phrases to unlock ${lesson.title}!"),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          },
        );
      },
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
        child: BackdropFilter(
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