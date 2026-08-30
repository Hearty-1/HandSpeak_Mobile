import 'dart:convert';
import 'dart:async'; 
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '/providers/sound_provider.dart';
import 'recognizer.dart'; 

// ==========================================
// 1. DATA MODELS
// ==========================================
class GivenFslItem {
  final int position;
  final String letter;
  final String image;

  GivenFslItem({
    required this.position,
    required this.letter,
    required this.image,
  });

  factory GivenFslItem.fromJson(Map<String, dynamic> json) {
    return GivenFslItem(
      position: json['position'] ?? 0,
      letter: json['letter'] ?? '',
      image: json['image'] ?? json['image_url'] ?? '',
    );
  }
}

class QuizQuestion {
  final String id;
  final String type;
  final String imageUrl;
  final String questionText;
  final List<String> options;
  final String correctAnswer;
  final List<GivenFslItem> givenFsl;

  QuizQuestion({
    required this.id,
    required this.type,
    required this.imageUrl,
    required this.questionText,
    required this.options,
    required this.correctAnswer,
    required this.givenFsl,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      id: json['id']?.toString() ?? '',
      type: json['type'] ?? 'sign_to_text',
      imageUrl: json['image_url'] ?? json['main_image'] ?? '',
      questionText: json['question_text'] ?? '',
      options: List<String>.from(json['options'] ?? []),
      correctAnswer: json['correct_answer'] ?? '',
      givenFsl: (json['given_fsl'] as List<dynamic>?)
              ?.map((e) => GivenFslItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class QuizApiService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<List<QuizQuestion>> fetchEasyQuestions(String levelId, String typeFilter) async {
    // Query Firestore strictly for questions belonging to this specific level ID
    final querySnapshot = await _db
        .collection('activity_questions')
        .where('category', isEqualTo: 'alphabet')
        .where('level', isEqualTo: levelId)
        .get();

    if (querySnapshot.docs.isEmpty) {
      throw Exception("LEVEL NOT FOUND!\n\nNo questions match levelId: '$levelId'.");
    }

    List<QuizQuestion> levelQuestions = [];
    for (var doc in querySnapshot.docs) {
      final data = doc.data();
      data['id'] = doc.id;
      levelQuestions.add(QuizQuestion.fromJson(data));
    }

    // Try filtering by specific type filter first
    List<QuizQuestion> matchingQuestions = levelQuestions.where((q) => q.type == typeFilter).toList();

    // If filtering by type excludes remaining questions in the level, fall back to all level questions
    List<QuizQuestion> finalQuestions = (matchingQuestions.length >= levelQuestions.length && matchingQuestions.isNotEmpty)
        ? matchingQuestions
        : levelQuestions;

    finalQuestions.shuffle();

    // Enforce 5 questions maximum per session
    return finalQuestions.take(5).toList();
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

  String get _formattedLevelName {
    final match = RegExp(r'\d+').firstMatch(widget.levelId);
    if (match != null) {
      return "Level ${match.group(0)}";
    }
    return widget.levelId.replaceAll('_', ' ');
  }

  LinearGradient _getDialogGradient(Color bgColor) {
    if (bgColor.value == 0xFF0F0C29) {
      return const LinearGradient(colors: [Color(0xFF240B36), Color(0xFFC31432)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    } else if (bgColor.value == 0xFF132A13) {
      return const LinearGradient(colors: [Color(0xFF134E5E), Color(0xFF71B280)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    } else if (bgColor.value == 0xFF001B3A) {
      return const LinearGradient(colors: [Color(0xFF005C97), Color(0xFF363795)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    } else if (bgColor.value == 0xFFE0EAFC) {
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

  // Typing Game State Variables
  List<String?> _userAnswerSlots = [];
  List<int?> _selectedOptionIndices = [];
  List<String> _shuffledOptions = [];

  // ---------------------------------------------------------
  // CAMERA & ML PIPELINE VARIABLES
  // ---------------------------------------------------------
  CameraController? _cameraController;
  HandLandmarkerPlugin? _landmarkerPlugin;
  StreamSubscription<List<Hand>>? _handSub;

  bool _isCameraInitialized = false;

  static const double _requiredHoldSeconds = 1.0;
  DateTime? _staticHoldStartTime;

  bool _isRecordingMotion = false;
  DateTime? _startRecordingTime;
  final List<Float32List> _recordingFrames = [];
  static const Duration _dropoutGracePeriod = Duration(milliseconds: 300);
  DateTime? _lastHandsSeenTime;

  static const List<String> _dynamicLetters = ['J', 'Z'];
  bool get _isDynamicLetter {
    if (_questions.isEmpty) return false;
    return _dynamicLetters.contains(_questions[_currentIndex].correctAnswer.toUpperCase());
  }
  
  PhraseRecognizer? _dynamicSignRecognizer;
  bool _dynamicModelReady = false;

  List<dynamic>? _template;
  double _currentScore = 0.0;
  double _holdProgress = 0.0;
  final double successThreshold = 70.0; 
  // ---------------------------------------------------------

  late AnimationController _feedbackAnimController;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _loadQuestions();

    if (widget.questionType == 'camera_spell' || widget.levelId.contains('hard')) {
      _initializeCameraPipeline();
    }

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
    _handSub?.cancel();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _landmarkerPlugin?.dispose();
    _dynamicSignRecognizer?.dispose();
    _feedbackAnimController.dispose();
    super.dispose();
  }

  // ==========================================
  // PIPELINE AND ML LOGIC
  // ==========================================
  Future<void> _initializeCameraPipeline() async {
    try {
      _landmarkerPlugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.gpu, 
      );
      _handSub = _landmarkerPlugin!.landmarkStream.listen(_onHandsDetected);

      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final frontCamera = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );
        _cameraController = CameraController(
          frontCamera, 
          ResolutionPreset.medium, 
          enableAudio: false,
        );
        await _cameraController!.initialize();
        await _cameraController!.startImageStream(_processCameraFrame);
      }

      try {
        _dynamicSignRecognizer = PhraseRecognizer(
          modelAssetPath: 'assets/alphabet/model.tflite', 
          labelAssetPath: 'assets/alphabet/label_map.json', 
        );
        await _dynamicSignRecognizer!.initialize();
        _dynamicModelReady = true;
      } catch (e) {
        debugPrint("J/Z dynamic-sign model failed to load: $e");
        _dynamicModelReady = false;
      }

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Camera Pipeline Setup Failed: $e");
    }
  }

  Future<void> _loadGestureLibrary(String letter) async {
    try {
      String jsonString = await rootBundle.loadString('assets/alphabet/$letter.json');
      setState(() {
        _template = jsonDecode(jsonString);
      });
    } catch (e) {
      debugPrint("Could not find gesture resource profile for: $letter");
      setState(() {
        _template = null;
      });
    }
  }

  void _processCameraFrame(CameraImage image) {
    if (!_isCameraInitialized || _landmarkerPlugin == null || _isAnswered) return;
    try {
      final int sensorOrientation = _cameraController!.description.sensorOrientation;
      _landmarkerPlugin!.processFrame(image, sensorOrientation);
    } catch (e) {
      debugPrint("Inference Error: $e");
    }
  }

  void _onHandsDetected(List<Hand> detectedHands) {
    if (_isAnswered) return;

    final now = DateTime.now();

    if (_isDynamicLetter) {
      if (!_dynamicModelReady || _dynamicSignRecognizer == null) return;

      final bool handsPresent = detectedHands.isNotEmpty;
      final targetLetter = _questions[_currentIndex].correctAnswer.toUpperCase();

      if (handsPresent) {
        _lastHandsSeenTime = now;
        if (!_isRecordingMotion) {
           _isRecordingMotion = true;
           _startRecordingTime = now;
           _recordingFrames.clear();
        }

        _recordingFrames.add(_dynamicSignRecognizer!.extractFrameFeatures(detectedHands));
        final double elapsedSeconds = now.difference(_startRecordingTime!).inMilliseconds / 1000.0;

        if (mounted) {
          setState(() {
            _holdProgress = (elapsedSeconds / _requiredHoldSeconds).clamp(0.0, 1.0); 
          });
        }

        if (elapsedSeconds >= _requiredHoldSeconds) {
           _isRecordingMotion = false;
           final result = _dynamicSignRecognizer!.predictFromRecording(_recordingFrames);
           _recordingFrames.clear();

           double finalScore = 0.0;
           if (result != null && result.label.toUpperCase() == targetLetter) {
               double rawConfidence = result.confidence;
               double normalizedConfidence = rawConfidence > 1.0 ? rawConfidence : rawConfidence * 100.0;
               finalScore = normalizedConfidence.clamp(0.0, 100.0);
           }
           
           _currentScore = finalScore;
           _holdProgress = 0.0;

           if (_currentScore >= successThreshold) {
             _verifyCurrentAnswer();
           } else {
             _startRecordingTime = null;
           }
        }
      } else if (_isRecordingMotion) {
        final lastSeen = _lastHandsSeenTime;
        final bool withinGrace = lastSeen != null && now.difference(lastSeen) <= _dropoutGracePeriod;
        if (!withinGrace) {
          if (mounted) {
            setState(() {
                _isRecordingMotion = false;
                _startRecordingTime = null;
                _holdProgress = 0.0;
            });
          }
          _recordingFrames.clear();
        }
      }
      return;
    }

    if (_template == null) return; 

    if (detectedHands.isNotEmpty) {
      double highestScoreAcrossAllHands = 0.0;
      for (int handIdx = 0; handIdx < detectedHands.length; handIdx++) {
        final double score = _calculateScore(detectedHands[handIdx].landmarks, _template!);
        if (score > highestScoreAcrossAllHands) highestScoreAcrossAllHands = score;
      }

      _currentScore = highestScoreAcrossAllHands;

      if (_currentScore >= successThreshold) {
        _staticHoldStartTime ??= now;
        final double holdSecs = now.difference(_staticHoldStartTime!).inMilliseconds / 1000.0;
        _holdProgress = (holdSecs / _requiredHoldSeconds).clamp(0.0, 1.0);

        if (holdSecs >= _requiredHoldSeconds) {
          _staticHoldStartTime = null;
          _holdProgress = 1.0;
          _verifyCurrentAnswer();
          return;
        }
      } else {
        _staticHoldStartTime = null;
        _holdProgress = 0.0;
      }

      if (mounted) {
        setState(() {});
      }
    } else {
      _staticHoldStartTime = null;
      _currentScore = 0.0;
      _holdProgress = 0.0;
      if (mounted) {
        setState(() {});
      }
    }
  }

  double _calculateScore(List<Landmark> liveLms, List<dynamic> template) {
    if (liveLms.isEmpty || template.length < 21 || liveLms.length < 21) return 0.0;
    final String letter = _questions[_currentIndex].correctAnswer.toUpperCase();

    if (['G', 'H', 'K', 'P', 'Q'].contains(letter)) {
      final Landmark wrist = liveLms[0];
      final Landmark mBase = liveLms[9]; 
      final Landmark indexTip = liveLms[8];

      double dist = math.sqrt(math.pow(wrist.x - mBase.x, 2) + math.pow(wrist.y - mBase.y, 2));
      double distIndex = math.sqrt(math.pow(wrist.x - indexTip.x, 2) + math.pow(wrist.y - indexTip.y, 2));
      dist = math.max(dist, distIndex * 0.55);
      if (dist < 0.05) dist = 0.05; 
      
      double bestScore = 0.0;
      final List<int> highPriorityLandmarks = [4, 8, 12]; 

      final orientationMatrices = [
        [1.0, 0.0, 0.0, 1.0, 1.0],     
        [0.0, -1.0, 1.0, 0.0, 1.0],    
        [-1.0, 0.0, 0.0, -1.0, 1.0],   
        [0.0, 1.0, -1.0, 0.0, 1.0],    
        [1.0, 0.0, 0.0, 1.0, -1.0],    
        [0.0, -1.0, 1.0, 0.0, -1.0],   
        [-1.0, 0.0, 0.0, -1.0, -1.0],  
        [0.0, 1.0, -1.0, 0.0, -1.0],   
      ];

      for (int mIdx = 0; mIdx < orientationMatrices.length; mIdx++) {
        if (['G', 'H', 'P', 'Q'].contains(letter) && (mIdx == 0 || mIdx == 2 || mIdx == 4 || mIdx == 6)) continue; 

        var matrix = orientationMatrices[mIdx];
        double xx = matrix[0], xy = matrix[1], yx = matrix[2], yy = matrix[3], flipX = matrix[4];
        double totalWeightedDifference = 0.0, totalWeight = 0.0;

        for (int i = 0; i < 21; i++) {
          double dx = ((liveLms[i].x - wrist.x) / dist) * flipX;
          double dy = (liveLms[i].y - wrist.y) / dist;
          double rx = dx * xx + dy * xy;
          double ry = dx * yx + dy * yy;
          double tx = (template[i]['x'] as num).toDouble();
          double ty = (template[i]['y'] as num).toDouble();
          double pointDiff = math.sqrt(math.pow(rx - tx, 2) + math.pow(ry - ty, 2));
          double weight = highPriorityLandmarks.contains(i) ? 1.5 : 1.0;
          totalWeightedDifference += (pointDiff * weight);
          totalWeight += weight;
        }

        double score = (100.0 - ((totalWeightedDifference / totalWeight) * 45.0)).clamp(0.0, 100.0);
        if (score > bestScore) bestScore = score;
      }
      return bestScore;

    } else {
      final Landmark wrist = liveLms[0];
      final Landmark mBase = liveLms[9]; 
      
      double dist = math.sqrt(math.pow(wrist.x - mBase.x, 2) + math.pow(wrist.y - mBase.y, 2) + math.pow(wrist.z - mBase.z, 2));
      if (dist == 0) dist = 1.0;
      
      double bestScore = 0.0;
      final orientationMatrices = [
        [1.0, 0.0, 0.0, 1.0, 1.0],
        [0.0, -1.0, 1.0, 0.0, 1.0],
        [-1.0, 0.0, 0.0, -1.0, 1.0],
        [0.0, 1.0, -1.0, 0.0, 1.0],
        [1.0, 0.0, 0.0, 1.0, -1.0],
        [0.0, -1.0, 1.0, 0.0, -1.0],
        [-1.0, 0.0, 0.0, -1.0, -1.0],
        [0.0, 1.0, -1.0, 0.0, -1.0],
      ];

      for (var matrix in orientationMatrices) {
        double xx = matrix[0], xy = matrix[1], yx = matrix[2], yy = matrix[3], flipX = matrix[4];
        double totalDifference = 0.0;

        for (int i = 0; i < 21; i++) {
          double dx = ((liveLms[i].x - wrist.x) / dist) * flipX;
          double dy = (liveLms[i].y - wrist.y) / dist;
          double dz = (liveLms[i].z - wrist.z) / dist;
          double rx = dx * xx + dy * xy;
          double ry = dx * yx + dy * yy;
          double tx = (template[i]['x'] as num).toDouble();
          double ty = (template[i]['y'] as num).toDouble();
          double tz = ((template[i]['z'] ?? 0.0) as num).toDouble();
          
          double pointDiff = math.sqrt(math.pow(rx - tx, 2) + math.pow(ry - ty, 2) + math.pow(dz - tz, 2));
          totalDifference += pointDiff;
        }

        double score = (100.0 - ((totalDifference / 21.0) * 80.0)).clamp(0.0, 100.0);
        if (score > bestScore) bestScore = score;
      }
      return bestScore;
    }
  }

  Future<void> _loadQuestions() async {
    try {
      final questions = await _apiService.fetchEasyQuestions(widget.levelId, widget.questionType);
      setState(() {
        _questions = questions;
        _isLoading = false;
        if (_questions.isNotEmpty) {
          _setupQuestionState(_currentIndex);
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll("Exception: ", "");
        _isLoading = false;
      });
    }
  }

  void _setupQuestionState(int index) {
    final q = _questions[index];
    _selectedAnswer = null;
    _isAnswered = false;

    if (widget.questionType == 'camera_spell' || widget.levelId.contains('hard')) {
      _isRecordingMotion = false;
      _staticHoldStartTime = null;
      _currentScore = 0.0;
      _holdProgress = 0.0;
      _loadGestureLibrary(q.correctAnswer.toUpperCase());
    } else if (q.type == 'typing') {
      final String target = q.correctAnswer.toUpperCase();
      _userAnswerSlots = List<String?>.filled(target.length, null);
      _selectedOptionIndices = List<int?>.filled(target.length, null);

      for (var item in q.givenFsl) {
        if (item.position >= 0 && item.position < target.length) {
          _userAnswerSlots[item.position] = item.letter.toUpperCase();
        }
      }

      _shuffledOptions = List<String>.from(q.options)..shuffle();
    }
  }

  void _handleOptionSelected(String option) {
    if (_isAnswered) return;
    setState(() => _selectedAnswer = option);
  }

  void _selectTypingLetter(int optionIndex) {
    if (_isAnswered) return;
    int emptySlotIndex = _userAnswerSlots.indexOf(null);
    if (emptySlotIndex == -1) return;

    setState(() {
      _userAnswerSlots[emptySlotIndex] = _shuffledOptions[optionIndex];
      _selectedOptionIndices[emptySlotIndex] = optionIndex;
    });
  }

  void _removeTypingLetter(int slotIndex) {
    if (_isAnswered) return;
    final q = _questions[_currentIndex];
    bool isGivenFixedLetter = q.givenFsl.any((item) => item.position == slotIndex);
    if (isGivenFixedLetter) return;

    if (_userAnswerSlots[slotIndex] != null) {
      setState(() {
        _userAnswerSlots[slotIndex] = null;
        _selectedOptionIndices[slotIndex] = null;
      });
    }
  }

  void _verifyCurrentAnswer() {
    if (_isAnswered) return;
    final q = _questions[_currentIndex];
    bool isCorrect = false;

    if (widget.questionType == 'camera_spell' || widget.levelId.contains('hard')) {
      isCorrect = _currentScore >= successThreshold;
      _selectedAnswer = isCorrect ? q.correctAnswer : null; 
    } else if (q.type == 'typing') {
      final userWord = _userAnswerSlots.join('');
      isCorrect = userWord.toUpperCase() == q.correctAnswer.toUpperCase();
    } else {
      isCorrect = _selectedAnswer == q.correctAnswer;
    }

    setState(() {
      _isAnswered = true;
      _isCorrect = isCorrect;

      final soundProvider = Provider.of<SoundProvider>(context, listen: false);
      _isCorrect ? soundProvider.playCorrect() : soundProvider.playIncorrect();

      if (!_isCorrect) {
        _hearts--;
        if (_hearts <= 0) _showGameOverDialog();
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
        _setupQuestionState(_currentIndex);
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
              final Map<String, dynamic> progress = data['progress'] != null ? Map<String, dynamic>.from(data['progress']) : {};
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

    if (bgColor == 0xFF0F0C29) {
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
    
    if (bgColor == 0xFF132A13) {
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

    if (bgColor == 0xFF001B3A) {
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

    if (bgColor == 0xFFE0EAFC) {
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
    if (!_isAnswered) return option == _selectedAnswer ? theme.primaryColor.withOpacity(0.2) : theme.cardColor;
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
    if (!_isAnswered) return option == _selectedAnswer ? theme.primaryColor : theme.dividerColor;
    if (option == correctAnswer) return const Color(0xFF58CC02);
    if (option == _selectedAnswer && option != correctAnswer) return const Color(0xFFEA2B2B);
    return theme.dividerColor;
  }

  bool get _isCheckButtonEnabled {
    if (widget.questionType == 'camera_spell' || widget.levelId.contains('hard')) return true; 
    final q = _questions[_currentIndex];
    if (q.type == 'typing') return !_userAnswerSlots.contains(null);
    return _selectedAnswer != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

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
    if (_isLoading) return Center(child: CircularProgressIndicator(color: theme.primaryColor));
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        )
      );
    }
    if (_questions.isEmpty) return Center(child: Text("No questions available.", style: TextStyle(color: textColor)));

    final currentQuestion = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;
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
                      height: 200,
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
                    const SizedBox(height: 24),
                  ],

                  Text(
                    currentQuestion.questionText,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textColor),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  if (widget.questionType == 'camera_spell' || widget.levelId.contains('hard'))
                    _buildCameraLayout(currentQuestion, theme)
                  else if (currentQuestion.type == 'typing')
                    _buildTypingLayout(currentQuestion, theme)
                  else
                    _buildMultipleChoiceLayout(currentQuestion, theme),
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
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 16, offset: const Offset(0, -4))]
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
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 2))],
                              ),
                              child: Icon(feedbackData['icon'] as IconData, color: Colors.white, size: 32),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  feedbackData['title'] as String,
                                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isCorrect 
                                      ? (feedbackData['subtitle'] as String)
                                      : "Correct Answer: ${currentQuestion.correctAnswer}",
                                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  if (!_isAnswered && (widget.questionType == 'camera_spell' || widget.levelId.contains('hard'))) ...[
                    Container(
                      width: double.infinity,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.videocam_rounded, color: theme.primaryColor, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            "Hold sign steadily in front of camera",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: theme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSaving
                            ? null
                            : (_isAnswered
                                ? _handleNext
                                : (_isCheckButtonEnabled ? _verifyCurrentAnswer : null)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: !_isAnswered ? theme.primaryColor : Colors.white,
                          disabledBackgroundColor: theme.dividerColor,
                          elevation: _isAnswered ? 4 : 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isSaving
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: theme.primaryColor, strokeWidth: 2))
                            : Text(
                                _isAnswered ? "CONTINUE" : "CHECK",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: !_isAnswered ? theme.colorScheme.onPrimary : (feedbackData['accentColor'] as Color),
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraLayout(QuizQuestion currentQuestion, ThemeData theme) {
    bool isPassing = _currentScore >= successThreshold;
    
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1 / 1.1, 
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                width: 4.0,
                color: isPassing ? Colors.greenAccent : theme.dividerColor.withOpacity(0.6),
              ),
              boxShadow: [
                if (isPassing) BoxShadow(color: Colors.greenAccent.withOpacity(0.6), blurRadius: 25, spreadRadius: 2)
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _isCameraInitialized && _cameraController != null
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _cameraController!.value.previewSize?.height ?? 1,
                        height: _cameraController!.value.previewSize?.width ?? 1,
                        child: CameraPreview(_cameraController!),
                      ),
                    )
                  : Center(child: CircularProgressIndicator(color: theme.primaryColor)),
            ),
          ),
        ),
        const SizedBox(height: 24),

        if (_holdProgress > 0.0) ...[
          Column(
            children: [
              Text(
                _isDynamicLetter ? "Recording motion..." : "Holding sign steady...",
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 220, 
                  height: 16,
                  decoration: BoxDecoration(
                    color: theme.dividerColor, 
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _holdProgress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.greenAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )
        ] else ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: isPassing ? Colors.green.withOpacity(0.2) : theme.cardColor,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isPassing ? Colors.greenAccent.withOpacity(0.6) : theme.dividerColor,
                width: 2
              ),
            ),
            child: Text(
              "Sign Match: ${_currentScore.toStringAsFixed(1)}%",
              style: TextStyle(
                color: isPassing ? Colors.green : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMultipleChoiceLayout(QuizQuestion currentQuestion, ThemeData theme) {
    final isImageOption = currentQuestion.options.isNotEmpty && 
                          (currentQuestion.options[0].contains('.png') || 
                           currentQuestion.options[0].contains('.jpg'));

    return GridView.count(
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
              border: Border.all(color: _getButtonBorderColor(option, currentQuestion.correctAnswer, theme), width: 2),
            ),
            alignment: Alignment.center,
            child: isImageOption
                ? Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Image.asset(
                      option,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Text(option, style: TextStyle(fontSize: 14, color: _getButtonTextColor(option, currentQuestion.correctAnswer, theme))),
                    ),
                  )
                : Text(option, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _getButtonTextColor(option, currentQuestion.correctAnswer, theme))),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTypingLayout(QuizQuestion currentQuestion, ThemeData theme) {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: List.generate(_userAnswerSlots.length, (index) {
            final String? char = _userAnswerSlots[index];
            final bool isGivenFixed = currentQuestion.givenFsl.any((item) => item.position == index);

            return GestureDetector(
              onTap: () => _removeTypingLetter(index),
              child: Container(
                width: 52,
                height: 64,
                decoration: BoxDecoration(
                  color: char != null ? (isGivenFixed ? theme.primaryColor.withOpacity(0.08) : theme.primaryColor.withOpacity(0.18)) : theme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: char != null ? theme.primaryColor : theme.dividerColor, width: 2),
                ),
                alignment: Alignment.center,
                child: isGivenFixed && char != null
                    ? Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Image.asset(
                          'assets/pictures/${char.toUpperCase()}.jpg',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Text(char, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                        ),
                      )
                    : Text(char ?? '', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              ),
            );
          }),
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: List.generate(_shuffledOptions.length, (index) {
            final bool isUsed = _selectedOptionIndices.contains(index);
            final String letter = _shuffledOptions[index].toUpperCase();

            return GestureDetector(
              onTap: isUsed ? null : () => _selectTypingLetter(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: isUsed ? theme.dividerColor.withOpacity(0.3) : theme.cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isUsed ? Colors.transparent : theme.primaryColor, width: 1.5),
                ),
                child: Opacity(
                  opacity: isUsed ? 0.3 : 1.0,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0), 
                    child: Image.asset(
                      'assets/pictures/$letter.jpg', 
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Center(child: Text(letter, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}