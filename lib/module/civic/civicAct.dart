import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import '/providers/sound_provider.dart';
import '/services/progress_service.dart';

class ThemedBackground extends StatelessWidget {
  final Color bgColor;

  const ThemedBackground({super.key, required this.bgColor});

  Widget _buildGlowingOrb(double size, Color color, double top, double left) {
    return Positioned(
      top: top,
      left: left,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.6), color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }

  Widget _buildCloud(double top, double left, double scale) {
    return Positioned(
      top: top, 
      left: left,
      child: Transform.scale(
        scale: scale,
        child: SizedBox(
          width: 140,
          height: 80,
          child: Stack(
            children: [
              Positioned(bottom: 0, left: 10, child: Container(width: 50, height: 50, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.65)))),
              Positioned(bottom: 12, left: 35, child: Container(width: 70, height: 70, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.8)))),
              Positioned(bottom: 0, left: 75, child: Container(width: 45, height: 45, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.65)))),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const confettiColors = [
      Color(0xFFFF6B8B),
      Color(0xFFFFB74D),
      Color(0xFF4DD0E1),
      Color(0xFFAED581),
      Color(0xFFBA68C8),
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            bgColor,
            bgColor.withOpacity(0.85),
            bgColor.withOpacity(0.70),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          _buildGlowingOrb(350, const Color(0xFFFFCA28).withOpacity(0.4), -100, -80),
          _buildGlowingOrb(300, const Color(0xFFFF80AB).withOpacity(0.3), 450, 180),
          _buildGlowingOrb(250, const Color(0xFF4DD0E1).withOpacity(0.3), 700, -60),

          _buildCloud(70, -30, 1.1),
          _buildCloud(380, 190, 1.0),
          _buildCloud(680, -20, 1.2),

          ...List.generate(20, (index) {
            final random = Random(index + 300);
            final color = confettiColors[random.nextInt(confettiColors.length)];
            return Positioned(
              top: random.nextDouble() * 900,
              left: random.nextDouble() * 380,
              child: Transform.rotate(
                angle: random.nextDouble() * 3.14,
                child: Icon(
                  random.nextBool() ? Icons.account_balance_rounded : Icons.gavel_rounded,
                  color: color.withOpacity(random.nextDouble() * 0.35 + 0.15),
                  size: random.nextDouble() * 18 + 14,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class CivicActivityInterface extends StatefulWidget {
  final String levelId;
  final String title;
  final List<Map<String, dynamic>> questions;

  const CivicActivityInterface({
    super.key,
    required this.levelId,
    this.title = 'Civic Activity',
    this.questions = const [],
  });

  @override
  State<CivicActivityInterface> createState() => _CivicActivityInterfaceState();
}

class _CivicActivityInterfaceState extends State<CivicActivityInterface> {
  int _currentIndex = 0;
  String? _selectedOption;
  bool _isAnswered = false;
  int _score = 0;
  int _starsEarned = 0;
  bool _progressSaved = false;

  List<Map<String, dynamic>> _questions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCivicQuestions();
  }

  bool _isCivicCategory(dynamic categoryValue) {
    if (categoryValue == null) return false;
    final cat = categoryValue.toString().trim().toLowerCase();
    return cat == 'civic' || cat == 'civics';
  }

  Future<void> _loadCivicQuestions() async {
    try {
      ProgressService().trackRecentModule(widget.levelId);
    } catch (_) {}

    if (widget.questions.isNotEmpty) {
      final sanitized = widget.questions.asMap().entries.map((entry) {
        final idx = entry.key;
        final q = Map<String, dynamic>.from(entry.value);
        q['id'] ??= 'civic_q_$idx';
        return q;
      }).where((q) {
        final cat = (q['category'] ?? '').toString().trim().toLowerCase();
        if (cat.isEmpty) return true;
        return _isCivicCategory(cat);
      }).toList();

      if (mounted) {
        setState(() {
          _questions = List.from(sanitized);
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('activity_questions')
          .where('level', isEqualTo: widget.levelId)
          .where('category', whereIn: ['civic', 'civics', 'Civic', 'Civics'])
          .get();

      List<Map<String, dynamic>> loadedQuestions = [];

      for (var doc in querySnapshot.docs) {
        final data = doc.data();

        String? audioUrl;
        if (data.containsKey('audioStoragePath') && data['audioStoragePath'] != null) {
          try {
            audioUrl = await FirebaseStorage.instance
                .ref(data['audioStoragePath'])
                .getDownloadURL();
          } catch (e) {
            debugPrint("Error fetching Cloud Storage URL: $e");
          }
        }

        loadedQuestions.add({
          'id': doc.id,
          'question': data['question'] ?? data['title'] ?? data['questionText'] ?? '',
          'correctAnswer': data['correctAnswer'] ?? data['answer'] ?? '',
          'options': List<String>.from(data['options'] ?? []),
          'category': data['category'] ?? 'civic',
          'audioUrl': audioUrl,
        });
      }

      if (mounted) {
        setState(() {
          _questions = loadedQuestions;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching civic questions: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _playSound(String effect) {
    try {
      final soundProvider = Provider.of<SoundProvider>(context, listen: false) as dynamic;
      if (effect.contains('correct')) {
        soundProvider.playSound('correct');
      } else {
        soundProvider.playSound('wrong');
      }
    } catch (_) {
      try {
        final soundProvider = Provider.of<SoundProvider>(context, listen: false) as dynamic;
        soundProvider.playSoundEffect(effect);
      } catch (_) {}
    }
  }

  Future<void> _updateProgress(String levelId) async {
    if (_progressSaved) return;
    _progressSaved = true;

    try {
      final progressService = ProgressService();

      await progressService.recordActivityAttempt(
        levelId: levelId,
        category: 'civic',
        isCompleted: true,
        starsEarned: _starsEarned,
      );

      final int xpEarned = _score * 10;
      await progressService.addXp(xpEarned);
      await progressService.updateLevelXP(levelId, xpEarned);
    } catch (e) {
      debugPrint("Error saving civic activity progress: $e");
    }
  }

  void _handleAnswer(String selectedOption, String correctAnswer, String levelId, int totalQuestions) {
    if (_isAnswered) return;

    final bool isCorrect = selectedOption.trim().toLowerCase() == correctAnswer.trim().toLowerCase();

    setState(() {
      _selectedOption = selectedOption;
      _isAnswered = true;

      if (isCorrect) {
        _score++;
        _playSound('correct');
      } else {
        _playSound('wrong');
      }

      final double accuracy = totalQuestions > 0 ? _score / totalQuestions : 0.0;
      if (accuracy >= 0.9) {
        _starsEarned = 3;
      } else if (accuracy >= 0.6) {
        _starsEarned = 2;
      } else if (accuracy > 0) {
        _starsEarned = 1;
      } else {
        _starsEarned = 0;
      }
    });

    if (_currentIndex == totalQuestions - 1) {
      _updateProgress(levelId);
    }
  }

  void _nextQuestion() {
    setState(() {
      _currentIndex++;
      _selectedOption = null;
      _isAnswered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaffoldBgColor = theme.scaffoldBackgroundColor;
    final textColor = theme.colorScheme.onSurface;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scaffoldBgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ThemedBackground(bgColor: scaffoldBgColor),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                  : _questions.isEmpty
                      ? _buildEmptyState(theme)
                      : (_currentIndex >= _questions.length
                          ? _buildCompletionView(theme)
                          : _buildQuestionUI(theme)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final textColor = theme.colorScheme.onSurface;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 70, color: textColor.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            'No activity questions available.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text('Go Back', style: TextStyle(color: theme.colorScheme.onPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionUI(ThemeData theme) {
    final questionData = _questions[_currentIndex];
    final String question = questionData['question'] ?? '';
    final List<String> options = List<String>.from(questionData['options'] ?? []);
    final String correctAnswer = questionData['correctAnswer'] ?? '';
    final textColor = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Question ${_currentIndex + 1}/${_questions.length}',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.7)),
        ),
        const SizedBox(height: 16),
        Text(
          question,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textColor),
        ),
        const SizedBox(height: 24),
        ...options.map((option) {
          Color borderClr = theme.dividerColor.withOpacity(0.2);
          Color fillClr = theme.cardColor;

          if (_isAnswered) {
            if (option.trim().toLowerCase() == correctAnswer.trim().toLowerCase()) {
              borderClr = Colors.green;
              fillClr = Colors.green.withOpacity(0.25);
            } else if (option == _selectedOption) {
              borderClr = Colors.red;
              fillClr = Colors.red.withOpacity(0.25);
            }
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: GestureDetector(
              onTap: () => _handleAnswer(option, correctAnswer, widget.levelId, _questions.length),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: fillClr,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderClr, width: 2),
                ),
                child: Text(
                  option,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
            ),
          );
        }),
        const Spacer(),
        if (_isAnswered)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _nextQuestion,
            child: Text(
              _currentIndex < _questions.length - 1 ? 'Next Question' : 'View Results',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary),
            ),
          ),
      ],
    );
  }

  Widget _buildCompletionView(ThemeData theme) {
    final textColor = theme.colorScheme.onSurface;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.stars_rounded, size: 90, color: Colors.amber),
          const SizedBox(height: 16),
          Text(
            'Activity Completed!',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 12),
          Text(
            'Stars Earned: $_starsEarned / 3',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: theme.primaryColor),
          ),
          const SizedBox(height: 8),
          Text(
            'Score: $_score / ${_questions.length}',
            style: TextStyle(fontSize: 16, color: textColor.withOpacity(0.8)),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Finish',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary),
            ),
          ),
        ],
      ),
    );
  }
}