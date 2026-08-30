import 'dart:convert';
import 'dart:async'; 
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'recognizer.dart';

/// Dynamic theme visual mapping for thematic icons & graphics
class _ThemeVisuals {
  final IconData mainBadgeIcon;
  final IconData secondaryIcon;
  final IconData ambientIcon1;
  final IconData ambientIcon2;

  const _ThemeVisuals({
    required this.mainBadgeIcon,
    required this.secondaryIcon,
    required this.ambientIcon1,
    required this.ambientIcon2,
  });

  factory _ThemeVisuals.fromTheme(ThemeData theme) {
    final primary = theme.primaryColor;
    final isDark = theme.brightness == Brightness.dark;

    // 1. DEEP OCEAN THEME (Blue Primary)
    if (primary.blue > 160 && primary.red < 120) {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.water_drop_rounded,
        secondaryIcon: Icons.waves_rounded,
        ambientIcon1: Icons.bubble_chart_rounded,
        ambientIcon2: Icons.sailing_rounded,
      );
    } 
    // 2. FOREST NATURE THEME (Green Primary)
    else if (primary.green > 160 && primary.red < 120) {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.eco_rounded,
        secondaryIcon: Icons.forest_rounded,
        ambientIcon1: Icons.park_rounded,
        ambientIcon2: Icons.energy_savings_leaf_rounded,
      );
    } 
    // 3. COSMIC SPACE THEME (Dark Theme with High Contrast)
    else if (isDark) {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.auto_awesome_rounded,
        secondaryIcon: Icons.nights_stay_rounded,
        ambientIcon1: Icons.star_border_rounded,
        ambientIcon2: Icons.wb_twilight_rounded,
      );
    } 
    // 4. GOLDEN PLAYFUL THEME (Default / Warm Colors)
    else {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.stars_rounded,
        secondaryIcon: Icons.workspace_premium_rounded,
        ambientIcon1: Icons.wb_sunny_rounded,
        ambientIcon2: Icons.auto_awesome_rounded,
      );
    }
  }
}

class TutorialPractice extends StatefulWidget {
  final String targetLetter;

  const TutorialPractice({super.key, required this.targetLetter});

  @override
  _TutorialPracticeState createState() => _TutorialPracticeState();
}

class _TutorialPracticeState extends State<TutorialPractice> {
  CameraController? _controller;
  HandLandmarkerPlugin? _landmarkerPlugin;
  StreamSubscription<List<Hand>>? _handSub;

  bool _isInitialized = false;
  bool _isSuccessAchieved = false;

  // Recording State Variables for Dynamic Letters
  bool _isRecordingMotion = false;
  DateTime? _startRecordingTime;
  bool _showMotionResult = false;

  // Every raw per-frame feature vector captured during the current
  // recording window. We feed the *whole* thing to the model at the end
  // (resampled to the model's fixed sequence length), instead of relying
  // on PhraseRecognizer's internal rolling buffer, which only remembers
  // the last ~30 raw camera frames -- too short to hold a full 'Z' if the
  // camera is delivering frames faster than the ~10fps that window
  // assumes.
  final List<Float32List> _recordingFrames = [];

  // Grace period for momentary hand-tracking loss during recording. Fast,
  // large motions like 'Z' are far more prone to a stray frame or two of
  // lost MediaPipe tracking (motion blur, hand briefly leaving the
  // optimal detection zone) than a small, controlled motion like 'J'. We
  // only cancel the recording if hands are missing for longer than this,
  // instead of on a single dropped frame.
  static const Duration _dropoutGracePeriod = Duration(milliseconds: 400);
  DateTime? _lastHandsSeenTime;

  // J and Z are moving signs -- recognized by a dedicated LSTM/TFLite
  // model (trained with train_lstm.py) instead of static template
  // matching, since a single frame can't capture the motion.
  static const List<String> _dynamicLetters = ['J', 'Z'];
  bool get _isDynamicLetter =>
      _dynamicLetters.contains(widget.targetLetter.toUpperCase());
  PhraseRecognizer? _dynamicSignRecognizer;
  bool _dynamicModelReady = false;

