import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DatabaseSeeder {
  static Future<void> seedActivities(BuildContext context) async {
    final CollectionReference ref = FirebaseFirestore.instance.collection('activity_questions');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Uploading mixed-style questions to Firebase...")),
    );

    try {
      final List<Map<String, dynamic>> questionsToUpload = [
        // =====================================================================
        // STYLE 1: SIGN-TO-TEXT 
        // =====================================================================
        {
          "category": "alphabet",
          "level": "easy",
          "type": "sign_to_text",
          "image_url": "assets/pictures/A.png",
          "question_text": "What letter is this sign?",
          "options": ["A", "S", "E", "M"],
          "correct_answer": "A"
        },
        {
          "category": "numbers",
          "level": "easy",
          "type": "sign_to_text",
          "image_url": "assets/pictures/3.png",
          "question_text": "What number is this sign?",
          "options": ["3", "7", "5", "8"],
          "correct_answer": "3"
        },

        // =====================================================================
        // STYLE 2: TEXT-TO-SIGN 
        // =====================================================================
        {
          "category": "alphabet",
          "level": "easy",
          "type": "text_to_sign",
          "image_url": "", // No main question image needed
          "question_text": "Which of these signs represents the letter 'B'?",
          "options": [
            "assets/pictures/A.png",
            "assets/pictures/B.png", // Correct choice
            "assets/pictures/C.png",
            "assets/pictures/D.png"
          ],
          "correct_answer": "assets/pictures/B.png"
        },
        {
          "category": "alphabet",
          "level": "easy",
          "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the letter 'C'?",
          "options": [
            "assets/pictures/E.png",
            "assets/pictures/D.png",
            "assets/pictures/C.png", // Correct choice
            "assets/pictures/A.png"
          ],
          "correct_answer": "assets/pictures/C.png"
        },
        {
          "category": "numbers",
          "level": "easy",
          "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the number '5'?",
          "options": [
            "assets/pictures/2.png",
            "assets/pictures/4.png",
            "assets/pictures/1.png",
            "assets/pictures/5.png" // Correct choice
          ],
          "correct_answer": "assets/pictures/5.png"
        }
      ];

      // Upload items to Firestore
      for (var question in questionsToUpload) {
        await ref.add(question);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Database Seeded with Mixed Activities!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Upload failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}