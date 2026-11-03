import 'dart:math' as math;
import '/module/custom_category_screen.dart' show PublishedCameraSign;
import '/widgets/button_3d.dart';
import 'dart:async';
import 'dart:convert';
import '/services/challenge_categories.dart';
import '/widgets/activity_video.dart';
import 'package:flutter/material.dart';
import '/widgets/challenge_camera_sign.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '/providers/sound_provider.dart';
import '/providers/theme_provider.dart';
import '/services/progress_service.dart';


class GameProperScreen extends StatefulWidget {
  final String roomCode;
  final String challengeTitle;
  final bool isHost;

  const GameProperScreen({
    super.key,
    required this.roomCode,
    required this.challengeTitle,
    required this.isHost,
  });

  @override
  State<GameProperScreen> createState() => _GameProperScreenState();
}

class _GameProperScreenState extends State<GameProperScreen> with SingleTickerProviderStateMixin {
  // Game music while this screen is open (see SoundProvider.claimBgm).
  late final SoundProvider _bgm;

  final ProgressService _progressService = ProgressService();

  late final String _currentUserId;
  late final String _displayName;

  List<Map<String, dynamic>> _questions = [];
  int _currentQuestionIndex = 0;
  int _score = 0;
  int _streak = 0; // correct answers in a row (streak bonus)

  // Web dashboard history tracking state variables
  int _correctAnswersCount = 0;
  int _mistakesCount = 0;
  final List<Map<String, dynamic>> _questionLogs = [];

  bool _isLoading = true;
  bool _hasAnswered = false;
  bool _isCleaningUp = false;
  String _selectedAnswer = '';

  // In-Memory Image Caching Pipeline
  final Map<String, Uint8List> _base64Cache = {};
  final Map<String, ImageProvider> _imageProviderCache = {};

  // Controllers & State variables per question type
  final TextEditingController _identificationController = TextEditingController();

  // Typing state
  List<String?> _userAnswerSlots = [];
  List<int?> _selectedOptionIndices = [];
  List<String> _shuffledOptions = [];

  // Sequence state
  List<String> _currentSequence = [];
  List<String> _availableSequenceOptions = [];

  // Matching state
  Map<String, String?> _matchingAnswers = {};
  String? _selectedLeftMatch;

  // Camera & ML Recognition State





  double _currentScore = 0.0;
  // Camera answers (widgets/challenge_camera_sign.dart): the model that
  // judged the last one (gesture_attempts modelVersion).
  String? _lastCameraModel;
  final double successThreshold = 70.0;


  Timer? _timer;
  int _timeLeft = 15;
  int _maxTime = 15;
  int _totalRounds = 10;
  String _category = 'Alphabet';

