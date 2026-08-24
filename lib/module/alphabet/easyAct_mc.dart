import 'dart:ui'; // Required for ImageFilter (Glassmorphism) //[cite: 13]
import 'package:flutter/material.dart'; //[cite: 13]
import 'package:cloud_firestore/cloud_firestore.dart'; //[cite: 13]
import 'package:firebase_auth/firebase_auth.dart'; //[cite: 13]
import 'package:provider/provider.dart';
import '/providers/sound_provider.dart'; // Adjust this path if needed

// ==========================================
// 1. DATA MODEL
// ==========================================
class QuizQuestion {
  final String id; //[cite: 13]
  final String type; //[cite: 13]
  final String imageUrl; //[cite: 13]
  final String questionText; //[cite: 13]
  final List<String> options; //[cite: 13]
  final String correctAnswer; //[cite: 13]

  QuizQuestion({ //[cite: 13]
    required this.id, //[cite: 13]
    required this.type, //[cite: 13]
    required this.imageUrl, //[cite: 13]
    required this.questionText, //[cite: 13]
    required this.options, //[cite: 13]
    required this.correctAnswer, //[cite: 13]
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) { //[cite: 13]
    return QuizQuestion( //[cite: 13]
      id: json['id']?.toString() ?? '', //[cite: 13]
      type: json['type'] ?? 'sign_to_text', //[cite: 13]
      imageUrl: json['image_url'] ?? '', //[cite: 13]
      questionText: json['question_text'] ?? '', //[cite: 13]
      options: List<String>.from(json['options'] ?? []), //[cite: 13]
      correctAnswer: json['correct_answer'] ?? '', //[cite: 13]
    );
  }
}

// ==========================================
// 2. SMART DIAGNOSTIC FIRESTORE API
// ==========================================
class QuizApiService {
  final FirebaseFirestore _db = FirebaseFirestore.instance; //[cite: 13]

  Future<List<QuizQuestion>> fetchEasyQuestions(String levelId, String typeFilter) async { //[cite: 13]
    final querySnapshot = await _db //[cite: 13]
        .collection('activity_questions') //[cite: 13]
        .where('category', isEqualTo: 'alphabet') //[cite: 13]
        .get(); //[cite: 13]

    if (querySnapshot.docs.isEmpty) { //[cite: 13]
      throw Exception("DATABASE IS EMPTY!\n\nPlease press the red 'DEV: SEED DATABASE' button first."); //[cite: 13]
    }

    List<QuizQuestion> levelQuestions = []; //[cite: 13]
    for (var doc in querySnapshot.docs) { //[cite: 13]
      final data = doc.data(); //[cite: 13]
      if (data['level'] == levelId || (levelId == 'alphabet_easy_1' && data['level'] == 'easy')) { //[cite: 13]
        data['id'] = doc.id; //[cite: 13]
        levelQuestions.add(QuizQuestion.fromJson(data)); //[cite: 13]
      }
    }

    if (levelQuestions.isEmpty) { //[cite: 13]
      throw Exception("LEVEL NOT FOUND!\n\nThe database has alphabet questions, but ZERO questions match levelId: '$levelId'."); //[cite: 13]
    }

    List<QuizQuestion> finalQuestions = []; //[cite: 13]
    
    if (typeFilter == 'mixed') { //[cite: 13]
      var signs = levelQuestions.where((q) => q.type == 'sign_to_text').toList()..shuffle(); //[cite: 13]
      var texts = levelQuestions.where((q) => q.type == 'text_to_sign').toList()..shuffle(); //[cite: 13]
      
      int maxLength = signs.length > texts.length ? signs.length : texts.length; //[cite: 13]
      for (int i = 0; i < maxLength; i++) { //[cite: 13]
        if (i < signs.length) finalQuestions.add(signs[i]); //[cite: 13]
        if (i < texts.length) finalQuestions.add(texts[i]); //[cite: 13]
      }
    } else {
      finalQuestions = levelQuestions.where((q) => q.type == typeFilter).toList()..shuffle(); //[cite: 13]
    }

    if (finalQuestions.isEmpty) { //[cite: 13]
      throw Exception("TYPE MISMATCH!\n\nQuestions were found for '$levelId', but none matched the requested questionType: '$typeFilter'."); //[cite: 13]
    }

    return finalQuestions; //[cite: 13]
  }
}

// ==========================================
// 3. MAIN UI SCREEN
// ==========================================
class EasyActMc extends StatefulWidget {
  final String levelId; //[cite: 13]
  final String questionType; //[cite: 13]

