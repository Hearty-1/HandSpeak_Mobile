import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DatabaseSeeder {
  // 1. Helper function that automatically generates a unique, deterministic ID
  // based on the question content and correct answer to guarantee no duplicates or collisions.
  static String _generateQuestionId(Map<String, dynamic> question) {
    final String category = question['category'] ?? 'cat';
    final String level = question['level'] ?? 'lvl';
    final String text = question['question_text'] ?? '';
    final String answer = question['correct_answer'] ?? '';

    // Convert text to lowercase, remove special characters, replace spaces with underscores
    final String cleanSlug = '$text $answer'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_') // replace spaces and punctuation with _
        .replaceAll(RegExp(r'_+'), '_');        // clean up multiple underscores

    return '${category}_${level}_$cleanSlug';
  }

  static Future<void> seedActivities(BuildContext context) async {
    final CollectionReference ref = FirebaseFirestore.instance.collection('activity_questions');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Migrating and seeding questions...")),
    );

    try {
      final List<Map<String, dynamic>> questionsToUpload = [
        {
          "category": "alphabet", "level": "alphabet_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_P.jpg",
          "question_text": "Which of these signs represents the letter 'P'?",
          "options": ["assets/pictures/K.jpg", "assets/pictures/Q.jpg", "assets/pictures/P.jpg", "assets/pictures/D.jpg"],
          "correct_answer": "assets/pictures/P.jpg"
        },
        {
          "category": "numbers", "level": "numbers_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/2.9.png",
          "question_text": "Which of these signs represents the number '9'?",
          "options": ["assets/pictures/6.png", "assets/pictures/1.png", "assets/pictures/4.png", "assets/pictures/9.png"],
          "correct_answer": "assets/pictures/9.png"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_L.jpg",
          "question_text": "Which of these signs represents the letter 'L'?",
          "options": ["assets/pictures/L.jpg", "assets/pictures/I.jpg", "assets/pictures/C.jpg", "assets/pictures/V.jpg"],
          "correct_answer": "assets/pictures/L.jpg"
        },
        {
          "category": "numbers", "level": "numbers_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/5.png",
          "question_text": "What number is this sign?",
          "options": ["5", "3", "7", "6"],
          "correct_answer": "5"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/D.jpg",
          "question_text": "What letter is this sign?",
          "options": ["F", "B", "Z", "D"],
          "correct_answer": "D"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/E.jpg",
          "question_text": "What letter is this sign?",
          "options": ["S", "E", "M", "T"],
          "correct_answer": "E"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/C.jpg",
          "question_text": "What letter is this sign?",
          "options": ["O", "G", "C", "Q"],
          "correct_answer": "C"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_3", "type": "sign_to_text",
          "image_url": "assets/pictures/I.jpg",
          "question_text": "What letter is this sign?",
          "options": ["J", "T", "Y", "I"],
          "correct_answer": "I"
        },
        {
          "category": "numbers", "level": "numbers_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/2.png",
          "question_text": "What number is this sign?",
          "options": ["4", "2", "6", "1"],
          "correct_answer": "2"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_O.jpg",
          "question_text": "Which of these signs represents the letter 'O'?",
          "options": ["assets/pictures/C.jpg", "assets/pictures/O.jpg", "assets/pictures/Q.jpg", "assets/pictures/E.jpg"],
          "correct_answer": "assets/pictures/O.jpg"
        },
        {
          "category": "numbers", "level": "numbers_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/2.6.png",
          "question_text": "Which of these signs represents the number '6'?",
          "options": ["assets/pictures/9.png", "assets/pictures/6.png", "assets/pictures/7.png", "assets/pictures/8.png"],
          "correct_answer": "assets/pictures/6.png"
        },
        {
          "category": "numbers", "level": "numbers_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/2.5.png",
          "question_text": "Which of these signs represents the number '5'?",
          "options": ["assets/pictures/5.png", "assets/pictures/9.png", "assets/pictures/8.png", "assets/pictures/7.png"],
          "correct_answer": "assets/pictures/5.png"
        },
        {
          "category": "numbers", "level": "numbers_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/2.10.png",
          "question_text": "Which of these signs represents the number '10'?",
          "options": ["assets/pictures/10.png", "assets/pictures/1.png", "assets/pictures/5.png", "assets/pictures/6.png"],
          "correct_answer": "assets/pictures/10.png"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/J.jpg",
          "question_text": "What letter is this sign?",
          "options": ["I", "L", "J", "U"],
          "correct_answer": "J"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_Q.jpg",
          "question_text": "Which of these signs represents the letter 'Q'?",
          "options": ["assets/pictures/Q.jpg", "assets/pictures/G.jpg", "assets/pictures/P.jpg", "assets/pictures/H.jpg"],
          "correct_answer": "assets/pictures/Q.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_3", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_S.jpg",
          "question_text": "Which of these signs represents the letter 'S'?",
          "options": ["assets/pictures/A.jpg", "assets/pictures/E.jpg", "assets/pictures/T.jpg", "assets/pictures/S.jpg"],
          "correct_answer": "assets/pictures/S.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/H.jpg",
          "question_text": "What letter is this sign?",
          "options": ["U", "H", "V", "G"],
          "correct_answer": "H"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_3", "type": "sign_to_text",
          "image_url": "assets/pictures/G.jpg",
          "question_text": "What letter is this sign?",
          "options": ["H", "Q", "G", "P"],
          "correct_answer": "G"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_3", "type": "sign_to_text",
          "image_url": "assets/pictures/F.jpg",
          "question_text": "What letter is this sign?",
          "options": ["F", "E", "W", "V"],
          "correct_answer": "F"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/B.jpg",
          "question_text": "What letter is this sign?",
          "options": ["D", "B", "P", "R"],
          "correct_answer": "B"
        },
        {
          "category": "numbers", "level": "numbers_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/2.7.png",
          "question_text": "Which of these signs represents the number '7'?",
          "options": ["assets/pictures/7.png", "assets/pictures/2.png", "assets/pictures/3.png", "assets/pictures/4.png"],
          "correct_answer": "assets/pictures/7.png"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_3", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_R.jpg",
          "question_text": "Which of these signs represents the letter 'R'?",
          "options": ["assets/pictures/U.jpg", "assets/pictures/R.jpg", "assets/pictures/V.jpg", "assets/pictures/K.jpg"],
          "correct_answer": "assets/pictures/R.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_N.jpg",
          "question_text": "Which of these signs represents the letter 'N'?",
          "options": ["assets/pictures/M.jpg", "assets/pictures/H.jpg", "assets/pictures/U.jpg", "assets/pictures/N.jpg"],
          "correct_answer": "assets/pictures/N.jpg"
        },
        {
          "category": "numbers", "level": "numbers_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/1.png",
          "question_text": "What number is this sign?",
          "options": ["1", "5", "8", "3"],
          "correct_answer": "1"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_3", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_K.jpg",
          "question_text": "Which of these signs represents the letter 'K'?",
          "options": ["assets/pictures/V.jpg", "assets/pictures/K.jpg", "assets/pictures/P.jpg", "assets/pictures/R.jpg"],
          "correct_answer": "assets/pictures/K.jpg"
        },
        {
          "category": "numbers", "level": "numbers_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/3.png",
          "question_text": "What number is this sign?",
          "options": ["7", "3", "5", "8"],
          "correct_answer": "3"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_T.jpg",
          "question_text": "Which of these signs represents the letter 'T'?",
          "options": ["assets/pictures/T.jpg", "assets/pictures/M.jpg", "assets/pictures/N.jpg", "assets/pictures/S.jpg"],
          "correct_answer": "assets/pictures/T.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/A.jpg",
          "question_text": "What letter is this sign?",
          "options": ["A", "S", "E", "M"],
          "correct_answer": "A"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_M.jpg",
          "question_text": "Which of these signs represents the letter 'M'?",
          "options": ["assets/pictures/N.jpg", "assets/pictures/T.jpg", "assets/pictures/M.jpg", "assets/pictures/S.jpg"],
          "correct_answer": "assets/pictures/M.jpg"
        },
        {
          "category": "numbers", "level": "numbers_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/4.png",
          "question_text": "What number is this sign?",
          "options": ["10", "2", "4", "9"],
          "correct_answer": "4"
        },
        // --- 5 NEW COUNTING-TO-SIGN QUESTIONS (LEVEL 3) ---
        {
          "category": "numbers", 
          "level": "numbers_easy_3", 
          "type": "text_to_sign",
          "image_url": "assets/pictures/1.2.png",
          "question_text": "Count the items in the picture. Which sign represents this number?",
          "options": ["assets/pictures/1.png", "assets/pictures/2.png", "assets/pictures/3.png", "assets/pictures/4.png"],
          "correct_answer": "assets/pictures/2.png"
        },
        {
          "category": "numbers", 
          "level": "numbers_easy_3", 
          "type": "text_to_sign",
          "image_url": "assets/pictures/1.4.png",
          "question_text": "Count the items in the picture. Which sign represents this number?",
          "options": ["assets/pictures/2.png", "assets/pictures/4.png", "assets/pictures/6.png", "assets/pictures/8.png"],
          "correct_answer": "assets/pictures/4.png"
        },
        {
          "category": "numbers", 
          "level": "numbers_easy_3", 
          "type": "text_to_sign",
          "image_url": "assets/pictures/1.5.png",
          "question_text": "Count the items in the picture. Which sign represents this number?",
          "options": ["assets/pictures/3.png", "assets/pictures/5.png", "assets/pictures/7.png", "assets/pictures/9.png"],
          "correct_answer": "assets/pictures/5.png"
        },
        {
          "category": "numbers", 
          "level": "numbers_easy_3", 
          "type": "text_to_sign",
          "image_url": "assets/pictures/1.6.png",
          "question_text": "Count the items in the picture. Which sign represents this number?",
          "options": ["assets/pictures/5.png", "assets/pictures/6.png", "assets/pictures/7.png", "assets/pictures/8.png"],
          "correct_answer": "assets/pictures/6.png"
        },
        {
          "category": "numbers", 
          "level": "numbers_easy_3", 
          "type": "text_to_sign",
          "image_url": "assets/pictures/1.8.png",
          "question_text": "Count the items in the picture. Which sign represents this number?",
          "options": ["assets/pictures/6.png", "assets/pictures/7.png", "assets/pictures/8.png", "assets/pictures/9.png"],
          "correct_answer": "assets/pictures/8.png"
        }
      ];

      // 3. THE WIPE: Get and delete existing random ID questions in Firestore.
      final QuerySnapshot existingDocs = await ref.get();
      final WriteBatch deleteBatch = FirebaseFirestore.instance.batch();
      for (var doc in existingDocs.docs) {
        deleteBatch.delete(doc.reference);
      }
      await deleteBatch.commit(); // Run the delete block

      // 4. THE FRESH SEED: Upload with deterministic IDs so they never duplicate again
      final WriteBatch writeBatch = FirebaseFirestore.instance.batch();
      for (var question in questionsToUpload) {
        final String docId = _generateQuestionId(question);
        writeBatch.set(ref.doc(docId), question);
      }
      await writeBatch.commit(); // Run the write block

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Database Seeded Safely! All duplicates wiped."),
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