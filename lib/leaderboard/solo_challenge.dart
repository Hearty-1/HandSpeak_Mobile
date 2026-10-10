import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '/module/alphabet/recognizer.dart';
import '/providers/sound_provider.dart';
import '/services/progress_service.dart';
import '/services/frame_gate.dart';


// ==========================================
// 1. SOLO CHALLENGE SETUP SCREEN
// ==========================================
class SoloChallengeSetupScreen extends StatefulWidget {
  const SoloChallengeSetupScreen({super.key});

  @override
  State<SoloChallengeSetupScreen> createState() => _SoloChallengeSetupScreenState();
}

class _SoloChallengeSetupScreenState extends State<SoloChallengeSetupScreen> {
  String _selectedCategory = 'Alphabet';
  int _selectedRounds = 10;
  int _selectedTimer = 15;

  final List<String> _categories = ['Alphabet', 'Numbers', 'Common Phrases', 'Civic Observances'];
  final List<int> _roundsOptions = [5, 10, 15, 20];
  final List<int> _timerOptions = [10, 15, 30, 0];

  void _startSoloMatch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameProperScreen(
          roomCode: 'SOLO',
          challengeTitle: 'Solo $_selectedCategory Challenge',
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
                    items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
  late String _currentUserId;

  List<Map<String, dynamic>> _questions = [];
  int _currentQuestionIndex = 0;
  int _score = 0;
  int _streak = 0;
  int _correctCount = 0;

  bool _isLoading = true;
  bool _hasAnswered = false;
  bool _isLastAnswerCorrect = false;
  String _selectedAnswer = '';

  final TextEditingController _identificationController = TextEditingController();

  List<String?> _userAnswerSlots = [];
  List<int?> _selectedOptionIndices = [];
  List<String> _shuffledOptions = [];

  List<String> _currentSequence = [];
  List<String> _availableSequenceOptions = [];

  Map<String, String?> _matchingAnswers = {};
  String? _selectedLeftMatch;
  List<String> _matchingLeftItems = [];
  List<String> _matchingRightItems = [];

  CameraController? _cameraController;
  HandLandmarkerPlugin? _landmarkerPlugin;
  StreamSubscription<List<Hand>>? _handSub;

  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;

  static const double _requiredHoldSeconds = 1.0;
  DateTime? _staticHoldStartTime;

  bool _isRecordingMotion = false;
  DateTime? _startRecordingTime;
  final List<Float32List> _recordingFrames = [];
  static const Duration _dropoutGracePeriod = Duration(milliseconds: 300);
  DateTime? _lastHandsSeenTime;

  PhraseRecognizer? _dynamicSignRecognizer;
  bool _dynamicModelReady = false;

  // In-memory caching for loaded gesture template JSONs
  static final Map<String, List<dynamic>> _templateCache = {};
  List<dynamic>? _template;
  String _templateLetter = ''; // letter of [_template] (tricky-letter scoring)
  double _currentScore = 0.0;
  double _holdProgress = 0.0;
  final double successThreshold = 70.0;

  static const List<String> _dynamicLetters = ['J', 'Z'];

  bool get _isDynamicLetter {
    if (_questions.isEmpty || _currentQuestionIndex >= _questions.length) return false;
    final correctAnswer = _extractCorrectAnswer(_questions[_currentQuestionIndex]);
    return _dynamicLetters.contains(correctAnswer.toUpperCase());
  }

  Timer? _timer;
  int _timeLeft = 15;
  late int _maxTime;
  late int _totalRounds;
  late String _category;

  @override
  void initState() {
    super.initState();
    _maxTime = widget.timerDuration;
    _totalRounds = widget.totalRounds;
    _category = widget.category;
    _initUser();
    _setupGameAndPlayer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _identificationController.dispose();
    _handSub?.cancel();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _landmarkerPlugin?.dispose();
    _dynamicSignRecognizer?.dispose();
    super.dispose();
  }

  void _initUser() {
    final user = FirebaseAuth.instance.currentUser;
    _currentUserId = user?.uid ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _initializeCameraPipeline() async {
    if (_isCameraInitialized) return;
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
        _dynamicModelReady = false;
      }

      if (mounted) setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint("Camera Pipeline Error: $e");
    }
  }

