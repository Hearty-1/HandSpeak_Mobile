import 'package:flutter/material.dart';

// ==========================================
// 1. DATA MODEL (Backend Ready)
// ==========================================
class QuizQuestion {
  final String id;
  final String imageUrl;
  final String questionText;
  final List<String> options;
  final String correctAnswer;

  QuizQuestion({
    required this.id,
    required this.imageUrl,
    required this.questionText,
    required this.options,
    required this.correctAnswer,
  });

  // Factory constructor to easily parse JSON responses from your future API
  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      id: json['id']?.toString() ?? '',
      imageUrl: json['image_url'] ?? '',
      questionText: json['question_text'] ?? '',
      options: List<String>.from(json['options'] ?? []),
      correctAnswer: json['correct_answer'] ?? '',
    );
  }
}

// ==========================================
// 2. API SERVICE (Mocked for now)
// ==========================================
class QuizApiService {
  // Replace this mock logic with your actual http.get() or Dio network call
  Future<List<QuizQuestion>> fetchEasyQuestions() async {
    // Simulate a network loading delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Mock JSON response matching your database schema
    final mockJsonResponse = [
      {
        "id": "1",
        "image_url": "assets/pictures/A.png", // Ensure these map to your actual asset paths or network URLs
        "question_text": "What letter is this?",
        "options": ["A", "S", "E", "M"],
        "correct_answer": "A"
      },
      {
        "id": "2",
        "image_url": "public/pictures/B.png",
        "question_text": "What letter is this?",
        "options": ["B", "D", "P", "R"],
        "correct_answer": "B"
      },
      {
        "id": "3",
        "image_url": "public/pictures/C.png",
        "question_text": "What letter is this?",
        "options": ["O", "C", "G", "Q"],
        "correct_answer": "C"
      },
      {
        "id": "4",
        "image_url": "public/pictures/D.png",
        "question_text": "What letter is this?",
        "options": ["F", "B", "D", "Z"],
        "correct_answer": "D"
      },
      {
        "id": "5",
        "image_url": "public/pictures/E.png",
        "question_text": "What letter is this?",
        "options": ["S", "T", "M", "E"],
        "correct_answer": "E"
      }
    ];

    return mockJsonResponse.map((json) => QuizQuestion.fromJson(json)).toList();
  }
}

// ==========================================
// 3. MAIN UI SCREEN
// ==========================================
class EasyQuizScreen extends StatefulWidget {
  const EasyQuizScreen({super.key});

  @override
  State<EasyQuizScreen> createState() => _EasyQuizScreenState();
}

class _EasyQuizScreenState extends State<EasyQuizScreen> {
  final QuizApiService _apiService = QuizApiService();
  
  List<QuizQuestion> _questions = [];
  bool _isLoading = true;
  String? _errorMessage;

  int _currentIndex = 0;
  String? _selectedAnswer;
  bool _isAnswered = false;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      final questions = await _apiService.fetchEasyQuestions();
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to load questions: $e";
        _isLoading = false;
      });
    }
  }

  void _handleOptionSelected(String option) {
    if (_isAnswered) return; // Prevent changing the answer once tapped

    setState(() {
      _selectedAnswer = option;
      _isAnswered = true;
      
      // Tally score
      if (option == _questions[_currentIndex].correctAnswer) {
        _score++;
      }
    });
  }

  void _handleNext() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = null;
        _isAnswered = false;
      });
    } else {
      _showResults();
    }
  }

  void _showResults() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Activity Completed!", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          "You scored $_score out of ${_questions.length}!",
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to Activity Interface Menu
            },
            child: const Text("Finish", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  // --- STYLING HELPERS FOR MULTIPLE CHOICE BUTTONS ---
  Color _getButtonColor(String option, String correctAnswer) {
    if (!_isAnswered) return Colors.white;
    if (option == correctAnswer) return Colors.green; 
    if (option == _selectedAnswer && option != correctAnswer) return Colors.red; 
    return Colors.white; 
  }

  Color _getButtonTextColor(String option, String correctAnswer) {
    if (!_isAnswered) return Colors.black;
    if (option == correctAnswer || option == _selectedAnswer) return Colors.white;
    return Colors.black;
  }

  Color _getButtonBorderColor(String option, String correctAnswer) {
    if (!_isAnswered) return const Color(0xFFE0E0E0);
    if (option == correctAnswer) return Colors.green;
    if (option == _selectedAnswer && option != correctAnswer) return Colors.red;
    return const Color(0xFFE0E0E0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFB800),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Easy Level",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB800)));
    }

    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    }

    if (_questions.isEmpty) {
      return const Center(child: Text("No questions available."));
    }

    final currentQuestion = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // --- IMAGE DISPLAY CARD ---
                  Container(
                    width: double.infinity,
                    height: 240,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      // If your backend returns web URLs, change this to Image.network()
                      child: Image.asset(
                        currentQuestion.imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // --- QUESTION TEXT ---
                  Text(
                    currentQuestion.questionText,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // --- 2x2 OPTIONS GRID ---
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 2.2, 
                    children: currentQuestion.options.map((option) {
                      return GestureDetector(
                        onTap: () => _handleOptionSelected(option),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: _getButtonColor(option, currentQuestion.correctAnswer),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _getButtonBorderColor(option, currentQuestion.correctAnswer), 
                              width: 2
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            option,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: _getButtonTextColor(option, currentQuestion.correctAnswer),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          // --- BOTTOM PROGRESS BAR AND NEXT BUTTON ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                )
              ],
            ),
            child: Row(
              children: [
                // Progress Tracker
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Question ${_currentIndex + 1} of ${_questions.length}",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: const Color(0xFFE0E0E0),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Next Button
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isAnswered ? _handleNext : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB800),
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _currentIndex == _questions.length - 1 ? "FINISH" : "NEXT",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: _isAnswered ? Colors.black : Colors.grey.shade500,
                      ),
                    ),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}