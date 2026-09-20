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

  Widget _buildJellyfish(double top, double left, Color color, double scale) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.scale(
        scale: scale,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 26,
              decoration: BoxDecoration(
                color: color.withOpacity(0.75),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(4, (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCuteFish(double top, double left, Color color, double scale, bool flip) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.scale(
        scaleX: flip ? -scale : scale,
        scaleY: scale,
        child: Icon(
          Icons.set_meal_rounded,
          color: color.withOpacity(0.8),
          size: 34,
        ),
      ),
    );
  }

  Widget _buildStarfish(double top, double left, Color color, double scale, double angle) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.rotate(
        angle: angle,
        child: Transform.scale(
          scale: scale,
          child: Icon(
            Icons.star_rounded,
            color: color.withOpacity(0.85),
            size: 38,
          ),
        ),
      ),
    );
  }

  Widget _buildMushroom(double top, double left, double scale) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.scale(
        scale: scale,
        child: Column(
          children: [
            Container(
              width: 32,
              height: 20,
              decoration: const BoxDecoration(
                color: Color(0xFFD7B3A1),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CircleAvatar(radius: 2, backgroundColor: Colors.white),
                  CircleAvatar(radius: 3, backgroundColor: Colors.white),
                  CircleAvatar(radius: 2, backgroundColor: Colors.white),
                ],
              ),
            ),
            Container(
              width: 14,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F5F4),
                borderRadius: BorderRadius.circular(3),
              ),
            )
          ],
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

  Widget _buildHotAirBalloon(double top, double left, Color balloonColor, double scale) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.scale(
        scale: scale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 52,
              decoration: BoxDecoration(
                color: balloonColor,
                borderRadius: const BorderRadius.all(Radius.elliptical(44, 52)),
                boxShadow: [
                  BoxShadow(color: balloonColor.withOpacity(0.4), blurRadius: 8, spreadRadius: 1)
                ],
              ),
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: 16,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.35),
                        borderRadius: const BorderRadius.all(Radius.elliptical(16, 52)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 12,
              height: 8,
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.black26, width: 1.5),
                  right: BorderSide(color: Colors.black26, width: 1.5),
                ),
              ),
            ),
            Container(
              width: 14,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFFFFB74D),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (bgColor.value == 0xFF080928) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF080928), Color(0xFF282059), Color(0xFF080928)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            _buildGlowingOrb(300, const Color(0xFF8750A1), -50, -100),
            _buildGlowingOrb(400, const Color(0xFF293088), 400, 200),
            _buildGlowingOrb(200, const Color(0xFF9F88D8), 700, -50),
            Positioned(top: 120, right: 30, child: Transform.rotate(angle: -0.5, child: const Icon(Icons.rocket_launch_rounded, color: Color(0xFF8750A1), size: 48))),
            Positioned(top: 480, left: 25, child: Transform.rotate(angle: 0.3, child: const Icon(Icons.public_rounded, color: Color(0xFF9F88D8), size: 54))),
            Positioned(top: 720, right: 40, child: const Icon(Icons.brightness_3_rounded, color: Color(0xFF9F88D8), size: 40)),
            ...List.generate(20, (index) {
              final random = Random(index);
              return Positioned(
                top: random.nextDouble() * 900,
                left: random.nextDouble() * 380,
                child: Icon(
                  Icons.auto_awesome, 
                  color: const Color(0xFF9F88D8).withOpacity(random.nextDouble() * 0.5 + 0.2),
                  size: random.nextDouble() * 18 + 10,
                ),
              );
            }),
          ],
        ),
      );
    }
    
    if (bgColor.value == 0xFF1D3D3A) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1D3D3A), Color(0xFF4D7C73), Color(0xFF1D3D3A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            _buildGlowingOrb(350, const Color(0xFFD7B3A1), -100, 150), 
            _buildGlowingOrb(250, const Color(0xFFB8D4CF), 300, -100),
            _buildMushroom(220, 25, 1.2),
            _buildMushroom(540, 320, 1.1),
            _buildMushroom(780, 50, 1.3),
            Positioned(top: 140, right: 40, child: Icon(Icons.flutter_dash_rounded, color: const Color(0xFFD7B3A1).withOpacity(0.8), size: 36)),
            Positioned(top: 410, left: 30, child: Icon(Icons.eco_rounded, color: const Color(0xFFB8D4CF).withOpacity(0.7), size: 32)),
            ...List.generate(15, (index) {
              final random = Random(index + 50);
              return _buildGlowingOrb(
                random.nextDouble() * 20 + 10, 
                const Color(0xFFF2F5F4), 
                random.nextDouble() * 900, 
                random.nextDouble() * 380
              );
            }),
          ],
        ),
      );
    }
    
    if (bgColor.value == 0xFF001B3A) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF005C97), Color(0xFF001B3A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            _buildGlowingOrb(400, const Color(0xFF00E5FF), -150, -50),
            _buildGlowingOrb(300, const Color(0xFF363795), 500, 150),
            _buildCuteFish(130, 40, const Color(0xFFFFD166), 1.2, false),
            _buildCuteFish(320, 280, const Color(0xFFFF6B6B), 1.1, true),
            _buildCuteFish(620, 50, const Color(0xFF00E5FF), 1.3, false),
            _buildJellyfish(230, 290, const Color(0xFFFF70A6), 1.1),
            _buildJellyfish(510, 30, const Color(0xFF70D6FF), 1.2),
            _buildStarfish(180, 310, const Color(0xFFFF9F1C), 1.0, 0.4),
            _buildStarfish(440, 20, const Color(0xFFFFD166), 1.1, -0.3),
            _buildStarfish(760, 300, const Color(0xFFFF6B6B), 1.2, 0.2),
            ...List.generate(18, (index) {
              final random = Random(index + 100);
              return Positioned(
                top: random.nextDouble() * 900,
                left: random.nextDouble() * 380,
                child: Icon(
                  Icons.bubble_chart_rounded,
                  color: Colors.white.withOpacity(random.nextDouble() * 0.35 + 0.15),
                  size: random.nextDouble() * 30 + 12,
                ),
              );
            }),
          ],
        ),
      );
    }
    
    if (bgColor.value == 0xFFE0EAFC) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFA8C0FF), Color(0xFFE0EAFC), Color(0xFFFFFFFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 40, 
              right: 30, 
              child: Icon(Icons.wb_sunny_rounded, color: const Color(0xFFFFD700).withOpacity(0.85), size: 70)
            ),
            _buildCloud(80, -30, 1.2),
            _buildCloud(280, 200, 0.9),
            _buildCloud(520, -40, 1.4),
            _buildCloud(720, 160, 1.1),
            Positioned(top: 190, left: 60, child: Icon(Icons.flutter_dash_rounded, color: const Color(0xFF5C7CFA).withOpacity(0.5), size: 30)),
            Positioned(top: 430, right: 50, child: Icon(Icons.flutter_dash_rounded, color: const Color(0xFF5C7CFA).withOpacity(0.5), size: 26)),
          ],
        ),
      );
    }
    
    const confettiColors = [
      Color(0xFFFF6B8B),
      Color(0xFFFFB74D),
      Color(0xFF4DD0E1),
      Color(0xFFAED581),
      Color(0xFFBA68C8),
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFF5D6), Color(0xFFFFE3E8), Color(0xFFE0F7FA)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          _buildGlowingOrb(350, const Color(0xFFFFCA28).withOpacity(0.5), -100, -80),
          _buildGlowingOrb(300, const Color(0xFFFF80AB).withOpacity(0.35), 450, 180),
          _buildGlowingOrb(250, const Color(0xFF4DD0E1).withOpacity(0.35), 700, -60),

          Positioned(
            top: 45,
            right: 25,
            child: Icon(Icons.wb_sunny_rounded, color: const Color(0xFFFFB300).withOpacity(0.9), size: 72),
          ),

          _buildCloud(70, -30, 1.1),
          _buildCloud(380, 190, 1.0),
          _buildCloud(680, -20, 1.2),

          _buildHotAirBalloon(150, 260, const Color(0xFFFF6B8B), 1.2),
          _buildHotAirBalloon(450, 30, const Color(0xFF4DD0E1), 1.0),
          _buildHotAirBalloon(720, 270, const Color(0xFFFFB74D), 1.1),

          Positioned(
            top: 280,
            left: 45,
            child: Transform.rotate(
              angle: -0.2,
              child: Icon(Icons.extension_rounded, color: const Color(0xFFBA68C8).withOpacity(0.7), size: 36),
            ),
          ),
          Positioned(
            top: 590,
            right: 40,
            child: Transform.rotate(
              angle: 0.3,
              child: Icon(Icons.pets_rounded, color: const Color(0xFFFF6B8B).withOpacity(0.65), size: 38),
            ),
          ),
          Positioned(
            top: 190,
            left: 170,
            child: Icon(Icons.music_note_rounded, color: const Color(0xFF4DD0E1).withOpacity(0.7), size: 30),
          ),

          ...List.generate(24, (index) {
            final random = Random(index + 200);
            final color = confettiColors[random.nextInt(confettiColors.length)];
            return Positioned(
              top: random.nextDouble() * 900,
              left: random.nextDouble() * 380,
              child: Transform.rotate(
                angle: random.nextDouble() * 3.14,
                child: Icon(
                  random.nextBool() ? Icons.star_rounded : Icons.auto_awesome_rounded,
                  color: color.withOpacity(random.nextDouble() * 0.5 + 0.3),
                  size: random.nextDouble() * 18 + 10,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class PhraseActivityInterface extends StatefulWidget {
  final String levelId;
  final String title;
  final List<Map<String, dynamic>> initialQuestions;

  const PhraseActivityInterface({
    super.key,
    required this.levelId,
    this.title = 'Phrase Activity',
    this.initialQuestions = const [],
  });

  @override
  State<PhraseActivityInterface> createState() => _PhraseActivityInterfaceState();
}

class _PhraseActivityInterfaceState extends State<PhraseActivityInterface> {
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
    _loadPhraseQuestions();
  }

  bool _isPhraseCategory(dynamic categoryValue) {
    if (categoryValue == null) return false;
    final cat = categoryValue.toString().trim().toLowerCase();
    return cat == 'phrase' || cat == 'phrases';
  }

  Future<void> _loadPhraseQuestions() async {
    try {
      ProgressService().trackRecentModule(widget.levelId);
    } catch (_) {}

    if (widget.initialQuestions.isNotEmpty) {
      final sanitized = widget.initialQuestions.asMap().entries.map((entry) {
        final idx = entry.key;
        final q = Map<String, dynamic>.from(entry.value);
        q['id'] ??= 'question_$idx';
        return q;
      }).where((q) {
        final cat = (q['category'] ?? '').toString().trim().toLowerCase();
        final lvl = (q['level'] ?? '').toString().trim().toLowerCase();
        
        if (cat.contains('alphabet') || lvl.contains('alphabet')) return false;
        return _isPhraseCategory(cat);
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
          .where('category', whereIn: ['phrase', 'phrases', 'Phrase', 'Phrases'])
          .get();

      List<Map<String, dynamic>> loadedQuestions = [];

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final cat = (data['category'] ?? '').toString().trim().toLowerCase();
        final lvl = (data['level'] ?? '').toString().trim().toLowerCase();

        if (cat.contains('alphabet') || lvl.contains('alphabet')) {
          continue;
        }

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
          'question': data['question'] ?? data['phrase'] ?? data['questionText'] ?? '',
          'correctAnswer': data['correctAnswer'] ?? data['answer'] ?? '',
          'options': List<String>.from(data['options'] ?? []),
          'category': data['category'] ?? 'phrase',
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
      debugPrint("Error fetching phrase questions: $e");
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

      // Record activity completion attempt summary in Firestore
      await progressService.recordActivityAttempt(
        levelId: levelId,
        category: 'phrase',
        isCompleted: true,
        starsEarned: _starsEarned,
      );

      // Award XP on level and overall profile
      final int xpEarned = _score * 10;
      await progressService.addXp(xpEarned);
      await progressService.updateLevelXP(levelId, xpEarned);
    } catch (e) {
      debugPrint("Error saving phrase activity progress: $e");
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
            fontSize: 20,
            fontWeight: FontWeight.w800,
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
            'No phrase activity questions available.',
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
          Color borderClr = theme.dividerColor.withOpacity(0.3);
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