  const EasyActMc({ //[cite: 13]
    super.key, //[cite: 13]
    required this.levelId, //[cite: 13]
    required this.questionType, //[cite: 13]
  });

  @override
  State<EasyActMc> createState() => _EasyActMcState(); //[cite: 13]
}

class _EasyActMcState extends State<EasyActMc> {
  final QuizApiService _apiService = QuizApiService(); //[cite: 13]
  
  List<QuizQuestion> _questions = []; //[cite: 13]
  bool _isLoading = true; //[cite: 13]
  String? _errorMessage; //[cite: 13]

  int _currentIndex = 0; //[cite: 13]
  String? _selectedAnswer; //[cite: 13]
  bool _isAnswered = false; //[cite: 13]
  bool _isSaving = false; //[cite: 13]

  int _hearts = 5; //[cite: 13]
  bool _isCorrect = false; //[cite: 13]

  @override
  void initState() {
    super.initState(); //[cite: 13]
    _loadQuestions(); //[cite: 13]
  }

  Future<void> _loadQuestions() async {
    try {
      final questions = await _apiService.fetchEasyQuestions(widget.levelId, widget.questionType); //[cite: 13]
      setState(() {
        _questions = questions; //[cite: 13]
        _isLoading = false; //[cite: 13]
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll("Exception: ", ""); //[cite: 13]
        _isLoading = false; //[cite: 13]
      });
    }
  }

  void _handleOptionSelected(String option) {
    if (_isAnswered) return; //[cite: 13]
    
    setState(() {
      _selectedAnswer = option; //[cite: 13]
      _isAnswered = true; //[cite: 13]
      _isCorrect = option == _questions[_currentIndex].correctAnswer; //[cite: 13]
      
      // Trigger sound effects for correct/incorrect answers
      final soundProvider = Provider.of<SoundProvider>(context, listen: false);
      _isCorrect ? soundProvider.playCorrect() : soundProvider.playIncorrect();

      if (!_isCorrect) { //[cite: 13]
        _hearts--; //[cite: 13]
        if (_hearts <= 0) { //[cite: 13]
          _showGameOverDialog(); //[cite: 13]
        }
      }
    });
  }

