import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '/providers/sound_provider.dart';
import '/services/performance_monitor.dart';
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
            colors: [Color(0xFF080928), Color(0xFF1B1A4B), Color(0xFF080928)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            _buildGlowingOrb(300, const Color(0xFF7C4DFF), -50, -100),
            _buildGlowingOrb(400, const Color(0xFF4C5FE6), 400, 200),
            _buildGlowingOrb(200, const Color(0xFFB9A6FF), 700, -50),
            Positioned(top: 120, right: 30, child: Transform.rotate(angle: -0.5, child: const Icon(Icons.rocket_launch_rounded, color: Color(0xFF7C4DFF), size: 48))),
            Positioned(top: 480, left: 25, child: Transform.rotate(angle: 0.3, child: const Icon(Icons.public_rounded, color: Color(0xFFB9A6FF), size: 54))),
            Positioned(top: 720, right: 40, child: const Icon(Icons.brightness_3_rounded, color: Color(0xFFB9A6FF), size: 40)),
            ...List.generate(20, (index) {
              final random = Random(index);
              return Positioned(
                top: random.nextDouble() * 900,
                left: random.nextDouble() * 380,
                child: Icon(
                  Icons.auto_awesome, 
                  color: const Color(0xFFB9A6FF).withOpacity(random.nextDouble() * 0.5 + 0.2),
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

/// A phrases level: every question type the web app uploads (same as
/// easyAct_mc.dart), see _QuizScreen below.
class PhraseActivityInterface extends StatelessWidget {
  final String levelId;
  final String title;
  final List<Map<String, dynamic>> initialQuestions;

  /// Category in activity_questions; also used by categories added from the
  /// web app (module/custom_category_screen.dart), which have no screen of
  /// their own.
  final String category;
  final String moduleKey;
  final String xpField;

  const PhraseActivityInterface({
    super.key,
    required this.levelId,
    this.title = 'Phrase Activity',
    this.initialQuestions = const [],
    this.category = 'phrases',
    this.moduleKey = 'phrases',
    this.xpField = 'phraseXp',
  });

  @override
  Widget build(BuildContext context) {
    return _QuizScreen(
      levelId: levelId,
      title: title,
      category: category,
      moduleKey: moduleKey,
      xpField: xpField,
      initialQuestions: initialQuestions,
      emptyMessage: 'No activity questions available.',
      background: ThemedBackground(bgColor: Theme.of(context).scaffoldBackgroundColor),
    );
  }
}

// =============================================================================
// QUIZ SCREEN, QUESTION TYPES AND QUESTION LOADING
// =============================================================================

/// A level of a category's activity map (phrases, civic, ...): loads the
/// level's `activity_questions` in every type the web app uploads and plays
/// them like easyAct_mc.dart (pick / build the answer, CHECK, feedback,
/// CONTINUE), then saves the stars.
class _QuizScreen extends StatefulWidget {
  final String levelId;
  final String title;

  /// Category in `activity_questions` ('phrases', 'civic').
  final String category;

  /// Progress / XP fields (progress_service.dart).
  final String moduleKey;
  final String xpField;

  /// Questions handed in by the caller (raw maps); fetched when empty.
  final List<Map<String, dynamic>> initialQuestions;

  final Widget background;
  final String emptyMessage;

  const _QuizScreen({
    required this.levelId,
    required this.title,
    required this.category,
    required this.moduleKey,
    required this.xpField,
    required this.background,
    this.initialQuestions = const [],
    this.emptyMessage = 'No activity questions available.',
  });

  @override
  State<_QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<_QuizScreen> {
  // Game music while this level is open (see SoundProvider.claimBgm).
  late final SoundProvider _bgm;

  final _QuestionRepository _repository = _QuestionRepository();
  final ProgressService _progress = ProgressService();
  final _AnswerController _answer = _AnswerController();

  List<_Question> _questions = [];
  bool _isLoading = true;
  String? _error;

  int _currentIndex = 0;
  bool _isAnswered = false;
  bool _isCorrect = false;
  int _score = 0;
  int _starsEarned = 0;
  bool _isSaving = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _bgm = Provider.of<SoundProvider>(context, listen: false)..claimBgm(this, BgmType.activity);
    _answer.addListener(_onAnswerChanged);
    _progress.trackRecentModule(widget.moduleKey).catchError((_) {});
    _load();
  }

  @override
  void dispose() {
    _bgm.releaseBgm(this);
    _answer.removeListener(_onAnswerChanged);
    _answer.dispose();
    super.dispose();
  }

  void _onAnswerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final questions = widget.initialQuestions.isNotEmpty
          ? await _repository.fromMaps(widget.initialQuestions, category: widget.category)
          : await _repository.fetchLevel(category: widget.category, levelId: widget.levelId);
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching ${widget.category} questions for ${widget.levelId}: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this level. Check your connection and try again.';
        _isLoading = false;
      });
    }
  }

  void _check() {
    if (_isAnswered || !_answer.isReady) return;
    final correct = _answer.grade();
    final sound = Provider.of<SoundProvider>(context, listen: false);
    correct ? sound.playCorrect() : sound.playIncorrect();
    FocusScope.of(context).unfocus();
    setState(() {
      _isAnswered = true;
      _isCorrect = correct;
      if (correct) _score++;
    });
  }

  int _starsFor(int score, int total) {
    final accuracy = total > 0 ? score / total : 0.0;
    if (accuracy >= 0.9) return 3;
    if (accuracy >= 0.6) return 2;
    if (accuracy > 0) return 1;
    return 0;
  }

  Future<void> _continue() async {
    if (_currentIndex < _questions.length - 1) {
      _answer.reset();
      setState(() {
        _currentIndex++;
        _isAnswered = false;
        _isCorrect = false;
      });
      return;
    }

    setState(() => _isSaving = true);
    _starsEarned = _starsFor(_score, _questions.length);
    try {
      await _progress.recordActivityAttempt(
        levelId: widget.levelId,
        category: widget.category,
        isCompleted: true,
        starsEarned: _starsEarned,
      );
      // Best stars per level (the activity map reads progress.<levelId> as
      // stars); fixed XP per new star, small repeat XP (xp_rewards.dart).
      await _progress.saveActivityStars(levelId: widget.levelId, stars: _starsEarned, xpField: widget.xpField);
    } catch (e) {
      debugPrint('Error saving ${widget.category} activity progress: $e');
    }
    if (!mounted) return;
    Provider.of<SoundProvider>(context, listen: false).playLevelComplete();
    setState(() {
      _isSaving = false;
      _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title, style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
        flexibleSpace: ClipRRect(
          child: SmartBlur(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: widget.background),
          SafeArea(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) return Center(child: CircularProgressIndicator(color: theme.primaryColor));
    if (_error != null) return _buildMessage(theme, Icons.wifi_off_rounded, _error!);
    if (_questions.isEmpty) return _buildMessage(theme, Icons.assignment_outlined, widget.emptyMessage);
    if (_finished) return _buildCompletionView(theme);

    final q = _questions[_currentIndex];
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: (_currentIndex + 1) / _questions.length,
                          backgroundColor: theme.dividerColor,
                          valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                          minHeight: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_currentIndex + 1}/${_questions.length}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _QuestionView(
                  key: ValueKey('${q.id}_$_currentIndex'),
                  question: q,
                  controller: _answer,
                  revealed: _isAnswered,
                ),
              ],
            ),
          ),
        ),
        _buildBottomBar(theme, q),
      ],
    );
  }

  Widget _buildBottomBar(ThemeData theme, _Question q) {
    const green = Color(0xFF58CC02);
    const red = Color(0xFFEA2B2B);
    final answerLabel = _QuestionView.answerLabel(q);
    final isLast = _currentIndex == _questions.length - 1;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: !_isAnswered ? theme.cardColor : (_isCorrect ? green : red),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isAnswered) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                  child: Icon(_isCorrect ? Icons.check_rounded : Icons.close_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isCorrect ? 'Awesome Job! 🎉' : 'Not Quite! 💡',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                      if (!_isCorrect && answerLabel.isNotEmpty)
                        Text(
                          'Correct answer: $answerLabel',
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isSaving ? null : (_isAnswered ? _continue : (_answer.isReady ? _check : null)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isAnswered ? Colors.white : theme.primaryColor,
                disabledBackgroundColor: theme.dividerColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isSaving
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: theme.primaryColor, strokeWidth: 2))
                  : Text(
                      _isAnswered ? (isLast ? 'VIEW RESULTS' : 'CONTINUE') : 'CHECK',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _isAnswered ? (_isCorrect ? green : red) : theme.colorScheme.onPrimary,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(ThemeData theme, IconData icon, String message) {
    final textColor = theme.colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 70, color: textColor.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
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
      ),
    );
  }

  Widget _buildCompletionView(ThemeData theme) {
    final textColor = theme.colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => Icon(
                  i < _starsEarned ? Icons.star_rounded : Icons.star_border_rounded,
                  color: i < _starsEarned ? const Color(0xFFFFD700) : textColor.withValues(alpha: 0.3),
                  size: 56,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Activity Completed!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 12),
            Text(
              'Stars Earned: $_starsEarned / 3',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: theme.primaryColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Score: $_score / ${_questions.length}',
              style: TextStyle(fontSize: 16, color: textColor.withValues(alpha: 0.8)),
            ),
            if (_starsEarned < 2) ...[
              const SizedBox(height: 8),
              Text(
                'Get 2 stars to unlock the next level.',
                style: TextStyle(fontSize: 14, color: textColor.withValues(alpha: 0.7)),
              ),
            ],
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
      ),
    );
  }
}