  // Visual Animation Controller for pulses
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _bgm = Provider.of<SoundProvider>(context, listen: false)..claimBgm(this, BgmType.activity); // gamebgm.mp3
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _initUser();
    _setupGameAndPlayer();
  }

  @override
  void dispose() {
    _bgm.releaseBgm(this);
    _base64Cache.clear();
    _imageProviderCache.clear();
    _pulseController.dispose();
    _timer?.cancel();
    _identificationController.dispose();
    super.dispose();
  }

  void _initUser() {
    final user = FirebaseAuth.instance.currentUser;
    _currentUserId = user?.uid ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';

    if (user != null && user.displayName != null && user.displayName!.trim().isNotEmpty) {
      _displayName = user.displayName!;
    } else {
      final shortUid = _currentUserId.length >= 4 
          ? _currentUserId.substring(0, 4) 
          : _currentUserId;
      _displayName = 'Guest_$shortUid';
    }
  }

  // Caching & Pre-caching Helpers
  ImageProvider? _getImageProvider(String cleaned) {
    if (_imageProviderCache.containsKey(cleaned)) {
      return _imageProviderCache[cleaned];
    }

    ImageProvider provider;
    if (cleaned.startsWith('data:image') || _isRawBase64(cleaned)) {
      try {
        final base64String = cleaned.contains(',') ? cleaned.split(',').last : cleaned;
        final bytes = _base64Cache.putIfAbsent(cleaned, () => base64Decode(base64String));
        provider = MemoryImage(bytes);
      } catch (_) {
        return null;
      }
    } else if (cleaned.startsWith('http://') || cleaned.startsWith('https://')) {
      provider = NetworkImage(cleaned);
    } else {
      final assetPath = cleaned.startsWith('assets/') ? cleaned : 'assets/pictures/$cleaned';
      provider = AssetImage(assetPath);
    }

    _imageProviderCache[cleaned] = provider;
    return provider;
  }

  void _precacheAllImages() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      for (var q in _questions) {
        final img = _extractQuestionImage(q);
        if (img != null) _precacheSingleImage(img);

        final options = _extractOptions(q);
        for (var opt in options) {
          if (opt is Map) {
            final imgVal = _getValueCaseInsensitive(
              Map<String, dynamic>.from(opt),
              ['image', 'image_url', 'imageUrl', 'img', 'url', 'src', 'photo', 'path'],
            );
            if (imgVal != null && imgVal.toString().trim().isNotEmpty) {
              _precacheSingleImage(imgVal.toString().trim());
            }
          } else if (opt is String && _isImageRef(opt)) {
            _precacheSingleImage(opt);
          }
        }

        final givenFsl = _extractGivenFsl(q);
        for (var fsl in givenFsl) {
          if (fsl['image'] != null && (fsl['image'] as String).isNotEmpty) {
            _precacheSingleImage(fsl['image']);
          }
        }
      }
    });
  }

  void _precacheSingleImage(String source) {
    final provider = _getImageProvider(source);
    if (provider != null && mounted) {
      precacheImage(provider, context).catchError((e) {
        debugPrint("Precache error for $source: $e");
      });
    }
  }


  /// G, H, K, P, Q: tricky letters (horizontal or crossing fingers). Scored in
  /// 2D only (no z noise), scale from wrist->middle base or the index reach,
  /// fingertips weighted 1.5x, a relaxed curve, and G/H/P/Q locked to the
  /// sideways orientations.

  dynamic _getValueCaseInsensitive(Map<String, dynamic> map, List<String> possibleKeys) {
    for (var key in possibleKeys) {
      if (map.containsKey(key) && map[key] != null) {
        return map[key];
      }
    }
    for (var entry in map.entries) {
      final keyClean = entry.key.toLowerCase().replaceAll('_', '').replaceAll(' ', '');
      for (var pk in possibleKeys) {
        if (keyClean == pk.toLowerCase().replaceAll('_', '').replaceAll(' ', '')) {
          if (entry.value != null) return entry.value;
        }
      }
    }
    return null;
  }

  bool _isImageRef(String str) {
    final s = str.trim().toLowerCase();
    return s.contains('assets/') ||
        s.startsWith('http') ||
        s.startsWith('data:image') ||
        s.endsWith('.jpg') ||
        s.endsWith('.jpeg') ||
        s.endsWith('.png') ||
        s.endsWith('.webp');
  }

  Future<void> _setupGameAndPlayer() async {
    try {
      final roomRef = FirebaseFirestore.instance.collection('rooms').doc(widget.roomCode);
      final user = FirebaseAuth.instance.currentUser;
      String? avatarUrl = user?.photoURL;

      if (avatarUrl == null || avatarUrl.isEmpty) {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(_currentUserId).get();
          if (userDoc.exists) {
            final userData = userDoc.data();
            avatarUrl = userData?['avatarUrl'] ?? userData?['photoUrl'] ?? userData?['avatar'];
          }
        } catch (_) {}
      }

      await roomRef.collection('players').doc(_currentUserId).set({
        'uid': _currentUserId,
        'name': _displayName,
        'avatarUrl': avatarUrl,
        'isHost': widget.isHost,
        'score': 0,
        'currentAnswer': '',
        'questionsCompleted': 0,
        'currentQuestionIndex': -1,
        'joinedAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final roomDoc = await roomRef.get();
      if (roomDoc.exists) {
        final roomData = roomDoc.data() as Map<String, dynamic>;
        _maxTime = roomData['timerDuration'] ?? 15;
        _totalRounds = roomData['totalRounds'] ?? 10;
        _category = (roomData['category'] ?? 'Alphabet').toString();

        if (roomData.containsKey('questions') && (roomData['questions'] as List).isNotEmpty) {
          _questions = List<Map<String, dynamic>>.from(
            (roomData['questions'] as List).map((e) => Map<String, dynamic>.from(e as Map))
          );
        } else if (widget.isHost) {
          final snapshot = await FirebaseFirestore.instance
              .collection('activity_questions')
              .get();

          if (snapshot.docs.isNotEmpty) {
            var allQuestions = snapshot.docs.map((doc) => doc.data()).toList();

            var filteredQuestions = allQuestions.where((q) {
              return ChallengeCategories.matches(
                  _getValueCaseInsensitive(q, ['category', 'topic', 'subject', 'group', 'tag'])?.toString(), _category);
            }).toList();

            // Only this category's questions (no fall-back to every category).

            filteredQuestions.shuffle();
            _questions = filteredQuestions
                .take(_totalRounds)
                .map((q) => Map<String, dynamic>.from(q))
                .toList();

            await roomRef.set({'questions': _questions}, SetOptions(merge: true));
          }
        } else {
          final roomSnap = await roomRef.snapshots().firstWhere((snap) {
            final data = snap.data();
            return data != null && data.containsKey('questions') && (data['questions'] as List).isNotEmpty;
          });
          final data = roomSnap.data() as Map<String, dynamic>;
          _questions = List<Map<String, dynamic>>.from(
            (data['questions'] as List).map((e) => Map<String, dynamic>.from(e as Map))
          );
        }
      }

      if (_questions.isNotEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }

        _precacheAllImages();
        _setupCurrentQuestionState();
        _startTimer();
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error setting up game: $e");
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
      for (var item in givenFsl) {
        int pos = item['position'] ?? -1;
        if (pos >= 0 && pos < target.length) {
          _userAnswerSlots[pos] = (item['letter'] ?? item['number'] ?? '').toString().toUpperCase();
        }
      }
      _shuffledOptions = options.map((e) => e.toString()).toList()..shuffle();
    } else if (type == 'sequence_order') {
      _currentSequence = [];
      _availableSequenceOptions = options.map((e) => e.toString()).toList()..shuffle();
    } else if (type == 'matching_type') {
      _matchingAnswers = {};
      _selectedLeftMatch = null;
      for (var opt in options) {
        String optStr = opt.toString();
        String leftItem = optStr.contains('|||') ? optStr.split('|||')[0] : optStr;
        _matchingAnswers[leftItem] = null;
      }
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
    final correctAnswer = _extractCorrectAnswer(_questions[_currentQuestionIndex]);
    _currentScore = r.score;
    _lastCameraModel = r.model;
    _submitAnswer(r.correct ? correctAnswer : '');
  }

  void _submitAnswer(String answer) {
    if (_hasAnswered) return;

    final currentQ = _questions[_currentQuestionIndex];
    final String type = _determineQuestionType(currentQ);
    final String correctAnswer = _extractCorrectAnswer(currentQ).toLowerCase();

    bool isCorrect = false;

    if (type == 'camera_spell') {
      isCorrect = _currentScore >= successThreshold || answer.trim().toLowerCase() == correctAnswer;
      if (answer.isEmpty && isCorrect) {
        answer = correctAnswer;
      }

      // Record camera gesture attempt metrics
      _progressService.recordGestureAttempt(
        sign: correctAnswer,
        levelId: widget.challengeTitle,
        questionId: currentQ['id']?.toString() ?? 'q_$_currentQuestionIndex',
        isCorrect: isCorrect,
        score: _currentScore,
        category: _category,
        isCameraGesture: true,
        // The file that actually scored it: the J / Z motion model when it
        // is loaded, else the letter's bundled template.
        modelVersion: _lastCameraModel ?? 'unknown',
      );
    } else if (type == 'typing') {
      isCorrect = answer.trim().toLowerCase() == correctAnswer;
    } else if (type == 'sequence_order') {
      final List<dynamic> options = _extractOptions(currentQ);
      isCorrect = _currentSequence.join(',') == options.join(',');
    } else if (type == 'matching_type') {
      bool allMatched = true;
      final List<dynamic> options = _extractOptions(currentQ);
      for (var opt in options) {
        String optStr = opt.toString();
        if (optStr.contains('|||')) {
          var parts = optStr.split('|||');
          if (_matchingAnswers[parts[0]] != parts[1]) {
            allMatched = false;
            break;
          }
        } else {
          if (_matchingAnswers[optStr] != optStr) {
            allMatched = false;
            break;
          }
        }
      }
      isCorrect = allMatched;
    } else {
      isCorrect = answer.isNotEmpty && answer.trim().toLowerCase() == correctAnswer;
    }

    // Capture counts and log itemized question breakdown for web dashboard indexing
    if (isCorrect) {
      _correctAnswersCount++;
    } else {
      _mistakesCount++;
    }

    _questionLogs.add({
      'questionIndex': _currentQuestionIndex + 1,
      'questionText': _extractQuestionText(currentQ),
      'userAnswer': answer,
      'correctAnswer': correctAnswer,
      'isCorrect': isCorrect,
    });

    final soundProvider = context.read<SoundProvider>();
    if (isCorrect) {
      soundProvider.playCorrect();
    } else {
      soundProvider.playIncorrect();
    }

    if (mounted) {
      setState(() {
        _hasAnswered = true;
        _selectedAnswer = answer;
      });
    }

    // Same points as the solo challenge (ChallengeScoring): streaks count too.
    _streak = isCorrect ? _streak + 1 : 0;
    final points = ChallengeScoring.points(correct: isCorrect, timeLeft: _timeLeft, maxTime: _maxTime, streak: _streak);
    if (points > 0 && mounted) setState(() => _score += points);

    _syncAnswerToFirestore(answer);

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _moveToNextQuestion();
    });
  }

  void _moveToNextQuestion() {
    if (!mounted) return;

    if (_currentQuestionIndex + 1 < _questions.length) {
      setState(() {
        _currentQuestionIndex++;
      });
      _setupCurrentQuestionState();
      _startTimer();
    } else {
      _timer?.cancel();
      _saveChallengeHistoryAndXP();
      _showFinalLeaderboard();
    }
  }

  Future<void> _syncAnswerToFirestore(String answer) async {
    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomCode)
        .collection('players')
        .doc(_currentUserId)
        .set({
      'score': _score,
      'currentAnswer': answer,
      'questionsCompleted': _currentQuestionIndex + 1,
      'currentQuestionIndex': _currentQuestionIndex,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Persists player's overall score, progress, and challenge history to Firestore
  /// Persists player's overall score, progress, and challenge history to a dedicated top-level 'group_challenges' collection
  Future<void> _saveChallengeHistoryAndXP() async {
    try {
      final playersSnapshot = await FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomCode)
          .collection('players')
          .orderBy('score', descending: true)
          .get();

      List<Map<String, dynamic>> standings = [];
      int userRank = 1;
      int totalPlayers = playersSnapshot.docs.length;

      for (int i = 0; i < playersSnapshot.docs.length; i++) {
        final doc = playersSnapshot.docs[i];
        final data = doc.data();
        final uid = data['uid'] ?? doc.id;

        if (uid == _currentUserId) {
          userRank = i + 1;
        }

        standings.add({
          'uid': uid,
          'name': data['name'] ?? 'Player',
          'score': data['score'] ?? 0,
          'rank': i + 1,
          'avatarUrl': data['avatarUrl'],
        });
      }

      // Update player XP & level progression
      if (_score > 0) {
        await _progressService.addXp(_score);
        // Category module XP (was written into the activity stars map).
        await _progressService.addModuleXp(_category, _score);

        int stars = _score >= 500 ? 3 : (_score >= 250 ? 2 : 1);
        await _progressService.recordActivityAttempt(
          levelId: widget.challengeTitle,
          category: _category,
          isCompleted: true,
          starsEarned: stars,
        );
      }

      // Store group challenge results directly in the root 'group_challenges' collection
      await FirebaseFirestore.instance.collection('group_challenges').add({
        'roomId': widget.roomCode,
        'userId': _currentUserId,
        'userName': _displayName,
        'challengeTitle': widget.challengeTitle,
        'category': _category,
        'score': _score,
        'xpEarned': _score,
        'rank': userRank,
        'totalPlayers': totalPlayers > 0 ? totalPlayers : 1,
        'correctCount': _correctAnswersCount,
        'mistakesCount': _mistakesCount,
        'standings': standings,
        'questionBreakdown': _questionLogs,
        'completedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error saving group challenge history: $e");
    }
  }

  String _extractQuestionText(Map<String, dynamic> q) {
    final val = _getValueCaseInsensitive(q, [
      'question_text', 'questionText', 'question', 'title', 'text', 'prompt', 'item', 'query'
    ]);
    return val?.toString().trim() ?? '';
  }

  String? _extractQuestionImage(Map<String, dynamic> q) {
    final val = _getValueCaseInsensitive(q, [
      'image_url', 'imageUrl', 'main_image', 'mainImage', 'image', 'img',
      'question_image', 'questionImage', 'media_url', 'mediaUrl', 'photo', 'picture', 'path', 'src', 'url'
    ]);
    if (val != null && val.toString().trim().isNotEmpty) {
      return val.toString().trim();
    }
    return null;
  }

  String _extractCorrectAnswer(Map<String, dynamic> q) {
    final val = _getValueCaseInsensitive(q, [
      'correct_answer', 'correctAnswer', 'answer', 'correct', 'right_answer', 'rightAnswer', 'solution'
    ]);
    return val?.toString().trim() ?? '';
  }

  List<dynamic> _extractOptions(Map<String, dynamic> q) {
    final rawOptions = _getValueCaseInsensitive(q, [
      'options', 'choices', 'answers', 'items', 'options_list', 'choices_list'
    ]);

    if (rawOptions is List && rawOptions.isNotEmpty) {
      return rawOptions;
    }
    if (rawOptions is Map && rawOptions.isNotEmpty) {
      return rawOptions.values.toList();
    }
    if (rawOptions is String && rawOptions.contains(',')) {
      return rawOptions.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return [];
  }

  List<Map<String, dynamic>> _extractGivenFsl(Map<String, dynamic> q) {
    final rawFsl = _getValueCaseInsensitive(q, ['given_fsl', 'givenFsl', 'given_fsl_items']);
    if (rawFsl is List) {
      return rawFsl.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  String _determineQuestionType(Map<String, dynamic> q) {
    final typeVal = _getValueCaseInsensitive(q, ['type', 'question_type', 'questionType', 'kind']);
    String type = typeVal?.toString().toLowerCase().trim() ?? '';

    if (type == 'multiple_choice' || 
        type == 'mcq' || 
        type == 'text_to_sign' || 
        type == 'sign_to_text') {
      return 'multiple_choice';
    }

    if (type == 'typing') return 'typing';
    if (type == 'fill_in_the_blank') return 'fill_in_the_blank';
    if (type == 'sequence_order') return 'sequence_order';
    if (type == 'matching_type') return 'matching_type';
    if (type == 'camera_spell') return 'camera_spell';
    
    if (type.contains('true') || type.contains('tf') || type == 'boolean') return 'true_false';
    if (type == 'identification' || type == 'ident') return 'identification';

    final opts = _extractOptions(q);
    if (opts.isEmpty) return 'identification';

    if (opts.length == 2) {
      final optStrings = opts.map((e) => e.toString().toLowerCase().trim()).toList();
      if (optStrings.contains('true') || optStrings.contains('false') ||
          optStrings.any((e) => e.contains('thumbs up') || e.contains('thumbs down'))) {
        return 'true_false';
      }
    }

    return 'multiple_choice';
  }

  Widget _buildSafeImage(String? imageSource, {double? height, double? width, BoxFit fit = BoxFit.contain}) {
    if (imageSource == null || imageSource.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    // Sign videos play with the shared activity player (play / pause).
    if (RegExp(r'\.(mp4|mov|webm|m4v)$', caseSensitive: false).hasMatch(Uri.decodeComponent(imageSource.trim().split('?').first))) {
      return SizedBox(height: height, width: width, child: ActivityVideo(url: imageSource.trim(), fit: BoxFit.cover, fallback: const Icon(Icons.videocam_off_rounded, size: 40, color: Colors.grey)));
    }

    final cleaned = imageSource
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll('\t', '')
        .replaceAll('\\', '/')
        .trim();

    final provider = _getImageProvider(cleaned);
    if (provider == null) {
      return _buildErrorBox("Invalid Image");
    }

    return Image(
      image: provider,
      height: height,
      width: width,
      fit: fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return SizedBox(
          height: height ?? 60,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        if (!cleaned.startsWith('assets/') && !cleaned.startsWith('http') && !_isRawBase64(cleaned)) {
          return Image.asset(
            cleaned,
            height: height,
            width: width,
            fit: fit,
            errorBuilder: (_, _, _) => _buildErrorBox("Asset Missing"),
          );
        }
        return _buildErrorBox("Image Error");
      },
    );
  }

  bool _isRawBase64(String str) {
    return str.length > 100 && !str.startsWith('http') && !str.contains('/') && !str.endsWith('.png') && !str.endsWith('.jpg');
  }

  Widget _buildErrorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x1FF44336),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x4DF44336)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_rounded, color: Colors.red, size: 20),
          const SizedBox(height: 2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 8, color: Colors.red, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarCircle({
    required String? avatarUrl,
    required String name,
    double radius = 22,
    Border? border,
    List<BoxShadow>? boxShadow,
  }) {
    final String initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'P';
    final theme = Theme.of(context);

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        boxShadow: boxShadow,
      ),
      child: ClipOval(
        child: (avatarUrl != null && avatarUrl.trim().isNotEmpty)
            ? _buildSafeImage(avatarUrl, fit: BoxFit.cover)
            : Container(
                color: theme.primaryColor.withAlpha(50),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: radius * 0.8,
                    color: theme.primaryColor,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildThemedFeedbackBanner(ThemeData theme, Color textColor) {
    if (!_hasAnswered || _questions.isEmpty) return const SizedBox.shrink();

    final currentQ = _questions[_currentQuestionIndex];
    final String correctAnswer = _extractCorrectAnswer(currentQ);
    final String type = _determineQuestionType(currentQ);

    bool isCorrect = false;
    if (type == 'sequence_order') {
      final options = _extractOptions(currentQ);
      isCorrect = _selectedAnswer == options.join(',');
    } else {
      isCorrect = _selectedAnswer.trim().toLowerCase() == correctAnswer.trim().toLowerCase();
    }

    final Color feedbackColor = isCorrect ? theme.colorScheme.primary : theme.colorScheme.error;

    AppThemeMode themeMode = AppThemeMode.defaultWarm;
    try {
      themeMode = Provider.of<ThemeProvider>(context, listen: false).themeMode;
    } catch (_) {}

    IconData feedbackIcon = Icons.cancel_rounded;
    String feedbackTitle = isCorrect ? "CORRECT!" : "INCORRECT";

    if (isCorrect) {
      switch (themeMode) {
        case AppThemeMode.galaxy:
          feedbackIcon = Icons.auto_awesome_rounded;
          feedbackTitle = "COSMIC SUCCESS! +50 pts";
          break;
        case AppThemeMode.enchantedForest:
          feedbackIcon = Icons.eco_rounded;
          feedbackTitle = "NATURAL BLOOM! +50 pts";
          break;
        case AppThemeMode.ocean:
          feedbackIcon = Icons.water_drop_rounded;
          feedbackTitle = "DEEP IMPACT! +50 pts";
          break;
        case AppThemeMode.cloudy:
          feedbackIcon = Icons.filter_drama_rounded;
          feedbackTitle = "SKY HIGH! +50 pts";
          break;
        case AppThemeMode.defaultWarm:
          feedbackIcon = Icons.star_rounded;
          feedbackTitle = "SUNNY STRIKE! +50 pts";
          break;
      }
    } else {
      feedbackTitle = _isImageRef(correctAnswer) 
          ? "INCORRECT" 
          : "Incorrect! Answer: $correctAnswer";
    }

    final glassTheme = theme.extension<GlassThemeExtension>();
    final Color bannerBorderColor = glassTheme?.glassBorder ?? feedbackColor;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.80, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.elasticOut,
      builder: (context, scaleValue, child) {
        return Transform.scale(
          scale: scaleValue,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  feedbackColor.withAlpha(80),
                  glassTheme?.glassCard ?? feedbackColor.withAlpha(40),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: isCorrect ? feedbackColor : bannerBorderColor, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: feedbackColor.withAlpha(120),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  feedbackIcon,
                  color: feedbackColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    feedbackTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMultipleChoiceOptions(List<dynamic> options, String correctAnswer, ThemeData theme, Color textColor, Map<String, int> answerCounts) {
    final bool isImageGrid = options.any((opt) {
      final str = opt.toString();
      return str.contains('assets/') || str.startsWith('http') || str.startsWith('data:image') || str.endsWith('.jpg') || str.endsWith('.png');
    });

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: isImageGrid ? 1.2 : 2.1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: options.length,
      itemBuilder: (context, index) {
        final rawOption = options[index];
        String optionText = '';
        String? optionImage;

        if (rawOption is Map) {
          final textVal = _getValueCaseInsensitive(Map<String, dynamic>.from(rawOption), ['text', 'label', 'title', 'value', 'option']);
          optionText = textVal?.toString() ?? '';
          final imgVal = _getValueCaseInsensitive(Map<String, dynamic>.from(rawOption), ['image', 'image_url', 'imageUrl', 'img', 'url', 'src', 'photo', 'path']);
          if (imgVal != null && imgVal.toString().trim().isNotEmpty) {
            optionImage = imgVal.toString().trim();
          }
        } else {
          final str = rawOption.toString().trim();
          if (str.startsWith('http') || str.startsWith('data:image') || str.endsWith('.png') || str.endsWith('.jpg') || str.contains('assets/')) {
            optionImage = str;
          } else {
            optionText = str;
          }
        }

        final String optionComparisonValue = optionText.isNotEmpty ? optionText : (optionImage ?? rawOption.toString());
        final bool isOptionSelected = _selectedAnswer.trim().toLowerCase() == optionComparisonValue.trim().toLowerCase();
        final bool isOptionCorrect = optionComparisonValue.trim().toLowerCase() == correctAnswer.trim().toLowerCase();
        final int selectCount = answerCounts[optionComparisonValue.trim().toLowerCase()] ?? 0;

        Color tileBg = theme.cardColor.withAlpha(200);
        Color borderColor = theme.colorScheme.outline.withAlpha(100);

        if (_hasAnswered) {
          if (isOptionCorrect) {
            tileBg = theme.colorScheme.primary.withAlpha(70);
            borderColor = theme.colorScheme.primary;
          } else if (isOptionSelected) {
            tileBg = theme.colorScheme.error.withAlpha(70);
            borderColor = theme.colorScheme.error;
          }
        }

        return AnimatedScale(
          scale: isOptionSelected ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: InkWell(
            onTap: _hasAnswered ? null : () => _submitAnswer(optionComparisonValue),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    tileBg,
                    tileBg.withAlpha(180),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: isOptionSelected || (_hasAnswered && isOptionCorrect) ? 2.5 : 1.5),
                boxShadow: [
                  BoxShadow(
                    color: (_hasAnswered && isOptionCorrect)
                        ? theme.colorScheme.primary.withAlpha(100)
                        : Colors.black.withAlpha(20),
                    blurRadius: (_hasAnswered && isOptionCorrect) ? 14 : 6,
                    spreadRadius: (_hasAnswered && isOptionCorrect) ? 1 : 0,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (optionImage != null && optionImage.isNotEmpty)
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _buildSafeImage(optionImage, fit: BoxFit.contain),
                            ),
                          ),
                        if (optionText.isNotEmpty) ...[
                          if (optionImage != null) const SizedBox(height: 4),
                          Text(
                            optionText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                  if (selectCount > 0)
                    Positioned(
                      top: 2, right: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [theme.primaryColor, theme.colorScheme.secondary],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_rounded, size: 10, color: Colors.white),
                            const SizedBox(width: 3),
                            Text("$selectCount", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrueFalseOptions(List<dynamic> options, String correctAnswer, ThemeData theme, Color textColor, Map<String, int> answerCounts) {
    List<dynamic> tfOptions = options.isNotEmpty ? options : ['True', 'False'];

    return Row(
      children: tfOptions.map((opt) {
        String optStr = opt.toString().trim();
        final bool isImage = optStr.contains('assets/') || optStr.endsWith('.jpg') || optStr.endsWith('.png') || optStr.startsWith('http');
        
        final bool isOptionSelected = _selectedAnswer.trim().toLowerCase() == optStr.toLowerCase();
        final bool isOptionCorrect = optStr.toLowerCase() == correctAnswer.toLowerCase();
        final int selectCount = answerCounts[optStr.toLowerCase()] ?? 0;

        Color tileBg = theme.cardColor.withAlpha(200);
        Color borderColor = theme.colorScheme.outline.withAlpha(100);

        if (_hasAnswered) {
          if (isOptionCorrect) {
            tileBg = theme.colorScheme.primary.withAlpha(70);
            borderColor = theme.colorScheme.primary;
          } else if (isOptionSelected) {
            tileBg = theme.colorScheme.error.withAlpha(70);
            borderColor = theme.colorScheme.error;
          }
        }

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: InkWell(
              onTap: _hasAnswered ? null : () => _submitAnswer(optStr),
              borderRadius: BorderRadius.circular(22),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [tileBg, tileBg.withAlpha(180)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: borderColor, width: isOptionSelected || (_hasAnswered && isOptionCorrect) ? 2.5 : 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: (_hasAnswered && isOptionCorrect) ? theme.colorScheme.primary.withAlpha(100) : Colors.black12,
                      blurRadius: 10, offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Center(
                      child: isImage
                          ? Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: _buildSafeImage(optStr, fit: BoxFit.contain),
                            )
                          : Text(
                              optStr.toUpperCase(),
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 1.0),
                            ),
                    ),
                    if (selectCount > 0)
                      Positioned(
                        top: 8, right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: theme.primaryColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.person_rounded, size: 12, color: Colors.white),
                              const SizedBox(width: 3),
                              Text("$selectCount", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTypingLayout(Map<String, dynamic> currentQuestion, ThemeData theme, Color textColor) {
    final givenFsl = _extractGivenFsl(currentQuestion);

    return SingleChildScrollView(
      child: Column(
        children: [
          Wrap(
            spacing: 8, runSpacing: 10,
            alignment: WrapAlignment.center,
            children: List.generate(_userAnswerSlots.length, (index) {
              final String? char = _userAnswerSlots[index];
              final givenMatch = givenFsl.where((item) => item['position'] == index);
              final Map<String, dynamic>? givenItem = givenMatch.isNotEmpty ? givenMatch.first : null;

              return InkWell(
                onTap: _hasAnswered ? null : () {
                  if (givenItem != null) return;
                  if (_userAnswerSlots[index] != null) {
                    setState(() {
                      _userAnswerSlots[index] = null;
                      _selectedOptionIndices[index] = null;
                    });
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 50, height: 58,
                  decoration: BoxDecoration(
                    color: char != null ? theme.primaryColor.withAlpha(50) : theme.cardColor.withAlpha(180),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: char != null ? theme.primaryColor : textColor.withAlpha(40),
                      width: char != null ? 2.5 : 1.5,
                    ),
                    boxShadow: char != null
                        ? [BoxShadow(color: theme.primaryColor.withAlpha(80), blurRadius: 8)]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: givenItem != null && givenItem['image'] != null && (givenItem['image'] as String).isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: _buildSafeImage(givenItem['image'], fit: BoxFit.contain),
                        )
                      : Text(char ?? '', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor)),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10, runSpacing: 10,
            alignment: WrapAlignment.center,
            children: List.generate(_shuffledOptions.length, (index) {
              final bool isUsed = _selectedOptionIndices.contains(index);
              final String optVal = _shuffledOptions[index];

              return InkWell(
                onTap: (isUsed || _hasAnswered) ? null : () {
                  int emptySlot = _userAnswerSlots.indexOf(null);
                  if (emptySlot != -1) {
                    setState(() {
                      _userAnswerSlots[emptySlot] = optVal;
                      _selectedOptionIndices[emptySlot] = index;
                    });
                  }
                },
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isUsed ? 0.25 : 1.0,
                  child: Container(
                    width: 54, height: 54,
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.primaryColor, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    padding: const EdgeInsets.all(5),
                    child: Center(
                      child: optVal.contains('/') || optVal.contains('.') || optVal.startsWith('http') || optVal.startsWith('data:image')
                          ? _buildSafeImage(optVal, fit: BoxFit.contain)
                          : _buildSafeImage('assets/pictures/${optVal.toUpperCase()}.jpg', fit: BoxFit.contain),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 18),
          if (!_hasAnswered)
            ElevatedButton(
              onPressed: _userAnswerSlots.contains(null) ? null : () => _submitAnswer(_userAnswerSlots.join('')),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: Button3DBorder(borderRadius: BorderRadius.circular(28)),
                elevation: 4,
              ),
              child: Text("SUBMIT ANSWER", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
            ),
        ],
      ),
    );
  }

  Widget _buildSequenceLayout(ThemeData theme, Color textColor) {
    return Column(
      children: [
        Container(
          width: double.infinity, height: 60,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.cardColor.withAlpha(200),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.primaryColor, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
          ),
          child: Wrap(
            spacing: 8, runSpacing: 8,
            children: _currentSequence.map((item) {
              return Chip(
                backgroundColor: theme.primaryColor.withAlpha(50),
                side: BorderSide(color: theme.primaryColor),
                label: Text(item, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                onDeleted: _hasAnswered ? null : () {
                  setState(() {
                    _currentSequence.remove(item);
                    _availableSequenceOptions.add(item);
                  });
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10, runSpacing: 10,
          children: _availableSequenceOptions.map((item) {
            return InkWell(
              onTap: _hasAnswered ? null : () {
                setState(() {
                  _currentSequence.add(item);
                  _availableSequenceOptions.remove(item);
                });
              },
              child: Chip(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                label: Text(item, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                backgroundColor: theme.cardColor,
                side: BorderSide(color: theme.colorScheme.outline),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        if (!_hasAnswered)
          ElevatedButton(
            onPressed: _availableSequenceOptions.isNotEmpty ? null : () => _submitAnswer(_currentSequence.join(',')),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              shape: Button3DBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: Text("SUBMIT ORDER", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold)),
          )
      ],
    );
  }

  bool _isMatchMedia(String s) => _isImageRef(s) || _MatchTile.isVideo(s);

  Widget _buildMatchingLayout(Map<String, dynamic> q, ThemeData theme, Color textColor) {
    final List<dynamic> options = _extractOptions(q);
    List<String> leftItems = [];
    List<String> rightItems = [];

    for (var opt in options) {
      String str = opt.toString();
      if (str.contains('|||')) {
        var parts = str.split('|||');
        leftItems.add(parts[0]);
        rightItems.add(parts[1]);
      } else {
        leftItems.add(str);
        rightItems.add(str);
      }
    }
    // Shuffled the same way on every player's phone (seeded by the round),
    // and stable across rebuilds.
    rightItems.shuffle(math.Random(_currentQuestionIndex * 7919 + leftItems.length));

    // Same tile size in both columns (_MatchTile): all square when either
    // column has pictures / videos, which fill their tile.
    final anyMedia = [...leftItems, ...rightItems].any(_isMatchMedia);
    Widget content(String item) => _isMatchMedia(item)
        ? _buildSafeImage(item, fit: BoxFit.cover)
        : Text(item, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: textColor));
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final item in leftItems)
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
                  for (var ri = 0; ri < rightItems.length; ri++)
                    () {
                      final item = rightItems[ri];
                      // Repeated answers: each tile is its own slot, taken in order.
                      final used = _matchingAnswers.values.where((v) => v == item).length;
                      final k = [for (var x = 0; x < ri; x++) if (rightItems[x] == item) x].length;
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
    );
  }

  Widget _buildIdentificationInput(String correctAnswer, ThemeData theme, Color textColor) {
    final bool isCorrect = _selectedAnswer.trim().toLowerCase() == correctAnswer.trim().toLowerCase();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextField(
          controller: _identificationController,
          enabled: !_hasAnswered,
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
          decoration: InputDecoration(
            hintText: "Type your answer here...",
            filled: true,
            fillColor: theme.cardColor.withAlpha(204),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: theme.primaryColor, width: 2.5)),
          ),
        ),
        const SizedBox(height: 16),
        if (!_hasAnswered)
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: () => _submitAnswer(_identificationController.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                shape: Button3DBorder(borderRadius: BorderRadius.circular(28)),
                elevation: 4,
              ),
              child: Text("SUBMIT ANSWER", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: isCorrect ? theme.colorScheme.primary.withAlpha(60) : theme.colorScheme.error.withAlpha(60),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isCorrect ? theme.colorScheme.primary : theme.colorScheme.error, width: 2),
            ),
            child: Text(
              isCorrect
                  ? "Correct!"
                  : (_isImageRef(correctAnswer) ? "Incorrect!" : "Correct Answer: $correctAnswer"),
              style: TextStyle(
                color: isCorrect ? theme.colorScheme.primary : theme.colorScheme.error,
                fontWeight: FontWeight.w900, fontSize: 16,
              ),
            ),
          )
      ],
    );
  }

  Widget _buildHorizontalPlayerList() {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomCode)
          .collection('players')
          .orderBy('score', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final docs = snapshot.data!.docs;

        return SizedBox(
          height: 96,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final player = docs[index].data() as Map<String, dynamic>;
              final bool isMe = player['uid'] == _currentUserId;
              final bool isLeader = index == 0;
              final String name = player['name'] ?? 'Player';
              final int score = player['score'] ?? 0;
              final String? avatarUrl = player['avatarUrl'] ?? player['photoUrl'] ?? player['avatar'];

              return Tooltip(
                message: isMe ? "$name (You)" : name,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(right: 12),
                  width: 64,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _buildAvatarCircle(
                            avatarUrl: avatarUrl,
                            name: name,
                            radius: 22,
                            border: Border.all(
                              color: isLeader
                                  ? const Color(0xFFFFD700)
                                  : (isMe ? theme.primaryColor : textColor.withAlpha(40)),
                              width: isLeader || isMe ? 2.5 : 1.5,
                            ),
                            boxShadow: isLeader
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFFFD700).withAlpha(120),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    )
                                  ]
                                : (isMe
                                    ? [
                                        BoxShadow(
                                          color: theme.primaryColor.withAlpha(80),
                                          blurRadius: 6,
                                        )
                                      ]
                                    : null),
                          ),
                          Positioned(
                            top: -4,
                            left: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isLeader
                                    ? const Color(0xFFFFD700)
                                    : (isMe ? theme.primaryColor : theme.cardColor),
                                shape: BoxShape.circle,
                                border: Border.all(color: theme.scaffoldBackgroundColor, width: 1.5),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 3)
                                ],
                              ),
                              child: Text(
                                "#${index + 1}",
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 9,
                                  color: isLeader ? Colors.black : (isMe ? Colors.white : textColor),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isMe ? "$name (You)" : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isMe ? FontWeight.w900 : FontWeight.bold,
                          color: isMe ? theme.primaryColor : textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: theme.cardColor.withAlpha(200),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isMe ? theme.primaryColor.withAlpha(100) : textColor.withAlpha(20),
                          ),
                        ),
                        child: Text(
                          "$score pts",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 9,
                            color: isMe ? theme.primaryColor : textColor.withAlpha(200),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showFinalLeaderboard() {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('rooms')
              .doc(widget.roomCode)
              .collection('players')
              .orderBy('score', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const AlertDialog(
                content: SizedBox(
                  height: 100, 
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final docs = snapshot.data!.docs;
            final List<Map<String, dynamic>> players = 
                docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

            final top3 = players.take(3).toList();
            final remaining = players.length > 3 ? players.sublist(3) : <Map<String, dynamic>>[];

            return AlertDialog(
              backgroundColor: theme.scaffoldBackgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              title: const Column(
                children: [
                  Text("🏆", style: TextStyle(fontSize: 48)),
                  SizedBox(height: 6),
                  Text(
                    "VICTORY BOARD",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: 1.0),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPodiumSection(top3, theme, textColor),
                      const SizedBox(height: 18),
                      if (remaining.isNotEmpty) ...[
                        const Divider(),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: remaining.length,
                          itemBuilder: (context, index) {
                            final player = remaining[index];
                            final rank = index + 4;
                            final String name = player['name'] ?? 'Player';
                            final String? avatarUrl = player['avatarUrl'] ?? player['photoUrl'] ?? player['avatar'];

                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 24,
                                    child: Text(
                                      "#$rank",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: textColor.withAlpha(150),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  _buildAvatarCircle(
                                    avatarUrl: avatarUrl,
                                    name: name,
                                    radius: 18,
                                    border: Border.all(
                                      color: textColor.withAlpha(40),
                                      width: 1,
                                    ),
                                  ),
                                ],
                              ),
                              title: Text(
                                name,
                                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              trailing: Text(
                                "${player['score']} pts",
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: theme.primaryColor,
                                  fontSize: 13,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _deleteRoomAndExit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: Button3DBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      "EXIT TO MAIN MENU",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPodiumSection(
    List<Map<String, dynamic>> top3, 
    ThemeData theme, 
    Color textColor,
  ) {
    if (top3.isEmpty) return const SizedBox.shrink();

    final first = top3.isNotEmpty ? top3[0] : null;
    final second = top3.length > 1 ? top3[1] : null;
    final third = top3.length > 2 ? top3[2] : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (second != null)
          _buildPodiumColumn(
            player: second,
            rank: 2,
            height: 95,
            badgeGradient: const [Color(0xFFE0E0E0), Color(0xFF9E9E9E)],
            icon: "🥈",
            theme: theme,
            textColor: textColor,
          )
        else
          const SizedBox(width: 80),

        const SizedBox(width: 8),

        if (first != null)
          _buildPodiumColumn(
            player: first,
            rank: 1,
            height: 130,
            badgeGradient: const [Color(0xFFFFD700), Color(0xFFFFA500)],
            icon: "🥇",
            theme: theme,
            textColor: textColor,
          ),

        const SizedBox(width: 8),

        if (third != null)
          _buildPodiumColumn(
            player: third,
            rank: 3,
            height: 75,
            badgeGradient: const [Color(0xFFCD7F32), Color(0xFF8B4513)],
            icon: "🥉",
            theme: theme,
            textColor: textColor,
          )
        else
          const SizedBox(width: 80),
      ],
    );
  }

  Widget _buildPodiumColumn({
    required Map<String, dynamic> player,
    required int rank,
    required double height,
    required List<Color> badgeGradient,
    required String icon,
    required ThemeData theme,
    required Color textColor,
  }) {
    final String name = player['name'] ?? 'Player';
    final int score = player['score'] ?? 0;
    final String? avatarUrl = player['avatarUrl'] ?? player['photoUrl'] ?? player['avatar'];

    final double avatarRadius = rank == 1 ? 26 : 22;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: TextStyle(fontSize: rank == 1 ? 28 : 22)),
          const SizedBox(height: 4),

          _buildAvatarCircle(
            avatarUrl: avatarUrl,
            name: name,
            radius: avatarRadius,
            border: Border.all(
              color: badgeGradient.first,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: badgeGradient.first.withAlpha(100),
                blurRadius: 8,
              )
            ],
          ),
          const SizedBox(height: 6),

          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: rank == 1 ? 13 : 11,
              color: textColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),

          Text(
            "$score pts",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: theme.primaryColor,
            ),
          ),
          const SizedBox(height: 6),

          Container(
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: badgeGradient,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
            ),
            child: Center(
              child: Text(
                "#$rank",
                style: TextStyle(
                  fontSize: rank == 1 ? 30 : 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  shadows: const [Shadow(color: Colors.black45, blurRadius: 4)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRoomAndExit() async {
    if (_isCleaningUp) return;
    setState(() => _isCleaningUp = true);

    try {
      final roomRef = FirebaseFirestore.instance.collection('rooms').doc(widget.roomCode);
      if (widget.isHost) {
        final playersSnapshot = await roomRef.collection('players').get();
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in playersSnapshot.docs) {
          batch.delete(doc.reference);
        }
        batch.delete(roomRef);
        await batch.commit();
      } else {
        await roomRef.collection('players').doc(_currentUserId).delete();
      }
    } catch (e) {
      debugPrint("Error deleting room data: $e");
    } finally {
      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final glassTheme = theme.extension<GlassThemeExtension>();

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator(color: theme.primaryColor)),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(child: Text("No questions found for this category.", style: TextStyle(color: textColor, fontWeight: FontWeight.bold))),
      );
    }

    final currentQuestion = _questions[_currentQuestionIndex];
    final String questionText = _extractQuestionText(currentQuestion);
    final String? questionImageUrl = _extractQuestionImage(currentQuestion);
    final List<dynamic> options = _extractOptions(currentQuestion);
    final String correctAnswer = _extractCorrectAnswer(currentQuestion);
    final String questionType = _determineQuestionType(currentQuestion);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: glassTheme?.glassCard ?? theme.cardColor.withAlpha(180),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: glassTheme?.glassBorder ?? textColor.withAlpha(30)),
          ),
          child: Text(
            "ROUND ${_currentQuestionIndex + 1} OF ${_questions.length}",
            style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.0),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: theme.cardColor, shape: BoxShape.circle),
              child: Icon(Icons.close_rounded, color: textColor, size: 20),
            ),
            onPressed: _deleteRoomAndExit,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHorizontalPlayerList(),
              const SizedBox(height: 12),

              if (_maxTime > 0) ...[
                Row(
                  children: [
                    Icon(Icons.timer_sharp, size: 18, color: _timeLeft < 5 ? theme.colorScheme.error : theme.primaryColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: (_timeLeft / _maxTime).clamp(0.0, 1.0),
                          backgroundColor: textColor.withAlpha(30),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _timeLeft < 5 ? theme.colorScheme.error : theme.primaryColor,
                          ),
                          minHeight: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "${_timeLeft}s",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: _timeLeft < 5 ? theme.colorScheme.error : textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        glassTheme?.glassCard ?? theme.cardColor.withAlpha(220),
                        theme.cardColor.withAlpha(160),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: glassTheme?.glassBorder ?? textColor.withAlpha(30), width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withAlpha(35),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _category.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: theme.primaryColor,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (questionText.isNotEmpty)
                                Text(
                                  questionText,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textColor, height: 1.3),
                                  textAlign: TextAlign.center,
                                ),
                              if (questionImageUrl != null) ...[
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: textColor.withAlpha(30)),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: _buildSafeImage(questionImageUrl, height: 150),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _buildThemedFeedbackBanner(theme, textColor),

              Expanded(
                flex: 5,
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('rooms').doc(widget.roomCode).collection('players').snapshots(),
                  builder: (context, snapshot) {
                    Map<String, int> answerCounts = {};

                    if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                      final docs = snapshot.data!.docs;

                      bool showAnswerCounts = false;
                      if (_maxTime > 0) {
                        showAnswerCounts = (_timeLeft == 0);
                      } else {
                        showAnswerCounts = docs.every((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final int qIndex = data['currentQuestionIndex'] ?? -1;
                          final String ans = (data['currentAnswer'] ?? '').toString().trim();
                          return qIndex == _currentQuestionIndex && ans.isNotEmpty;
                        });
                      }

                      if (showAnswerCounts) {
                        for (var doc in docs) {
                          final data = doc.data() as Map<String, dynamic>;
                          final int qIndex = data['currentQuestionIndex'] ?? -1;
                          final String ans = (data['currentAnswer'] ?? '').toString().trim().toLowerCase();
                          if (qIndex == _currentQuestionIndex && ans.isNotEmpty) {
                            answerCounts[ans] = (answerCounts[ans] ?? 0) + 1;
                          }
                        }
                      }
                    }

                    switch (questionType) {
                      case 'true_false':
                        return _buildTrueFalseOptions(options, correctAnswer, theme, textColor, answerCounts);
                      case 'typing':
                        return _buildTypingLayout(currentQuestion, theme, textColor);
                      case 'sequence_order':
                        return _buildSequenceLayout(theme, textColor);
                      case 'matching_type':
                        return _buildMatchingLayout(currentQuestion, theme, textColor);
                      case 'camera_spell':
                        return (RegExp(r'^([A-Za-z]|\d+)$').hasMatch(correctAnswer.trim())
                                ? ChallengeCameraSign(sign: correctAnswer, enabled: !_hasAnswered, onResult: _onCameraResult)
                                : PublishedCameraSign(category: _category, sign: correctAnswer, enabled: !_hasAnswered, onResult: _onCameraResult));
                      case 'identification':
                        return _buildIdentificationInput(correctAnswer, theme, textColor);
                      case 'multiple_choice':
                      default:
                        return _buildMultipleChoiceOptions(options, correctAnswer, theme, textColor, answerCounts);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ViewfinderCornersPainter extends CustomPainter {
  final Color color;
  final double pulseValue;

  ViewfinderCornersPainter({required this.color, required this.pulseValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withAlpha((180 + (pulseValue * 75)).toInt())
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 22.0;

    canvas.drawPath(
      Path()
        ..moveTo(0, cornerLength)
        ..lineTo(0, 0)
        ..lineTo(cornerLength, 0),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLength, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, cornerLength),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - cornerLength)
        ..lineTo(0, size.height)
        ..lineTo(cornerLength, size.height),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(size.width - cornerLength, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, size.height - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant ViewfinderCornersPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pulseValue != pulseValue;
}

// =============================================================================
// CAMERA HELPERS (local to this screen)
// =============================================================================

/// One item of a matching question (all categories). A picture or video is
/// a square tile the width of its column, filled edge to edge (videos keep
/// their play button; a tap on the rest of the tile selects it), so it is
/// big enough to read; text is a compact tile. [fill] / [border] show the
/// item's state (selected, matched, right / wrong).
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
          height: sq ? null : 64,
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
