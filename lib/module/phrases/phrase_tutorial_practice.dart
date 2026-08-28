import 'dart:async';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'phrase_recognizer.dart';

class PhraseTutorialPractice extends StatefulWidget {
  final String targetPhrase;

  const PhraseTutorialPractice({super.key, required this.targetPhrase});

  @override
  _PhraseTutorialPracticeState createState() => _PhraseTutorialPracticeState();
}

class _PhraseTutorialPracticeState extends State<PhraseTutorialPractice> {
  CameraController? _controller;
  HandLandmarkerPlugin? _landmarkerPlugin;
  StreamSubscription<List<Hand>>? _landmarkSubscription;
  final PhraseRecognizer _phraseRecognizer = PhraseRecognizer();
  
  bool _isInitialized = false;
  bool _isSuccessAchieved = false;
  int _consecutiveEmptyFrames = 0;
  static const int _emptyFrameResetThreshold = 15;

  String _debugStatus = "1/4 Initializing...";

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
      setState(() => _debugStatus = "1/4 Loading TFLite Model & Labels...");
      await _phraseRecognizer.initialize();

      setState(() => _debugStatus = "2/4 Initializing MediaPipe Landmarker...");
      _landmarkerPlugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.gpu,
      );

      _landmarkSubscription = _landmarkerPlugin!.landmarkStream.listen(
        _onHandsDetected,
        onError: (e) {
          if (mounted) {
            setState(() => _debugStatus = "❌ LANDMARK STREAM ERROR: $e");
          }
        },
      );

      setState(() => _debugStatus = "3/4 Opening Camera Stream...");
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _debugStatus = "❌ Error: Camera Hardware Not Found!");
        return;
      }

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

      await _controller!.startImageStream((CameraImage image) {
        if (!_isInitialized || _landmarkerPlugin == null || _isSuccessAchieved) {
          return;
        }
        try {
          _landmarkerPlugin!.processFrame(
            image,
            _controller!.description.sensorOrientation,
          );
        } catch (e) {
          if (mounted) {
            setState(() => _debugStatus = "❌ FRAME STREAM ERROR: $e");
          }
        }
      });

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _debugStatus = "✅ PIPELINE ACTIVE: Show hand to camera";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _debugStatus = "❌ PIPELINE INITIALIZATION CRASH:\n$e");
      }
    }
  }

  void _onHandsDetected(List<Hand> detectedHands) {
    if (_isSuccessAchieved || !mounted) return;

    if (detectedHands.isEmpty) {
      _consecutiveEmptyFrames++;
    } else {
      _consecutiveEmptyFrames = 0;
    }

    final RecognitionResult? result = _phraseRecognizer.processFrame(detectedHands);
    if (result == null) return;

    if (result.label.startsWith("ERR:")) {
      setState(() => _debugStatus = "❌ PREDICTION ERROR:\n${result.label}");
      return;
    }

    if (_consecutiveEmptyFrames >= _emptyFrameResetThreshold) {
      _phraseRecognizer.resetBuffer();
      setState(() {
        _currentScore = 0.0;
        _holdProgress = 0.0;
        _startHoldTime = null;
        _debugStatus = "✋ Place your hand inside camera view...";
      });
      return;
    }

    String targetClean = widget.targetPhrase.replaceAll(" ", "_").replaceAll("-", "_").toLowerCase().trim();
    String predictedClean = result.label.replaceAll(" ", "_").replaceAll("-", "_").toLowerCase().trim();

    setState(() {
      _debugStatus = "🤖 Detected: '$predictedClean'\n🎯 Target: '$targetClean' (${result.confidence.toStringAsFixed(1)}%)";
    });

    if (predictedClean == targetClean) {
      _updateGameLogic(result.confidence);
    } else {
      _updateGameLogic(0.0);
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
          'phraseXp': FieldValue.increment(xpReward),   
          'xp': FieldValue.increment(xpReward),           
          'dailyXp': FieldValue.increment(xpReward),      
          'weeklyXp': FieldValue.increment(xpReward),     
          'completedLessons': FieldValue.increment(1),    
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Firestore XP Update Error: $e");
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

    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: theme.cardColor.withOpacity(0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: theme.dividerColor.withOpacity(0.15), width: 1.5), 
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: theme.cardColor, shape: BoxShape.circle),
                child: Icon(Icons.waving_hand_rounded, color: theme.primaryColor, size: 24),
              ),
              const SizedBox(width: 10),
              Text("Success!", style: TextStyle(fontWeight: FontWeight.w900, color: textColor)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Outstanding job! You have successfully mastered the phrase \"${widget.targetPhrase}\"!",
                style: TextStyle(fontSize: 16, color: textColor, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.green.withOpacity(0.3), width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, color: Colors.green, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        "+$xpReward XP Earned!",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.pop(context); 
                  Navigator.pop(context); 
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  child: Text("Back to Tutorial", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _landmarkSubscription?.cancel();
    _landmarkerPlugin?.dispose();
    _phraseRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    String phraseDisplay = widget.targetPhrase;
    String formattedPhrase = widget.targetPhrase.replaceAll(" ", "_").toLowerCase();
    
    bool isPassing = _currentScore >= successThreshold;
    final double screenWidth = MediaQuery.of(context).size.width;

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
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.6), 
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withOpacity(0.1),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'Practice Mode',
          style: TextStyle(
            color: textColor, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -30, right: -30,
            child: Container(
              width: 200, height: 200, 
              decoration: BoxDecoration(
                shape: BoxShape.circle, 
                color: theme.primaryColor.withOpacity(0.2),
              ),
            ),
          ),
          Positioned(
            bottom: 50, left: -50,
            child: Container(
              width: 260, height: 260, 
              decoration: BoxDecoration(
                shape: BoxShape.circle, 
                color: const Color(0xFF4CAF50).withOpacity(0.15),
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
                      phraseDisplay, 
                      style: TextStyle(
                        color: textColor, fontSize: 32, fontWeight: FontWeight.w900, fontFamily: 'Inter',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Real-time Logger Box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _debugStatus,
                        style: const TextStyle(
                          color: Colors.yellowAccent, 
                          fontSize: 12, 
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: screenWidth * 0.55, 
                      child: AspectRatio(
                        aspectRatio: 1 / 1, 
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(isDark ? 0.3 : 0.06), 
                                blurRadius: 12, 
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              "assets/pictures/$formattedPhrase.jpg", 
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: theme.dividerColor.withOpacity(0.1),
                                child: Icon(Icons.broken_image, color: textColor.withOpacity(0.4), size: 50),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: screenWidth * 0.55, 
                      child: AspectRatio(
                        aspectRatio: 1 / 1, 
                        child: Stack(
                          alignment: Alignment.center,
                          fit: StackFit.expand,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: theme.cardColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  width: 4.0,
                                  color: isPassing ? Colors.green : theme.dividerColor.withOpacity(0.3),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.06), 
                                    blurRadius: 12, 
                                    offset: const Offset(0, 4),
                                  ),
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
                                  width: 100, height: 100,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: isPassing ? Colors.green.withOpacity(0.8) : Colors.white54, width: 3.0),
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
                                          child: Text(
                                            "Position Hand",
                                            style: TextStyle(color: isPassing ? Colors.greenAccent : Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
                    const SizedBox(height: 16),

                    if (_holdProgress > 0.0) ...[
                      Column(
                        children: [
                          const Text("Hold steady...", style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 18)),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                width: screenWidth * 0.70, height: 16,
                                decoration: BoxDecoration(
                                  color: theme.cardColor.withOpacity(0.5), 
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: theme.dividerColor.withOpacity(0.2), width: 1)
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
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: isPassing ? Colors.green.withOpacity(0.2) : theme.cardColor.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: isPassing ? Colors.green.withOpacity(0.4) : theme.dividerColor.withOpacity(0.2), width: 1.5),
                            ),
                            child: Text(
                              "Score: ${_currentScore.toStringAsFixed(1)}%",
                              style: TextStyle(
                                color: isPassing ? Colors.green.shade700 : textColor.withOpacity(0.7),
                                fontWeight: FontWeight.w900, fontSize: 16, fontFamily: 'Inter',
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