/// Links an [_QuestionView] to its screen: the screen enables CHECK
/// while [isReady] and grades the answer with [grade].
class _AnswerController extends ChangeNotifier {
  bool _ready = false;
  bool Function()? _grader;

  bool get isReady => _ready;

  bool grade() => _grader?.call() ?? false;

  void _attach(bool Function() grader) => _grader = grader;

  void _setReady(bool ready) {
    if (_ready == ready) return;
    _ready = ready;
    notifyListeners();
  }

  void reset() {
    _grader = null;
    _ready = false;
    notifyListeners();
  }
}

/// Renders one activity question in its own type, the same layouts as
/// easyAct_mc.dart (multiple choice with text / picture / video options,
/// true or false, fill in the blank, typing with FSL letter pieces, sequence,
/// matching, identification). Give it a new key per question.
class _QuestionView extends StatefulWidget {
  final _Question question;
  final _AnswerController controller;

  /// After CHECK: answers are locked and right / wrong picks are shown.
  final bool revealed;

  const _QuestionView({
    super.key,
    required this.question,
    required this.controller,
    this.revealed = false,
  });

  /// The correct answer as text for the feedback ('' when it is a picture).
  static String answerLabel(_Question q) {
    switch (q.type) {
      case _QType.sequenceOrder:
        final parts = q.sequenceAnswer;
        return parts.any(_Media.isMedia) ? '' : parts.join(' → ');
      case _QType.matching:
        return '';
      default:
        return _Media.isMedia(q.correctAnswer) ? '' : q.correctAnswer;
    }
  }