  List<dynamic>? _template;
  double _currentScore = 0.0;
  double _holdProgress = 0.0;
  DateTime? _startHoldTime;

  final double successThreshold = 70.0; 
  final double holdDurationSeconds = 1.0;
  final int xpReward = 25;

  @override
  void initState() {
    super.initState();
    _initializePipeline();
  }

  Future<void> _initializePipeline() async {
    try {
      if (_isDynamicLetter) {
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
      } else {
        await _loadGestureLibrary();
      }

      _landmarkerPlugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.gpu, 
      );

      _handSub = _landmarkerPlugin!.landmarkStream.listen(_onHandsDetected);

      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        frontCamera, 
        ResolutionPreset.medium, 
        enableAudio: false,
      );

      await _controller!.initialize();
      await _controller!.startImageStream(_processCameraFrame);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Pipeline setup failed: $e");
    }
  }

  Future<void> _loadGestureLibrary() async {
    try {
      String jsonString = await rootBundle.loadString('assets/alphabet/${widget.targetLetter}.json');
      _template = jsonDecode(jsonString);
    } catch (e) {
      debugPrint("Could not find gesture resource profile for: ${widget.targetLetter}");
    }
  }

  void _processCameraFrame(CameraImage image) {
    if (!_isInitialized || _landmarkerPlugin == null || _isSuccessAchieved) return;

    try {
      final int sensorOrientation = _controller!.description.sensorOrientation;
      _landmarkerPlugin!.processFrame(image, sensorOrientation);
    } catch (e) {
      debugPrint("Inference Error: $e");
    }
  }

  void _onHandsDetected(List<Hand> detectedHands) {
    if (_isSuccessAchieved) return;

    // --- DYNAMIC LETTER RECORDING LOGIC ---
    if (_isDynamicLetter) {
      if (!_dynamicModelReady || _dynamicSignRecognizer == null) return;
      if (_showMotionResult) return; 

      final bool handsPresent = detectedHands.isNotEmpty;
      final now = DateTime.now();

      if (handsPresent) {
        _lastHandsSeenTime = now;

        // Start a fresh recording when hands enter the frame
        if (!_isRecordingMotion) {
           _isRecordingMotion = true;
           _startRecordingTime = now;
           _recordingFrames.clear();
        }

        // Capture the raw feature vector for THIS frame into our own
        // recording list -- we deliberately do not use
        // PhraseRecognizer.processFrame()/its internal ring buffer here.
        // That buffer only ever remembers the last ~_sequenceLength raw
        // camera frames; if the camera delivers frames faster than the
        // model's training-time assumption, a slower/larger motion like
        // 'Z' gets evicted out of the buffer before we ever evaluate it,
        // leaving only a truncated tail fragment. Recording every frame
        // ourselves and resampling the *whole* thing at the end (via
        // predictFromRecording) guarantees the full gesture is captured
        // regardless of frame rate or how long it actually took.
        _recordingFrames.add(_dynamicSignRecognizer!.extractFrameFeatures(detectedHands));

        // Calculate exact time elapsed in seconds
        final double elapsedSeconds = now.difference(_startRecordingTime!).inMilliseconds / 1000.0;

        // Update progress bar based on a strict 3.0 second duration
        setState(() {
            _holdProgress = (elapsedSeconds / 3.0).clamp(0.0, 1.0); 
        });

        // Once 3 seconds have passed, evaluate the FULL recording
        if (elapsedSeconds >= 3.0) {
           _isRecordingMotion = false;
           _showMotionResult = true;

           final result = _dynamicSignRecognizer!.predictFromRecording(_recordingFrames);

           // --- TEMPORARY DEBUG INSTRUMENTATION ---
           // Prints the full score breakdown under BOTH windowing
           // strategies, plus how many frames actually got captured and
           // at what effective frame rate, so we can see what the model
           // is actually doing instead of guessing. Safe to delete once
           // we've diagnosed this -- it doesn't affect scoring.
           final double elapsedForDebug =
               DateTime.now().difference(_startRecordingTime!).inMilliseconds / 1000.0;
           final double effectiveFps = elapsedForDebug > 0
               ? _recordingFrames.length / elapsedForDebug
               : 0.0;
           final resampledScores = _dynamicSignRecognizer!
               .rawScoresForRecording(_recordingFrames, resample: true);
           final rawTailScores = _dynamicSignRecognizer!
               .rawScoresForRecording(_recordingFrames, resample: false);
           debugPrint(
             "=== ${widget.targetLetter.toUpperCase()} EVAL === "
             "frames=${_recordingFrames.length} elapsed=${elapsedForDebug.toStringAsFixed(2)}s "
             "fps=${effectiveFps.toStringAsFixed(1)} | "
             "FULL-RESAMPLE=$resampledScores | "
             "RAW-LAST-30=$rawTailScores",
           );
           // --- END DEBUG INSTRUMENTATION ---

           _recordingFrames.clear();

           double finalScore = 0.0;

           // Check if the model recognized anything and if the label matches the target letter
           if (result != null && result.label.toUpperCase() == widget.targetLetter.toUpperCase()) {
               // Fix for the 5000+ score: Handle both 0.0-1.0 and 0-100 formats dynamically
               double rawConfidence = result.confidence;
               double normalizedConfidence = rawConfidence > 1.0 ? rawConfidence : rawConfidence * 100.0;
               
               // Clamp ensures the score never visually exceeds 100%
               finalScore = normalizedConfidence.clamp(0.0, 100.0);
           }
           
           setState(() {
               _currentScore = finalScore;
               _holdProgress = 0.0; // Hide the progress bar
           });

           if (_currentScore >= successThreshold) {
               _onSuccess();
           } else {
               // Failed attempt: Show the score for 2 seconds, then let them try again
               Future.delayed(const Duration(seconds: 2), () {
                   if (mounted && !_isSuccessAchieved) {
                       setState(() {
                           _showMotionResult = false;
                           _currentScore = 0.0;
                       });
                   }
               });
           }
        }
      } else if (_isRecordingMotion) {
        // Hands dropped out mid-recording. Fast, sweeping motions like
        // 'Z' are much more likely to cause a stray frame or two of lost
        // MediaPipe tracking than a small motion like 'J' -- don't
        // punish that with an instant full reset. Only cancel the
        // recording if hands stay missing longer than the grace period.
        final lastSeen = _lastHandsSeenTime;
        final bool withinGrace = lastSeen != null &&
            now.difference(lastSeen) <= _dropoutGracePeriod;

        if (!withinGrace) {
          setState(() {
              _isRecordingMotion = false;
              _startRecordingTime = null;
              _holdProgress = 0.0;
          });
          _recordingFrames.clear();
        }
        // else: within grace period -- just skip this frame (don't
        // append anything, don't touch the timer) and keep recording on
        // the next frame where hands reappear.
      }
      return;
    }
    // ------------------------------------------

    if (_template == null) return; // static template not loaded yet

    if (detectedHands.isNotEmpty) {
      double highestScoreAcrossAllHands = 0.0;

      for (int handIdx = 0; handIdx < detectedHands.length; handIdx++) {
        final double score = _calculateScore(
          detectedHands[handIdx].landmarks, 
          _template!,
        );
        if (score > highestScoreAcrossAllHands) {
          highestScoreAcrossAllHands = score;
        }
      }

      _updateGameLogic(highestScoreAcrossAllHands);
    } else {
      if (mounted) {
        setState(() {
          _currentScore = 0.0;
          _holdProgress = 0.0;
          _startHoldTime = null;
        });
      }
    }
  }

  double _calculateScore(List<Landmark> liveLms, List<dynamic> template) {
    if (liveLms.isEmpty || template.length < 21 || liveLms.length < 21) return 0.0;

    final String letter = widget.targetLetter.toUpperCase();

    if (['G', 'H', 'K', 'P', 'Q'].contains(letter)) {
      final Landmark wrist = liveLms[0];
      final Landmark mBase = liveLms[9]; 
      final Landmark indexTip = liveLms[8];

      double dist = math.sqrt(
        math.pow(wrist.x - mBase.x, 2) + 
        math.pow(wrist.y - mBase.y, 2)
      );

      double distIndex = math.sqrt(
        math.pow(wrist.x - indexTip.x, 2) + 
        math.pow(wrist.y - indexTip.y, 2)
      );
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
        if (['G', 'H', 'P', 'Q'].contains(letter) &&
            (mIdx == 0 || mIdx == 2 || mIdx == 4 || mIdx == 6)) {
          continue; 
        }

        var matrix = orientationMatrices[mIdx];
        double xx = matrix[0];
        double xy = matrix[1];
        double yx = matrix[2];
        double yy = matrix[3];
        double flipX = matrix[4];

        double totalWeightedDifference = 0.0;
        double totalWeight = 0.0;

        for (int i = 0; i < 21; i++) {
          double dx = (liveLms[i].x - wrist.x) / dist;
          double dy = (liveLms[i].y - wrist.y) / dist;

          dx = dx * flipX;

          double rx = dx * xx + dy * xy;
          double ry = dx * yx + dy * yy;

          double tx = (template[i]['x'] as num).toDouble();
          double ty = (template[i]['y'] as num).toDouble();

          double pointDiff = math.sqrt(
            math.pow(rx - tx, 2) + 
            math.pow(ry - ty, 2)
          );

          double weight = highPriorityLandmarks.contains(i) ? 1.5 : 1.0;
          
          totalWeightedDifference += (pointDiff * weight);
          totalWeight += weight;
        }

        double meanDiff = totalWeightedDifference / totalWeight;
        double score = (100.0 - (meanDiff * 45.0)).clamp(0.0, 100.0);

        if (score > bestScore) {
          bestScore = score;
        }
      }
      return bestScore;

    } else {
      final Landmark wrist = liveLms[0];
      final Landmark mBase = liveLms[9]; 
      
      double dist = math.sqrt(
        math.pow(wrist.x - mBase.x, 2) + 
        math.pow(wrist.y - mBase.y, 2) + 
        math.pow(wrist.z - mBase.z, 2)
      );
      
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
        double xx = matrix[0];
        double xy = matrix[1];
        double yx = matrix[2];
        double yy = matrix[3];
        double flipX = matrix[4];

        double totalDifference = 0.0;

        for (int i = 0; i < 21; i++) {
          double dx = (liveLms[i].x - wrist.x) / dist;
          double dy = (liveLms[i].y - wrist.y) / dist;
          double dz = (liveLms[i].z - wrist.z) / dist;

          dx = dx * flipX;

          double rx = dx * xx + dy * xy;
          double ry = dx * yx + dy * yy;

          double tx = (template[i]['x'] as num).toDouble();
          double ty = (template[i]['y'] as num).toDouble();
          double tz = ((template[i]['z'] ?? 0.0) as num).toDouble();

          double pointDiff = math.sqrt(
            math.pow(rx - tx, 2) + 
            math.pow(ry - ty, 2) + 
            math.pow(dz - tz, 2)
          );
          totalDifference += pointDiff;
        }

        double meanDiff = totalDifference / 21.0;
        double score = (100.0 - (meanDiff * 80.0)).clamp(0.0, 100.0);
        
        if (score > bestScore) {
          bestScore = score;
        }
      }
      return bestScore;
    }
  }

  void _updateGameLogic(double score) {
    if (!mounted) return;
    final now = DateTime.now();

    setState(() {
      _currentScore = score;

      if (_currentScore >= successThreshold) {
        _startHoldTime ??= now;
        final difference = now.difference(_startHoldTime!).inMilliseconds / 1000.0;
        _holdProgress = (difference / holdDurationSeconds).clamp(0.0, 1.0);

        if (difference >= holdDurationSeconds) {
          _onSuccess();
        }
      } else {
        _startHoldTime = null;
        _holdProgress = 0.0;
      }
    });
  }

  Future<void> _awardXp() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
        
        await docRef.set({
          'alphabetXp': FieldValue.increment(xpReward),   
          'xp': FieldValue.increment(xpReward),           
          'dailyXp': FieldValue.increment(xpReward),      
          'weeklyXp': FieldValue.increment(xpReward),     
          'completedLessons': FieldValue.increment(1),    
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Failed to award XP: $e");
    }
  }

  void _onSuccess() async {
    _isSuccessAchieved = true;
    _startHoldTime = null;
    _holdProgress = 0.0;

    // Reset recording variables cleanly 
    _isRecordingMotion = false;
    _startRecordingTime = null;
    _showMotionResult = false;
    
    HapticFeedback.heavyImpact(); 
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.heavyImpact(); 
    
    await _awardXp();
    
    if (!mounted) return;

    final theme = Theme.of(context);
    final visuals = _ThemeVisuals.fromTheme(theme);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: TweenAnimationBuilder(
            tween: Tween<double>(begin: 0.5, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: theme.primaryColor.withOpacity(0.6), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.35),
                    blurRadius: 40,
                    spreadRadius: 8,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thematic reward badge icon
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(visuals.mainBadgeIcon, color: theme.primaryColor, size: 64),
                      ),
                      Positioned(
                        right: 0, top: 0,
                        child: Icon(visuals.secondaryIcon, color: theme.primaryColor.withOpacity(0.7), size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Mastered!",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Outstanding job! You have successfully mastered the letter ${widget.targetLetter.toUpperCase()}!",
                    style: TextStyle(
                      fontSize: 16, 
                      color: theme.colorScheme.onSurface.withOpacity(0.8), 
                      fontWeight: FontWeight.w500
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TweenAnimationBuilder(
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: child,
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.green.withOpacity(0.4), width: 2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(visuals.secondaryIcon, color: Colors.green, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              "+$xpReward XP Earned!",
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.green),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: theme.colorScheme.onPrimary,
                      elevation: 4,
                      shadowColor: theme.primaryColor.withOpacity(0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      minimumSize: const Size(double.infinity, 54),
                    ),
                    onPressed: () {
                      Navigator.pop(context); 
                      Navigator.pop(context); 
                    },
                    child: const Text("Continue", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _handSub?.cancel(); 
    _controller?.stopImageStream();
    _controller?.dispose();
    _landmarkerPlugin?.dispose();
    _dynamicSignRecognizer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String currentLetter = widget.targetLetter.toUpperCase();
    bool isPassing = _currentScore >= successThreshold;
    final double screenWidth = MediaQuery.of(context).size.width;
    final theme = Theme.of(context);
    final visuals = _ThemeVisuals.fromTheme(theme);
    final isDark = theme.brightness == Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: theme.scaffoldBackgroundColor,
      
      appBar: AppBar(
        backgroundColor: theme.cardColor.withOpacity(0.4), 
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text(
          'Practice Mode',
          style: TextStyle(
            color: theme.colorScheme.onSurface, 
            fontSize: 22, 
            fontFamily: 'Inter', 
            fontWeight: FontWeight.w800, 
            letterSpacing: -0.96
          ),
        ),
      ),
      body: Stack(
        children: [
          // Theme-aligned ambient background element 1 (Top-right)
          Positioned(
            top: -20, right: -20,
            child: Opacity(
              opacity: 0.12,
              child: Transform.rotate(
                angle: -0.2,
                child: Icon(visuals.ambientIcon1, size: 220, color: theme.primaryColor),
              ),
            ),
          ),
          
          // Theme-aligned ambient background element 2 (Bottom-left)
          Positioned(
            bottom: 40, left: -30,
            child: Opacity(
              opacity: 0.10,
              child: Transform.rotate(
                angle: 0.3,
                child: Icon(visuals.ambientIcon2, size: 240, color: theme.colorScheme.secondary),
              ),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: SizedBox(
                width: double.infinity, 
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '$currentLetter${currentLetter.toLowerCase()}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface, 
                        fontSize: 42, 
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: screenWidth * 0.60, 
                      child: AspectRatio(
                        aspectRatio: 1 / 1, 
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              "assets/pictures/$currentLetter.jpg", 
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                                child: const Icon(Icons.broken_image, color: Colors.grey, size: 50),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Front Camera Preview Container
                    SizedBox(
                      width: screenWidth * 0.60, 
                      child: AspectRatio(
                        aspectRatio: 1 / 1, 
                        child: Stack(
                          alignment: Alignment.center,
                          fit: StackFit.expand,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  width: 4.0,
                                  color: isPassing ? Colors.greenAccent : theme.dividerColor.withOpacity(0.6),
                                ),
                                boxShadow: [
                                  if (isPassing)
                                    BoxShadow(
                                      color: Colors.greenAccent.withOpacity(0.6),
                                      blurRadius: 25,
                                      spreadRadius: 2,
                                    )
                                  else
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    )
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: _isInitialized && _controller != null
                                    ? FittedBox(
                                        fit: BoxFit.cover,
                                        child: SizedBox(
                                          width: _controller!.value.previewSize?.height ?? 1,
                                          height: _controller!.value.previewSize?.width ?? 1,
                                          child: CameraPreview(_controller!),
                                        ),
                                      )
                                    : Center(
                                        child: CircularProgressIndicator(color: theme.primaryColor),
                                      ),
                              ),
                            ),

                            if (_isInitialized && !_isSuccessAchieved)
                              Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: 110, 
                                  height: 110,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isPassing ? Colors.greenAccent.withOpacity(0.9) : Colors.white54,
                                      width: isPassing ? 4.0 : 3.0,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          color: Colors.black45,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (isPassing) ...[
                                                Icon(visuals.mainBadgeIcon, color: Colors.greenAccent, size: 12),
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                isPassing ? "Hold!" : "Position Hand",
                                                style: TextStyle(
                                                  color: isPassing ? Colors.greenAccent : Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_holdProgress > 0.0) ...[
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(visuals.secondaryIcon, color: Colors.green, size: 20),
                              const SizedBox(width: 6),
                              // Dynamic UI Text Switch
                              Text(
                                _isDynamicLetter ? "Recording motion..." : "Hold steady...",
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 18),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                width: screenWidth * 0.70, 
                                height: 20,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface.withOpacity(0.4), 
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: theme.colorScheme.surface.withOpacity(0.5), width: 1)
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: _holdProgress,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [Colors.greenAccent, Colors.green]),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(color: Colors.greenAccent.withOpacity(0.5), blurRadius: 10)
                                        ]
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    ] else ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: isPassing ? Colors.green.withOpacity(0.2) : theme.cardColor.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: isPassing ? Colors.greenAccent.withOpacity(0.6) : theme.colorScheme.surface.withOpacity(0.8),
                                width: 1.5
                              ),
                            ),
                            child: Text(
                              "Score: ${_currentScore.toStringAsFixed(1)}%",
                              style: TextStyle(
                                color: isPassing ? (isDark ? Colors.greenAccent : Colors.green.shade700) : theme.colorScheme.onSurface.withOpacity(0.7),
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}