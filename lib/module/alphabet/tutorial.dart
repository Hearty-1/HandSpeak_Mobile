import 'package:flutter/material.dart';
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

  // This list holds the data we actually display on screen
  List<Map<String, String>> filteredLessons = [];

  @override
  void initState() {
    super.initState();
    // Initially, show all lessons
    filteredLessons = lessons;
  }

  // The function that runs every time the user types in the search bar
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
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFB800),
        title: const Text("Tutorial List", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFFFF9E5),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: TextField(
                onChanged: (value) => _runFilter(value), // Trigger the filter
                decoration: const InputDecoration(
                  hintText: 'Search letter...',
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),

          // Lesson List Directory Builder
          Expanded(
            child: filteredLessons.isEmpty
                ? const Center(child: Text("No letters found.", style: TextStyle(fontSize: 18)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: filteredLessons.length, // Use filtered list
                    itemBuilder: (context, index) {
                      final lesson = filteredLessons[index];
                      final bool isLocked = lesson['status'] == 'locked';
                      
                      return LessonCard(
                        title: lesson['title']!,
                        isLocked: isLocked,
                        onTap: () {
                          if (!isLocked) {
                            // Find the original index so the slider opens to the correct letter
                            final originalIndex = lessons.indexOf(lesson);
                            
                            // ROUTING LINK
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isLocked ? Colors.grey.shade200 : Colors.amber, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isLocked ? Colors.grey : Colors.black,
              ),
            ),
            Icon(
              isLocked ? Icons.lock_outline : Icons.play_circle_fill,
              color: isLocked ? Colors.grey : Colors.orange,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}