import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'civic_tutorial_detail.dart';

import '/services/performance_monitor.dart';

class CivicLesson {
  final String id;
  final String title;
  final String videoUrl;
  final String description;
  final int order;
  final bool isLocked;
  final List<Map<String, dynamic>> questions;

  CivicLesson({
    required this.id,
    required this.title,
    required this.videoUrl,
    this.description = '',
    required this.order,
    this.isLocked = false,
    this.questions = const [],
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

class CivicTutorialInterface extends StatefulWidget {
  const CivicTutorialInterface({super.key});

  @override
  State<CivicTutorialInterface> createState() => _CivicTutorialInterfaceState();
}

class _CivicTutorialInterfaceState extends State<CivicTutorialInterface> {
  List<CivicLesson> _allLessons = [];
  List<CivicLesson> _filteredLessons = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchLessonsFromFirestore();
  }

  Future<void> _fetchLessonsFromFirestore() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tutorial_lessons')
          .where('category', isEqualTo: 'civic')
          .get();

      List<CivicLesson> lessons = snapshot.docs
          .map((doc) => CivicLesson.fromJson(doc.data(), doc.id))
          .toList();

      lessons.sort((a, b) => a.order.compareTo(b.order));

      if (mounted) {
        setState(() {
          _allLessons = lessons;
          _filteredLessons = lessons;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to load lessons from Firestore: $e";
          _isLoading = false;
        });
      }
    }
  }

  void _runFilter(String enteredKeyword) {
    List<CivicLesson> results = [];
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
          'Civic Video Tutorials',
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
                            hintText: 'Search video tutorial...',
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

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.redAccent),
          ),
        ),
      );
    }

    if (_filteredLessons.isEmpty) {
      return Center(
        child: Text(
          "No civic video lessons found in Firestore.", 
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor.withOpacity(0.6)),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _filteredLessons.length, 
      itemBuilder: (context, index) {
        final lesson = _filteredLessons[index];
        
        return CivicCard(
          title: lesson.title,
          isLocked: lesson.isLocked,
          onTap: () {
            if (!lesson.isLocked) {
              final originalIndex = _allLessons.indexWhere((l) => l.id == lesson.id);
              
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CivicTutorialDetail(
                    civicList: _allLessons, 
                    initialIndex: originalIndex == -1 ? 0 : originalIndex,
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Complete previous video lessons to unlock ${lesson.title}!"),
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

class CivicCard extends StatelessWidget {
  final String title;
  final bool isLocked;
  final VoidCallback onTap;

  const CivicCard({
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
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
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
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.video_library_rounded, color: isLocked ? textColor.withOpacity(0.3) : theme.primaryColor, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 18, 
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Inter',
                                color: isLocked ? textColor.withOpacity(0.4) : textColor,
                                letterSpacing: -0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    isLocked
                        ? Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: textColor.withOpacity(0.08), 
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.lock_outline, color: textColor.withOpacity(0.4), size: 20),
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