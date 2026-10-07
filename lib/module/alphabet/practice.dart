import 'dart:convert';
import 'dart:async'; // Required for StreamSubscription
import 'dart:math' as math;
import 'dart:ui'; // Required for ImageFilter (Glassmorphism)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart'; // Added Firebase Cloud Storage
import 'recognizer.dart';
import '/services/frame_gate.dart';

import '/services/performance_monitor.dart';

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

class PracticeInterface extends StatefulWidget {
  const PracticeInterface({super.key});

  @override
  _PracticeInterfaceState createState() => _PracticeInterfaceState();
}

class _PracticeInterfaceState extends State<PracticeInterface> {
  CameraController? _controller;
  HandLandmarkerPlugin? _landmarkerPlugin;
  StreamSubscription<List<Hand>>? _handSub;

  bool _isInitialized = false;
  bool _isSuccessAchieved = false;

  // --- CONTINUOUS GAME SYSTEM ---
  final String _alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  int _currentIdx = 0;
  String get targetLetter => _alphabet[_currentIdx];

  // In-memory template cache across letter cycles
  static final Map<String, List<dynamic>> _templateCache = {};

  // J and Z are moving signs -- a single static template can't represent
  // them, so they're recognized by a small dedicated LSTM/TFLite model
  // (trained with train_lstm.py) instead of the frame-by-frame template
  // matching used for every other letter.
  static const List<String> _dynamicLetters = ['J', 'Z'];
  bool get _isDynamicLetter => _dynamicLetters.contains(targetLetter);
  PhraseRecognizer? _dynamicSignRecognizer;
  bool _dynamicModelReady = false;

  List<dynamic>? _template;
  double _currentScore = 0.0;
  double _holdProgress = 0.0;
  DateTime? _startHoldTime;

  final double successThreshold = 70.0; 
  final double holdDurationSeconds = 1.0;
  
  // --- XP SETTINGS ---
  final int xpReward = 10; 

  @override
  void initState() {
    super.initState();
    _initializePipeline();
  }

