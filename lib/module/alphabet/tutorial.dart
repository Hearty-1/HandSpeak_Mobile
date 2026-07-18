import 'dart:ui'; // Required for ImageFilter (Glassmorphism)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Import the slide-deck screen to allow routing
import 'tutorial_interface_3.dart'; 

class TutorialInterface extends StatefulWidget {
  const TutorialInterface({super.key});

  @override
  State<TutorialInterface> createState() => _TutorialInterfaceState();
}

class _TutorialInterfaceState extends State<TutorialInterface> {
  // Centralized tracking list for alphabet progress status
  final List<Map<String, String>> lessons = [
    {'title': 'Aa', 'status': 'completed'},
    {'title': 'Bb', 'status': 'completed'},
    {'title': 'Cc', 'status': 'completed'},
    {'title': 'Dd', 'status': 'completed'},
    {'title': 'Ee', 'status': 'completed'},
    {'title': 'Ff', 'status': 'completed'},
    {'title': 'Gg', 'status': 'completed'},
    {'title': 'Hh', 'status': 'completed'},
    {'title': 'Ii', 'status': 'completed'},
    {'title': 'Jj', 'status': 'completed'},
    {'title': 'Kk', 'status': 'completed'},
    {'title': 'Ll', 'status': 'completed'},
    {'title': 'Mm', 'status': 'completed'},
    {'title': 'Nn', 'status': 'completed'},
    {'title': 'Oo', 'status': 'completed'},
    {'title': 'Pp', 'status': 'completed'},
    {'title': 'Qq', 'status': 'completed'},
    {'title': 'Rr', 'status': 'completed'},
    {'title': 'Ss', 'status': 'completed'},
    {'title': 'Tt', 'status': 'completed'},
    {'title': 'Uu', 'status': 'completed'},
    {'title': 'Vv', 'status': 'completed'},
    {'title': 'Ww', 'status': 'completed'},
    {'title': 'Xx', 'status': 'completed'},
    {'title': 'Yy', 'status': 'completed'},
    {'title': 'Zz', 'status': 'completed'},
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
      extendBodyBehindAppBar: true, // Allow layout under glass app bar
      backgroundColor: const Color(0xFFFFF9E5),
      
      // --- GLASSMORPHISM APP BAR ---
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.4), // Frosted glass
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
          'Tutorial List',
          style: TextStyle(
            color: Colors.black87, 
            fontSize: 22, 
            fontFamily: 'Inter', 
            fontWeight: FontWeight.w800, 
            letterSpacing: -0.96
          ),
        ),
      ),
      
      body: Stack(
        children: [
          // Ambient Color Blobs
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFB800).withOpacity(0.25),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7DC579).withOpacity(0.15),
              ),
            ),
          ),

          // Main View Content
          SafeArea(
            child: Column(
              children: [
                // Glassmorphism Search Bar Container
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
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03), 
                              blurRadius: 8, 
                              offset: const Offset(0, 3)
                            )
                          ],
                        ),
                        child: TextField(
                          onChanged: (value) => _runFilter(value), 
                          decoration: const InputDecoration(
                            hintText: 'Search letter...',
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
                      ? const Center(child: Text("No letters found.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black54)))
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          itemCount: filteredLessons.length, 
                          itemBuilder: (context, index) {
                            final lesson = filteredLessons[index];
                            final bool isLocked = lesson['status'] == 'locked';
                            
                            return LessonCard(
                              title: lesson['title']!,
                              isLocked: isLocked,
                              onTap: () {
                                if (!isLocked) {
                                  final originalIndex = lessons.indexOf(lesson);
                                  
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TutorialInterface3(initialIndex: originalIndex),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Complete previous letters to unlock ${lesson['title']}!"),
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

class LessonCard extends StatelessWidget {
  final String title;
  final bool isLocked;
  final VoidCallback onTap;

  const LessonCard({
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
                  color: isLocked 
                      ? Colors.white.withOpacity(0.4) 
                      : Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLocked 
                        ? Colors.white.withOpacity(0.4) 
                        : const Color(0xFFFFB800).withOpacity(0.5), 
                    width: 1.5
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04), 
                      blurRadius: 10, 
                      offset: const Offset(0, 4)
                    )
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Inter',
                        color: isLocked ? Colors.black45 : Colors.black87,
                        letterSpacing: -1.0,
                      ),
                    ),
                    isLocked
                        ? Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.05),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.lock_outline, color: Colors.black45, size: 22),
                          )
                        : Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFB800).withOpacity(0.3),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ],
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded, // Customized theme item badge
                              color: Color(0xFFFFB800),
                              size: 22,
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