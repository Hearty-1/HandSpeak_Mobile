import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ==========================================
// 1. DATA MODEL
// ==========================================
class QuizQuestion {
  final String id;
  final String type; // Supports sign_to_text vs text_to_sign
  final String imageUrl;
  final String questionText;
  final List<String> options;
  final String correctAnswer;

  QuizQuestion({
    required this.id,
    required this.type,
    required this.imageUrl,
    required this.questionText,
    required this.options,
    required this.correctAnswer,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      id: json['id']?.toString() ?? '',
      type: json['type'] ?? 'sign_to_text',
      imageUrl: json['image_url'] ?? '',
      questionText: json['question_text'] ?? '',
      options: List<String>.from(json['options'] ?? []),
      correctAnswer: json['correct_answer'] ?? '',
    );
  }
}

// ==========================================
// 2. SMART DIAGNOSTIC FIRESTORE API
// ==========================================
class QuizApiService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<List<QuizQuestion>> fetchEasyQuestions(String levelId, String typeFilter) async {
    // STEP 1: Fetch ALL alphabet questions to bypass any Firestore Index errors
    final querySnapshot = await _db
        .collection('activity_questions')
        .where('category', isEqualTo: 'alphabet')
        .get();

    // ERROR CHECK 1: Is the database empty?
    if (querySnapshot.docs.isEmpty) {
      throw Exception("DATABASE IS EMPTY!\n\nPlease press the red 'DEV: SEED DATABASE' button first.");
    }

    // STEP 2: Filter by Level LOCALLY in Dart 
    // Checks for exact levelId match (or fallback to "easy" just in case your database isn't updated)
    List<QuizQuestion> levelQuestions = [];
    for (var doc in querySnapshot.docs) {
      final data = doc.data();
      if (data['level'] == levelId || (levelId == 'alphabet_easy_1' && data['level'] == 'easy')) { 
        data['id'] = doc.id;
        levelQuestions.add(QuizQuestion.fromJson(data));
      }
    }

    // ERROR CHECK 2: Did the Level ID match anything?
    if (levelQuestions.isEmpty) {
      throw Exception("LEVEL NOT FOUND!\n\nThe database has alphabet questions, but ZERO questions match levelId: '$levelId'.");
    }

    // STEP 3: Filter by Question Type & SHUFFLE
    List<QuizQuestion> finalQuestions = [];
    
    if (typeFilter == 'mixed') {
      var signs = levelQuestions.where((q) => q.type == 'sign_to_text').toList()..shuffle();
      var texts = levelQuestions.where((q) => q.type == 'text_to_sign').toList()..shuffle();
      
      int maxLength = signs.length > texts.length ? signs.length : texts.length;
      for (int i = 0; i < maxLength; i++) {
        if (i < signs.length) finalQuestions.add(signs[i]);
        if (i < texts.length) finalQuestions.add(texts[i]);
      }
    } else {
      finalQuestions = levelQuestions.where((q) => q.type == typeFilter).toList()..shuffle();
    }

    // ERROR CHECK 3: Did the Type Filter hide all questions?
    if (finalQuestions.isEmpty) {
      throw Exception("TYPE MISMATCH!\n\nQuestions were found for '$levelId', but none matched the requested questionType: '$typeFilter'.");
    }

    return finalQuestions.take(5).toList();
  }
}

// ==========================================
// 3. MAIN UI SCREEN
// ==========================================
class EasyActMc extends StatefulWidget {
  final String levelId; // ADDED: Now perfectly accepts levelId from activity_interface.dart
  final String questionType;

  const EasyActMc({
    super.key, 
    required this.levelId, // ADDED REQUIRED PARAMETER
    required this.questionType,
  });

  @override
  State<EasyActMc> createState() => _EasyActMcState();
}

class _EasyActMcState extends State<EasyActMc> {
  final QuizApiService _apiService = QuizApiService();
  
  List<QuizQuestion> _questions = [];
  bool _isLoading = true;
  String? _errorMessage;

  int _currentIndex = 0;
  String? _selectedAnswer;
  bool _isAnswered = false;
  bool _isSaving = false;

