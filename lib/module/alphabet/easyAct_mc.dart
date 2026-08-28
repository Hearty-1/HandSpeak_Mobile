import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '/providers/sound_provider.dart';

// ==========================================
// 1. DATA MODEL
// ==========================================
class QuizQuestion {
  final String id;
  final String type;
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
// 2. FIRESTORE API SERVICE
// ==========================================
class QuizApiService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<List<QuizQuestion>> fetchEasyQuestions(String levelId, String typeFilter) async {
    final querySnapshot = await _db
        .collection('activity_questions')
        .where('category', isEqualTo: 'alphabet')
        .get();

    if (querySnapshot.docs.isEmpty) {
      throw Exception("DATABASE IS EMPTY!\n\nPlease press the red 'DEV: SEED DATABASE' button first.");
    }

    List<QuizQuestion> levelQuestions = [];
    for (var doc in querySnapshot.docs) {
      final data = doc.data();
      if (data['level'] == levelId || (levelId == 'alphabet_easy_1' && data['level'] == 'easy')) {
        data['id'] = doc.id;
        levelQuestions.add(QuizQuestion.fromJson(data));
      }
    }

    if (levelQuestions.isEmpty) {
      throw Exception("LEVEL NOT FOUND!\n\nNo questions match levelId: '$levelId'.");
    }

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

    if (finalQuestions.isEmpty) {
      throw Exception("TYPE MISMATCH!\n\nNo questions match requested questionType: '$typeFilter'.");
    }

    return finalQuestions;
  }
}

// ==========================================
// 3. ANIMATED THEMED LEVEL COMPLETE DIALOG
// ==========================================
class ThemedLevelCompleteDialog extends StatefulWidget {
  final int starsEarned;
  final String levelId;

  const ThemedLevelCompleteDialog({
    super.key,
    required this.starsEarned,
    required this.levelId,
  });

  @override
  State<ThemedLevelCompleteDialog> createState() => _ThemedLevelCompleteDialogState();
}

