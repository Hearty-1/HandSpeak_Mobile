import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DatabaseSeeder {
  // Helper function generating unique, deterministic IDs based on content and level
  static String _generateQuestionId(Map<String, dynamic> question) {
    final String category = question['category'] ?? 'cat';
    final String level = question['level'] ?? 'lvl';
    final String text = question['question_text'] ?? '';
    final String answer = question['correct_answer'] ?? '';

    final String cleanSlug = '$text $answer'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    return '${category}_${level}_$cleanSlug';
  }

  static Future<void> seedActivities(BuildContext context) async {
    final CollectionReference ref = FirebaseFirestore.instance.collection('activity_questions');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Migrating and seeding questions...")),
    );

    try {
      final List<Map<String, dynamic>> questionsToUpload = [
        // ==========================================
        // ALPHABET EASY (4 LEVELS x MAX 5 QUESTIONS)
        // ==========================================
        // --- ALPHABET EASY 1 (5 QUESTIONS) ---
        {
          "category": "alphabet", "level": "alphabet_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/D.jpg",
          "question_text": "Anong letra ang kumakatawan sa sign na ito?",
          "options": ["F", "B", "Z", "D"],
          "correct_answer": "D"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/E.jpg",
          "question_text": "Anong letra ang kumakatawan sa sign na ito?",
          "options": ["S", "E", "M", "T"],
          "correct_answer": "E"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/C.jpg",
          "question_text": "Anong letra ang kumakatawan sa sign na ito?",
          "options": ["O", "G", "C", "Q"],
          "correct_answer": "C"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/J.jpg",
          "question_text": "Anong letra ang kumakatawan sa sign na ito?",
          "options": ["I", "L", "J", "U"],
          "correct_answer": "J"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/H.jpg",
          "question_text": "Anong letra ang kumakatawan sa sign na ito?",
          "options": ["U", "H", "V", "G"],
          "correct_answer": "H"
        },

        // --- ALPHABET EASY 2 (5 QUESTIONS) ---
        {
          "category": "alphabet", "level": "alphabet_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_P.jpg",
          "question_text": "Aling sign ang kumakatawan sa letra 'P'?",
          "options": ["assets/pictures/K.jpg", "assets/pictures/Q.jpg", "assets/pictures/P.jpg", "assets/pictures/D.jpg"],
          "correct_answer": "assets/pictures/P.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_L.jpg",
          "question_text": "Aling sign ang kumakatawan sa letra 'L'?",
          "options": ["assets/pictures/L.jpg", "assets/pictures/I.jpg", "assets/pictures/C.jpg", "assets/pictures/V.jpg"],
          "correct_answer": "assets/pictures/L.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_O.jpg",
          "question_text": "Aling sign ang kumakatawan sa letra 'O'?",
          "options": ["assets/pictures/C.jpg", "assets/pictures/O.jpg", "assets/pictures/Q.jpg", "assets/pictures/E.jpg"],
          "correct_answer": "assets/pictures/O.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_Q.jpg",
          "question_text": "Aling sign ang kumakatawan sa letra 'Q'?",
          "options": ["assets/pictures/Q.jpg", "assets/pictures/G.jpg", "assets/pictures/P.jpg", "assets/pictures/H.jpg"],
          "correct_answer": "assets/pictures/Q.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_N.jpg",
          "question_text": "Aling sign ang kumakatawan sa letra 'N'?",
          "options": ["assets/pictures/M.jpg", "assets/pictures/H.jpg", "assets/pictures/U.jpg", "assets/pictures/N.jpg"],
          "correct_answer": "assets/pictures/N.jpg"
        },

        // --- ALPHABET EASY 3 (5 QUESTIONS) ---
        {
          "category": "alphabet", "level": "alphabet_easy_3", "type": "sign_to_text",
          "image_url": "assets/pictures/I.jpg",
          "question_text": "Anong letra ang kumakatawan sa sign na ito?",
          "options": ["J", "T", "Y", "I"],
          "correct_answer": "I"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_3", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_S.jpg",
          "question_text": "Aling sign ang kumakatawan sa letra 'S'?",
          "options": ["assets/pictures/A.jpg", "assets/pictures/E.jpg", "assets/pictures/T.jpg", "assets/pictures/S.jpg"],
          "correct_answer": "assets/pictures/S.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_3", "type": "sign_to_text",
          "image_url": "assets/pictures/G.jpg",
          "question_text": "Anong letra ang kumakatawan sa sign na ito?",
          "options": ["H", "Q", "G", "P"],
          "correct_answer": "G"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_3", "type": "sign_to_text",
          "image_url": "assets/pictures/F.jpg",
          "question_text": "Anong letra ang kumakatawan sa sign na ito?",
          "options": ["F", "E", "W", "V"],
          "correct_answer": "F"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_3", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_R.jpg",
          "question_text": "Aling sign ang kumakatawan sa letra 'R'?",
          "options": ["assets/pictures/U.jpg", "assets/pictures/R.jpg", "assets/pictures/V.jpg", "assets/pictures/K.jpg"],
          "correct_answer": "assets/pictures/R.jpg"
        },

        // --- ALPHABET EASY 4 (CONSOLIDATED EXCESS ITEMS - 5 QUESTIONS) ---
        {
          "category": "alphabet", "level": "alphabet_easy_4", "type": "sign_to_text",
          "image_url": "assets/pictures/B.jpg",
          "question_text": "Anong letra ang kumakatawan sa sign na ito?",
          "options": ["D", "B", "P", "R"],
          "correct_answer": "B"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_4", "type": "sign_to_text",
          "image_url": "assets/pictures/A.jpg",
          "question_text": "Anong letra ang kumakatawan sa sign na ito?",
          "options": ["A", "S", "E", "M"],
          "correct_answer": "A"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_4", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_T.jpg",
          "question_text": "Aling sign ang kumakatawan sa letra 'T'?",
          "options": ["assets/pictures/T.jpg", "assets/pictures/M.jpg", "assets/pictures/N.jpg", "assets/pictures/S.jpg"],
          "correct_answer": "assets/pictures/T.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_4", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_M.jpg",
          "question_text": "Aling sign ang kumakatawan sa letra 'M'?",
          "options": ["assets/pictures/N.jpg", "assets/pictures/T.jpg", "assets/pictures/M.jpg", "assets/pictures/S.jpg"],
          "correct_answer": "assets/pictures/M.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_easy_4", "type": "text_to_sign",
          "image_url": "assets/pictures/letter_K.jpg",
          "question_text": "Aling sign ang kumakatawan sa letra 'K'?",
          "options": ["assets/pictures/V.jpg", "assets/pictures/K.jpg", "assets/pictures/P.jpg", "assets/pictures/R.jpg"],
          "correct_answer": "assets/pictures/K.jpg"
        },

        // ==========================================
        // ALPHABET MEDIUM (5 LEVELS x MAX 5 QUESTIONS)
        // ==========================================
        // --- ALPHABET MEDIUM 1 (5 QUESTIONS) ---
        {
          "category": "alphabet", "level": "alphabet_medium_1", "type": "true_false",
          "image_url": "assets/pictures/tf_H.jpg",
          "question_text": "Ang hand sign na ito ay kumakatawan sa letra 'H'.",
          "options": ["assets/pictures/thumbs up.jpg", "assets/pictures/thumbs down.jpg"],
          "correct_answer": "assets/pictures/thumbs up.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_1", "type": "true_false",
          "image_url": "assets/pictures/tf_D.jpg",
          "question_text": "Ang hand sign na ito ay kumakatawan sa letra 'D'.",
          "options": ["assets/pictures/thumbs up.jpg", "assets/pictures/thumbs down.jpg"],
          "correct_answer": "assets/pictures/thumbs up.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_1", "type": "true_false",
          "image_url": "assets/pictures/tf_Z.jpg",
          "question_text": "Ang hand sign na ito ay kumakatawan sa letra 'Z'.",
          "options": ["assets/pictures/thumbs up.jpg", "assets/pictures/thumbs down.jpg"],
          "correct_answer": "assets/pictures/thumbs up.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_1", "type": "true_false",
          "image_url": "assets/pictures/tf_G.jpg",
          "question_text": "Ang hand sign na ito ay kumakatawan sa letra 'G'.",
          "options": ["assets/pictures/thumbs up.jpg", "assets/pictures/thumbs down.jpg"],
          "correct_answer": "assets/pictures/thumbs down.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_1", "type": "true_false",
          "image_url": "assets/pictures/tf_B.jpg",
          "question_text": "Ang hand sign na ito ay kumakatawan sa letra 'B'.",
          "options": ["assets/pictures/thumbs up.jpg", "assets/pictures/thumbs down.jpg"],
          "correct_answer": "assets/pictures/thumbs down.jpg"
        },

        // --- ALPHABET MEDIUM 2 (5 QUESTIONS) ---
        {
          "category": "alphabet", "level": "alphabet_medium_2", "type": "true_false",
          "image_url": "assets/pictures/tf_A.jpg",
          "question_text": "Ang hand sign na ito ay kumakatawan sa letra 'A'.",
          "options": ["assets/pictures/thumbs up.jpg", "assets/pictures/thumbs down.jpg"],
          "correct_answer": "assets/pictures/thumbs up.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_2", "type": "true_false",
          "image_url": "assets/pictures/tf_J.jpg",
          "question_text": "Ang hand sign na ito ay kumakatawan sa letra 'J'.",
          "options": ["assets/pictures/thumbs up.jpg", "assets/pictures/thumbs down.jpg"],
          "correct_answer": "assets/pictures/thumbs down.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_2", "type": "true_false",
          "image_url": "assets/pictures/tf_C.jpg",
          "question_text": "Ang hand sign na ito ay kumakatawan sa letra 'C'.",
          "options": ["assets/pictures/thumbs up.jpg", "assets/pictures/thumbs down.jpg"],
          "correct_answer": "assets/pictures/thumbs up.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_2", "type": "true_false",
          "image_url": "assets/pictures/tf_F.jpg",
          "question_text": "Ang hand sign na ito ay kumakatawan sa letra 'F'.",
          "options": ["assets/pictures/thumbs up.jpg", "assets/pictures/thumbs down.jpg"],
          "correct_answer": "assets/pictures/thumbs up.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_2", "type": "true_false",
          "image_url": "assets/pictures/tf_I.jpg",
          "question_text": "Ang hand sign na ito ay kumakatawan sa letra 'I'.",
          "options": ["assets/pictures/thumbs up.jpg", "assets/pictures/thumbs down.jpg"],
          "correct_answer": "assets/pictures/thumbs up.jpg"
        },

        // --- ALPHABET MEDIUM 3 (5 QUESTIONS) ---
        {
          "category": "alphabet", "level": "alphabet_medium_3", "type": "fill_in",
          "image_url": "assets/pictures/ate.jpg",
          "question_text": "Aling FSL hand sign ang kulang para mabuo ang salita?",
          "options": ["assets/pictures/E.jpg", "assets/pictures/L.jpg", "assets/pictures/N.jpg", "assets/pictures/O.jpg"],
          "correct_answer": "assets/pictures/E.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_3", "type": "fill_in",
          "image_url": "assets/pictures/kuya.jpg",
          "question_text": "Aling FSL hand sign ang kulang para mabuo ang salita?",
          "options": ["assets/pictures/U.jpg", "assets/pictures/Y.jpg", "assets/pictures/E.jpg", "assets/pictures/L.jpg"],
          "correct_answer": "assets/pictures/U.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_3", "type": "fill_in",
          "image_url": "assets/pictures/lola.jpg",
          "question_text": "Aling FSL hand sign ang kulang para mabuo ang salita?",
          "options": ["assets/pictures/N.jpg", "assets/pictures/E.jpg", "assets/pictures/O.jpg", "assets/pictures/L.jpg"],
          "correct_answer": "assets/pictures/O.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_3", "type": "fill_in",
          "image_url": "assets/pictures/lolo.jpg",
          "question_text": "Aling FSL hand sign ang kulang para mabuo ang salita?",
          "options": ["assets/pictures/L.jpg", "assets/pictures/N.jpg", "assets/pictures/U.jpg", "assets/pictures/O.jpg"],
          "correct_answer": "assets/pictures/L.jpg"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_3", "type": "fill_in",
          "image_url": "assets/pictures/nanay.jpg",
          "question_text": "Aling FSL hand sign ang kulang para mabuo ang salita?",
          "options": ["assets/pictures/Y.jpg", "assets/pictures/N.jpg", "assets/pictures/E.jpg", "assets/pictures/O.jpg"],
          "correct_answer": "assets/pictures/N.jpg"
        },

        {
          "category": "alphabet", "level": "alphabet_medium_3", "type": "fill_in",
          "image_url": "assets/pictures/tatay.jpg",
          "question_text": "Aling FSL hand sign ang kulang para mabuo ang salita?",
          "options": ["assets/pictures/Y.jpg", "assets/pictures/U.jpg", "assets/pictures/L.jpg", "assets/pictures/N.jpg"],
          "correct_answer": "assets/pictures/Y.jpg"
        },

        // --- ALPHABET MEDIUM 4 (5 QUESTIONS) ---
        {
          "category": "alphabet", "level": "alphabet_medium_4", "type": "spell",
          "image_url": "assets/pictures/spell(1).jpg",
          "question_text": "Isulat ang salitang binubuo para sa bawat bilang.",
          "options": ["MABUHAY", "MABUTI", "MASAYA", "MAHAL"],
          "correct_answer": "MABUHAY"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_4", "type": "spell",
          "image_url": "assets/pictures/spell(2).jpg",
          "question_text": "Isulat ang salitang binubuo para sa bawat bilang.",
          "options": ["LUBOS", "LAKAS", "KAHON", "KOTSE"],
          "correct_answer": "KOTSE"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_4", "type": "spell",
          "image_url": "assets/pictures/spell(3).jpg",
          "question_text": "Isulat ang salitang binubuo para sa bawat bilang.",
          "options": ["RETO", "RELO", "RITO", "ROSA"],
          "correct_answer": "RELO"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_4", "type": "spell",
          "image_url": "assets/pictures/spell(4).jpg",
          "question_text": "Isulat ang salitang binubuo para sa bawat bilang.",
          "options": ["PUSO", "PUNO", "PUSA", "PULA"],
          "correct_answer": "PUSA"
        },
        {
          "category": "alphabet", "level": "alphabet_medium_4", "type": "spell",
          "image_url": "assets/pictures/spell(5).jpg",
          "question_text": "Isulat ang salitang binubuo para sa bawat bilang.",
          "options": ["SALAMAT", "SALITA", "SARANG", "SABIHIN"],
          "correct_answer": "SALAMAT"
        },

        // ==========================================
        // ALPHABET HARD (2 LEVELS)
        // ==========================================
        // --- ALPHABET HARD 1 (4 QUESTIONS) ---
        {
          "category": "alphabet", "level": "alphabet_hard_1", "type": "typing",
          "question_text": "I-type ang mga kulang na letra upang mabuo ang salita:",
          "correct_answer": "PENCIL",
          "main_image": "assets/pictures/type1.png",
          "given_fsl": [
            { "position": 1, "letter": "E", "image_url": "assets/pictures/E.jpg" },
            { "position": 4, "letter": "I", "image_url": "assets/pictures/I.jpg" }
          ],
          "options": ["P", "E", "N", "C", "I", "L", "A", "R"]
        },
        {
          "category": "alphabet", "level": "alphabet_hard_1", "type": "typing",
          "question_text": "I-type ang mga kulang na letra upang mabuo ang salita:",
          "correct_answer": "PAPER",
          "main_image": "assets/pictures/type2.png",
          "given_fsl": [
            { "position": 1, "letter": "A", "image_url": "assets/pictures/A.jpg" },
            { "position": 3, "letter": "E", "image_url": "assets/pictures/E.jpg" }
          ],
          "options": ["P", "A", "P", "E", "R", "S", "T", "O"]
        },
        {
          "category": "alphabet", "level": "alphabet_hard_1", "type": "typing",
          "question_text": "I-type ang mga kulang na letra upang mabuo ang salita:",
          "correct_answer": "BICYCLE",
          "main_image": "assets/pictures/type3.png",
          "given_fsl": [
            { "position": 1, "letter": "I", "image_url": "assets/pictures/I.jpg" },
            { "position": 2, "letter": "C", "image_url": "assets/pictures/C.jpg" },
            { "position": 5, "letter": "L", "image_url": "assets/pictures/L.jpg" }
          ],
          "options": ["B", "I", "C", "Y", "C", "L", "E", "K", "U"]
        },
        {
          "category": "alphabet", "level": "alphabet_hard_1", "type": "typing",
          "question_text": "I-type ang mga kulang na letra upang mabuo ang salita:",
          "correct_answer": "WINDOW",
          "main_image": "assets/pictures/type4.png",
          "given_fsl": [
            { "position": 1, "letter": "I", "image_url": "assets/pictures/I.jpg" },
            { "position": 3, "letter": "D", "image_url": "assets/pictures/D.jpg" }
          ],
          "options": ["W", "I", "N", "D", "O", "W", "S", "E"]
        },

        // --- ALPHABET HARD 2 (5 QUESTIONS) ---
        {
          "category": "alphabet", "level": "alphabet_hard_2", "type": "camera_spell",
          "question_text": "Ipakita ang senyas sa FSL para sa titik na ito.",
          "image_url": "assets/pictures/letter_S.jpg",
          "correct_answer": "S"
        },
        {
          "category": "alphabet", "level": "alphabet_hard_2", "type": "camera_spell",
          "question_text": "Ipakita ang senyas sa FSL para sa titik na ito.",
          "image_url": "assets/pictures/letter_X.jpg",
          "correct_answer": "X"
        },
        {
          "category": "alphabet", "level": "alphabet_hard_2", "type": "camera_spell",
          "question_text": "Ipakita ang senyas sa FSL para sa titik na ito.",
          "image_url": "assets/pictures/letter_L.jpg",
          "correct_answer": "L"
        },
        {
          "category": "alphabet", "level": "alphabet_hard_2", "type": "camera_spell",
          "question_text": "Ipakita ang senyas sa FSL para sa titik na ito.",
          "image_url": "assets/pictures/letter_M.jpg",
          "correct_answer": "M"
        },
        {
          "category": "alphabet", "level": "alphabet_hard_2", "type": "camera_spell",
          "question_text": "Ipakita ang senyas sa FSL para sa titik na ito.",
          "image_url": "assets/pictures/letter_R.jpg",
          "correct_answer": "R"
        },

        // ==========================================
        // NUMBERS EASY (3 LEVELS x MAX 5 QUESTIONS)
        // ==========================================
        // --- NUMBERS EASY 1 (5 QUESTIONS) ---
        {
          "category": "numbers", "level": "numbers_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/5.png",
          "question_text": "Anong numero ang kumakatawan sa sign na ito?",
          "options": ["5", "3", "7", "6"],
          "correct_answer": "5"
        },
        {
          "category": "numbers", "level": "numbers_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/2.png",
          "question_text": "Anong numero ang kumakatawan sa sign na ito?",
          "options": ["4", "2", "6", "1"],
          "correct_answer": "2"
        },
        {
          "category": "numbers", "level": "numbers_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/1.png",
          "question_text": "Anong numero ang kumakatawan sa sign na ito?",
          "options": ["1", "5", "8", "3"],
          "correct_answer": "1"
        },
        {
          "category": "numbers", "level": "numbers_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/3.png",
          "question_text": "Anong numero ang kumakatawan sa sign na ito?",
          "options": ["7", "3", "5", "8"],
          "correct_answer": "3"
        },
        {
          "category": "numbers", "level": "numbers_easy_1", "type": "sign_to_text",
          "image_url": "assets/pictures/4.png",
          "question_text": "Anong numero ang kumakatawan sa sign na ito?",
          "options": ["10", "2", "4", "9"],
          "correct_answer": "4"
        },

        // --- NUMBERS EASY 2 (5 QUESTIONS) ---
        {
          "category": "numbers", "level": "numbers_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/2.9.png",
          "question_text": "Aling sign ang kumakatawan sa numero '9'?",
          "options": ["assets/pictures/6.png", "assets/pictures/1.png", "assets/pictures/4.png", "assets/pictures/9.png"],
          "correct_answer": "assets/pictures/9.png"
        },
        {
          "category": "numbers", "level": "numbers_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/2.6.png",
          "question_text": "Aling sign ang kumakatawan sa numero '6'?",
          "options": ["assets/pictures/9.png", "assets/pictures/6.png", "assets/pictures/7.png", "assets/pictures/8.png"],
          "correct_answer": "assets/pictures/6.png"
        },
        {
          "category": "numbers", "level": "numbers_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/2.5.png",
          "question_text": "Aling sign ang kumakatawan sa numero '5'?",
          "options": ["assets/pictures/5.png", "assets/pictures/9.png", "assets/pictures/8.png", "assets/pictures/7.png"],
          "correct_answer": "assets/pictures/5.png"
        },
        {
          "category": "numbers", "level": "numbers_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/2.10.png",
          "question_text": "Aling sign ang kumakatawan sa numero '10'?",
          "options": ["assets/pictures/10.png", "assets/pictures/1.png", "assets/pictures/5.png", "assets/pictures/6.png"],
          "correct_answer": "assets/pictures/10.png"
        },
        {
          "category": "numbers", "level": "numbers_easy_2", "type": "text_to_sign",
          "image_url": "assets/pictures/2.7.png",
          "question_text": "Aling sign ang kumakatawan sa numero '7'?",
          "options": ["assets/pictures/7.png", "assets/pictures/2.png", "assets/pictures/3.png", "assets/pictures/4.png"],
          "correct_answer": "assets/pictures/7.png"
        },

        // --- NUMBERS EASY 3 (5 QUESTIONS) ---
        {
          "category": "numbers", "level": "numbers_easy_3", "type": "text_to_sign",
          "image_url": "assets/pictures/1.2.png",
          "question_text": "Bilangin ang mga item sa larawan.",
          "options": ["assets/pictures/1.png", "assets/pictures/2.png", "assets/pictures/3.png", "assets/pictures/4.png"],
          "correct_answer": "assets/pictures/2.png"
        },
        {
          "category": "numbers", "level": "numbers_easy_3", "type": "text_to_sign",
          "image_url": "assets/pictures/1.4.png",
          "question_text": "Bilangin ang mga item sa larawan.",
          "options": ["assets/pictures/2.png", "assets/pictures/4.png", "assets/pictures/6.png", "assets/pictures/8.png"],
          "correct_answer": "assets/pictures/4.png"
        },
        {
          "category": "numbers", "level": "numbers_easy_3", "type": "text_to_sign",
          "image_url": "assets/pictures/1.5.png",
          "question_text": "Bilangin ang mga item sa larawan.",
          "options": ["assets/pictures/3.png", "assets/pictures/5.png", "assets/pictures/7.png", "assets/pictures/9.png"],
          "correct_answer": "assets/pictures/5.png"
        },
        {
          "category": "numbers", "level": "numbers_easy_3", "type": "text_to_sign",
          "image_url": "assets/pictures/1.6.png",
          "question_text": "Bilangin ang mga item sa larawan.",
          "options": ["assets/pictures/5.png", "assets/pictures/6.png", "assets/pictures/7.png", "assets/pictures/8.png"],
          "correct_answer": "assets/pictures/6.png"
        },
        {
          "category": "numbers", "level": "numbers_easy_3", "type": "text_to_sign",
          "image_url": "assets/pictures/1.8.png",
          "question_text": "Bilangin ang mga item sa larawan.",
          "options": ["assets/pictures/6.png", "assets/pictures/7.png", "assets/pictures/8.png", "assets/pictures/9.png"],
          "correct_answer": "assets/pictures/8.png"
        },

        // ==========================================
        // NUMBERS MEDIUM (4 LEVELS x MAX 5 QUESTIONS)
        // ==========================================
        // --- NUMBERS MEDIUM 1 (5 QUESTIONS) ---
        {
          "category": "numbers", "level": "numbers_medium_1", "type": "addition",
          "image_url": "assets/pictures/add1.jpg",
          "question_text": "Kwentahin ang kabuuan ng mga numero sa larawan.",
          "options": ["assets/pictures/1.png", "assets/pictures/2.png", "assets/pictures/3.png", "assets/pictures/4.png"],
          "correct_answer": "assets/pictures/4.png"
        },
        {
          "category": "numbers", "level": "numbers_medium_1", "type": "addition",
          "image_url": "assets/pictures/add2.jpg",
          "question_text": "Kwentahin ang kabuuan ng mga numero sa larawan.",
          "options": ["assets/pictures/5.png", "assets/pictures/6.png", "assets/pictures/7.png", "assets/pictures/8.png"],
          "correct_answer": "assets/pictures/7.png"
        },
        {
          "category": "numbers", "level": "numbers_medium_1", "type": "addition",
          "image_url": "assets/pictures/add3.jpg",
          "question_text": "Kwentahin ang kabuuan ng mga numero sa larawan.",
          "options": ["assets/pictures/2.png", "assets/pictures/4.png", "assets/pictures/3.png", "assets/pictures/5.png"],
          "correct_answer": "assets/pictures/4.png"
        },
        {
          "category": "numbers", "level": "numbers_medium_1", "type": "addition",
          "image_url": "assets/pictures/add4.jpg",
          "question_text": "Kwentahin ang kabuuan ng mga numero sa larawan.",
          "options": ["assets/pictures/6.png", "assets/pictures/5.png", "assets/pictures/4.png", "assets/pictures/7.png"],
          "correct_answer": "assets/pictures/6.png"
        },
        {
          "category": "numbers", "level": "numbers_medium_1", "type": "addition",
          "image_url": "assets/pictures/add5.jpg",
          "question_text": "Kwentahin ang kabuuan ng mga numero sa larawan.",
          "options": ["assets/pictures/6.png", "assets/pictures/7.png", "assets/pictures/9.png", "assets/pictures/8.png"],
          "correct_answer": "assets/pictures/8.png"
        },

        // --- NUMBERS MEDIUM 2 (5 QUESTIONS) ---
        {
          "category": "numbers", "level": "numbers_medium_2", "type": "subtraction",
          "image_url": "assets/pictures/sub5.jpg",
          "question_text": "Kwentahin ang natitirang bilang ng mga item sa larawan.",
          "options": ["assets/pictures/4.png", "assets/pictures/5.png", "assets/pictures/6.png", "assets/pictures/7.png"],
          "correct_answer": "assets/pictures/5.png"
        },
        {
          "category": "numbers", "level": "numbers_medium_2", "type": "subtraction",
          "image_url": "assets/pictures/sub1.jpg",
          "question_text": "Kwentahin ang natitirang bilang ng mga item sa larawan.",
          "options": ["assets/pictures/1.png", "assets/pictures/2.png", "assets/pictures/3.png", "assets/pictures/4.png"],
          "correct_answer": "assets/pictures/1.png"
        },
        {
          "category": "numbers", "level": "numbers_medium_2", "type": "subtraction",
          "image_url": "assets/pictures/sub2.jpg",
          "question_text": "Kwentahin ang natitirang bilang ng mga item sa larawan.",
          "options": ["assets/pictures/1.png", "assets/pictures/2.png", "assets/pictures/4.png", "assets/pictures/3.png"],
          "correct_answer": "assets/pictures/3.png"
        },
        {
          "category": "numbers", "level": "numbers_medium_2", "type": "subtraction",
          "image_url": "assets/pictures/sub3.jpg",
          "question_text": "Kwentahin ang natitirang bilang ng mga item sa larawan.",
          "options": ["assets/pictures/4.png", "assets/pictures/3.png", "assets/pictures/2.png", "assets/pictures/5.png"],
          "correct_answer": "assets/pictures/4.png"
        },
        {
          "category": "numbers", "level": "numbers_medium_2", "type": "subtraction",
          "image_url": "assets/pictures/sub4.jpg",
          "question_text": "Kwentahin ang natitirang bilang ng mga item sa larawan.",
          "options": ["assets/pictures/1.png", "assets/pictures/3.png", "assets/pictures/4.png", "assets/pictures/2.png"],
          "correct_answer": "assets/pictures/2.png"
        },

        // --- NUMBERS MEDIUM 3 (5 QUESTIONS) ---
        {
          "category": "numbers", "level": "numbers_medium_3", "type": "mixed",
          "question_text": "Kwentahin ang kabuuang snail",
          "correct_answer": "assets/pictures/6.png",
          "image_url": "assets/pictures/3.5.png",
          "options": ["assets/pictures/6.png", "assets/pictures/5.png", "assets/pictures/7.png", "assets/pictures/4.png"]
        },
        {
          "category": "numbers", "level": "numbers_medium_3", "type": "mixed",
          "question_text": "Kwentahin ang natirang bag",
          "correct_answer": "assets/pictures/2.png",
          "image_url": "assets/pictures/4.3.png",
          "options": ["assets/pictures/2.png", "assets/pictures/3.png", "assets/pictures/1.png", "assets/pictures/4.png"]
        },
        {
          "category": "numbers", "level": "numbers_medium_3", "type": "mixed",
          "question_text": "Kwentahin ang kabuuang Christmas tree",
          "correct_answer": "assets/pictures/8.png",
          "image_url": "assets/pictures/3.1.png",
          "options": ["assets/pictures/8.png", "assets/pictures/7.png", "assets/pictures/9.png", "assets/pictures/6.png"]
        },
        {
          "category": "numbers", "level": "numbers_medium_3", "type": "mixed",
          "question_text": "Kwentahin ang natirang gorilla",
          "correct_answer": "assets/pictures/1.png",
          "image_url": "assets/pictures/4.4.png",
          "options": ["assets/pictures/1.png", "assets/pictures/2.png", "assets/pictures/3.png", "assets/pictures/5.png"]
        },
        {
          "category": "numbers", "level": "numbers_medium_3", "type": "mixed",
          "question_text": "Kwentahin ang kabuuang seashell",
          "correct_answer": "assets/pictures/7.png",
          "image_url": "assets/pictures/3.3.png",
          "options": ["assets/pictures/7.png", "assets/pictures/6.png", "assets/pictures/8.png", "assets/pictures/5.png"]
        },

        // --- NUMBERS MEDIUM 4 (CONSOLIDATED EXCESS ITEMS - 2 QUESTIONS) ---
        {
          "category": "numbers", "level": "numbers_medium_4", "type": "addition",
          "image_url": "assets/pictures/add6.jpg",
          "question_text": "Kwentahin ang kabuuan ng mga numero sa larawan.",
          "options": ["assets/pictures/6.png", "assets/pictures/8.png", "assets/pictures/7.png", "assets/pictures/9.png"],
          "correct_answer": "assets/pictures/8.png"
        },
        {
          "category": "numbers", "level": "numbers_medium_4", "type": "mixed",
          "question_text": "Kwentahin ang natirang ice cream",
          "correct_answer": "assets/pictures/9.png",
          "image_url": "assets/pictures/4.2.png",
          "options": ["assets/pictures/9.png", "assets/pictures/8.png", "assets/pictures/10.png", "assets/pictures/7.png"]
        }
      ]; 

      // Wipe old/scattered documents
      final QuerySnapshot existingDocs = await ref.get();
      final WriteBatch deleteBatch = FirebaseFirestore.instance.batch();
      for (var doc in existingDocs.docs) {
        deleteBatch.delete(doc.reference);
      }
      await deleteBatch.commit();

      // Upload consolidated documents with unique deterministic IDs
      final WriteBatch writeBatch = FirebaseFirestore.instance.batch();
      for (var question in questionsToUpload) {
        final String docId = _generateQuestionId(question);
        writeBatch.set(ref.doc(docId), question);
      }
      await writeBatch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Database Seeded Safely! All levels fixed to max 5 questions."),
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