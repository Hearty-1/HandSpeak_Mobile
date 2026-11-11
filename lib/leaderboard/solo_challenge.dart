import '/widgets/activity_feedback.dart';
import '/widgets/challenge_feedback.dart';
import '/module/custom_category_screen.dart' show PublishedCameraSign;
import '/widgets/button_3d.dart';
import 'dart:async';
import 'dart:convert';
import '/services/challenge_categories.dart';
import '/widgets/activity_video.dart';
import '/widgets/media_prefetch.dart';
import 'package:flutter/material.dart';
import '/widgets/challenge_camera_sign.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '/providers/sound_provider.dart';
import '/providers/theme_provider.dart';
import '/services/progress_service.dart';


// ==========================================
// 1. SOLO CHALLENGE SETUP SCREEN
// ==========================================
class SoloChallengeSetupScreen extends StatefulWidget {
  const SoloChallengeSetupScreen({super.key});

  @override
  State<SoloChallengeSetupScreen> createState() => _SoloChallengeSetupScreenState();
}

class _SoloChallengeSetupScreenState extends State<SoloChallengeSetupScreen> {
  // Game music while this screen is open (see SoundProvider.claimBgm).
  late final SoundProvider _bgm;

  @override
  void dispose() {
    _bgm.releaseBgm(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    ChallengeCategories.load().then((c) {
      if (mounted) setState(() => _categories = c);
    });
    _bgm = Provider.of<SoundProvider>(context, listen: false)..claimBgm(this, BgmType.activity); // gamebgm.mp3
  }

  String _selectedCategory = 'Alphabet';
  int _selectedRounds = 10;
  int _selectedTimer = 15;

  /// Built-in modules + the web app's categories (services/challenge_categories.dart).
  List<({String value, String label})> _categories = ChallengeCategories.builtIn;
  final List<int> _roundsOptions = [5, 10, 15, 20];
  final List<int> _timerOptions = [10, 15, 30, 0];

  void _startSoloMatch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameProperScreen(
          roomCode: 'SOLO',
          challengeTitle: 'Solo ${_categories.where((c) => c.value == _selectedCategory).map((c) => c.label).firstOrNull ?? _selectedCategory} Challenge',
          isHost: true,
          category: _selectedCategory,
          totalRounds: _selectedRounds,
          timerDuration: _selectedTimer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Solo Challenge",
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w900,
            fontFamily: 'Inter',
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.cardColor.withValues(alpha: isDark ? 0.6 : 0.9),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: theme.primaryColor.withValues(alpha: 0.15), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: theme.primaryColor.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [theme.primaryColor.withValues(alpha: 0.2), theme.primaryColor.withValues(alpha: 0.05)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: theme.primaryColor.withValues(alpha: 0.2), blurRadius: 12),
                        ],
                      ),
                      child: Icon(Icons.bolt_rounded, size: 40, color: theme.primaryColor),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Practice Mode",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, fontFamily: 'Inter', color: textColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Level up your sign language mastery at your own rhythm.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textColor.withValues(alpha: 0.65), fontSize: 13, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Text("⚡ Category", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textColor)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: textColor.withValues(alpha: 0.1)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    isExpanded: true,
                    dropdownColor: theme.cardColor,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: theme.primaryColor),
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15),
                    items: _categories.map((c) => DropdownMenuItem(value: c.value, child: Text(c.label))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCategory = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text("🎯 Total Rounds", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textColor)),
              const SizedBox(height: 10),
              Row(
                children: _roundsOptions.map((rounds) {
                  final bool isSelected = _selectedRounds == rounds;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRounds = rounds),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? theme.primaryColor : textColor.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: isSelected
                              ? [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]
                              : null,
                          border: Border.all(color: isSelected ? theme.primaryColor : textColor.withValues(alpha: 0.1)),
                        ),
                        child: Text(
                          "$rounds",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: isSelected ? theme.colorScheme.onPrimary : textColor,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              Text("⏱️ Timer Per Question", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textColor)),
              const SizedBox(height: 10),
              Row(
                children: _timerOptions.map((timerSec) {
                  final bool isSelected = _selectedTimer == timerSec;
                  final String label = timerSec == 0 ? "Untimed" : "${timerSec}s";
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTimer = timerSec),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFF34B1B) : textColor.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: isSelected
                              ? [BoxShadow(color: const Color(0xFFF34B1B).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]
                              : null,
                          border: Border.all(color: isSelected ? const Color(0xFFF34B1B) : textColor.withValues(alpha: 0.1)),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: isSelected ? Colors.white : textColor,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),

              Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [theme.primaryColor, theme.primaryColor.withBlue(220)],
                  ),
                  boxShadow: [
                    BoxShadow(color: theme.primaryColor.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5)),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _startSoloMatch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: Button3DBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: Text(
                    "START MATCH",
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. GAME PROPER SCREEN
// ==========================================
class GameProperScreen extends StatefulWidget {
  final String roomCode;
  final String challengeTitle;
  final bool isHost;
  final String category;
  final int totalRounds;
  final int timerDuration;

  const GameProperScreen({
    super.key,
    required this.roomCode,
    required this.challengeTitle,
    required this.isHost,
    this.category = 'Alphabet',
    this.totalRounds = 10,
    this.timerDuration = 15,
  });

  @override
  State<GameProperScreen> createState() => _GameProperScreenState();
}

class _GameProperScreenState extends State<GameProperScreen> {
  // Game music while this screen is open (see SoundProvider.claimBgm).
  late final SoundProvider _bgm;

  late String _currentUserId;

  List<Map<String, dynamic>> _questions = [];
  int _currentQuestionIndex = 0;
  int _score = 0;
  int _streak = 0;
  int _correctCount = 0;

  // For the solo_challenges record: best streak, one entry per question, start.
  int _peakStreak = 0;
  int _lastPoints = 0; // shown in the feedback (+N pts)
  final List<Map<String, dynamic>> _questionLogs = [];
  DateTime _startedAt = DateTime.now();

  bool _isLoading = true;
  bool _hasAnswered = false;
  bool _isLastAnswerCorrect = false;
  String _selectedAnswer = '';

  final TextEditingController _identificationController = TextEditingController();

  List<String?> _userAnswerSlots = [];
  List<int?> _selectedOptionIndices = [];
  List<String> _shuffledOptions = [];
  /// Typing: slots pre-filled by `given_fsl` (position -> FSL image, may be ''),
  /// shown as hand-sign hints and not removable (same as easyAct_mc.dart).
  Map<int, String> _givenFslImages = {};

  List<String> _currentSequence = [];
  List<String> _availableSequenceOptions = [];

  Map<String, String?> _matchingAnswers = {};
  String? _selectedLeftMatch;
  List<String> _matchingLeftItems = [];
  List<String> _matchingRightItems = [];






  double _currentScore = 0.0;
  // Camera answers (widgets/challenge_camera_sign.dart): the model that
  // judged the last one (gesture_attempts modelVersion).
  String? _lastCameraModel;
  final double successThreshold = 70.0;



  Timer? _timer;
  int _timeLeft = 15;
  late int _maxTime;
  late int _totalRounds;
  late String _category;

  @override
  void initState() {
    super.initState();
    _bgm = Provider.of<SoundProvider>(context, listen: false)..claimBgm(this, BgmType.activity); // gamebgm.mp3
    _maxTime = widget.timerDuration;
    _totalRounds = widget.totalRounds;
    _category = widget.category;
    _initUser();
    _setupGameAndPlayer();
  }

  @override
  void dispose() {
    _bgm.releaseBgm(this);
    _timer?.cancel();
    _identificationController.dispose();
    super.dispose();
  }

  void _initUser() {
    final user = FirebaseAuth.instance.currentUser;
    _currentUserId = user?.uid ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';
  }



  /// G, H, K, P, Q: tricky letters (horizontal or crossing fingers). Scored in
  /// 2D only (no z noise), scale from wrist->middle base or the index reach,
  /// fingertips weighted 1.5x, a relaxed curve, and G/H/P/Q locked to the
  /// sideways orientations.

  dynamic _getValueCaseInsensitive(Map<String, dynamic> map, List<String> possibleKeys) {
    for (var key in possibleKeys) {
      if (map.containsKey(key) && map[key] != null) return map[key];
    }
    return null;
  }

  bool _isImageString(String str) {
    final s = str.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('data:image') ||
        s.startsWith('assets/')) {
      return true;
    }
    if (s.endsWith('.png') ||
        s.endsWith('.jpg') ||
        s.endsWith('.jpeg') ||
        s.endsWith('.webp') ||
        s.endsWith('.gif') ||
        s.endsWith('.svg')) {
      return true;
    }
    if (s.length > 100 && (s.startsWith('ivborw0kggo') || s.startsWith('/9j/') || s.startsWith('r0lgod') || s.startsWith('uklgr'))) {
      return true;
    }
    return false;
  }

  Future<void> _setupGameAndPlayer() async {
    try {
      if (widget.roomCode != 'SOLO') {
        final roomDoc = await FirebaseFirestore.instance.collection('rooms').doc(widget.roomCode).get();
        if (roomDoc.exists) {
          final data = roomDoc.data()!;
          _maxTime = data['timerDuration'] ?? 15;
          _totalRounds = data['totalRounds'] ?? 10;
          _category = (data['category'] ?? 'Alphabet').toString();
        }
      }

      // This category's questions only (cached for the session).
      final allQuestions = await ChallengeCategories.questionsFor(_category);
      if (allQuestions.isNotEmpty) {
        var filtered = allQuestions.where((q) {
          return ChallengeCategories.matches(_getValueCaseInsensitive(q, ['category', 'topic', 'group', 'tag'])?.toString(), _category);
        }).toList();

        // Only this category's questions (no fall-back to every category).
        filtered.shuffle();

        if (mounted) {
          setState(() {
            _questions = filtered.take(_totalRounds).toList();
            _isLoading = false;
            _score = 0;
            _streak = 0;
            _correctCount = 0;
            _peakStreak = 0;
            _questionLogs.clear();
            _startedAt = DateTime.now();
          });
        }

        // This round's pictures / videos load in the background now.
        if (mounted) MediaPrefetch.questions(context, _questions);
        _setupCurrentQuestionState();
        _startTimer();
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupCurrentQuestionState() {
    if (_questions.isEmpty || _currentQuestionIndex >= _questions.length) return;
    final q = _questions[_currentQuestionIndex];
    final type = _determineQuestionType(q);
    final String correctAnswer = _extractCorrectAnswer(q);
    final List<dynamic> options = _extractOptions(q);

    _hasAnswered = false;
    _isLastAnswerCorrect = false;
    _selectedAnswer = '';
    _identificationController.clear();

    if (type == 'camera_spell') {
      // Camera answered by ChallengeCameraSign (widgets/challenge_camera_sign.dart).
      _currentScore = 0.0;
      _lastCameraModel = null;
    } else if (type == 'typing') {
      final target = correctAnswer.toUpperCase();
      _userAnswerSlots = List<String?>.filled(target.length, null);
      _selectedOptionIndices = List<int?>.filled(target.length, null);

      final givenFsl = _extractGivenFsl(q);
      _givenFslImages = {};
      for (var item in givenFsl) {
        final int pos = (item['position'] as num?)?.toInt() ?? -1;
        if (pos >= 0 && pos < target.length) {
          _userAnswerSlots[pos] = (item['letter'] ?? item['number'] ?? '').toString().toUpperCase();
          _givenFslImages[pos] = (item['image_url'] ?? item['imageUrl'] ?? item['image'] ?? '').toString();
        }
      }
      _shuffledOptions = options.map((e) => e.toString()).toList()..shuffle();
    } else if (type == 'sequence_order') {
      _currentSequence = [];
      _availableSequenceOptions = options.map((e) => e.toString()).toList()..shuffle();
    } else if (type == 'matching_type') {
      _matchingAnswers = {};
      _selectedLeftMatch = null;
      _matchingLeftItems = [];
      _matchingRightItems = [];

      for (var opt in options) {
        String optStr = opt.toString();
        if (optStr.contains('|||')) {
          var parts = optStr.split('|||');
          _matchingLeftItems.add(parts[0]);
          _matchingRightItems.add(parts[1]);
          _matchingAnswers[parts[0]] = null;
        } else {
          _matchingLeftItems.add(optStr);
          _matchingRightItems.add(optStr);
          _matchingAnswers[optStr] = null;
        }
      }
      _matchingRightItems.shuffle();
    }
  }

  void _startTimer() {
    _timeLeft = _maxTime;
    _timer?.cancel();
    if (_maxTime == 0) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_timeLeft > 0) {
            _timeLeft--;
          } else {
            _timer?.cancel();
            _handleTimeOut();
          }
        });
      }
    });
  }

  void _handleTimeOut() {
    if (!_hasAnswered) {
      final q = _questions[_currentQuestionIndex];
      final type = _determineQuestionType(q);
      String ans = '';
      if (type == 'typing') {
        ans = _userAnswerSlots.join('');
      } else if (type == 'sequence_order') {
        ans = _currentSequence.join(',');
      } else if (type == 'identification' || type == 'camera_spell') {
        ans = _identificationController.text.trim();
      } else {
        ans = _selectedAnswer;
      }
      _submitAnswer(ans);
    }
  }


  /// A camera answer from ChallengeCameraSign: right or wrong, it is the
  /// answer to this question (score, gesture_attempts, next question).
  void _onCameraResult(ChallengeSignResult r) {
    if (_hasAnswered) return;
    // No model can check this sign yet: skip it without a score change.
    if (r.skipped) {
      _timer?.cancel();
      _moveToNextQuestion();
      return;
    }
    final correctAnswer = _extractCorrectAnswer(_questions[_currentQuestionIndex]);
    _currentScore = r.score;
    _lastCameraModel = r.model;
    _submitAnswer(r.correct ? correctAnswer : '');
  }

  void _submitAnswer(String answer) {
    if (_hasAnswered) return;
    final q = _questions[_currentQuestionIndex];
    final type = _determineQuestionType(q);
    final correctAnswer = _extractCorrectAnswer(q).toLowerCase();

    bool isCorrect = false;
    if (type == 'camera_spell') {
      isCorrect = _currentScore >= successThreshold || answer.trim().toLowerCase() == correctAnswer;

      // Log camera gesture attempt via ProgressService
      final questionId = (q['id'] ?? q['docId'] ?? q['questionId'] ?? 'q_$_currentQuestionIndex').toString();
      final levelId = (q['levelId'] ?? 'solo_$_category').toString();

      ProgressService().recordGestureAttempt(
        sign: correctAnswer,
        levelId: levelId,
        questionId: questionId,
        isCorrect: isCorrect,
        score: _currentScore,
        category: _category,
        isCameraGesture: true,
        modelVersion: _lastCameraModel ?? 'unknown',
      );
    } else if (type == 'typing') {
      isCorrect = answer.trim().toLowerCase() == correctAnswer;
    } else if (type == 'sequence_order') {
      isCorrect = _currentSequence.join(',') == _extractOptions(q).join(',');
    } else if (type == 'matching_type') {
      bool allMatched = true;
      for (var opt in _extractOptions(q)) {
        String optStr = opt.toString();
        if (optStr.contains('|||')) {
          var parts = optStr.split('|||');
          if (_matchingAnswers[parts[0]] != parts[1]) {
            allMatched = false;
            break;
          }
        }
      }
      isCorrect = allMatched;
    } else {
      isCorrect = answer.isNotEmpty && answer.trim().toLowerCase() == correctAnswer;
    }

    setState(() {
      _hasAnswered = true;
      _selectedAnswer = answer;
      _isLastAnswerCorrect = isCorrect;
      if (isCorrect) {
        _streak++;
        _correctCount++;
        if (_streak > _peakStreak) _peakStreak = _streak;
      } else {
        _streak = 0;
      }
    });

    final soundProvider = Provider.of<SoundProvider>(context, listen: false);
    if (isCorrect) {
      soundProvider.playCorrect();
    } else {
      soundProvider.playIncorrect();
    }

    _timer?.cancel();
    // Same points as the group challenge (ChallengeScoring).
    final points = ChallengeScoring.points(correct: isCorrect, timeLeft: _timeLeft, maxTime: _maxTime, streak: _streak);
    _score += points;
    _lastPoints = points;
    // Timed game: the feedback shows briefly, then the next round starts.
    final answeredIndex = _currentQuestionIndex;
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && _hasAnswered && _currentQuestionIndex == answeredIndex) _moveToNextQuestion();
    });
    // What the student gave, per question type (solo_challenges.questionBreakdown).
    final given = switch (type) {
      'sequence_order' => _currentSequence.join(' > '),
      'matching_type' => _matchingAnswers.entries.map((e) => '${e.key} = ${e.value ?? ''}').join('; '),
      'camera_spell' => isCorrect ? _extractCorrectAnswer(q) : '',
      _ => answer,
    };
    _questionLogs.add({
      'questionIndex': _currentQuestionIndex + 1,
      'questionId': (q['id'] ?? q['docId'] ?? q['questionId'] ?? '').toString(),
      'type': type,
      'questionText': _extractQuestionText(q),
      'userAnswer': given,
      'correctAnswer': _extractCorrectAnswer(q),
      'isCorrect': isCorrect,
      'points': points,
      'timeLeft': _timeLeft,
      if (type == 'camera_spell') 'cameraScore': double.parse(_currentScore.toStringAsFixed(1)),
      if (type == 'camera_spell' && _lastCameraModel != null) 'model': _lastCameraModel,
    });

    if (widget.roomCode != 'SOLO') {
      FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomCode)
          .collection('players')
          .doc(_currentUserId)
          .set({'score': _score, 'currentAnswer': answer}, SetOptions(merge: true));
    }
  }

  void _moveToNextQuestion() {
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() => _currentQuestionIndex++);
      _setupCurrentQuestionState();
      _startTimer();
    } else {
      _showFinalScoreDialog();
    }
  }

  String _rawQuestionText(Map<String, dynamic> q) => (_getValueCaseInsensitive(q, ['question_text', 'questionText', 'question', 'title', 'prompt']) ?? '').toString();

  String _extractQuestionText(Map<String, dynamic> q) {
    final t = _rawQuestionText(q);
    final ans = _extractCorrectAnswer(q).trim();
    // Don't give away the answer ("What is this sign? 100").
    return ans.isEmpty ? t : questionWithoutAnswer(t, ans);
  }

  String? _extractQuestionImage(Map<String, dynamic> q) => _getValueCaseInsensitive(q, [
    'main_image', // typing questions (web app content tool)
    'mainImage',
    'image_url',
    'imageUrl',
    'image',
    'photo',
    'picture',
    'url',
    'img',
    'imgUrl',
    'src',
    'photo_url',
    'imagePath',
  ])?.toString();

  // Fill in the blank: blank_answer is the right piece (correct_answer is
  // then the text with its "_", shown by _blankSentence).
  String _extractCorrectAnswer(Map<String, dynamic> q) =>
      (_getValueCaseInsensitive(q, ['blank_answer', 'blankAnswer', 'correct_answer', 'correctAnswer', 'answer', 'correct']) ?? '').toString();

  String? _blankSentence(Map<String, dynamic> q) {
    final b = _getValueCaseInsensitive(q, ['blank_answer', 'blankAnswer']);
    final text = (_getValueCaseInsensitive(q, ['correct_answer', 'correctAnswer']) ?? '').toString();
    final img = (_getValueCaseInsensitive(q, ['image_url', 'imageUrl', 'main_image', 'video_url', 'videoUrl']) ?? '').toString();
    // The sentence repeats the question when its picture / video shows it.
    return img.trim().isEmpty && b != null && '$b'.trim().isNotEmpty && text.contains('_') ? text : null;
  }

  List<dynamic> _extractOptions(Map<String, dynamic> q) {
    final opts = _getValueCaseInsensitive(q, ['options', 'choices', 'answers']);
    return opts is List ? opts : [];
  }

  List<Map<String, dynamic>> _extractGivenFsl(Map<String, dynamic> q) {
    final raw = _getValueCaseInsensitive(q, ['given_fsl', 'givenFsl']);
    return raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
  }

  String _determineQuestionType(Map<String, dynamic> q) {
    final t = (_getValueCaseInsensitive(q, ['type', 'question_type']) ?? '').toString().toLowerCase();
    if (t.contains('camera')) return 'camera_spell';
    if (t.contains('typing')) return 'typing';
    if (t.contains('sequence')) return 'sequence_order';
    if (t.contains('matching')) return 'matching_type';
    if (t.contains('true') || t.contains('tf') || t == 'boolean') return 'true_false';
    if (t.contains('ident')) return 'identification';

    final opts = _extractOptions(q);
    if (opts.isEmpty) return 'identification';
    if (opts.length == 2 && opts.any((e) => e.toString().toLowerCase() == 'true')) return 'true_false';

    return 'multiple_choice';
  }

  Widget _buildSafeImage(String? source, {double? height, double? width, BoxFit fit = BoxFit.contain}) {
    if (source == null || source.trim().isEmpty) return const SizedBox.shrink();
    final cleanSource = source.trim();
    // Sign videos play with the shared activity player (play / pause).
    if (RegExp(r'\.(mp4|mov|webm|m4v)$', caseSensitive: false).hasMatch(Uri.decodeComponent(cleanSource.split('?').first))) {
      return SizedBox(height: height, width: width, child: ActivityVideo(url: cleanSource, fit: fit, fallback: const Icon(Icons.videocam_off_rounded, size: 40, color: Colors.grey)));
    }

    if (cleanSource.startsWith('http://') || cleanSource.startsWith('https://')) {
      return Image.network(
        cleanSource,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
      );
    }

    if (cleanSource.startsWith('data:image') || cleanSource.contains(';base64,') || (cleanSource.length > 100 && (cleanSource.startsWith('iVBORw0KGgo') || cleanSource.startsWith('/9j/')))) {
      try {
        final base64Str = cleanSource.contains(',') ? cleanSource.split(',').last : cleanSource;
        return Image.memory(
          base64Decode(base64Str),
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
        );
      } catch (_) {
        return const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey);
      }
    }

    final String assetPath = cleanSource.startsWith('assets/') ? cleanSource : 'assets/pictures/$cleanSource';

    return Image.asset(
      assetPath,
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        if (!cleanSource.startsWith('assets/')) {
          return Image.asset(
            'assets/alphabet/$cleanSource',
            height: height,
            width: width,
            fit: fit,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
          );
        }
        return const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey);
      },
    );
  }

  Widget _buildMultipleChoiceOptions(List<dynamic> options, String correctAnswer, ThemeData theme, Color textColor) {
    final bool hasImageOptions = options.any((opt) => _isImageString(opt.toString()));

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: hasImageOptions ? 1.05 : 2.1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: options.length,
      itemBuilder: (context, idx) {
        final opt = options[idx].toString();
        final bool isSelected = _selectedAnswer.trim().toLowerCase() == opt.trim().toLowerCase();
        final bool isCorrect = opt.trim().toLowerCase() == correctAnswer.trim().toLowerCase();

        Color tileBg = theme.cardColor;
        Color borderCol = theme.primaryColor.withValues(alpha: 0.2);

        if (_hasAnswered) {
          if (isCorrect) {
            tileBg = const Color(0xFF2E7D32).withValues(alpha: 0.25);
            borderCol = const Color(0xFF4CAF50);
          } else if (isSelected) {
            tileBg = const Color(0xFFC62828).withValues(alpha: 0.25);
            borderCol = const Color(0xFFEF5350);
          }
        }

        final bool isImg = _isImageString(opt);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _hasAnswered ? null : () => _submitAnswer(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.all(10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderCol, width: isSelected ? 2.5 : 1.5),
                boxShadow: isSelected
                    ? [BoxShadow(color: borderCol.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))]
                    : [],
              ),
              child: isImg
                  ? Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: _buildSafeImage(opt, fit: BoxFit.contain),
                    )
                  : Text(
                      opt,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textColor),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrueFalseOptions(List<dynamic> options, String correctAnswer, ThemeData theme, Color textColor) {
    List<dynamic> tfOpts = options.isNotEmpty ? options : ['True', 'False'];
    return Row(
      children: tfOpts.map((opt) {
        final optStr = opt.toString();
        final bool isSelected = _selectedAnswer.trim().toLowerCase() == optStr.trim().toLowerCase();
        final bool isCorrect = optStr.trim().toLowerCase() == correctAnswer.trim().toLowerCase();

        Color tileBg = theme.cardColor;
        Color borderCol = theme.primaryColor.withValues(alpha: 0.3);

        if (_hasAnswered) {
          if (isCorrect) {
            tileBg = const Color(0xFF2E7D32).withValues(alpha: 0.25);
            borderCol = const Color(0xFF4CAF50);
          } else if (isSelected) {
            tileBg = const Color(0xFFC62828).withValues(alpha: 0.25);
            borderCol = const Color(0xFFEF5350);
          }
        }

        final bool isImg = _isImageString(optStr);

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: _hasAnswered ? null : () => _submitAnswer(optStr),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 110,
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: borderCol, width: 2),
                  boxShadow: isSelected ? [BoxShadow(color: borderCol.withValues(alpha: 0.3), blurRadius: 10)] : [],
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(10),
                child: isImg
                    ? _buildSafeImage(optStr, fit: BoxFit.contain)
                    : Text(
                        optStr.toUpperCase(),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 1.0),
                      ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// FSL hand-sign picture for a letter / number answer piece (A-Z -> jpg,
  /// 1-10 -> png in assets/pictures), the piece itself when it is already an
  /// image, else null (shown as text).
  String? _signImageFor(String value) {
    final v = value.trim();
    if (_isImageString(v)) return v;
    if (RegExp(r'^[A-Za-z]$').hasMatch(v)) return 'assets/pictures/${v.toUpperCase()}.jpg';
    if (RegExp(r'^[0-9]+$').hasMatch(v)) return 'assets/pictures/$v.png';
    return null;
  }

  /// A sign picture with the plain text as fallback (missing picture).
  Widget _signTile(String value, TextStyle style, {String? image}) {
    final src = (image != null && image.trim().isNotEmpty) ? image : _signImageFor(value);
    if (src == null) return Text(value, style: style);
    if (src.startsWith('assets/')) {
      return Image.asset(src, fit: BoxFit.contain, errorBuilder: (_, _, _) => Text(value, style: style));
    }
    return _buildSafeImage(src, fit: BoxFit.contain);
  }

  /// Typing (same as easyAct_mc.dart): letter slots, the `given_fsl` hints
  /// pre-filled as hand-sign pictures (fixed), and the letter pieces shown as
  /// FSL hand signs; tap a piece to fill the next empty slot, tap a filled
  /// slot to take it back.
  Widget _buildTypingLayout(ThemeData theme, Color textColor) {
    final slotText = TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: List.generate(_userAnswerSlots.length, (index) {
              final char = _userAnswerSlots[index];
              final bool isGiven = _givenFslImages.containsKey(index);
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: (_hasAnswered || isGiven || char == null)
                    ? null
                    : () => setState(() {
                          _userAnswerSlots[index] = null;
                          _selectedOptionIndices[index] = null;
                        }),
                child: Container(
                  width: 52,
                  height: 64,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: char == null
                        ? theme.cardColor
                        : theme.primaryColor.withValues(alpha: isGiven ? 0.08 : 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: char != null ? theme.primaryColor : theme.dividerColor, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: char == null
                      ? const SizedBox.shrink()
                      : isGiven
                          ? _signTile(char, slotText, image: _givenFslImages[index])
                          : Text(char, style: slotText),
                ),
              );
            }),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: List.generate(_shuffledOptions.length, (index) {
              final isUsed = _selectedOptionIndices.contains(index);
              final opt = _shuffledOptions[index];
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: (isUsed || _hasAnswered)
                    ? null
                    : () {
                        final empty = _userAnswerSlots.indexOf(null);
                        if (empty != -1) {
                          setState(() {
                            _userAnswerSlots[empty] = _signImageFor(opt) != null && !_isImageString(opt)
                                ? opt.toUpperCase()
                                : opt;
                            _selectedOptionIndices[empty] = index;
                          });
                        }
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 60,
                  height: 60,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isUsed ? theme.dividerColor.withValues(alpha: 0.3) : theme.cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isUsed ? Colors.transparent : theme.primaryColor, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: isUsed ? 0.3 : 1.0,
                    child: _signTile(opt, TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: (_hasAnswered || _userAnswerSlots.contains(null))
                  ? null
                  : () => _submitAnswer(_userAnswerSlots.join('')),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                shape: Button3DBorder(borderRadius: BorderRadius.circular(28)),
                elevation: 4,
              ),
              child: Text("SUBMIT ANSWER", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSequenceLayout(ThemeData theme, Color textColor) {
    Widget content(String o) => _isMatchMedia(o) ? _buildSafeImage(o, fit: BoxFit.contain) : Text(o, style: TextStyle(color: textColor));
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.primaryColor.withValues(alpha: 0.5), width: 2),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: [
                for (var pos = 0; pos < _currentSequence.length; pos++)
                  SequencePiece(
                    isMedia: _isMatchMedia(_currentSequence[pos]),
                    placed: true,
                    order: pos + 1,
                    onTap: _hasAnswered
                        ? null
                        : () => setState(() => _availableSequenceOptions.add(_currentSequence.removeAt(pos))),
                    child: content(_currentSequence[pos]),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 14,
            alignment: WrapAlignment.center,
            children: [
              for (final item in List.of(_availableSequenceOptions))
                SequencePiece(
                  isMedia: _isMatchMedia(item),
                  onTap: _hasAnswered
                      ? null
                      : () => setState(() {
                            _availableSequenceOptions.remove(item);
                            _currentSequence.add(item);
                          }),
                  child: content(item),
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _hasAnswered ? null : () => _submitAnswer(_currentSequence.join(',')),
              style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor, shape: Button3DBorder(borderRadius: BorderRadius.circular(28))),
              child: Text("SUBMIT SEQUENCE", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  bool _isMatchMedia(String s) => _isImageString(s) || _MatchTile.isVideo(s);

  Widget _buildMatchingLayout(Map<String, dynamic> q, ThemeData theme, Color textColor) {
    // Same tile size in both columns (_MatchTile): all square when either
    // column has pictures / videos, which fill their tile.
    final anyMedia = [..._matchingLeftItems, ..._matchingRightItems].any(_isMatchMedia);
    Widget content(String item) => _isMatchMedia(item)
        ? _buildSafeImage(item, fit: BoxFit.contain)
        : Text(item, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: textColor));
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final item in _matchingLeftItems)
                    () {
                      final isSelected = _selectedLeftMatch == item;
                      final isMatched = _matchingAnswers[item] != null;
                      return _MatchTile(
                        isMedia: _isMatchMedia(item),
                        square: anyMedia,
                        fill: isMatched ? Colors.green.withValues(alpha: 0.2) : (isSelected ? theme.primaryColor.withValues(alpha: 0.3) : theme.cardColor),
                        border: isMatched ? Colors.green : (isSelected ? theme.primaryColor : textColor.withValues(alpha: 0.2)),
                        onTap: (_hasAnswered || isMatched) ? null : () => setState(() => _selectedLeftMatch = item),
                        child: content(item),
                      );
                    }(),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  for (var ri = 0; ri < _matchingRightItems.length; ri++)
                    () {
                      final item = _matchingRightItems[ri];
                      // Repeated answers: each tile is its own slot, taken in order.
                      final used = _matchingAnswers.values.where((v) => v == item).length;
                      final k = [for (var x = 0; x < ri; x++) if (_matchingRightItems[x] == item) x].length;
                      final isMatched = k < used;
                      return _MatchTile(
                        isMedia: _isMatchMedia(item),
                        square: anyMedia,
                        fill: isMatched ? Colors.green.withValues(alpha: 0.2) : theme.cardColor,
                        border: isMatched ? Colors.green : textColor.withValues(alpha: 0.2),
                        onTap: (_hasAnswered || isMatched || _selectedLeftMatch == null)
                            ? null
                            : () => setState(() {
                                  _matchingAnswers[_selectedLeftMatch!] = item;
                                  _selectedLeftMatch = null;
                                }),
                        child: content(item),
                      );
                    }(),
                ],
              ),
            ),
          ],
            ),
          ),
        ),
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _hasAnswered ? null : () => _submitAnswer(''),
            style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor, shape: Button3DBorder(borderRadius: BorderRadius.circular(28))),
            child: Text("SUBMIT MATCHES", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildIdentificationInput(String correctAnswer, ThemeData theme, Color textColor) {
    return Column(
      children: [
        TextField(
          controller: _identificationController,
          enabled: !_hasAnswered,
          textInputAction: TextInputAction.done,
          onSubmitted: _hasAnswered ? null : (val) => _submitAnswer(val.trim()),
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18),
          decoration: InputDecoration(
            hintText: "Type your answer...",
            filled: true,
            fillColor: theme.cardColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: theme.primaryColor.withValues(alpha: 0.3))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: theme.primaryColor, width: 2)),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _hasAnswered ? null : () => _submitAnswer(_identificationController.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor, shape: Button3DBorder(borderRadius: BorderRadius.circular(28))),
            child: Text("SUBMIT IDENTIFICATION", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  /// Records comprehensive challenge progress and game session metrics into Firestore.
  Future<void> _recordProgress() async {
    if (_currentUserId.isEmpty || _currentUserId.startsWith('guest_')) return;

    final double accuracy = _questions.isEmpty ? 0.0 : (_correctCount / _questions.length) * 100.0;

    try {
      await ProgressService().recordSoloChallengeHistory(
        category: _category,
        score: _score,
        correctCount: _correctCount,
        totalQuestions: _questions.length,
        accuracy: accuracy,
        peakStreak: _peakStreak,
      );
    } catch (e) {
      debugPrint("Failed to record progress to Firestore: $e");
    }

    // One document per game in the root 'solo_challenges' collection, laid
    // out like 'group_challenges' (for the web dashboard / reports).
    try {
      final user = FirebaseAuth.instance.currentUser;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(_currentUserId).get();
      final data = userDoc.data() ?? const <String, dynamic>{};
      final name = (data['displayName'] ?? data['name'] ?? user?.displayName ?? 'Student').toString();
      final section = (data['section'] ?? data['sectionId'] ?? '').toString().trim();
      await FirebaseFirestore.instance.collection('solo_challenges').add({
        'userId': _currentUserId,
        'userName': name,
        if (section.isNotEmpty) 'sectionId': section,
        'roomId': widget.roomCode,
        'challengeTitle': 'Solo Challenge: $_category',
        'category': _category,
        'score': _score,
        'xpEarned': _score,
        'correctCount': _correctCount,
        'mistakesCount': _questionLogs.where((l) => l['isCorrect'] != true).length,
        'totalQuestions': _questions.length,
        'answeredCount': _questionLogs.length,
        'accuracy': double.parse(accuracy.toStringAsFixed(1)),
        'peakStreak': _peakStreak,
        'durationSec': DateTime.now().difference(_startedAt).inSeconds,
        'questionBreakdown': _questionLogs,
        'startedAt': Timestamp.fromDate(_startedAt),
        'completedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error saving solo challenge record: $e");
    }
  }

  void _showFinalScoreDialog() {
    Provider.of<SoundProvider>(context, listen: false).playLevelComplete();

    // Persist session progress and user stats to Firestore
    _recordProgress();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text("Challenge Completed! 🏆", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFFFD700).withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.emoji_events_rounded, size: 70, color: Color(0xFFFFD700)),
            ),
            const SizedBox(height: 16),
            Text("Total Score: $_score XP", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Theme.of(context).primaryColor)),
            const SizedBox(height: 8),
            Text(
              "Accuracy: ${_questions.isNotEmpty ? ((_correctCount / _questions.length) * 100).toStringAsFixed(0) : 0}% ($_correctCount / ${_questions.length})",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75)),
            ),
            if (_streak > 1) ...[
              const SizedBox(height: 6),
              Text("🔥 Peak Streak: $_streak", style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFF34B1B))),
            ]
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                shape: Button3DBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: const Text("CONTINUE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    if (_isLoading) return Scaffold(backgroundColor: theme.scaffoldBackgroundColor, body: Center(child: CircularProgressIndicator(color: theme.primaryColor)));
    if (_questions.isEmpty) return Scaffold(backgroundColor: theme.scaffoldBackgroundColor, body: Center(child: Text("No questions found for category: $_category", style: TextStyle(color: textColor))));

    final currentQuestion = _questions[_currentQuestionIndex];
    final type = _determineQuestionType(currentQuestion);
    final options = _extractOptions(currentQuestion);
    final correctAnswer = _extractCorrectAnswer(currentQuestion);
    final imageUrl = _extractQuestionImage(currentQuestion);

    final glass = theme.extension<GlassThemeExtension>();
    final danger = _timeLeft < 5 ? theme.colorScheme.error : theme.primaryColor;
    // Answer line in the feedback: only a readable answer (not pictures /
    // videos, placeholders, or sequence / matching shown on the pieces).
    final readable = !const {'sequence_order', 'matching_type', 'camera_spell'}.contains(type) &&
        !_isMatchMedia(correctAnswer) &&
        !correctAnswer.contains('_') &&
        correctAnswer.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      // Same header as the group challenge: round pill + close.
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: glass?.glassCard ?? theme.cardColor.withAlpha(180),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: glass?.glassBorder ?? textColor.withAlpha(30)),
          ),
          child: Text(
            "ROUND ${_currentQuestionIndex + 1} OF ${_questions.length}",
            style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.0),
          ),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: theme.cardColor, shape: BoxShape.circle),
              child: Icon(Icons.close_rounded, color: textColor, size: 20),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Score and streak (where the group shows its players).
                  Row(
                    children: [
                      _soloChip(theme, Icons.bolt_rounded, '$_score pts', theme.primaryColor),
                      const SizedBox(width: 8),
                      if (_streak > 1) _soloChip(theme, Icons.local_fire_department_rounded, '$_streak streak', const Color(0xFFF34B1B)),
                      const Spacer(),
                      _soloChip(theme, Icons.check_circle_rounded, '$_correctCount / ${_questions.length}', const Color(0xFF58CC02)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_maxTime > 0) ...[
                    Row(
                      children: [
                        Icon(Icons.timer_sharp, size: 18, color: danger),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: (_timeLeft / _maxTime).clamp(0.0, 1.0),
                              backgroundColor: textColor.withAlpha(30),
                              valueColor: AlwaysStoppedAnimation<Color>(danger),
                              minHeight: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text("${_timeLeft}s",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: _timeLeft < 5 ? theme.colorScheme.error : textColor)),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  // Question card (group challenge style).
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [glass?.glassCard ?? theme.cardColor.withAlpha(220), theme.cardColor.withAlpha(160)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: glass?.glassBorder ?? textColor.withAlpha(30), width: 1.5),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: theme.primaryColor.withAlpha(35), borderRadius: BorderRadius.circular(12)),
                          child: Text(_category.toUpperCase(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: theme.primaryColor, letterSpacing: 1.0)),
                        ),
                        const SizedBox(height: 8),
                        Text(_extractQuestionText(currentQuestion),
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textColor, height: 1.3)),
                        if (_blankSentence(currentQuestion) != null) ...[
                          const SizedBox(height: 10),
                          Text(_blankSentence(currentQuestion)!.replaceFirst(RegExp(r'_+'), _hasAnswered ? _extractCorrectAnswer(currentQuestion) : '_____'),
                              textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: theme.primaryColor)),
                        ],
                        if (imageUrl != null && imageUrl.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          // Whole picture / video, never cropped.
                          Container(
                            height: 170,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              border: Border.all(color: textColor.withAlpha(30)),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: _buildSafeImage(imageUrl, fit: BoxFit.contain),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Builder(
                      builder: (_) {
                        switch (type) {
                          case 'true_false':
                            return _buildTrueFalseOptions(options, correctAnswer, theme, textColor);
                          case 'typing':
                            return _buildTypingLayout(theme, textColor);
                          case 'sequence_order':
                            return _buildSequenceLayout(theme, textColor);
                          case 'matching_type':
                            return _buildMatchingLayout(currentQuestion, theme, textColor);
                          case 'identification':
                            return _buildIdentificationInput(correctAnswer, theme, textColor);
                          case 'camera_spell':
                            return (RegExp(r'^([A-Za-z]|\d+)$').hasMatch(correctAnswer.trim())
                                ? ChallengeCameraSign(sign: correctAnswer, enabled: !_hasAnswered, countdown: 0, onResult: _onCameraResult)
                                : PublishedCameraSign(category: _category, sign: correctAnswer, enabled: !_hasAnswered, countdown: 0, onResult: _onCameraResult));
                          case 'multiple_choice':
                          default:
                            return _buildMultipleChoiceOptions(options, correctAnswer, theme, textColor);
                        }
                      },
                    ),
                  ),
                  if (_hasAnswered) const SizedBox(height: 150),
                ],
              ),
            ),
          ),
          if (_hasAnswered)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ChallengeFeedbackBanner(
                isCorrect: _isLastAnswerCorrect,
                correctAnswer: readable ? correctAnswer : '',
                streak: _streak,
                points: _lastPoints,
              ),
            ),
        ],
      ),
    );
  }

  Widget _soloChip(ThemeData theme, IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(90)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: theme.colorScheme.onSurface)),
          ],
        ),
      );
}