  /// Fetches sign gesture landmarks template JSON from Firebase Storage with in-memory caching and asset fallback.
  Future<void> _loadGestureLibrary(String letter) async {
    final charKey = letter.trim().toUpperCase();
    if (charKey.isEmpty) return;
    _templateLetter = charKey;

    // 1. Check in-memory cache
    if (_templateCache.containsKey(charKey)) {
      if (mounted) {
        setState(() => _template = _templateCache[charKey]);
      }
      return;
    }

    // 2. Fetch template JSON from Firebase Cloud Storage
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('gesture_templates/$charKey.json');
      final Uint8List? data = await ref.getData(2 * 1024 * 1024); // 2MB max download
      if (data != null && data.isNotEmpty) {
        final jsonString = utf8.decode(data);
        final List<dynamic> decoded = jsonDecode(jsonString);
        _templateCache[charKey] = decoded;
        if (mounted) {
          setState(() => _template = decoded);
        }
        return;
      }
    } catch (e) {
      debugPrint("Firebase Storage gesture fetch for '$charKey' failed: $e. Falling back to asset bundle.");
    }

    // 3. Fallback to local app bundle assets
    try {
      String jsonString = await rootBundle.loadString('assets/alphabet/$charKey.json');
      final List<dynamic> decoded = jsonDecode(jsonString);
      _templateCache[charKey] = decoded;
      if (mounted) {
        setState(() => _template = decoded);
      }
    } catch (e) {
      debugPrint("Local asset fallback for gesture template '$charKey' failed: $e");
      if (mounted) {
        setState(() => _template = null);
      }
    }
  }

  final FrameGate _frameGate = FrameGate();

  void _processCameraFrame(CameraImage image) {
    if (!_isCameraInitialized || _landmarkerPlugin == null || _hasAnswered || _isProcessingFrame) return;
    _isProcessingFrame = true;
    try {
      if (!_frameGate.tryEnter()) return; // one frame in flight (services/frame_gate.dart)
      _landmarkerPlugin!.processFrame(image, _cameraImageRotation(_cameraController));
    } catch (e) {
      debugPrint("Inference Error: $e");
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _onHandsDetected(List<Hand> detectedHands) {
    _frameGate.done();
    if (_hasAnswered || _questions.isEmpty || _currentQuestionIndex >= _questions.length) return;
    final currentQ = _questions[_currentQuestionIndex];
    if (_determineQuestionType(currentQ) != 'camera_spell') return;

    final now = DateTime.now();
    final correctAnswer = _extractCorrectAnswer(currentQ).toUpperCase();

    if (_isDynamicLetter) {
      if (!_dynamicModelReady || _dynamicSignRecognizer == null) return;
      if (detectedHands.isNotEmpty) {
        _lastHandsSeenTime = now;
        if (!_isRecordingMotion) {
          _isRecordingMotion = true;
          _startRecordingTime = now;
          _recordingFrames.clear();
        }

        _recordingFrames.add(_dynamicSignRecognizer!.extractFrameFeatures(detectedHands));
        final double elapsed = now.difference(_startRecordingTime!).inMilliseconds / 1000.0;
        if (mounted) setState(() => _holdProgress = (elapsed / _requiredHoldSeconds).clamp(0.0, 1.0));

        if (elapsed >= _requiredHoldSeconds) {
          _isRecordingMotion = false;
          final result = _dynamicSignRecognizer!.predictFromRecording(_recordingFrames);
          _recordingFrames.clear();

          if (result != null && result.label.toUpperCase() == correctAnswer) {
            _currentScore = (result.confidence * 100.0).clamp(0.0, 100.0);
          }
          if (_currentScore >= successThreshold) _submitAnswer(correctAnswer);
        }
      } else if (_isRecordingMotion) {
        final lastSeen = _lastHandsSeenTime;
        if (lastSeen == null || now.difference(lastSeen) > _dropoutGracePeriod) {
          if (mounted) setState(() { _isRecordingMotion = false; _holdProgress = 0.0; });
          _recordingFrames.clear();
        }
      }
      return;
    }

    if (_template == null) return;
    if (detectedHands.isNotEmpty) {
      double maxScore = 0.0;
      for (var hand in detectedHands) {
        double score = _calculateScore(hand.landmarks, _template!);
        if (score > maxScore) maxScore = score;
      }
      _currentScore = maxScore;
      if (_currentScore >= successThreshold) {
        _staticHoldStartTime ??= now;
        double secs = now.difference(_staticHoldStartTime!).inMilliseconds / 1000.0;
        _holdProgress = (secs / _requiredHoldSeconds).clamp(0.0, 1.0);
        if (secs >= _requiredHoldSeconds) _submitAnswer(correctAnswer);
      } else {
        _staticHoldStartTime = null;
        _holdProgress = 0.0;
      }
      if (mounted) setState(() {});
    }
  }

  /// G, H, K, P, Q: tricky letters (horizontal or crossing fingers). Scored in
  /// 2D only (no z noise), scale from wrist->middle base or the index reach,
  /// fingertips weighted 1.5x, a relaxed curve, and G/H/P/Q locked to the
  /// sideways orientations.
  static const List<String> _trickyLetters = ['G', 'H', 'K', 'P', 'Q'];

  double _calculateTrickyScore(List<Landmark> liveLms, List<dynamic> template, String letter) {
    final Landmark wrist = liveLms[0];
    final Landmark mBase = liveLms[9];
    final Landmark indexTip = liveLms[8];

    // Stable scale factor to prevent small-fist error inflation
    double dist = math.sqrt(math.pow(wrist.x - mBase.x, 2) + math.pow(wrist.y - mBase.y, 2));
    final double distIndex = math.sqrt(math.pow(wrist.x - indexTip.x, 2) + math.pow(wrist.y - indexTip.y, 2));
    dist = math.max(dist, distIndex * 0.55);
    if (dist < 0.05) dist = 0.05; // Safety floor

    // High priority weighting on action fingertips: thumb, index, middle tips
    const List<int> highPriorityLandmarks = [4, 8, 12];

    const orientationMatrices = [
      [1.0, 0.0, 0.0, 1.0, 1.0], // 0: Upright Normal
      [0.0, -1.0, 1.0, 0.0, 1.0], // 1: 90 deg
      [-1.0, 0.0, 0.0, -1.0, 1.0], // 2: 180 deg
      [0.0, 1.0, -1.0, 0.0, 1.0], // 3: 270 deg
      [1.0, 0.0, 0.0, 1.0, -1.0], // 4: Upright Mirrored
      [0.0, -1.0, 1.0, 0.0, -1.0], // 5: 90 deg Mirrored
      [-1.0, 0.0, 0.0, -1.0, -1.0], // 6: 180 deg Mirrored
      [0.0, 1.0, -1.0, 0.0, -1.0], // 7: 270 deg Mirrored
    ];

    double bestScore = 0.0;
    for (int mIdx = 0; mIdx < orientationMatrices.length; mIdx++) {
      // Directional Lock: horizontal letters use the sideways matrices only ('K' excluded)
      if (letter != 'K' && mIdx.isEven) continue;

      final matrix = orientationMatrices[mIdx];
      final double xx = matrix[0], xy = matrix[1], yx = matrix[2], yy = matrix[3], flipX = matrix[4];

      double totalWeightedDifference = 0.0;
      double totalWeight = 0.0;
      for (int i = 0; i < 21; i++) {
        final double dx = ((liveLms[i].x - wrist.x) / dist) * flipX;
        final double dy = (liveLms[i].y - wrist.y) / dist;
        final double rx = dx * xx + dy * xy;
        final double ry = dx * yx + dy * yy;
        final double tx = (template[i]['x'] as num).toDouble();
        final double ty = (template[i]['y'] as num).toDouble();

        // Purely 2D comparison to eliminate Z-depth noise
        final double pointDiff = math.sqrt(math.pow(rx - tx, 2) + math.pow(ry - ty, 2));
        final double weight = highPriorityLandmarks.contains(i) ? 1.5 : 1.0;
        totalWeightedDifference += pointDiff * weight;
        totalWeight += weight;
      }

      // Relaxed scoring curve for G, H, K, P, Q
      final double score = (100.0 - (totalWeightedDifference / totalWeight * 45.0)).clamp(0.0, 100.0);
      if (score > bestScore) bestScore = score;
    }
    return bestScore;
  }

  double _calculateScore(List<Landmark> liveLms, List<dynamic> template) {
    if (liveLms.length < 21 || template.length < 21) return 0.0;
    final String letter = _templateLetter;
    if (_trickyLetters.contains(letter)) return _calculateTrickyScore(liveLms, template, letter);
    Landmark wrist = liveLms[0];
    Landmark mBase = liveLms[9];
    double dist = math.sqrt(math.pow(wrist.x - mBase.x, 2) + math.pow(wrist.y - mBase.y, 2) + math.pow(wrist.z - mBase.z, 2));
    if (dist == 0) dist = 1.0;

    double bestScore = 0.0;
    final matrices = [
      [1.0, 0.0, 0.0, 1.0, 1.0], [-1.0, 0.0, 0.0, -1.0, 1.0], [0.0, -1.0, 1.0, 0.0, 1.0], [0.0, 1.0, -1.0, 0.0, 1.0]
    ];

    for (var m in matrices) {
      double diff = 0.0;
      for (int i = 0; i < 21; i++) {
        double dx = ((liveLms[i].x - wrist.x) / dist) * m[4];
        double dy = (liveLms[i].y - wrist.y) / dist;
        double dz = (liveLms[i].z - wrist.z) / dist;
        double rx = dx * m[0] + dy * m[1];
        double ry = dx * m[2] + dy * m[3];
        double tx = (template[i]['x'] as num).toDouble();
        double ty = (template[i]['y'] as num).toDouble();
        double tz = ((template[i]['z'] ?? 0.0) as num).toDouble();
        diff += math.sqrt(math.pow(rx - tx, 2) + math.pow(ry - ty, 2) + math.pow(dz - tz, 2));
      }
      double score = (100.0 - ((diff / 21.0) * 80.0)).clamp(0.0, 100.0);
      if (score > bestScore) bestScore = score;
    }
    return bestScore;
  }

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

      final snapshot = await FirebaseFirestore.instance.collection('activity_questions').get();
      if (snapshot.docs.isNotEmpty) {
        var allQuestions = snapshot.docs.map((d) => d.data()).toList();
        var filtered = allQuestions.where((q) {
          final cat = (_getValueCaseInsensitive(q, ['category', 'topic', 'group', 'tag']) ?? '').toString().trim().toLowerCase();
          final target = _category.trim().toLowerCase();
          return cat == target || cat.contains(target) || target.contains(cat);
        }).toList();

        if (filtered.isEmpty) filtered = allQuestions;
        filtered.shuffle();

        if (mounted) {
          setState(() {
            _questions = filtered.take(_totalRounds).toList();
            _isLoading = false;
            _score = 0;
            _streak = 0;
            _correctCount = 0;
          });
        }

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
      _isRecordingMotion = false;
      _staticHoldStartTime = null;
      _currentScore = 0.0;
      _holdProgress = 0.0;
      if (!_isCameraInitialized) {
        _initializeCameraPipeline().then((_) => _loadGestureLibrary(correctAnswer));
      } else {
        _loadGestureLibrary(correctAnswer);
      }
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
    if (isCorrect) {
      int timeBonus = _maxTime > 0 ? (100 * (_timeLeft / _maxTime)).round() : 0;
      int streakBonus = _streak > 1 ? (_streak * 15) : 0;
      _score += 50 + timeBonus + streakBonus;
    }

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

  String _extractQuestionText(Map<String, dynamic> q) => (_getValueCaseInsensitive(q, ['question_text', 'questionText', 'question', 'title', 'prompt']) ?? '').toString();

  String? _extractQuestionImage(Map<String, dynamic> q) => _getValueCaseInsensitive(q, [
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

  String _extractCorrectAnswer(Map<String, dynamic> q) => (_getValueCaseInsensitive(q, ['correct_answer', 'correctAnswer', 'answer', 'correct']) ?? '').toString();

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

    if (cleanSource.startsWith('http://') || cleanSource.startsWith('https://')) {
      return Image.network(
        cleanSource,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
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
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
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
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
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

  Widget _buildTypingLayout(ThemeData theme, Color textColor) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: List.generate(_userAnswerSlots.length, (index) {
              final char = _userAnswerSlots[index];
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _hasAnswered ? null : () => setState(() { _userAnswerSlots[index] = null; _selectedOptionIndices[index] = null; }),
                child: Container(
                  width: 50, height: 58,
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.primaryColor, width: 2),
                    boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.1), blurRadius: 6)],
                  ),
                  alignment: Alignment.center,
                  child: Text(char ?? '', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor)),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8, runSpacing: 8,
            alignment: WrapAlignment.center,
            children: List.generate(_shuffledOptions.length, (index) {
              final isUsed = _selectedOptionIndices.contains(index);
              final opt = _shuffledOptions[index];
              final isImg = _isImageString(opt);

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: (isUsed || _hasAnswered) ? null : () {
                  int empty = _userAnswerSlots.indexOf(null);
                  if (empty != -1) {
                    setState(() { _userAnswerSlots[empty] = opt; _selectedOptionIndices[empty] = index; });
                  }
                },
                child: Opacity(
                  opacity: isUsed ? 0.25 : 1.0,
                  child: Container(
                    width: 50, height: 50,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.primaryColor.withValues(alpha: 0.4), width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: isImg ? _buildSafeImage(opt, fit: BoxFit.contain) : Text(opt, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: _hasAnswered ? null : () => _submitAnswer(_userAnswerSlots.join('')),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    return Column(
      children: [
        Container(
          height: 64,
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.primaryColor),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _currentSequence.map((item) {
              final isImg = _isImageString(item);
              return Chip(
                backgroundColor: theme.primaryColor.withValues(alpha: 0.2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                label: isImg
                    ? SizedBox(height: 26, width: 26, child: _buildSafeImage(item))
                    : Text(
                        item,
                        style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                      ),
                onDeleted: _hasAnswered
                    ? null
                    : () => setState(() {
                          _currentSequence.remove(item);
                          _availableSequenceOptions.add(item);
                        }),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableSequenceOptions.map((item) {
            final isImg = _isImageString(item);
            return ActionChip(
              backgroundColor: theme.cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.2)),
              ),
              label: isImg
                  ? SizedBox(height: 28, width: 28, child: _buildSafeImage(item))
                  : Text(
                      item,
                      style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
                    ),
              onPressed: _hasAnswered
                  ? null
                  : () => setState(() {
                        _availableSequenceOptions.remove(item);
                        _currentSequence.add(item);
                      }),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _hasAnswered
                ? null
                : () => _submitAnswer(_currentSequence.join(',')),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              "SUBMIT SEQUENCE",
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMatchingLayout(Map<String, dynamic> q, ThemeData theme, Color textColor) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: _matchingLeftItems.map((item) {
                    bool isSelected = _selectedLeftMatch == item;
                    bool isMatched = _matchingAnswers[item] != null;
                    final bool isImg = _isImageString(item);
                    return InkWell(
                      onTap: (_hasAnswered || isMatched) ? null : () => setState(() => _selectedLeftMatch = item),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 58, margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isMatched ? Colors.green.withValues(alpha: 0.2) : (isSelected ? theme.primaryColor.withValues(alpha: 0.3) : theme.cardColor),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isMatched ? Colors.green : (isSelected ? theme.primaryColor : theme.primaryColor.withValues(alpha: 0.2)), width: 2),
                        ),
                        alignment: Alignment.center,
                        child: isImg ? _buildSafeImage(item, fit: BoxFit.contain) : Text(item, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: _matchingRightItems.map((item) {
                    bool isMatched = _matchingAnswers.containsValue(item);
                    final bool isImg = _isImageString(item);
                    return InkWell(
                      onTap: (_hasAnswered || isMatched || _selectedLeftMatch == null) ? null : () {
                        setState(() {
                          _matchingAnswers[_selectedLeftMatch!] = item;
                          _selectedLeftMatch = null;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 58, margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isMatched ? Colors.green.withValues(alpha: 0.2) : theme.cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isMatched ? Colors.green : textColor.withValues(alpha: 0.2), width: 2),
                        ),
                        alignment: Alignment.center,
                        child: isImg ? _buildSafeImage(item, fit: BoxFit.contain) : Text(item, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _hasAnswered ? null : () => _submitAnswer(''),
            style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
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
            style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: Text("SUBMIT IDENTIFICATION", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraSpellLayout(ThemeData theme, Color textColor) {
    if (!_isCameraInitialized || _cameraController == null) {
      return Center(child: CircularProgressIndicator(color: theme.primaryColor));
    }
    final bool landscape = _isLandscape(context);
    // Landscape: taller camera on the right, accuracy + progress on the left.
    final double camHeight = landscape ? MediaQuery.of(context).size.height * 0.55 : 230;
    final Widget camera = SizedBox(
      height: camHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: _CameraView(controller: _cameraController!),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _currentScore >= successThreshold ? Colors.green : theme.primaryColor.withValues(alpha: 0.6), width: 3),
            ),
          ),
        ],
      ),
    );
    final List<Widget> status = [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LinearProgressIndicator(
          value: _holdProgress,
          backgroundColor: textColor.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation<Color>(_currentScore >= successThreshold ? const Color(0xFF4CAF50) : theme.primaryColor),
          minHeight: 10,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.center_focus_strong_rounded, color: theme.primaryColor, size: 20),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              "Sign Accuracy: ${_currentScore.toStringAsFixed(1)}%",
              style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ],
      ),
    ];
    if (landscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 5, child: Column(mainAxisSize: MainAxisSize.min, children: status)),
          const SizedBox(width: 16),
          Expanded(flex: 6, child: camera),
        ],
      );
    }
    return Column(children: [camera, const SizedBox(height: 14), ...status]);
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
        peakStreak: _streak,
      );
    } catch (e) {
      debugPrint("Failed to record progress to Firestore: $e");
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.close_rounded, color: textColor), onPressed: () => Navigator.pop(context)),
        title: Text("Round ${_currentQuestionIndex + 1} / ${_questions.length}", style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 18)),
        actions: [
          if (_streak > 1)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFF34B1B).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: Text("🔥 $_streak", style: const TextStyle(color: Color(0xFFF34B1B), fontWeight: FontWeight.w900, fontSize: 14)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text("Score: $_score", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.w900, fontSize: 16))),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  if (_maxTime > 0) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (_timeLeft / _maxTime).clamp(0.0, 1.0),
                        backgroundColor: textColor.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(_timeLeft <= 3 ? const Color(0xFFF34B1B) : theme.primaryColor),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: theme.primaryColor.withValues(alpha: 0.1)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(_extractQuestionText(currentQuestion), textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: textColor)),
                        if (imageUrl != null && imageUrl.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _buildSafeImage(imageUrl, height: 130),
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
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
                            return _buildCameraSpellLayout(theme, textColor);
                          case 'multiple_choice':
                          default:
                            return _buildMultipleChoiceOptions(options, correctAnswer, theme, textColor);
                        }
                      },
                    ),
                  ),
                  if (_hasAnswered) const SizedBox(height: 120),
                ],
              ),
            ),
          ),
          if (_hasAnswered)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedThemedFeedbackBanner(
                isCorrect: _isLastAnswerCorrect,
                correctAnswer: correctAnswer,
                streak: _streak,
                onContinue: _moveToNextQuestion,
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// 3. ANIMATED THEMED FEEDBACK BANNER WIDGET
// ==========================================
class AnimatedThemedFeedbackBanner extends StatelessWidget {
  final bool isCorrect;
  final String correctAnswer;
  final int streak;
  final VoidCallback onContinue;

  const AnimatedThemedFeedbackBanner({
    super.key,
    required this.isCorrect,
    required this.correctAnswer,
    this.streak = 0,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color backgroundColor = isCorrect
        ? (isDark ? const Color(0xFF133B23) : const Color(0xFFE8F5E9))
        : (isDark ? const Color(0xFF3E1415) : const Color(0xFFFFEBEE));

    final Color accentColor = isCorrect
        ? (isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32))
        : (isDark ? const Color(0xFFE57373) : const Color(0xFFC62828));

    String title = isCorrect ? "Fantastic! 🎉" : "Not Quite! 💡";
    if (isCorrect && streak > 2) {
      title = "On Fire! 🔥 ($streak Streak)";
    } else if (isCorrect && streak == 2) {
      title = "Double Streak! ⚡";
    }

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      tween: Tween<double>(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 120),
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCorrect ? Icons.check_circle_rounded : Icons.close_rounded,
                      color: accentColor,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text( 
                          title,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Inter',
                            color: accentColor,
                          ),
                        ),
                        // Removed the incorrect correct answer display block here
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    elevation: 3,
                    shadowColor: accentColor.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    "CONTINUE",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      fontFamily: 'Inter',
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

// =============================================================================
// CAMERA HELPERS (local to this screen)
// =============================================================================

/// Clockwise rotation that makes the camera image upright for the current
/// device orientation (front: sensor + deviceCCW, back: sensor - deviceCCW).
int _cameraImageRotation(CameraController? c) {
  if (c == null) return 0;
  final sensor = c.description.sensorOrientation;
  final ccw = switch (c.value.deviceOrientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  return c.description.lensDirection == CameraLensDirection.front
      ? (sensor + ccw) % 360
      : (sensor - ccw + 360) % 360;
}

bool _isLandscape(BuildContext context) => MediaQuery.orientationOf(context) == Orientation.landscape;

/// Camera preview scaled to cover its box without stretching. Display only:
/// recognition uses the image stream, not this widget.
class _CameraView extends StatelessWidget {
  final CameraController controller;
  const _CameraView({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final size = value.previewSize;
        if (!value.isInitialized || size == null) return const ColoredBox(color: Colors.black);
        final landscape = value.deviceOrientation == DeviceOrientation.landscapeLeft ||
            value.deviceOrientation == DeviceOrientation.landscapeRight;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.05,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.28)],
              stops: const [0.62, 1.0],
            ),
          ),
          child: ColoredBox(
            color: Colors.black,
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: landscape ? size.longestSide : size.shortestSide,
                  height: landscape ? size.shortestSide : size.longestSide,
                  child: CameraPreview(controller),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