class _ThemedLevelCompleteDialogState extends State<ThemedLevelCompleteDialog>
    with TickerProviderStateMixin {
  late List<AnimationController> _starControllers;
  late List<Animation<double>> _starScaleAnimations;

  @override
  void initState() {
    super.initState();
    _starControllers = List.generate(
      3,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );

    _starScaleAnimations = _starControllers.map((controller) {
      return CurvedAnimation(
        parent: controller,
        curve: Curves.elasticOut,
      );
    }).toList();

    _animateStars();
  }

  void _animateStars() async {
    for (int i = 0; i < widget.starsEarned; i++) {
      await Future.delayed(Duration(milliseconds: 280 * (i + 1)));
      if (mounted) {
        _starControllers[i].forward();
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _starControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // Formats levelId (e.g., "alphabet_easy_1") to "Level 1"
  String get _formattedLevelName {
    final match = RegExp(r'\d+').firstMatch(widget.levelId);
    if (match != null) {
      return "Level ${match.group(0)}";
    }
    return widget.levelId.replaceAll('_', ' ');
  }

  LinearGradient _getDialogGradient(Color bgColor) {
    if (bgColor.value == 0xFF0F0C29) { // Galaxy
      return const LinearGradient(colors: [Color(0xFF240B36), Color(0xFFC31432)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    } else if (bgColor.value == 0xFF132A13) { // Enchanted Forest
      return const LinearGradient(colors: [Color(0xFF134E5E), Color(0xFF71B280)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    } else if (bgColor.value == 0xFF001B3A) { // Ocean
      return const LinearGradient(colors: [Color(0xFF005C97), Color(0xFF363795)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    } else if (bgColor.value == 0xFFE0EAFC) { // Cloudy Sky
      return const LinearGradient(colors: [Color(0xFFA8C0FF), Color(0xFF3F2B96)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    }
    return const LinearGradient(colors: [Color(0xFF11998E), Color(0xFF38EF7D)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogGradient = _getDialogGradient(theme.scaffoldBackgroundColor);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: dialogGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Activity Complete! 🎉",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              "You finished $_formattedLevelName!",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                final isEarned = index < widget.starsEarned;
                return ScaleTransition(
                  scale: isEarned
                      ? _starScaleAnimations[index]
                      : const AlwaysStoppedAnimation(1.0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Icon(
                      isEarned ? Icons.star_rounded : Icons.star_border_rounded,
                      color: isEarned ? const Color(0xFFFFD700) : Colors.white38,
                      size: 54,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),

            Text(
              "Earned ${widget.starsEarned} / 3 Stars",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                child: const Text(
                  "AWESOME!",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 4. MAIN UI SCREEN
// ==========================================
class EasyActMc extends StatefulWidget {
  final String levelId;
  final String questionType;

  const EasyActMc({
    super.key,
    required this.levelId,
    required this.questionType,
  });

  @override
  State<EasyActMc> createState() => _EasyActMcState();
}

class _EasyActMcState extends State<EasyActMc> with SingleTickerProviderStateMixin {
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

  late AnimationController _feedbackAnimController;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _loadQuestions();

    _feedbackAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _feedbackAnimController,
      curve: Curves.elasticOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _feedbackAnimController,
      curve: Curves.easeOutBack,
    ));
  }

  @override
  void dispose() {
    _feedbackAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    try {
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
      
      final soundProvider = Provider.of<SoundProvider>(context, listen: false);
      _isCorrect ? soundProvider.playCorrect() : soundProvider.playIncorrect();

      if (!_isCorrect) {
        _hearts--;
        if (_hearts <= 0) {
          _showGameOverDialog();
        }
      }
    });

    _feedbackAnimController.forward(from: 0.0);
  }

  void _showGameOverDialog() {
    Provider.of<SoundProvider>(context, listen: false).playGameOver();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Out of Hearts! 💔", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        content: Text(
          "You made a few mistakes. Take a break and review the tutorials, then try again!",
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
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
    _feedbackAnimController.reset();

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

      Provider.of<SoundProvider>(context, listen: false).playLevelComplete();

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => ThemedLevelCompleteDialog(
          starsEarned: starsEarned,
          levelId: widget.levelId,
        ),
      );
    }
  }

  Map<String, dynamic> _getThemeFeedbackVisuals(BuildContext context, bool isCorrect) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor.value;
    final IconData feedbackIcon = isCorrect ? Icons.check_rounded : Icons.close_rounded;

    if (bgColor == 0xFF0F0C29) { // Galaxy
      return {
        'icon': feedbackIcon,
        'title': isCorrect ? "Cosmic Victory! 🚀" : "Asteroid Bump! ☄️",
        'subtitle': isCorrect ? "Out of this world accuracy!" : "Recalibrate trajectory and try again.",
        'gradient': isCorrect 
            ? const LinearGradient(colors: [Color(0xFF240B36), Color(0xFFC31432)])
            : const LinearGradient(colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)]),
        'badgeColor': isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),
        'accentColor': const Color(0xFFFF2A85),
      };
    }
    
    if (bgColor == 0xFF132A13) { // Enchanted Forest
      return {
        'icon': feedbackIcon,
        'title': isCorrect ? "Magical Spell! 🌿" : "Lost in the Woods! 🍃",
        'subtitle': isCorrect ? "Ancient wisdom guided you!" : "Listen to the forest breeze and retry.",
        'gradient': isCorrect 
            ? const LinearGradient(colors: [Color(0xFF134E5E), Color(0xFF71B280)])
            : const LinearGradient(colors: [Color(0xFF2C3E50), Color(0xFF000000)]),
        'badgeColor': isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),
        'accentColor': const Color(0xFFFFD700),
      };
    }

    if (bgColor == 0xFF001B3A) { // Ocean
      return {
        'icon': feedbackIcon,
        'title': isCorrect ? "Splashtastic! 🌊" : "Washed Away! 🐙",
        'subtitle': isCorrect ? "Riding the big wave like a pro!" : "Take a breath and dive back in.",
        'gradient': isCorrect 
            ? const LinearGradient(colors: [Color(0xFF005C97), Color(0xFF363795)])
            : const LinearGradient(colors: [Color(0xFF1F4037), Color(0xFF99F2C8)]),
        'badgeColor': isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),
        'accentColor': const Color(0xFF00E5FF),
      };
    }

    if (bgColor == 0xFFE0EAFC) { // Cloudy Sky
      return {
        'icon': feedbackIcon,
        'title': isCorrect ? "On Cloud Nine! ☁️" : "A Little Stormy! 🌧️",
        'subtitle': isCorrect ? "Bright sky ahead, great job!" : "The sun will shine on your next guess.",
        'gradient': isCorrect 
            ? const LinearGradient(colors: [Color(0xFFA8C0FF), Color(0xFF3F2B96)])
            : const LinearGradient(colors: [Color(0xFF8E9EAB), Color(0xFFEEF2F3)]),
        'badgeColor': isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),
        'accentColor': const Color(0xFF5C7CFA),
      };
    }

    return {
      'icon': feedbackIcon,
      'title': isCorrect ? "Awesome Job! 🎉" : "Not Quite! 💡",
      'subtitle': isCorrect ? "You nailed the correct answer!" : "Review the sign and try again.",
      'gradient': isCorrect 
          ? const LinearGradient(colors: [Color(0xFF11998E), Color(0xFF38EF7D)])
          : const LinearGradient(colors: [Color(0xFFCB2D3E), Color(0xFFEF473A)]),
      'badgeColor': isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),
      'accentColor': isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),
    };
  }

  Color _getButtonColor(String option, String correctAnswer, ThemeData theme) {
    if (!_isAnswered) return theme.cardColor;
    if (option == correctAnswer) return const Color(0xFF58CC02);
    if (option == _selectedAnswer && option != correctAnswer) return const Color(0xFFEA2B2B);
    return theme.cardColor; 
  }

  Color _getButtonTextColor(String option, String correctAnswer, ThemeData theme) {
    if (!_isAnswered) return theme.colorScheme.onSurface;
    if (option == correctAnswer || option == _selectedAnswer) return Colors.white;
    return theme.colorScheme.onSurface;
  }

  Color _getButtonBorderColor(String option, String correctAnswer, ThemeData theme) {
    if (!_isAnswered) return theme.dividerColor;
    if (option == correctAnswer) return const Color(0xFF58CC02);
    if (option == _selectedAnswer && option != correctAnswer) return const Color(0xFFEA2B2B);
    return theme.dividerColor;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onBackground;

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: theme.scaffoldBackgroundColor,
      
      appBar: AppBar(
        backgroundColor: theme.cardColor.withOpacity(0.5),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), 
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text(
          "Alphabet Activities",
          style: TextStyle(
            color: textColor, 
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
            letterSpacing: -0.5
          ),
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
                  style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          )
        ],
      ),
      body: _buildBody(theme, textColor),
    );
  }

  Widget _buildBody(ThemeData theme, Color textColor) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: theme.primaryColor));
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
      return Center(child: Text("No questions available.", style: TextStyle(color: textColor)));
    }

    final currentQuestion = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;
    
    final isImageOption = currentQuestion.options.isNotEmpty && 
                          (currentQuestion.options[0].contains('.png') || 
                           currentQuestion.options[0].contains('.jpg'));

    final feedbackData = _getThemeFeedbackVisuals(context, _isCorrect);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: theme.dividerColor,
                      valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
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
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
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
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: textColor,
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
                            color: _getButtonColor(option, currentQuestion.correctAnswer, theme),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _getButtonBorderColor(option, currentQuestion.correctAnswer, theme), 
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
                                        color: _getButtonTextColor(option, currentQuestion.correctAnswer, theme),
                                      ),
                                    ),
                                  ),
                                )
                              : Text(
                                  option,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: _getButtonTextColor(option, currentQuestion.correctAnswer, theme),
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: !_isAnswered ? theme.cardColor : null,
                gradient: _isAnswered ? (feedbackData['gradient'] as LinearGradient) : null,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: theme.dividerColor, width: 2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isAnswered) ...[
                    SlideTransition(
                      position: _slideAnimation,
                      child: Row(
                        children: [
                          ScaleTransition(
                            scale: _scaleAnimation,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: (feedbackData['badgeColor'] as Color),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  )
                                ],
                              ),
                              child: Icon(
                                feedbackData['icon'] as IconData,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  feedbackData['title'] as String,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isImageOption 
                                      ? (feedbackData['subtitle'] as String) 
                                      : (_isCorrect 
                                          ? (feedbackData['subtitle'] as String)
                                          : "Correct Answer: ${currentQuestion.correctAnswer}"),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: (_isAnswered && !_isSaving) ? _handleNext : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: !_isAnswered 
                            ? theme.primaryColor  
                            : Colors.white,
                        disabledBackgroundColor: theme.dividerColor,
                        elevation: _isAnswered ? 4 : 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isSaving
                          ? SizedBox(
                              width: 20, 
                              height: 20, 
                              child: CircularProgressIndicator(color: theme.primaryColor, strokeWidth: 2)
                            )
                          : Text(
                              _isAnswered ? "CONTINUE" : "CHECK",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: !_isAnswered 
                                    ? theme.colorScheme.onPrimary 
                                    : (feedbackData['accentColor'] as Color),
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