  @override
  State<_QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends State<_QuestionView> {
  _Question get q => widget.question;
  bool get _locked => widget.revealed;

  static const Color _green = Color(0xFF58CC02);
  static const Color _red = Color(0xFFEA2B2B);

  // Multiple choice / true-false / fill in the blank
  String? _selected;
  late final List<String> _choices;

  // Typing
  List<String?> _slots = [];
  List<int?> _slotPiece = [];
  Set<int> _fixedSlots = {};
  Map<int, String> _givenImages = {};
  List<String> _pieces = [];

  // Sequence
  List<int> _sequence = [];
  late final List<String> _sequencePool;

  // Matching
  late final List<String> _leftItems;
  late final List<String> _rightItems;
  final Map<String, String> _matches = {};
  String? _pickedLeft;

  // Identification
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _choices = _buildChoices();
    _sequencePool = List<String>.from(q.sequenceAnswer)..shuffle();
    final pairs = q.matchingPairs;
    _leftItems = pairs.keys.toList();
    _rightItems = pairs.values.toList()..shuffle();
    if (q.type == _QType.typing) _setupTyping();
    widget.controller._attach(_grade);
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyReady());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  List<String> _buildChoices() {
    if (q.type == _QType.trueFalse) {
      return q.options.length == 2 ? q.options : const ['True', 'False'];
    }
    final opts = List<String>.from(q.options);
    // The answer is always a choice (some uploads list only the distractors).
    if (q.type == _QType.multipleChoice &&
        q.correctAnswer.isNotEmpty &&
        !opts.any((o) => _same(o, q.correctAnswer))) {
      opts.add(q.correctAnswer);
      opts.shuffle();
    }
    return opts;
  }

  // ---------------------------------------------------------------------------
  // Typing
  // ---------------------------------------------------------------------------

  static bool _isPieceChar(String c) => RegExp(r'[A-Za-z0-9ÑñÁÉÍÓÚáéíóú]').hasMatch(c);

  void _setupTyping() {
    final target = q.correctAnswer.toUpperCase();
    _slots = List<String?>.filled(target.length, null);
    _slotPiece = List<int?>.filled(target.length, null);
    _fixedSlots = {};
    _givenImages = {};
    // Spaces / punctuation of a phrase are part of the word, not pieces.
    for (var i = 0; i < target.length; i++) {
      if (!_isPieceChar(target[i])) {
        _slots[i] = target[i];
        _fixedSlots.add(i);
      }
    }
    for (final g in q.givenFsl) {
      if (g.position < 0 || g.position >= target.length) continue;
      _slots[g.position] = g.letter.isNotEmpty ? g.letter.toUpperCase() : target[g.position];
      _fixedSlots.add(g.position);
      _givenImages[g.position] = g.image;
    }
    if (q.options.isNotEmpty) {
      _pieces = q.options.map((o) => _isPieceText(o) ? o.toUpperCase() : o).toList()..shuffle();
    } else {
      // No pieces uploaded: the missing letters plus a few distractors.
      final missing = [
        for (var i = 0; i < target.length; i++)
          if (!_fixedSlots.contains(i)) target[i],
      ];
      const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      final extra = (letters.split('')..shuffle()).where((l) => !missing.contains(l)).take(3);
      _pieces = [...missing, ...extra]..shuffle();
    }
  }

  static bool _isPieceText(String v) => v.length <= 3 && !_Media.isMedia(v);

  void _tapPiece(int index) {
    if (_locked) return;
    final empty = _slots.indexOf(null);
    if (empty == -1) return;
    setState(() {
      _slots[empty] = _pieces[index];
      _slotPiece[empty] = index;
    });
    _notifyReady();
  }

  void _tapSlot(int index) {
    if (_locked || _fixedSlots.contains(index) || _slots[index] == null) return;
    setState(() {
      _slots[index] = null;
      _slotPiece[index] = null;
    });
    _notifyReady();
  }

  // ---------------------------------------------------------------------------
  // Grading
  // ---------------------------------------------------------------------------

  static String _norm(String v) => v
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _same(String a, String b) {
    if (_Media.isMedia(a) || _Media.isMedia(b)) return a.trim() == b.trim();
    return _norm(a) == _norm(b);
  }

  /// Fill in the blank: the word shown with its blank, and the piece that
  /// fills it. Docs store either the full word + a blank text ("BATA" +
  /// "B_TA") or the answer as the piece itself.
  String get _blankDisplay {
    if (q.blankText.contains('_')) return q.blankText;
    if (q.correctAnswer.contains('_')) return q.correctAnswer;
    return '';
  }

  bool _gradeBlank(String picked) {
    final display = _blankDisplay;
    final answer = q.correctAnswer;
    if (display.isEmpty || display == answer) {
      // The answer is the piece itself (or legacy docs with only "B_TA":
      // nothing to compare against, same as easyAct_mc.dart).
      return display.isEmpty ? _same(picked, answer) : true;
    }
    return _same(display.replaceFirst(RegExp(r'_+'), picked), answer) || _same(picked, answer);
  }

  bool _grade() {
    switch (q.type) {
      case _QType.typing:
        return _slots.join().toUpperCase() == q.correctAnswer.toUpperCase();
      case _QType.fillInTheBlank:
        return _selected != null && _gradeBlank(_selected!);
      case _QType.sequenceOrder:
        final built = [for (final i in _sequence) _sequencePool[i]];
        final answer = q.sequenceAnswer;
        if (built.length != answer.length) return false;
        for (var i = 0; i < built.length; i++) {
          if (!_same(built[i], answer[i])) return false;
        }
        return true;
      case _QType.matching:
        final pairs = q.matchingPairs;
        return pairs.entries.every((e) => _matches[e.key] == e.value);
      case _QType.identification:
        final typed = _textController.text;
        return q.correctAnswer.split('|').any((alt) => _same(typed, alt));
      default:
        return _selected != null && _same(_selected!, q.correctAnswer);
    }
  }

  bool get _isReady {
    switch (q.type) {
      case _QType.typing:
        return _slots.isNotEmpty && !_slots.contains(null);
      case _QType.sequenceOrder:
        return _sequence.length == _sequencePool.length;
      case _QType.matching:
        return _matches.length == _leftItems.length;
      case _QType.identification:
        return _textController.text.trim().isNotEmpty;
      default:
        return _selected != null;
    }
  }

