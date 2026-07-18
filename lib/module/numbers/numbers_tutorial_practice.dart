import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui'; // Required for ImageFilter (Glassmorphism & Blurs)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NumbersTutorialPractice extends StatefulWidget {
  final String targetNumber;

  const NumbersTutorialPractice({super.key, required this.targetNumber});

  @override
  _NumbersTutorialPracticeState createState() => _NumbersTutorialPracticeState();
}

class _NumbersTutorialPracticeState extends State<NumbersTutorialPractice> {
  CameraController? _controller;
  HandLandmarkerPlugin? _landmarkerPlugin;
  
  bool _isInitialized = false;
  bool _isDetecting = false;
  bool _isSuccessAchieved = false;

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
      await _loadGestureLibrary();

      _landmarkerPlugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.gpu, 
      );

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
      String jsonString = await rootBundle.loadString('assets/numbers/${widget.targetNumber}.json');
      setState(() {
         _template = jsonDecode(jsonString);
      });
    } catch (e) {
      debugPrint("Could not find gesture resource profile for: ${widget.targetNumber}");
    }
  }

  void _processCameraFrame(CameraImage image) {
    if (_isDetecting || !_isInitialized || _landmarkerPlugin == null || _isSuccessAchieved || _template == null) return;
    _isDetecting = true;

    try {
      int sensorOrientation = _controller!.description.sensorOrientation;
      final List<Hand> detectedHands = _landmarkerPlugin!.detect(image, sensorOrientation);

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
    } catch (e) {
      debugPrint("Inference Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  double _calculateScore(List<Landmark> liveLms, List<dynamic> template) {
    if (liveLms.isEmpty || template.length < 21 || liveLms.length < 21) return 0.0;

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

        double tx = template[i]['x'];
        double ty = template[i]['y'];
        double tz = template[i]['z'];

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
          'numbersXp': FieldValue.increment(xpReward),
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
    
    HapticFeedback.heavyImpact(); 
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.heavyImpact(); 
    
    await _awardXp();

    if (!mounted) return;
    
    // --- SLEEK IOS ALIGNMENT DIALOG ---
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.stars_rounded, color: Color(0xFFFFB800), size: 30),
            SizedBox(width: 8),
            Text(
              "Success! ⭐⭐⭐", 
              style: TextStyle(fontWeight: FontWeight.w900, fontFamily: 'Inter', letterSpacing: -0.5),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Outstanding job! You have successfully mastered the number ${widget.targetNumber}!",
              style: const TextStyle(fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w500, color: Color(0xFF322144)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF7DC579).withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF7DC579).withOpacity(0.4), width: 1.5),
              ),
              child: Text(
                "+$xpReward XP Earned!",
                style: const TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  color: Color(0xFF27AE60),
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFB800).withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB800),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () {
                    Navigator.pop(context); 
                    Navigator.pop(context); 
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    child: Text(
                      "Back to Tutorial", 
                      style: TextStyle(fontWeight: FontWeight.w900, fontFamily: 'Inter', fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _landmarkerPlugin?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isPassing = _currentScore >= successThreshold;
    const double baseWidth = 393;

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: const Color(0xFFFFF9E5),
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.7),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: Colors.black.withOpacity(0.05),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: const Text(
          'Tutorial Practice',
          style: TextStyle(
            color: Colors.black, 
            fontSize: 22, 
            fontFamily: 'Inter', 
            fontWeight: FontWeight.w800, 
            letterSpacing: -0.96
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double scale = constraints.maxWidth / baseWidth;

          return Stack(
            children: [
              Positioned(
                top: 180 * scale, left: -50 * scale,
                child: Container(
                  width: 200 * scale, 
                  height: 200 * scale, 
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, 
                    color: const Color(0xFFFFB800).withOpacity(0.2),
                  ),
                ),
              ),
              Positioned(
                bottom: 100 * scale, right: -60 * scale,
                child: Container(
                  width: 250 * scale, 
                  height: 250 * scale, 
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, 
                    color: const Color(0xFF7DC579).withOpacity(0.18),
                  ),
                ),
              ),

              // 3. UI Content Layer
              SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: 24.0 * scale, vertical: 20.0 * scale),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          widget.targetNumber,
                          style: TextStyle(
                            color: Colors.black, 
                            fontSize: 52 * scale, 
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Inter',
                            letterSpacing: -1.5,
                          ),
                        ),
                        SizedBox(height: 16 * scale),

                        // Target Flashcard Container
                        Container(
                          width: 240 * scale, 
                          height: 240 * scale,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(20 * scale),
                            border: Border.all(color: Colors.white.withOpacity(0.6), width: 2 * scale),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0C132C4A),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18 * scale),
                            child: Image.asset(
                              "assets/pictures/${widget.targetNumber}.png", 
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.black.withOpacity(0.05),
                                child: const Icon(Icons.broken_image, color: Colors.grey, size: 50),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 28 * scale),

                        // Live Camera Preview Container
                        Container(
                          width: 240 * scale, 
                          height: 240 * scale,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(24 * scale),
                            border: Border.all(
                              width: 4.0 * scale,
                              color: isPassing ? const Color(0xFF7DC579) : Colors.white.withOpacity(0.8),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0C132C4A),
                                blurRadius: 16,
                                offset: Offset(0, 6),
                              )
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(19 * scale),
                                child: _isInitialized && _controller != null
                                    ? FittedBox(
                                        fit: BoxFit.cover,
                                        child: SizedBox(
                                          width: _controller!.value.previewSize?.height ?? 1,
                                          height: _controller!.value.previewSize?.width ?? 1,
                                          child: CameraPreview(_controller!),
                                        ),
                                      )
                                    : const Center(
                                        child: CircularProgressIndicator(color: Color(0xFFFFB800)),
                                      ),
                              ),

                              if (_isInitialized && !_isSuccessAchieved)
                                Center(
                                  child: Container(
                                    width: 110 * scale, 
                                    height: 110 * scale,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: isPassing ? const Color(0xFF7DC579).withOpacity(0.8) : Colors.white54,
                                        width: 2.5 * scale,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Container(
                                        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.4),
                                          borderRadius: BorderRadius.circular(8 * scale),
                                        ),
                                        child: Text(
                                          "Position Hand",
                                          style: TextStyle(
                                            color: isPassing ? const Color(0xFF2ECC71) : Colors.white,
                                            fontSize: 10 * scale,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Inter',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(height: 28 * scale),

                        // --- INTERACTIVE iOS PROGRESS / SCORE TRACK ---
                        if (_holdProgress > 0.0) ...[
                          Column(
                            children: [
                              Text(
                                "Hold steady...",
                                style: TextStyle(
                                  color: const Color(0xFF27AE60),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18 * scale,
                                  fontFamily: 'Inter',
                                ),
                              ),
                              SizedBox(height: 10 * scale),
                              Container(
                                width: 260 * scale, 
                                height: 14 * scale,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.06), 
                                  borderRadius: BorderRadius.circular(25 * scale),
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: _holdProgress,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF7DC579),
                                        borderRadius: BorderRadius.circular(25 * scale),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF7DC579).withOpacity(0.4),
                                            blurRadius: 4,
                                            offset: const Offset(0, 1),
                                          )
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        ] else ...[
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 12 * scale),
                            decoration: BoxDecoration(
                              color: isPassing ? const Color(0xFF7DC579).withOpacity(0.15) : Colors.black.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(30 * scale),
                              border: Border.all(
                                color: isPassing ? const Color(0xFF7DC579).withOpacity(0.25) : Colors.transparent, 
                                width: 1 * scale,
                              ),
                            ),
                            child: Text(
                              "Score: ${_currentScore.toStringAsFixed(1)}%",
                              style: TextStyle(
                                color: isPassing ? const Color(0xFF27AE60) : Colors.black54,
                                fontWeight: FontWeight.w800,
                                fontSize: 16 * scale,
                                fontFamily: 'Inter',
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
          );
        },
      ),
    );
  }
}