  int _hearts = 5;
  bool _isCorrect = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      // ADDED: Passing widget.levelId to the API
      final questions = await _apiService.fetchEasyQuestions(widget.levelId, widget.questionType);
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll("Exception: ", "");
        _isLoading = false;
      });
    }
  }

  void _handleOptionSelected(String option) {
    if (_isAnswered) return;
    
    setState(() {
      _selectedAnswer = option;
      _isAnswered = true;
      _isCorrect = option == _questions[_currentIndex].correctAnswer;
      
      if (!_isCorrect) {
        _hearts--; 
        if (_hearts <= 0) {
          _showGameOverDialog();
        }
      }
    });
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Out of Hearts! 💔", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        content: const Text("You made a few mistakes. Take a break and review the tutorials, then try again!"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); 
              Navigator.pop(context); 
            },
            child: const Text("Exit Activity", style: TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Future<void> _handleNext() async {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = null;
        _isAnswered = false;
      });
    } else {
      setState(() => _isSaving = true);
      
      int starsEarned = 1;
      if (_hearts == 5) {
        starsEarned = 3;
      } else if (_hearts >= 3) {
        starsEarned = 2;
      }
      
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
          
          await FirebaseFirestore.instance.runTransaction((transaction) async {
            final snapshotDoc = await transaction.get(userRef);
            if (snapshotDoc.exists) {
              final data = snapshotDoc.data() as Map<String, dynamic>;
              
              final Map<String, dynamic> progress = data['progress'] != null 
                  ? Map<String, dynamic>.from(data['progress']) 
                  : {};
                  
              // ADDED: Dynamically saves progress to the exact Level ID passed in
              final int previousStars = progress[widget.levelId] ?? 0;
              
              int globalStarsToAdd = 0;
              if (starsEarned > previousStars) {
                globalStarsToAdd = starsEarned - previousStars;
                progress[widget.levelId] = starsEarned; 
              }

              final int currentGlobalStars = data['stars'] ?? 0;

              transaction.update(userRef, {
                'stars': currentGlobalStars + globalStarsToAdd,
                'progress': progress, 
              });
            }
          });
        }
      } catch (e) {
        debugPrint("Error updating Stars: $e");
      }

      setState(() => _isSaving = false);

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Activity Complete! 🎉", style: TextStyle(color: Color(0xFF322144), fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "You finished ${widget.levelId.replaceAll('_', ' ').toUpperCase()}!",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  return Icon(
                    index < starsEarned ? Icons.star_rounded : Icons.star_border_rounded,
                    color: const Color(0xFFFFB800),
                    size: 42,
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text(
                "Earned $starsEarned / 3 Stars", 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF222222))
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); 
                Navigator.of(context).pop(); 
              },
              child: const Text("Awesome!", style: TextStyle(color: Color(0xFFFFB800), fontWeight: FontWeight.bold, fontSize: 16)),
            )
          ],
        ),
      );
    }
  }

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
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Alphabet Activities",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Row(
              children: [
                const Icon(Icons.favorite, color: Colors.red, size: 24),
                const SizedBox(width: 4),
                Text(
                  "$_hearts",
                  style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          )
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB800)));
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              Text(
                _errorMessage!, 
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)
              ),
            ],
          ),
        )
      );
    }

    if (_questions.isEmpty) {
      return const Center(child: Text("No questions available."));
    }

    final currentQuestion = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;
    final isImageOption = currentQuestion.type == "text_to_sign";

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFFE0E0E0),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                      minHeight: 12,
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (currentQuestion.imageUrl.isNotEmpty) ...[
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
                  ],

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

                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: isImageOption ? 1.2 : 2.2, 
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
                          child: isImageOption
                              ? Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Image.asset(
                                    option,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) => Text(
                                      option,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: _getButtonTextColor(option, currentQuestion.correctAnswer),
                                      ),
                                    ),
                                  ),
                                )
                              : Text(
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

          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: BoxDecoration(
                color: !_isAnswered 
                    ? Colors.white 
                    : (_isCorrect ? const Color(0xFFD7FFB7) : const Color(0xFFFFDFE0)),
                border: Border(top: BorderSide(color: Colors.grey.shade200, width: 2)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isAnswered) ...[
                    Row(
                      children: [
                        Icon(
                          _isCorrect ? Icons.check_circle : Icons.cancel, 
                          color: _isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B), 
                          size: 28
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isCorrect 
                              ? "Awesome!" 
                              : (isImageOption 
                                  ? "Try again!" 
                                  : "Correct answer: ${_questions[_currentIndex].correctAnswer}"),
                          style: TextStyle(
                            color: _isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: (_isAnswered && !_isSaving) ? _handleNext : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: !_isAnswered 
                            ? const Color(0xFFFFB800) 
                            : (_isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B)),
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(
                              _isAnswered ? "CONTINUE" : "CHECK",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: _isAnswered ? Colors.white : Colors.black,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}