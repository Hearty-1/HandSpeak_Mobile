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
// 2. API SERVICE (Mocked for Numbers)
// ==========================================
class NumbersQuizApiService {
  Future<List<QuizQuestion>> fetchNumberQuestions() async {
    await Future.delayed(const Duration(milliseconds: 800));

    final mockJsonResponse = [
      {
        "id": "1",
        "image_url": "assets/pictures/number_1.png", 
        "question_text": "What number is this?",
        "options": ["1", "5", "8", "3"],
        "correct_answer": "1"
      },
      {
        "id": "2",
        "image_url": "assets/pictures/number_2.png",
        "question_text": "What number is this?",
        "options": ["2", "4", "6", "9"],
        "correct_answer": "2"
      },
      {
        "id": "3",
        "image_url": "assets/pictures/number_3.png",
        "question_text": "What number is this?",
        "options": ["7", "3", "4", "0"],
        "correct_answer": "3"
      }
    ];

    return mockJsonResponse.map((json) => QuizQuestion.fromJson(json)).toList();
  }
}

// ==========================================
// 3. MAIN UI SCREEN
// ==========================================
class NumbersQuizScreen extends StatefulWidget {
  const NumbersQuizScreen({super.key});

  @override
  State<NumbersQuizScreen> createState() => _NumbersQuizScreenState();
}

class _NumbersQuizScreenState extends State<NumbersQuizScreen> {
  final NumbersQuizApiService _apiService = NumbersQuizApiService();
  
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
      final questions = await _apiService.fetchNumberQuestions();
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
    if (_isAnswered) return;

    setState(() {
      _selectedAnswer = option;
      _isAnswered = true;
      
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
        content: Text("You scored $_score out of ${_questions.length}!", style: const TextStyle(fontSize: 18)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xCCF39C12), // Using Numbers theme Blue
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context); 
              Navigator.pop(context, _score * 100); // Return XP back to the interface
            },
            child: const Text("Finish", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  // --- STYLING HELPERS ---
  Color _getButtonColor(String option, String correctAnswer) {
    if (!_isAnswered) return Colors.white;
    if (option == correctAnswer) return Colors.green; 
    if (option == _selectedAnswer && option != correctAnswer) return Colors.red; 
    return Colors.white; 
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
        backgroundColor: const Color(0xCCF39C12), 
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Easy Level", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF6AABFF)));
    if (_errorMessage != null) return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    if (_questions.isEmpty) return const Center(child: Text("No questions available."));

    final currentQuestion = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    height: 240,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(currentQuestion.imageUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 50)),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(currentQuestion.questionText, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 32),
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
                            border: Border.all(color: _getButtonBorderColor(option, currentQuestion.correctAnswer), width: 2),
                          ),
                          alignment: Alignment.center,
                          child: Text(option, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _isAnswered && (option == currentQuestion.correctAnswer || option == _selectedAnswer) ? Colors.white : Colors.black)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: Colors.white),
            child: Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(value: progress, backgroundColor: Colors.grey[200], valueColor: const AlwaysStoppedAnimation<Color>(Colors.green)),
                ),
                const SizedBox(width: 24),
                ElevatedButton(
                  onPressed: _isAnswered ? _handleNext : null,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xCCF39C12)),
                  child: Text(_currentIndex == _questions.length - 1 ? "FINISH" : "NEXT", style: const TextStyle(color: Colors.white)),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}