  void _notifyReady() {
    if (mounted) widget.controller._setReady(_isReady);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (q.videoUrl.isNotEmpty || q.imageUrl.isNotEmpty) ...[
          Container(
            height: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _Media(source: q.videoUrl.isNotEmpty ? q.videoUrl : q.imageUrl, iconSize: 40),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (q.audioUrl.isNotEmpty) ...[
          Center(child: _AudioButton(url: q.audioUrl)),
          const SizedBox(height: 12),
        ],
        if (q.questionText.isNotEmpty) ...[
          Text(
            q.questionText,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textColor),
          ),
          const SizedBox(height: 20),
        ],
        switch (q.type) {
          _QType.typing => _buildTyping(theme),
          _QType.fillInTheBlank => _buildFillInBlank(theme),
          _QType.sequenceOrder => _buildSequence(theme),
          _QType.matching => _buildMatching(theme),
          _QType.identification => _buildIdentification(theme),
          _QType.trueFalse => _buildTrueFalse(theme),
          _ => _buildMultipleChoice(theme),
        },
      ],
    );
  }

  /// Fill / border of a pickable choice before and after CHECK.
  (Color fill, Color border, Color text) _choiceColors(String option, ThemeData theme) {
    final isSelected = option == _selected;
    if (!_locked) {
      return (
        isSelected ? theme.primaryColor.withValues(alpha: 0.2) : theme.cardColor,
        isSelected ? theme.primaryColor : theme.dividerColor,
        theme.colorScheme.onSurface,
      );
    }
    final bool isRight = q.type == _QType.fillInTheBlank ? _gradeBlank(option) : _same(option, q.correctAnswer);
    if (isRight) return (_green, _green, Colors.white);
    if (isSelected) return (_red, _red, Colors.white);
    return (theme.cardColor, theme.dividerColor, theme.colorScheme.onSurface);
  }

  void _select(String option) {
    if (_locked) return;
    setState(() => _selected = option);
    _notifyReady();
  }

  Widget _buildMultipleChoice(ThemeData theme) {
    final hasMedia = _choices.any(_Media.isMedia);
    final longText = !hasMedia && _choices.any((o) => o.length > 14);
    if (longText) {
      // Phrases / civic answers are often sentences: one per row.
      return Column(
        children: [
          for (final option in _choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _choiceTile(option, theme, height: null),
            ),
        ],
      );
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: hasMedia ? 1.1 : 2.2,
      children: [for (final option in _choices) _choiceTile(option, theme)],
    );
  }

  Widget _choiceTile(String option, ThemeData theme, {double? height = double.infinity}) {
    final (fill, border, text) = _choiceColors(option, theme);
    return GestureDetector(
      onTap: () => _select(option),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: height,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: height == null ? 16 : 6),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 2),
        ),
        alignment: Alignment.center,
        child: _Media.isMedia(option)
            ? ClipRRect(borderRadius: BorderRadius.circular(10), child: _Media(source: option, iconSize: 28))
            : Text(
                option,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: option.length > 14 ? 16 : 20, fontWeight: FontWeight.w800, color: text),
              ),
      ),
    );
  }

  Widget _buildTrueFalse(ThemeData theme) {
    return Row(
      children: [
        for (var i = 0; i < _choices.length; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          Expanded(child: SizedBox(height: 80, child: _choiceTile(_choices[i], theme))),
        ],
      ],
    );
  }

  Widget _buildFillInBlank(ThemeData theme) {
    var display = _blankDisplay;
    if (display.isNotEmpty && _selected != null && !_Media.isMedia(_selected!)) {
      display = display.replaceFirst(RegExp(r'_+'), _selected!);
    }
    return Column(
      children: [
        if (display.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Text(
              display,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 3, color: theme.colorScheme.onSurface),
            ),
          ),
          const SizedBox(height: 28),
        ],
        Wrap(
          spacing: 14,
          runSpacing: 14,
          alignment: WrapAlignment.center,
          children: [
            for (final option in _choices)
              SizedBox(
                width: option.length > 3 || _Media.isMedia(option) ? 140 : 70,
                height: _Media.isMedia(option) ? 110 : 70,
                child: _choiceTile(option, theme),
              ),
          ],
        ),
      ],
    );
  }

  /// FSL hand-sign picture for a letter / number piece, or the piece itself
  /// when it is already a picture.
  static String? _signImageFor(String value) {
    final v = value.trim();
    if (_Media.isMedia(v)) return v;
    if (RegExp(r'^[A-Za-z]$').hasMatch(v)) return 'assets/pictures/${v.toUpperCase()}.jpg';
    if (RegExp(r'^([1-9]|10)$').hasMatch(v)) return 'assets/pictures/$v.png';
    return null;
  }

  Widget _signTile(String value, TextStyle style, {String? image}) {
    final src = (image != null && image.isNotEmpty) ? image : _signImageFor(value);
    if (src == null) return Text(value, style: style);
    return _Media(source: src, fallback: Text(value, style: style));
  }

  Widget _buildTyping(ThemeData theme) {
    final slotText = TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface);
    final bool? right = _locked ? _grade() : null;
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: List.generate(_slots.length, (i) {
            final char = _slots[i];
            final isGiven = _givenImages.containsKey(i);
            final isSpace = _fixedSlots.contains(i) && !isGiven;
            if (isSpace) return SizedBox(width: char == ' ' ? 18 : 14, height: 64, child: Center(child: Text(char ?? '', style: slotText)));
            final Color border = right == null
                ? (char != null ? theme.primaryColor : theme.dividerColor)
                : (right ? _green : _red);
            return GestureDetector(
              onTap: () => _tapSlot(i),
              child: Container(
                width: 52,
                height: 64,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: char == null ? theme.cardColor : theme.primaryColor.withValues(alpha: isGiven ? 0.08 : 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border, width: 2),
                ),
                alignment: Alignment.center,
                child: char == null
                    ? const SizedBox.shrink()
                    : isGiven
                        ? _signTile(char, slotText, image: _givenImages[i])
                        : (_Media.isMedia(char) ? _Media(source: char) : Text(char, style: slotText)),
              ),
            );
          }),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: List.generate(_pieces.length, (i) {
            final used = _slotPiece.contains(i);
            return GestureDetector(
              onTap: used ? null : () => _tapPiece(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: used ? theme.dividerColor.withValues(alpha: 0.3) : theme.cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: used ? Colors.transparent : theme.primaryColor, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Opacity(
                  opacity: used ? 0.3 : 1.0,
                  child: _signTile(_pieces[i], TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _sequenceChip(String value, ThemeData theme, {required bool placed, Color? border}) {
    final media = _Media.isMedia(value);
    return Container(
      width: media ? 72 : null,
      height: media ? 72 : null,
      padding: EdgeInsets.symmetric(horizontal: media ? 4 : 14, vertical: media ? 4 : 10),
      decoration: BoxDecoration(
        color: placed ? theme.primaryColor.withValues(alpha: 0.18) : theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border ?? (placed ? theme.primaryColor : theme.dividerColor), width: 2),
      ),
      child: media
          ? ClipRRect(borderRadius: BorderRadius.circular(10), child: _Media(source: value))
          : Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
    );
  }

  Widget _buildSequence(ThemeData theme) {
    final answer = q.sequenceAnswer;
    return Column(
      children: [
        Text(
          'Tap the pieces in the correct order:',
          style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withValues(alpha: 0.8)),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var pos = 0; pos < _sequence.length; pos++)
                GestureDetector(
                  onTap: _locked
                      ? null
                      : () {
                          setState(() => _sequence.removeAt(pos));
                          _notifyReady();
                        },
                  child: _sequenceChip(
                    _sequencePool[_sequence[pos]],
                    theme,
                    placed: true,
                    border: !_locked
                        ? null
                        : (pos < answer.length && _same(_sequencePool[_sequence[pos]], answer[pos]) ? _green : _red),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < _sequencePool.length; i++)
              if (!_sequence.contains(i))
                GestureDetector(
                  onTap: _locked
                      ? null
                      : () {
                          setState(() => _sequence.add(i));
                          _notifyReady();
                        },
                  child: _sequenceChip(_sequencePool[i], theme, placed: false),
                ),
          ],
        ),
      ],
    );
  }

  Widget _matchTile(String item, ThemeData theme, {required Color fill, required Color border, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 80,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 2),
        ),
        alignment: Alignment.center,
        child: _Media.isMedia(item)
            ? _Media(source: item, iconSize: 32)
            : Text(
                item,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
              ),
      ),
    );
  }

  Widget _buildMatching(ThemeData theme) {
    final pairs = q.matchingPairs;
    // Each matched pair gets its own color so the learner sees what goes together.
    const pairColors = [Color(0xFF4DD0E1), Color(0xFFFFB74D), Color(0xFFBA68C8), Color(0xFFAED581), Color(0xFFFF8A80), Color(0xFF90CAF9)];
    Color colorOf(String left) => pairColors[_leftItems.indexOf(left) % pairColors.length];

    return Column(
      children: [
        Text(
          'Tap an item on the left, then its match on the right.',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withValues(alpha: 0.8)),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final left in _leftItems)
                    () {
                      final matched = _matches.containsKey(left);
                      final picked = _pickedLeft == left;
                      Color border = picked ? theme.primaryColor : theme.dividerColor;
                      Color fill = picked ? theme.primaryColor.withValues(alpha: 0.25) : theme.cardColor;
                      if (matched) {
                        border = _locked ? (_matches[left] == pairs[left] ? _green : _red) : colorOf(left);
                        fill = border.withValues(alpha: 0.18);
                      }
                      return _matchTile(left, theme, fill: fill, border: border, onTap: _locked
                          ? null
                          : () {
                              setState(() {
                                // Tap a matched item again to undo its match.
                                if (matched) {
                                  _matches.remove(left);
                                  _pickedLeft = null;
                                } else {
                                  _pickedLeft = left;
                                }
                              });
                              _notifyReady();
                            });
                    }(),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                children: [
                  for (final right in _rightItems)
                    () {
                      final owner = _matches.entries.where((e) => e.value == right).map((e) => e.key).firstOrNull;
                      Color border = theme.dividerColor;
                      Color fill = theme.cardColor;
                      if (owner != null) {
                        border = _locked ? (pairs[owner] == right ? _green : _red) : colorOf(owner);
                        fill = border.withValues(alpha: 0.18);
                      }
                      return _matchTile(right, theme, fill: fill, border: border, onTap: (_locked || owner != null || _pickedLeft == null)
                          ? null
                          : () {
                              setState(() {
                                _matches[_pickedLeft!] = right;
                                _pickedLeft = null;
                              });
                              _notifyReady();
                            });
                    }(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdentification(ThemeData theme) {
    final bool? right = _locked ? _grade() : null;
    final Color border = right == null ? theme.primaryColor : (right ? _green : _red);
    return TextField(
      controller: _textController,
      enabled: !_locked,
      textAlign: TextAlign.center,
      textCapitalization: TextCapitalization.sentences,
      onChanged: (_) => _notifyReady(),
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        hintText: 'Type your answer',
        filled: true,
        fillColor: theme.cardColor,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: theme.dividerColor, width: 2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border, width: 2)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border, width: 2)),
      ),
    );
  }
}

