import 'dart:ui'; // Required for ImageFilter (Glassmorphism)
import 'package:flutter/material.dart';
import 'numbers_tutorial_detail.dart'; 

class NumbersTutorialInterface extends StatefulWidget {
  const NumbersTutorialInterface({super.key});

  @override
  State<NumbersTutorialInterface> createState() => _NumbersTutorialInterfaceState();
}

class _NumbersTutorialInterfaceState extends State<NumbersTutorialInterface> {
  final List<Map<String, String>> lessons = [
    {'title': '1', 'status': 'completed'},
    {'title': '2', 'status': 'completed'},
    {'title': '3', 'status': 'completed'},
    {'title': '4', 'status': 'completed'},
    {'title': '5', 'status': 'completed'},
    {'title': '6', 'status': 'completed'},
    {'title': '7', 'status': 'completed'},
    {'title': '8', 'status': 'completed'},
    {'title': '9', 'status': 'completed'},
    {'title': '10', 'status': 'completed'},
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
    return Scaffold(
      extendBodyBehindAppBar: true, // Blends background image behind the frosted AppBar
      backgroundColor: const Color(0xFFFFF9E5),
      
      // --- FROSTED PREMIUM APP BAR ---
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.35),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF322144)),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: const Text(
          'Number List',
          style: TextStyle(
            color: Color(0xFF322144), 
            fontSize: 22, 
            fontFamily: 'Inter', 
            fontWeight: FontWeight.w800, 
            letterSpacing: -0.96
          ),
        ),
      ),
      
      body: Stack(
        children: [

          // 2. Translucent Ambient Visual Orbs
          Positioned(
            top: 140, right: -40,
            child: Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFB800).withOpacity(0.2))),
          ),
          Positioned(
            bottom: 120, left: -60,
            child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7DC579).withOpacity(0.18))),
          ),

          // 3. User Interface Control Layout Pipeline
          SafeArea(
            child: Column(
              children: [
                // Frosted Search Bar Container Frame
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: TextField(
                          onChanged: (value) => _runFilter(value),
                          style: const TextStyle(color: Color(0xFF322144), fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            hintText: 'Search number...', 
                            hintStyle: TextStyle(color: Colors.black38),
                            prefixIcon: Icon(Icons.search, color: Color(0xFF322144)),
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
                      ? const Center(
                          child: Text(
                            "No numbers found.", 
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF322144))
                          ),
                        )
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
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
                                      builder: (context) => NumbersTutorialDetail(initialIndex: originalIndex),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Complete previous numbers to unlock ${lesson['title']}!"),
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

// --- MICRO-GLASS PREMIUM LESSON INTERFACE CARD ---
class LessonCard extends StatelessWidget {
  final String title;
  final bool isLocked;
  final VoidCallback onTap;

  const LessonCard({
    super.key, 
    required this.title, 
    required this.isLocked, 
    required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15.0),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(
                color: isLocked ? Colors.white.withOpacity(0.35) : Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isLocked ? Colors.white.withOpacity(0.4) : Colors.amber.withOpacity(0.7), 
                  width: 2
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.01),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title, 
                    style: TextStyle(
                      fontSize: 32, 
                      fontWeight: FontWeight.w900, 
                      fontFamily: 'Inter',
                      color: isLocked ? Colors.black38 : const Color(0xFF322144)
                    ),
                  ),
                  Icon(
                    isLocked ? Icons.lock_outline : Icons.play_circle_fill, 
                    color: isLocked ? Colors.black38 : const Color(0xFFFFB800), 
                    size: 32
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