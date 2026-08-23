import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'phrase_tutorial_detail.dart'; // Adjust import to your detail screen

class PhraseTutorialInterface extends StatefulWidget {
  const PhraseTutorialInterface({super.key});

  @override
  State<PhraseTutorialInterface> createState() => _PhraseTutorialInterfaceState();
}

class _PhraseTutorialInterfaceState extends State<PhraseTutorialInterface> {
  // Centralized tracking list for phrase progress status
  final List<Map<String, String>> lessons = [
    {'title': 'Hello', 'status': 'completed'},
    {'title': 'Thank You', 'status': 'completed'},
    {'title': 'Good Morning', 'status': 'completed'},
    {'title': 'Good Afternoon', 'status': 'completed'},
    {'title': 'How are you?', 'status': 'completed'},
    {'title': 'I\'m Fine', 'status': 'completed'}
  ];

  List<Map<String, String>> filteredLessons = [];

  @override
  void initState() {
    super.initState();
    filteredLessons = lessons;
  }

  void _runFilter(String enteredKeyword) {
    List<Map<String, String>> results = [];
    if (enteredKeyword.isEmpty) {
      results = lessons;
    } else {
      results = lessons
          .where((lesson) =>
              lesson['title']!.toLowerCase().contains(enteredKeyword.toLowerCase()))
          .toList();
    }

    setState(() {
      filteredLessons = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: const Color(0xFFFFF9E5),
      
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.4), 
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: const Text(
          'Phrases Tutorial',
          style: TextStyle(
            color: Colors.black87, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96
          ),
        ),
      ),
      
      body: Stack(
        children: [
          Positioned(
            top: -50, left: -50,
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFB800).withOpacity(0.25)),
            ),
          ),
          Positioned(
            bottom: 100, right: -80,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7DC579).withOpacity(0.15)),
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
                          color: Colors.white.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.7), width: 1.5),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: TextField(
                          onChanged: (value) => _runFilter(value), 
                          decoration: const InputDecoration(
                            hintText: 'Search phrase...',
                            hintStyle: TextStyle(color: Colors.black45, fontWeight: FontWeight.w500),
                            prefixIcon: Icon(Icons.search, color: Colors.black45),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
                Expanded(
                  child: filteredLessons.isEmpty
                      ? const Center(child: Text("No phrases found.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black54)))
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          itemCount: filteredLessons.length, 
                          itemBuilder: (context, index) {
                            final lesson = filteredLessons[index];
                            final bool isLocked = lesson['status'] == 'locked';
                            
                            return PhraseCard(
                              title: lesson['title']!,
                              isLocked: isLocked,
                              onTap: () {
                                if (!isLocked) {
                                  final originalIndex = lessons.indexOf(lesson);
                                  
                                  // Navigate to your Phrase slide deck / tutorial screen here
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => PhraseTutorialDetail(initialIndex: originalIndex),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Complete previous phrases to unlock ${lesson['title']}!"),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
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
                  color: isLocked ? Colors.white.withOpacity(0.4) : Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLocked ? Colors.white.withOpacity(0.4) : const Color(0xFFFFB800).withOpacity(0.5), 
                    width: 1.5
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 22, // Slightly smaller font size since phrases are longer words
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Inter',
                        color: isLocked ? Colors.black45 : Colors.black87,
                        letterSpacing: -1.0,
                      ),
                    ),
                    isLocked
                        ? Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), shape: BoxShape.circle),
                            child: const Icon(Icons.lock_outline, color: Colors.black45, size: 22),
                          )
                        : Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: const Color(0xFFFFB800).withOpacity(0.3), blurRadius: 8, spreadRadius: 1)],
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Color(0xFFFFB800), size: 22),
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