/// One item of a matching question (all categories).
class _MatchTile extends StatelessWidget {
  final bool isMedia;
  final Widget child;
  final Color fill;
  final Color border;
  final VoidCallback? onTap;

  /// Square tile even for text, so both columns have the same tile size
  /// when either column has pictures / videos (default: [isMedia]).
  final bool? square;

  const _MatchTile({required this.isMedia, required this.child, required this.fill, required this.border, this.onTap, this.square});

  static final RegExp _video = RegExp(r'\.(mp4|mov|webm|m4v|3gp|mkv)$', caseSensitive: false);

  /// A video link / path (query string ignored).
  static bool isVideo(String s) => _video.hasMatch(Uri.decodeComponent(s.trim().split('?').first));

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(14);
    final sq = square ?? isMedia;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          // Text tiles grow with long answers (phrases) instead of cutting them.
          constraints: sq ? null : const BoxConstraints(minHeight: 64),
          padding: EdgeInsets.all(sq ? 3 : 8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: r,
            border: Border.all(color: border, width: 2.5),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          alignment: Alignment.center,
          child: sq
              ? AspectRatio(
                  aspectRatio: 1,
                  child: isMedia
                      ? ClipRRect(borderRadius: BorderRadius.circular(11), child: SizedBox.expand(child: child))
                      : Center(child: FittedBox(fit: BoxFit.scaleDown, child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 28), child: child))),
                )
              : child,
        ),
      ),
    );
  }
}
