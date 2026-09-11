import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/providers/sound_provider.dart';
import '/services/progress_service.dart';

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
      } catch (_) {
        // Silently catch missing audio method exceptions
      }
    }
  }

  Future<void> _updateProgress(String levelId) async {
    if (_progressSaved) return;
    _progressSaved = true;

    try {
      dynamic service = ProgressService();
      try {
        await service.updateUserProgress(
          levelKey: levelId,
          stars: _starsEarned,
          xpEarned: _score * 10,
          xpCategoryKey: 'civicXp',
        );
      } catch (_) {
        await service.updateUserProgress(levelId, _starsEarned, _score * 10);
      }
    } catch (e) {
      debugPrint("Error saving civic activity progress: $e");
    }
  }

  void _handleAnswer(String selectedOption, String correctAnswer, String levelId, int totalQuestions) {
    if (_isAnswered) return;

    setState(() {
      _selectedOption = selectedOption;
      _isAnswered = true;

      if (selectedOption == correctAnswer) {
        _score++;
        _playSound('correct');
      } else {
        _playSound('wrong');
      }

      final double accuracy = totalQuestions > 0 ? _score / totalQuestions : 0.0;
      if (accuracy > 0.9) {
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
    final textColor = theme.colorScheme.onSurface;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.6),
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
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.scaffoldBackgroundColor,
                  theme.primaryColor.withOpacity(0.08),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: widget.questions.isEmpty
                  ? _buildEmptyState(theme)
                  : (_currentIndex >= widget.questions.length
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
    final questionData = widget.questions[_currentIndex];
    final String question = questionData['question'] ?? '';
    final List<String> options = List<String>.from(questionData['options'] ?? []);
    final String correctAnswer = questionData['correctAnswer'] ?? '';
    final textColor = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Question ${_currentIndex + 1}/${widget.questions.length}',
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
            if (option == correctAnswer) {
              borderClr = Colors.green;
              fillClr = Colors.green.withOpacity(0.15);
            } else if (option == _selectedOption) {
              borderClr = Colors.red;
              fillClr = Colors.red.withOpacity(0.15);
            }
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: GestureDetector(
              onTap: () => _handleAnswer(option, correctAnswer, widget.levelId, widget.questions.length),
              child: Container(
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
              _currentIndex < widget.questions.length - 1 ? 'Next Question' : 'View Results',
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
            'Score: $_score / ${widget.questions.length}',
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