/// A question / option picture or sign video: network URL, bundled asset or
/// base64 image; videos (mp4, mov, webm) loop muted.
class _Media extends StatelessWidget {
  final String source;
  final BoxFit fit = BoxFit.contain;
  final double iconSize;
  final Widget? fallback;

  const _Media({required this.source, this.iconSize = 24, this.fallback});

  static final RegExp _imageExt = RegExp(r'\.(png|jpe?g|webp|gif)$', caseSensitive: false);
  static final RegExp _videoExt = RegExp(r'\.(mp4|mov|webm|m4v)$', caseSensitive: false);

  static String _path(String v) => Uri.decodeComponent(v.split('?').first);

  static bool isVideo(String v) => _videoExt.hasMatch(_path(v.trim()));

  /// A picture or video rather than answer text.
  static bool isMedia(String v) {
    final s = v.trim();
    if (s.isEmpty) return false;
    return s.startsWith('data:image') ||
        s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('assets/') ||
        _imageExt.hasMatch(_path(s)) ||
        isVideo(s) ||
        (s.length > 100 && !s.contains(' '));
  }

  static Uint8List? _decodeBase64(String input) {
    try {
      var cleaned = input.contains(',') ? input.split(',').last : input;
      cleaned = cleaned.replaceAll(RegExp(r'\s+'), '').replaceAll('-', '+').replaceAll('_', '/');
      return base64Decode(base64.normalize(cleaned));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = source.trim();
    final broken = fallback ?? Icon(Icons.image_not_supported, size: iconSize, color: Colors.grey);
    if (s.isEmpty) return broken;
    if (isVideo(s)) return _LoopingVideo(url: s, fit: fit, fallback: broken);
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return Image.network(
        s,
        fit: fit,
        errorBuilder: (_, __, ___) => broken,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (s.startsWith('assets/')) return Image.asset(s, fit: fit, errorBuilder: (_, __, ___) => broken);
    final bytes = _decodeBase64(s);
    if (bytes != null) return Image.memory(bytes, fit: fit, errorBuilder: (_, __, ___) => broken);
    return broken;
  }
}

class _LoopingVideo extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final Widget fallback;

  const _LoopingVideo({required this.url, required this.fit, required this.fallback});

  @override
  State<_LoopingVideo> createState() => _LoopingVideoState();
}

class _LoopingVideoState extends State<_LoopingVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final url = widget.url;
    final c = url.startsWith('assets/')
        ? VideoPlayerController.asset(url)
        : VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Activity video unavailable ($url): $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed) return widget.fallback;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return FittedBox(
      fit: widget.fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
    );
  }
}

