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
        {
          "category": "alphabet", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the letter 'P'?",
          "options": ["assets/pictures/K.jpg", "assets/pictures/Q.jpg", "assets/pictures/P.jpg", "assets/pictures/D.jpg"],
          "correct_answer": "assets/pictures/P.jpg"
        },
        {
          "category": "numbers", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the number '9'?",
          "options": ["assets/pictures/6.png", "assets/pictures/1.png", "assets/pictures/4.png", "assets/pictures/9.png"],
          "correct_answer": "assets/pictures/9.png"
        },
        {
          "category": "alphabet", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the letter 'L'?",
          "options": ["assets/pictures/L.jpg", "assets/pictures/I.jpg", "assets/pictures/C.jpg", "assets/pictures/V.jpg"],
          "correct_answer": "assets/pictures/L.jpg"
        },
        {
          "category": "numbers", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/5.png",
          "question_text": "What number is this sign?",
          "options": ["5", "3", "7", "6"],
          "correct_answer": "5"
        },
        {
          "category": "alphabet", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/D.jpg",
          "question_text": "What letter is this sign?",
          "options": ["F", "B", "Z", "D"],
          "correct_answer": "D"
        },
        {
          "category": "alphabet", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/E.jpg",
          "question_text": "What letter is this sign?",
          "options": ["S", "E", "M", "T"],
          "correct_answer": "E"
        },
        {
          "category": "alphabet", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/C.jpg",
          "question_text": "What letter is this sign?",
          "options": ["O", "G", "C", "Q"],
          "correct_answer": "C"
        },
        {
          "category": "alphabet", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/I.jpg",
          "question_text": "What letter is this sign?",
          "options": ["J", "T", "Y", "I"],
          "correct_answer": "I"
        },
        {
          "category": "numbers", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/2.png",
          "question_text": "What number is this sign?",
          "options": ["4", "2", "6", "1"],
          "correct_answer": "2"
        },
        {
          "category": "alphabet", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the letter 'O'?",
          "options": ["assets/pictures/C.jpg", "assets/pictures/O.jpg", "assets/pictures/Q.jpg", "assets/pictures/E.jpg"],
          "correct_answer": "assets/pictures/O.jpg"
        },
        {
          "category": "numbers", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the number '6'?",
          "options": ["assets/pictures/9.png", "assets/pictures/6.png", "assets/pictures/7.png", "assets/pictures/8.png"],
          "correct_answer": "assets/pictures/6.png"
        },
        {
          "category": "numbers", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the number '8'?",
          "options": ["assets/pictures/5.png", "assets/pictures/9.png", "assets/pictures/8.png", "assets/pictures/7.png"],
          "correct_answer": "assets/pictures/8.png"
        },
        {
          "category": "numbers", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the number '10'?",
          "options": ["assets/pictures/10.png", "assets/pictures/1.png", "assets/pictures/5.png", "assets/pictures/6.png"],
          "correct_answer": "assets/pictures/10.png"
        },
        {
          "category": "alphabet", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/J.jpg",
          "question_text": "What letter is this sign?",
          "options": ["I", "L", "J", "U"],
          "correct_answer": "J"
        },
        {
          "category": "alphabet", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the letter 'Q'?",
          "options": ["assets/pictures/Q.jpg", "assets/pictures/G.jpg", "assets/pictures/P.jpg", "assets/pictures/H.jpg"],
          "correct_answer": "assets/pictures/Q.jpg"
        },
        {
          "category": "alphabet", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the letter 'S'?",
          "options": ["assets/pictures/A.jpg", "assets/pictures/E.jpg", "assets/pictures/T.jpg", "assets/pictures/S.jpg"],
          "correct_answer": "assets/pictures/S.jpg"
        },
        {
          "category": "alphabet", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/H.jpg",
          "question_text": "What letter is this sign?",
          "options": ["U", "H", "V", "G"],
          "correct_answer": "H"
        },
        {
          "category": "alphabet", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/G.jpg",
          "question_text": "What letter is this sign?",
          "options": ["H", "Q", "G", "P"],
          "correct_answer": "G"
        },
        {
          "category": "alphabet", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/F.jpg",
          "question_text": "What letter is this sign?",
          "options": ["F", "E", "W", "V"],
          "correct_answer": "F"
        },
        {
          "category": "alphabet", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/B.jpg",
          "question_text": "What letter is this sign?",
          "options": ["D", "B", "P", "R"],
          "correct_answer": "B"
        },
        {
          "category": "numbers", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the number '7'?",
          "options": ["assets/pictures/7.png", "assets/pictures/2.png", "assets/pictures/3.png", "assets/pictures/4.png"],
          "correct_answer": "assets/pictures/7.png"
        },
        {
          "category": "alphabet", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the letter 'R'?",
          "options": ["assets/pictures/U.jpg", "assets/pictures/R.jpg", "assets/pictures/V.jpg", "assets/pictures/K.jpg"],
          "correct_answer": "assets/pictures/R.jpg"
        },
        {
          "category": "alphabet", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the letter 'N'?",
          "options": ["assets/pictures/M.jpg", "assets/pictures/H.jpg", "assets/pictures/U.jpg", "assets/pictures/N.jpg"],
          "correct_answer": "assets/pictures/N.jpg"
        },
        {
          "category": "numbers", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/1.png",
          "question_text": "What number is this sign?",
          "options": ["1", "5", "8", "3"],
          "correct_answer": "1"
        },
        {
          "category": "alphabet", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the letter 'K'?",
          "options": ["assets/pictures/V.jpg", "assets/pictures/K.jpg", "assets/pictures/P.jpg", "assets/pictures/R.jpg"],
          "correct_answer": "assets/pictures/K.jpg"
        },
        {
          "category": "numbers", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/3.png",
          "question_text": "What number is this sign?",
          "options": ["7", "3", "5", "8"],
          "correct_answer": "3"
        },
        {
          "category": "alphabet", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the letter 'T'?",
          "options": ["assets/pictures/T.jpg", "assets/pictures/M.jpg", "assets/pictures/N.jpg", "assets/pictures/S.jpg"],
          "correct_answer": "assets/pictures/T.jpg"
        },
        {
          "category": "alphabet", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/A.jpg",
          "question_text": "What letter is this sign?",
          "options": ["A", "S", "E", "M"],
          "correct_answer": "A"
        },
        {
          "category": "alphabet", "level": "easy", "type": "text_to_sign",
          "image_url": "",
          "question_text": "Which of these signs represents the letter 'M'?",
          "options": ["assets/pictures/N.jpg", "assets/pictures/T.jpg", "assets/pictures/M.jpg", "assets/pictures/S.jpg"],
          "correct_answer": "assets/pictures/M.jpg"
        },
        {
          "category": "numbers", "level": "easy", "type": "sign_to_text",
          "image_url": "assets/pictures/4.png",
          "question_text": "What number is this sign?",
          "options": ["10", "2", "4", "9"],
          "correct_answer": "4"
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