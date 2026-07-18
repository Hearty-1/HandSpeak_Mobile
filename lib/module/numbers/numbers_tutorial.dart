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
      backgroundColor: const Color(0xFFFFF9E5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFB800),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          'Number List',
          style: TextStyle(
            color: Colors.black, 
            fontSize: 22, 
            fontFamily: 'Inter', 
            fontWeight: FontWeight.w800, 
            letterSpacing: -0.96
          ),
        ),
      ),
      body: Column(
        children: [
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
                  hintText: 'Search number...', 
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          Expanded(
            child: filteredLessons.isEmpty
                ? const Center(child: Text("No numbers found.", style: TextStyle(fontSize: 18)))
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
                            // Find original index
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
    );
  }
}

// LessonCard remains the same
class LessonCard extends StatelessWidget {
  final String title;
  final bool isLocked;
  final VoidCallback onTap;

  const LessonCard({super.key, required this.title, required this.isLocked, required this.onTap});

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
            Text(title, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: isLocked ? Colors.grey : Colors.black)),
            Icon(isLocked ? Icons.lock_outline : Icons.play_circle_fill, color: isLocked ? Colors.grey : Colors.orange, size: 28),
          ],
        ),
      ),
    );
  }
}