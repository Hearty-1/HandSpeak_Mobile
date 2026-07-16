import 'dart:convert';
import 'dart:math' as math;
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
    
    // --- AWARD THE XP ---
    await _awardXp();

    if (!mounted) return;
    
    // --- EXACT DIALOG FROM TUTORIAL_PRACTICE ---
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.stars, color: Colors.amber, size: 28),
            SizedBox(width: 8),
            Text("Success! ⭐⭐⭐", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Outstanding job! You have successfully mastered the number ${widget.targetNumber}!",
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // --- DISPLAY REWARD IN DIALOG ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200, width: 2),
              ),
              child: Text(
                "+$xpReward XP Earned!",
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800
                ),
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB800),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context); 
                Navigator.pop(context); 
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text("Back to Tutorial", style: TextStyle(fontWeight: FontWeight.bold)),
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
    final double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      body: SafeArea(
        child: Column(
          children: [
            // TOP HEADER BAR
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFFB800),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  )
                ],
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 42, 
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white24, 
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.black, size: 22),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'TUTORIAL PRACTICE', 
                        style: TextStyle(
                          color: Colors.black, 
                          fontSize: 16, 
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          fontFamily: 'Inter',
                        )
                      ),
                    ),
                  ),
                  const SizedBox(width: 42),
                ],
              ),
            ),

            // DYNAMIC SCROLLABLE BODY
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      widget.targetNumber,
                      style: const TextStyle(
                        color: Colors.black, 
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
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              "assets/pictures/${widget.targetNumber}.png", 
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.grey.shade300,
                                child: const Icon(Icons.broken_image, color: Colors.grey, size: 50),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: screenWidth * 0.60, 
                      child: AspectRatio(
                        aspectRatio: 1 / 1, 
                        child: Stack(
                          alignment: Alignment.center,
                          fit: StackFit.expand,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  width: 5.0,
                                  color: isPassing ? Colors.green : const Color(0xFFCBD0DC),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  )
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(15),
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
                                        child: CircularProgressIndicator(color: Colors.amber),
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
                                      color: isPassing ? Colors.green.withOpacity(0.8) : Colors.white54,
                                      width: 3.0,
                                      style: BorderStyle.solid,
                                    ),
                                    borderRadius: BorderRadius.circular(60),
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        "Position Hand",
                                        style: TextStyle(
                                          color: isPassing ? Colors.greenAccent : Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
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
                    const SizedBox(height: 20),

                    // --- FEEDBACK SECTION ---
                    if (_holdProgress > 0.0) ...[
                      Column(
                        children: [
                          const Text(
                            "Hold steady...",
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: screenWidth * 0.70, 
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.grey[300], 
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: _holdProgress,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Colors.greenAccent, Colors.green],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: isPassing ? Colors.green.withOpacity(0.15) : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          "Score: ${_currentScore.toStringAsFixed(1)}%",
                          style: TextStyle(
                            color: isPassing ? Colors.green : Colors.black54,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            fontFamily: 'Inter',
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
      ),
    );
  }
}