/// Plays the question's audio clip (audioStoragePath in the doc).
class _AudioButton extends StatefulWidget {
  final String url;
  const _AudioButton({required this.url});

  @override
  State<_AudioButton> createState() => _AudioButtonState();
}

class _AudioButtonState extends State<_AudioButton> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    setState(() => _loading = true);
    try {
      await _player.setUrl(widget.url);
      _player.play();
    } catch (e) {
      debugPrint('Activity audio unavailable: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilledButton.icon(
      onPressed: _loading ? null : _play,
      style: FilledButton.styleFrom(backgroundColor: theme.primaryColor),
      icon: _loading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.volume_up_rounded),
      label: const Text('Play audio'),
    );
  }
}

/// Question types the activity screens render (same set as easyAct_mc.dart).
/// Web app type names are mapped onto these by [_Question.normalizeType].
class _QType {
  static const multipleChoice = 'multiple_choice'; // sign_to_text, text_to_sign, pecs
  static const trueFalse = 'true_false';
  static const fillInTheBlank = 'fill_in_the_blank';
  static const typing = 'typing'; // spell the answer with FSL letter pieces
  static const sequenceOrder = 'sequence_order';
  static const matching = 'matching_type';
  static const identification = 'identification'; // free text answer
  static const camera = 'camera_spell'; // not playable on these screens
}

/// A slot of a typing question that is already filled (hint), shown as its
/// FSL hand sign.
class _GivenFsl {
  final int position;
  final String letter;
  final String image;

  const _GivenFsl({required this.position, required this.letter, required this.image});
}

/// One `activity_questions` document, normalized: the web app content tool
/// and older uploads use different field names for the same thing.
class _Question {
  final String id;
  final String type;
  final String rawType;
  final String level;
  final String category;
  final String questionText;
  final String correctAnswer;
  final List<String> options;

  /// Text for fill-in-the-blank (e.g. "B_TA"), when the doc has one.
  final String blankText;

  /// Picture / sign video shown above the question ('' when none).
  final String imageUrl;
  final String videoUrl;
  final String audioUrl;
  final List<_GivenFsl> givenFsl;

  /// Answer pieces in the correct order (sequence questions), when the doc
  /// stores it apart from the options.
  final List<String> correctOrder;

  const _Question({
    required this.id,
    required this.type,
    required this.rawType,
    required this.level,
    required this.category,
    required this.questionText,
    required this.correctAnswer,
    required this.options,
    this.blankText = '',
    this.imageUrl = '',
    this.videoUrl = '',
    this.audioUrl = '',
    this.givenFsl = const [],
    this.correctOrder = const [],
  });

  bool get isCamera => type == _QType.camera;

  /// Sequence pieces in the correct order.
  List<String> get sequenceAnswer => correctOrder.isNotEmpty ? correctOrder : options;

  /// Matching pairs (left -> right) from "left|||right" options.
  Map<String, String> get matchingPairs => {
        for (final o in options)
          if (o.contains('|||')) o.split('|||')[0]: o.split('|||')[1] else o: o,
      };

  /// The doc value of the first key present (case-insensitive, non-empty).
  static dynamic pick(Map<String, dynamic> data, List<String> keys) {
    final lower = {for (final k in data.keys) k.toLowerCase(): k};
    for (final key in keys) {
      final real = lower[key.toLowerCase()];
      if (real == null) continue;
      final v = data[real];
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      if (v is List && v.isEmpty) continue;
      return v;
    }
    return null;
  }

  static String _str(dynamic v) => v == null ? '' : v.toString().trim();

