import 'package:flutter/material.dart';
// Import the slide-deck screen to allow routing
import 'tutorial_interface_3.dart'; 

class TutorialInterface extends StatelessWidget {
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

  TutorialInterface({super.key});

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
              child: const TextField(
                decoration: InputDecoration(
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
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: lessons.length,
              itemBuilder: (context, index) {
                final bool isLocked = lessons[index]['status'] == 'locked';
                return LessonCard(
                  title: lessons[index]['title']!,
                  isLocked: isLocked,
                  onTap: () {
                    if (!isLocked) {
                      // ROUTING LINK: Pass the exact chosen letter index into the view slider
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TutorialInterface3(initialIndex: index),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Complete previous letters to unlock ${lessons[index]['title']}!"),
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