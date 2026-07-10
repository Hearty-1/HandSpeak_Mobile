import 'package:flutter/material.dart';
import 'numbers_tutorial_detail.dart'; // Updated import

class NumbersTutorialInterface extends StatelessWidget {
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

  NumbersTutorialInterface({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFB800),
        title: const Text("Number List", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFFFF9E5),
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
              child: const TextField(
                decoration: InputDecoration(
                  hintText: 'Search number...', // Changed hint
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NumbersTutorialDetail(initialIndex: index),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Complete previous numbers to unlock ${lessons[index]['title']}!"),
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