  void _showGameOverDialog() {
    // Play Game Over Sound
    Provider.of<SoundProvider>(context, listen: false).playGameOver();

    showDialog( //[cite: 13]
      context: context, //[cite: 13]
      barrierDismissible: false, //[cite: 13]
      builder: (context) => AlertDialog( //[cite: 13]
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), //[cite: 13]
        title: const Text("Out of Hearts! 💔", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)), //[cite: 13]
        content: const Text("You made a few mistakes. Take a break and review the tutorials, then try again!"), //[cite: 13]
        actions: [ //[cite: 13]
          TextButton( //[cite: 13]
            onPressed: () { //[cite: 13]
              Navigator.pop(context); //[cite: 13]
              Navigator.pop(context); //[cite: 13]
            },
            child: const Text("Exit Activity", style: TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold)), //[cite: 13]
          )
        ],
      ),
    );
  }

  Future<void> _handleNext() async {
    if (_currentIndex < _questions.length - 1) { //[cite: 13]
      setState(() {
        _currentIndex++; //[cite: 13]
        _selectedAnswer = null; //[cite: 13]
        _isAnswered = false; //[cite: 13]
      });
    } else {
      setState(() => _isSaving = true); //[cite: 13]
      
      int starsEarned = 1; //[cite: 13]
      if (_hearts == 5) { //[cite: 13]
        starsEarned = 3; //[cite: 13]
      } else if (_hearts >= 3) { //[cite: 13]
        starsEarned = 2; //[cite: 13]
      }
      
      try {
        final user = FirebaseAuth.instance.currentUser; //[cite: 13]
        if (user != null) { //[cite: 13]
          final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid); //[cite: 13]
          
          await FirebaseFirestore.instance.runTransaction((transaction) async { //[cite: 13]
            final snapshotDoc = await transaction.get(userRef); //[cite: 13]
            if (snapshotDoc.exists) { //[cite: 13]
              final data = snapshotDoc.data() as Map<String, dynamic>; //[cite: 13]
              
              final Map<String, dynamic> progress = data['progress'] != null //[cite: 13]
                  ? Map<String, dynamic>.from(data['progress']) //[cite: 13]
                  : {}; //[cite: 13]
                  
              final int previousStars = progress[widget.levelId] ?? 0; //[cite: 13]
              
              int globalStarsToAdd = 0; //[cite: 13]
              if (starsEarned > previousStars) { //[cite: 13]
                globalStarsToAdd = starsEarned - previousStars; //[cite: 13]
                progress[widget.levelId] = starsEarned;  //[cite: 13]
              }

              final int currentGlobalStars = data['stars'] ?? 0; //[cite: 13]

              transaction.update(userRef, { //[cite: 13]
                'stars': currentGlobalStars + globalStarsToAdd, //[cite: 13]
                'progress': progress,  //[cite: 13]
              });
            }
          });
        }
      } catch (e) {
        debugPrint("Error updating Stars: $e"); //[cite: 13]
      }

      setState(() => _isSaving = false); //[cite: 13]

      if (!mounted) return; //[cite: 13]

      // Play Level Complete Sound
      Provider.of<SoundProvider>(context, listen: false).playLevelComplete();

      showDialog( //[cite: 13]
        context: context, //[cite: 13]
        barrierDismissible: false, //[cite: 13]
        builder: (context) => AlertDialog( //[cite: 13]
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), //[cite: 13]
          title: const Text("Activity Complete! 🎉", style: TextStyle(color: Color(0xFF322144), fontWeight: FontWeight.bold)), //[cite: 13]
          content: Column( //[cite: 13]
            mainAxisSize: MainAxisSize.min, //[cite: 13]
            children: [ //[cite: 13]
              Text( //[cite: 13]
                "You finished ${widget.levelId.replaceAll('_', ' ').toUpperCase()}!", //[cite: 13]
                textAlign: TextAlign.center, //[cite: 13]
              ),
              const SizedBox(height: 16), //[cite: 13]
              Row( //[cite: 13]
                mainAxisAlignment: MainAxisAlignment.center, //[cite: 13]
                children: List.generate(3, (index) { //[cite: 13]
                  return Icon( //[cite: 13]
                    index < starsEarned ? Icons.star_rounded : Icons.star_border_rounded, //[cite: 13]
                    color: const Color(0xFFFFB800), //[cite: 13]
                    size: 42, //[cite: 13]
                  );
                }),
              ),
              const SizedBox(height: 8), //[cite: 13]
              Text( //[cite: 13]
                "Earned $starsEarned / 3 Stars",  //[cite: 13]
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF222222)) //[cite: 13]
              ),
            ],
          ),
          actions: [ //[cite: 13]
            TextButton( //[cite: 13]
              onPressed: () { //[cite: 13]
                Navigator.of(context).pop();  //[cite: 13]
                Navigator.of(context).pop();  //[cite: 13]
              },
              child: const Text("Awesome!", style: TextStyle(color: Color(0xFFFFB800), fontWeight: FontWeight.bold, fontSize: 16)), //[cite: 13]
            )
          ],
        ),
      );
    }
  }

  Color _getButtonColor(String option, String correctAnswer) {
    if (!_isAnswered) return Colors.white; //[cite: 13]
    if (option == correctAnswer) return Colors.green;  //[cite: 13]
    if (option == _selectedAnswer && option != correctAnswer) return Colors.red;  //[cite: 13]
    return Colors.white;  //[cite: 13]
  }

  Color _getButtonTextColor(String option, String correctAnswer) {
    if (!_isAnswered) return Colors.black; //[cite: 13]
    if (option == correctAnswer || option == _selectedAnswer) return Colors.white; //[cite: 13]
    return Colors.black; //[cite: 13]
  }

  Color _getButtonBorderColor(String option, String correctAnswer) {
    if (!_isAnswered) return const Color(0xFFE0E0E0); //[cite: 13]
    if (option == correctAnswer) return Colors.green; //[cite: 13]
    if (option == _selectedAnswer && option != correctAnswer) return Colors.red; //[cite: 13]
    return const Color(0xFFE0E0E0); //[cite: 13]
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold( //[cite: 13]
      extendBodyBehindAppBar: true,  //[cite: 13]
      backgroundColor: const Color(0xFFFFF9E5), //[cite: 13]
      
      appBar: AppBar( //[cite: 13]
        backgroundColor: Colors.white.withOpacity(0.4),  //[cite: 13]
        elevation: 0, //[cite: 13]
        leading: IconButton( //[cite: 13]
          icon: const Icon(Icons.close, color: Colors.black87), //[cite: 13]
          onPressed: () => Navigator.pop(context), //[cite: 13]
        ),
        flexibleSpace: ClipRRect( //[cite: 13]
          child: BackdropFilter( //[cite: 13]
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),  //[cite: 13]
            child: Container(color: Colors.transparent), //[cite: 13]
          ),
        ),
        title: const Text( //[cite: 13]
          "Alphabet Activities", //[cite: 13]
          style: TextStyle( //[cite: 13]
            color: Colors.black87,  //[cite: 13]
            fontWeight: FontWeight.w800, //[cite: 13]
            fontFamily: 'Inter', //[cite: 13]
            letterSpacing: -0.5 //[cite: 13]
          ),
        ),
        centerTitle: true, //[cite: 13]
        actions: [ //[cite: 13]
          Padding( //[cite: 13]
            padding: const EdgeInsets.only(right: 16.0), //[cite: 13]
            child: Row( //[cite: 13]
              children: [ //[cite: 13]
                const Icon(Icons.favorite, color: Colors.red, size: 24), //[cite: 13]
                const SizedBox(width: 4), //[cite: 13]
                Text( //[cite: 13]
                  "$_hearts", //[cite: 13]
                  style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold), //[cite: 13]
                ),
              ],
            ),
          )
        ],
      ),
      body: _buildBody(), //[cite: 13]
    );
  }

  Widget _buildBody() {
    if (_isLoading) { //[cite: 13]
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB800))); //[cite: 13]
    }

    if (_errorMessage != null) { //[cite: 13]
      return Center( //[cite: 13]
        child: Padding( //[cite: 13]
          padding: const EdgeInsets.all(32.0), //[cite: 13]
          child: Column( //[cite: 13]
            mainAxisSize: MainAxisSize.min, //[cite: 13]
            children: [ //[cite: 13]
              const Icon(Icons.error_outline, color: Colors.red, size: 64), //[cite: 13]
              const SizedBox(height: 16), //[cite: 13]
              Text( //[cite: 13]
                _errorMessage!,  //[cite: 13]
                textAlign: TextAlign.center, //[cite: 13]
                style: const TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold) //[cite: 13]
              ),
            ],
          ),
        )
      );
    }

    if (_questions.isEmpty) { //[cite: 13]
      return const Center(child: Text("No questions available.")); //[cite: 13]
    }

    final currentQuestion = _questions[_currentIndex]; //[cite: 13]
    final progress = (_currentIndex + 1) / _questions.length; //[cite: 13]
    
    final isImageOption = currentQuestion.options.isNotEmpty &&  //[cite: 13]
                          (currentQuestion.options[0].contains('.png') ||  //[cite: 13]
                           currentQuestion.options[0].contains('.jpg')); //[cite: 13]

    return SafeArea( //[cite: 13]
      child: Column( //[cite: 13]
        children: [ //[cite: 13]
          Expanded( //[cite: 13]
            child: SingleChildScrollView( //[cite: 13]
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0), //[cite: 13]
              child: Column( //[cite: 13]
                crossAxisAlignment: CrossAxisAlignment.center, //[cite: 13]
                children: [ //[cite: 13]
                  ClipRRect( //[cite: 13]
                    borderRadius: BorderRadius.circular(10), //[cite: 13]
                    child: LinearProgressIndicator( //[cite: 13]
                      value: progress, //[cite: 13]
                      backgroundColor: const Color(0xFFE0E0E0), //[cite: 13]
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.green), //[cite: 13]
                      minHeight: 12, //[cite: 13]
                    ),
                  ),
                  const SizedBox(height: 24), //[cite: 13]

                  if (currentQuestion.imageUrl.isNotEmpty) ...[ //[cite: 13]
                    Container( //[cite: 13]
                      width: double.infinity, //[cite: 13]
                      height: 240, //[cite: 13]
                      padding: const EdgeInsets.all(16), //[cite: 13]
                      decoration: BoxDecoration( //[cite: 13]
                        color: Colors.white, //[cite: 13]
                        borderRadius: BorderRadius.circular(20), //[cite: 13]
                        boxShadow: [ //[cite: 13]
                          BoxShadow( //[cite: 13]
                            color: Colors.black.withOpacity(0.04), //[cite: 13]
                            blurRadius: 10, //[cite: 13]
                            offset: const Offset(0, 4), //[cite: 13]
                          )
                        ],
                      ),
                      child: ClipRRect( //[cite: 13]
                        borderRadius: BorderRadius.circular(12), //[cite: 13]
                        child: Image.asset( //[cite: 13]
                          currentQuestion.imageUrl, //[cite: 13]
                          fit: BoxFit.contain, //[cite: 13]
                          errorBuilder: (context, error, stackTrace) => const Center( //[cite: 13]
                            child: Icon(Icons.image_not_supported, size: 40, color: Colors.grey), //[cite: 13]
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40), //[cite: 13]
                  ],

                  Text( //[cite: 13]
                    currentQuestion.questionText, //[cite: 13]
                    style: const TextStyle( //[cite: 13]
                      fontSize: 22, //[cite: 13]
                      fontWeight: FontWeight.w800, //[cite: 13]
                      color: Colors.black, //[cite: 13]
                    ),
                    textAlign: TextAlign.center, //[cite: 13]
                  ),
                  const SizedBox(height: 32), //[cite: 13]

                  GridView.count( //[cite: 13]
                    shrinkWrap: true, //[cite: 13]
                    physics: const NeverScrollableScrollPhysics(), //[cite: 13]
                    crossAxisCount: 2, //[cite: 13]
                    mainAxisSpacing: 16, //[cite: 13]
                    crossAxisSpacing: 16, //[cite: 13]
                    childAspectRatio: isImageOption ? 1.2 : 2.2,  //[cite: 13]
                    children: currentQuestion.options.map((option) { //[cite: 13]
                      return GestureDetector( //[cite: 13]
                        onTap: () => _handleOptionSelected(option), //[cite: 13]
                        child: AnimatedContainer( //[cite: 13]
                          duration: const Duration(milliseconds: 200), //[cite: 13]
                          decoration: BoxDecoration( //[cite: 13]
                            color: _getButtonColor(option, currentQuestion.correctAnswer), //[cite: 13]
                            borderRadius: BorderRadius.circular(16), //[cite: 13]
                            border: Border.all( //[cite: 13]
                              color: _getButtonBorderColor(option, currentQuestion.correctAnswer),  //[cite: 13]
                              width: 2 //[cite: 13]
                            ),
                          ),
                          alignment: Alignment.center, //[cite: 13]
                          child: isImageOption //[cite: 13]
                              ? Padding( //[cite: 13]
                                  padding: const EdgeInsets.all(8.0), //[cite: 13]
                                  child: Image.asset( //[cite: 13]
                                    option, //[cite: 13]
                                    fit: BoxFit.contain, //[cite: 13]
                                    errorBuilder: (context, error, stackTrace) => Text( //[cite: 13]
                                      option, //[cite: 13]
                                      style: TextStyle( //[cite: 13]
                                        fontSize: 14, //[cite: 13]
                                        color: _getButtonTextColor(option, currentQuestion.correctAnswer), //[cite: 13]
                                      ),
                                    ),
                                  ),
                                )
                              : Text( //[cite: 13]
                                  option, //[cite: 13]
                                  style: TextStyle( //[cite: 13]
                                    fontSize: 24, //[cite: 13]
                                    fontWeight: FontWeight.w800, //[cite: 13]
                                    color: _getButtonTextColor(option, currentQuestion.correctAnswer), //[cite: 13]
                                  ),
                                ),
                        ),
                      );
                    }).toList(), //[cite: 13]
                  ),
                ],
              ),
            ),
          ),

          Align( //[cite: 13]
            alignment: Alignment.bottomCenter, //[cite: 13]
            child: AnimatedContainer( //[cite: 13]
              duration: const Duration(milliseconds: 300), //[cite: 13]
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24), //[cite: 13]
              decoration: BoxDecoration( //[cite: 13]
                color: !_isAnswered  //[cite: 13]
                    ? Colors.white  //[cite: 13]
                    : (_isCorrect ? const Color(0xFFD7FFB7) : const Color(0xFFFFDFE0)), //[cite: 13]
                border: Border(top: BorderSide(color: Colors.grey.shade200, width: 2)), //[cite: 13]
              ),
              child: Column( //[cite: 13]
                mainAxisSize: MainAxisSize.min, //[cite: 13]
                crossAxisAlignment: CrossAxisAlignment.start, //[cite: 13]
                children: [ //[cite: 13]
                  if (_isAnswered) ...[ //[cite: 13]
                    Row( //[cite: 13]
                      children: [ //[cite: 13]
                        Icon( //[cite: 13]
                          _isCorrect ? Icons.check_circle : Icons.cancel,  //[cite: 13]
                          color: _isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),  //[cite: 13]
                          size: 28 //[cite: 13]
                        ),
                        const SizedBox(width: 8), //[cite: 13]
                        Text( //[cite: 13]
                          _isCorrect  //[cite: 13]
                              ? "Awesome!"  //[cite: 13]
                              : (isImageOption  //[cite: 13]
                                  ? "Try again!"  //[cite: 13]
                                  : "Correct answer: ${_questions[_currentIndex].correctAnswer}"), //[cite: 13]
                          style: TextStyle( //[cite: 13]
                            color: _isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B), //[cite: 13]
                            fontSize: 18, //[cite: 13]
                            fontWeight: FontWeight.bold, //[cite: 13]
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16), //[cite: 13]
                  ],
                  SizedBox( //[cite: 13]
                    width: double.infinity, //[cite: 13]
                    height: 54, //[cite: 13]
                    child: ElevatedButton( //[cite: 13]
                      onPressed: (_isAnswered && !_isSaving) ? _handleNext : null, //[cite: 13]
                      style: ElevatedButton.styleFrom( //[cite: 13]
                        backgroundColor: !_isAnswered  //[cite: 13]
                            ? const Color(0xFFFFB800)  //[cite: 13]
                            : (_isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B)), //[cite: 13]
                        disabledBackgroundColor: Colors.grey.shade300, //[cite: 13]
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), //[cite: 13]
                      ),
                      child: _isSaving //[cite: 13]
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) //[cite: 13]
                          : Text( //[cite: 13]
                              _isAnswered ? "CONTINUE" : "CHECK", //[cite: 13]
                              style: TextStyle( //[cite: 13]
                                fontSize: 16, //[cite: 13]
                                fontWeight: FontWeight.w900, //[cite: 13]
                                color: _isAnswered ? Colors.white : Colors.black, //[cite: 13]
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