  static List<String> _strList(dynamic v) {
    if (v is List) return [for (final e in v) if (e != null && e.toString().trim().isNotEmpty) e.toString().trim()];
    if (v is String && v.trim().isNotEmpty) {
      return v.split(RegExp(r'[,;\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  /// Web app / legacy type names -> [_QType].
  static String normalizeType(String raw, List<String> options) {
    final t = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    if (t.contains('camera') || t.contains('sign_it')) return _QType.camera;
    if (t.contains('typing') || t.contains('type_the') || t == 'spell' || t == 'spelling') {
      return _QType.typing;
    }
    if (t.contains('blank') || t == 'fill_in' || t == 'fill') return _QType.fillInTheBlank;
    if (t.contains('sequence') || t.contains('order')) return _QType.sequenceOrder;
    if (t.contains('match')) return _QType.matching;
    if (t.contains('true') || t == 'tf' || t == 'boolean') return _QType.trueFalse;
    if (t.contains('ident') || t.contains('short_answer') || t.contains('free_text')) {
      return _QType.identification;
    }
    if (t.isNotEmpty) {
      // sign_to_text, text_to_sign, pecs, multiple_choice, mc, ...
      if (options.isNotEmpty) return _QType.multipleChoice;
    }
    if (options.isEmpty) return _QType.identification;
    final lowerOpts = options.map((e) => e.toLowerCase()).toSet();
    if (options.length == 2 && lowerOpts.contains('true') && lowerOpts.contains('false')) {
      return _QType.trueFalse;
    }
    return _QType.multipleChoice;
  }

  factory _Question.fromMap(Map<String, dynamic> data, {String? id, String fallbackCategory = ''}) {
    final options = _strList(pick(data, ['options', 'choices', 'answers', 'letters', 'pieces']));
    final rawType = _str(pick(data, ['type', 'question_type', 'questionType', 'activity_type']));
    var type = normalizeType(rawType, options);

    final givenRaw = pick(data, ['given_fsl', 'givenFsl', 'given_letters', 'hints']);
    final given = <_GivenFsl>[];
    if (givenRaw is List) {
      for (final e in givenRaw) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final pos = pick(m, ['position', 'index', 'pos']);
        given.add(_GivenFsl(
          position: pos is num ? pos.toInt() : int.tryParse(_str(pos)) ?? -1,
          letter: _str(pick(m, ['letter', 'number', 'value', 'char'])),
          image: _str(pick(m, ['image_url', 'imageUrl', 'image', 'url'])),
        ));
      }
    }

    var answer = _str(pick(data, ['correct_answer', 'correctAnswer', 'answer', 'correct', 'right_answer']));
    // True / false docs sometimes store a bool.
    if (type == _QType.trueFalse) {
      final b = pick(data, ['correct_answer', 'correctAnswer', 'answer', 'correct', 'is_true', 'isTrue']);
      if (b is bool) answer = b ? 'True' : 'False';
    }

    return _Question(
      id: id ?? _str(data['id']),
      type: type,
      rawType: rawType,
      level: _str(pick(data, ['level', 'levelId', 'level_id'])),
      category: _str(pick(data, ['category'])).isEmpty ? fallbackCategory : _str(pick(data, ['category'])),
      questionText: _str(pick(data, ['question_text', 'questionText', 'question', 'prompt', 'title', 'phrase', 'instruction'])),
      correctAnswer: answer,
      options: options,
      blankText: _str(pick(data, ['blank_text', 'blankText', 'display_text', 'displayText', 'word_with_blank', 'question_word'])),
      imageUrl: _str(pick(data, [
        'main_image', 'mainImage', 'image_url', 'imageUrl', 'image', 'picture', 'photo', 'photo_url', 'img', 'imagePath',
        'imageStoragePath', 'image_storage_path',
      ])),
      videoUrl: _str(pick(data, [
        'video_url', 'videoUrl', 'video', 'main_video', 'mainVideo', 'sign_video', 'videoStoragePath', 'video_storage_path',
      ])),
      audioUrl: _str(pick(data, ['audioUrl', 'audio_url', 'audio', 'audioStoragePath', 'audio_storage_path'])),
      givenFsl: given,
      correctOrder: _strList(pick(data, ['correct_order', 'correctOrder', 'answer_order', 'sequence'])),
    );
  }

  _Question copyWith({
    String? imageUrl,
    String? videoUrl,
    String? audioUrl,
    List<String>? options,
    String? correctAnswer,
    List<_GivenFsl>? givenFsl,
    List<String>? correctOrder,
  }) {
    return _Question(
      id: id,
      type: type,
      rawType: rawType,
      level: level,
      category: category,
      questionText: questionText,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      options: options ?? this.options,
      blankText: blankText,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      givenFsl: givenFsl ?? this.givenFsl,
      correctOrder: correctOrder ?? this.correctOrder,
    );
  }
}

/// Loads a level's questions for any category (phrases, civic, ...) from
/// `activity_questions`, the same way easyAct_mc.dart does for alphabet:
/// every question of the level in its own type, short levels topped up with
/// review questions, and Firebase Storage paths turned into download URLs.
class _QuestionRepository {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  _QuestionRepository({FirebaseFirestore? db, FirebaseStorage? storage})
      : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  /// Questions a level should have; shorter levels get review questions.
  static const int minQuestionsPerLevel = 4;
  static const int maxQuestionsPerLevel = 5;

  /// The category values the web app may have written for a module.
  static List<String> categoryAliases(String category) {
    final base = category.trim().toLowerCase();
    final names = <String>{base};
    if (base.startsWith('phrase')) names.addAll(['phrase', 'phrases']);
    if (base.startsWith('civic')) names.addAll(['civic', 'civics', 'civic_observances', 'civic observances']);
    if (base.startsWith('number')) names.addAll(['number', 'numbers']);
    return {
      for (final n in names) ...[n, n[0].toUpperCase() + n.substring(1), n.toUpperCase()],
    }.toList();
  }

  Future<List<_Question>> fetchLevel({
    required String category,
    required String levelId,
    bool topUp = true,
  }) async {
    final aliases = categoryAliases(category);
    final snap = await _db
        .collection('activity_questions')
        .where('level', isEqualTo: levelId)
        .where('category', whereIn: aliases)
        .get();

    var questions = [
      for (final doc in snap.docs) _Question.fromMap(doc.data(), id: doc.id, fallbackCategory: category),
    ].where(_playable).toList();

    if (topUp && questions.length < minQuestionsPerLevel) {
      questions = [
        ...questions,
        ...await _reviewQuestions(aliases, category, levelId, questions, minQuestionsPerLevel - questions.length),
      ];
    }
    questions.shuffle();
    return resolveMedia(questions.take(maxQuestionsPerLevel).toList());
  }

  /// Questions handed in by the caller (raw maps, e.g. from a cache).
  Future<List<_Question>> fromMaps(List<Map<String, dynamic>> maps, {required String category}) {
    final list = [
      for (var i = 0; i < maps.length; i++)
        _Question.fromMap(maps[i], id: (maps[i]['id'] ?? '${category}_q_$i').toString(), fallbackCategory: category),
    ].where(_playable).toList();
    return resolveMedia(list);
  }

  /// Camera questions need the recognition pipeline of their own screen;
  /// a question without an answer cannot be graded.
  static bool _playable(_Question q) {
    if (q.isCamera) {
      debugPrint('Skipping camera question ${q.id} (not supported on this screen).');
      return false;
    }
    switch (q.type) {
      case _QType.sequenceOrder:
        return q.options.isNotEmpty || q.correctOrder.isNotEmpty;
      case _QType.matching:
        return q.options.isNotEmpty;
      default:
        return q.correctAnswer.isNotEmpty;
    }
  }

  /// Up to [count] questions from other levels of the same difficulty
  /// (e.g. 'phrases_easy_*' for 'phrases_easy_3'), never an answer the level
  /// already asks.
  Future<List<_Question>> _reviewQuestions(
    List<String> aliases,
    String category,
    String levelId,
    List<_Question> current,
    int count,
  ) async {
    final cut = levelId.lastIndexOf('_');
    if (cut <= 0 || count <= 0) return [];
    final prefix = levelId.substring(0, cut + 1);
    try {
      final snap = await _db.collection('activity_questions').where('category', whereIn: aliases).get();
      final answers = {for (final q in current) q.correctAnswer.toLowerCase()};
      final types = {for (final q in current) q.type};
      final pool = <_Question>[];
      for (final doc in snap.docs) {
        final q = _Question.fromMap(doc.data(), id: doc.id, fallbackCategory: category);
        if (!q.level.startsWith(prefix) || q.level == levelId || !_playable(q)) continue;
        if (answers.contains(q.correctAnswer.toLowerCase())) continue;
        pool.add(q);
      }
      pool.shuffle();
      pool.sort((a, b) => (types.contains(a.type) ? 0 : 1).compareTo(types.contains(b.type) ? 0 : 1));
      final picked = <_Question>[];
      for (final q in pool) {
        if (picked.length >= count) break;
        if (answers.add(q.correctAnswer.toLowerCase())) picked.add(q);
      }
      return picked;
    } catch (e) {
      debugPrint('Review questions unavailable for $levelId: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Firebase Storage paths -> download URLs
  // ---------------------------------------------------------------------------

  final Map<String, String> _urlCache = {};

  static final RegExp _mediaExt = RegExp(r'\.(png|jpe?g|webp|gif|mp4|mov|webm|m4v|mp3|m4a|wav|aac|ogg)$', caseSensitive: false);

  /// A Storage object path ("phrases/hello.mp4", "gs://bucket/x.png"), not a
  /// URL, bundled asset, base64 image or plain answer text.
  static bool isStoragePath(String v) {
    final s = v.trim();
    if (s.isEmpty) return false;
    if (s.startsWith('gs://')) return true;
    if (s.startsWith('http://') || s.startsWith('https://') || s.startsWith('data:') || s.startsWith('assets/')) {
      return false;
    }
    return s.contains('/') && _mediaExt.hasMatch(s);
  }

  Future<String> _resolve(String v) async {
    if (!isStoragePath(v)) return v;
    final cached = _urlCache[v];
    if (cached != null) return cached;
    try {
      final ref = v.startsWith('gs://') ? _storage.refFromURL(v) : _storage.ref(v);
      final url = await ref.getDownloadURL().timeout(const Duration(seconds: 8));
      _urlCache[v] = url;
      return url;
    } catch (e) {
      debugPrint('Storage URL unavailable for $v: $e');
      return v;
    }
  }

  /// Resolves the media of every question. Options and the answer are
  /// resolved with the same mapping, so grading still compares equal values.
  Future<List<_Question>> resolveMedia(List<_Question> questions) {
    return Future.wait(questions.map((q) async {
      final options = await Future.wait(q.options.map(_resolveOption));
      final order = await Future.wait(q.correctOrder.map(_resolve));
      final given = await Future.wait(q.givenFsl.map((g) async =>
          _GivenFsl(position: g.position, letter: g.letter, image: await _resolve(g.image))));
      return q.copyWith(
        imageUrl: await _resolve(q.imageUrl),
        videoUrl: await _resolve(q.videoUrl),
        audioUrl: await _resolve(q.audioUrl),
        options: options,
        correctAnswer: await _resolve(q.correctAnswer),
        givenFsl: given,
        correctOrder: order,
      );
    }));
  }

  /// Matching options are "left|||right"; each side may be a Storage path.
  Future<String> _resolveOption(String option) async {
    if (!option.contains('|||')) return _resolve(option);
    final parts = option.split('|||');
    return (await Future.wait(parts.map(_resolve))).join('|||');
  }
}