  Future<void> _initializePipeline() async {
    try {
      await _loadGestureLibrary(targetLetter);

      _landmarkerPlugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.gpu, 
      );

      _handSub = _landmarkerPlugin!.landmarkStream.listen(_onHandsDetected);

      // Loaded once up front (not per-letter) since the continuous A-Z
      // loop revisits J and Z repeatedly -- keeping it warm avoids
      // reloading the model every lap through the alphabet.
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

  /// Loads template with in-memory caching and Firebase Cloud Storage fallback
  Future<void> _loadGestureLibrary(String letter) async {
    // 1. Return cached template immediately if present
    if (_templateCache.containsKey(letter)) {
      if (mounted) {
        setState(() {
          _template = _templateCache[letter];
        });
      }
      return;
    }

    String? jsonString;

    // 2. Fetch from Firebase Cloud Storage
    try {
      final storageRef = FirebaseStorage.instance.ref().child('alphabet/$letter.json');
      final data = await storageRef.getData();
      if (data != null) {
        jsonString = utf8.decode(data);
      }
    } catch (e) {
      debugPrint("Firebase Storage fetch failed for $letter: $e");
    }

    // 3. Fallback to local rootBundle asset if Cloud Storage fetch failed
    if (jsonString == null) {
      try {
        jsonString = await rootBundle.loadString('assets/alphabet/$letter.json');
      } catch (e) {
        debugPrint("Could not find gesture resource profile for: $letter");
      }
    }

    // 4. Decode JSON and store in memory cache
    if (jsonString != null) {
      try {
        final List<dynamic> decodedTemplate = jsonDecode(jsonString);
        _templateCache[letter] = decodedTemplate;
        if (mounted) {
          setState(() {
            _template = decodedTemplate;
          });
        }
      } catch (e) {
        debugPrint("Failed to decode JSON template for $letter: $e");
      }
    }
  }

  final FrameGate _frameGate = FrameGate();

  void _processCameraFrame(CameraImage image) {
    // NOTE: no longer gated on `_template == null` -- J/Z have no static
    // template at all, so that check would block the pipeline forever
    // whenever a dynamic letter comes up in the rotation.
    if (!_isInitialized || _landmarkerPlugin == null || _isSuccessAchieved) return;

    try {
      final int sensorOrientation = _controller!.description.sensorOrientation;
      if (!_frameGate.tryEnter()) return; // one frame in flight (services/frame_gate.dart)
      _landmarkerPlugin!.processFrame(image, sensorOrientation);
    } catch (e) {
      debugPrint("Inference Error: $e");
    }
  }

  void _onHandsDetected(List<Hand> detectedHands) {
    _frameGate.done();
    if (_isSuccessAchieved) return;

    if (_isDynamicLetter) {
      if (!_dynamicModelReady || _dynamicSignRecognizer == null) return;

      final result = _dynamicSignRecognizer!.processFrame(detectedHands);
      final bool handsPresent = _dynamicSignRecognizer!.handsPresentInLastFrame;
      // Only count it if hands are actually in frame right now AND the
      // model's current top prediction is the letter being practiced --
      // otherwise a stale window (hands just left frame) could keep
      // reporting a lingering high-confidence match.
      final double score = (handsPresent && result != null && result.label == targetLetter)
          ? result.confidence
          : 0.0;

      _updateGameLogic(score);
      return;
    }

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

    final String letter = targetLetter.toUpperCase();

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
    
    HapticFeedback.heavyImpact(); 
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.heavyImpact(); 
    
    await _awardXp();
    
    if (!mounted) return;

    setState(() {});

    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    setState(() {
      _currentIdx = (_currentIdx + 1) % _alphabet.length;
      _isSuccessAchieved = false;
      _currentScore = 0.0;
    });

    // Clear leftover frames so a fresh J/Z attempt (or the transition
    // away from one) doesn't start from a stale window.
    _dynamicSignRecognizer?.resetBuffer();

    await _loadGestureLibrary(targetLetter);
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
    String currentLetter = targetLetter.toUpperCase();
    bool isPassing = _currentScore >= successThreshold;
    final double screenWidth = MediaQuery.of(context).size.width;

    // Grab the current theme and visual configurations
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
      
      // --- GLASSMORPHISM APP BAR ---
      appBar: AppBar(
        backgroundColor: theme.cardColor.withOpacity(0.4), 
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        flexibleSpace: ClipRRect(
          child: SmartBlur(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text(
          'Continuous Practice',
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

                    // Front Camera Preview Container Envelope
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
                                child: Container(
                                  width: 110, 
                                  height: 110,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isPassing ? Colors.greenAccent.withOpacity(0.8) : Colors.white54,
                                      width: 3.0,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SmartBlur(
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

                    // --- GLASSMORPHISM FEEDBACK TRACK ---
                    if (_isSuccessAchieved) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SmartBlur(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: TweenAnimationBuilder(
                            tween: Tween<double>(begin: 0.8, end: 1.0),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.elasticOut,
                            builder: (context, scale, child) {
                              return Transform.scale(
                                scale: scale,
                                child: child,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.green.withOpacity(0.3), width: 1.5),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(visuals.mainBadgeIcon, color: Colors.green, size: 24),
                                      const SizedBox(width: 8),
                                      Text(
                                        "Success! +$xpReward XP",
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 20,
                                          fontFamily: 'Inter',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "Loading next letter...",
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    ] else if (_holdProgress > 0.0) ...[
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(visuals.secondaryIcon, color: Colors.green, size: 20),
                              const SizedBox(width: 6),
                              const Text(
                                "Hold steady...",
                                style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 18),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SmartBlur(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                width: screenWidth * 0.70, 
                                height: 16,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface.withOpacity(0.4), 
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: theme.colorScheme.surface.withOpacity(0.5), width: 1)
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: _holdProgress,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [Colors.greenAccent, Colors.green]),
                                        borderRadius: BorderRadius.circular(8),
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
                        child: SmartBlur(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: isPassing ? Colors.green.withOpacity(0.2) : theme.cardColor.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: isPassing ? Colors.greenAccent.withOpacity(0.4) : theme.colorScheme.surface.withOpacity(0.8),
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