import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui'; // Required for ImageFilter (Glassmorphism)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PracticeInterface extends StatefulWidget {
  const PracticeInterface({super.key});

  @override
  _PracticeInterfaceState createState() => _PracticeInterfaceState();
}

class _PracticeInterfaceState extends State<PracticeInterface> {
  CameraController? _controller;
  HandLandmarkerPlugin? _landmarkerPlugin;
  
  bool _isInitialized = false;
  bool _isDetecting = false;
  bool _isSuccessAchieved = false;

  // --- CONTINUOUS GAME SYSTEM ---
  final String _alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  int _currentIdx = 0;
  String get targetLetter => _alphabet[_currentIdx];

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

  Future<void> _loadGestureLibrary(String letter) async {
    try {
      String jsonString = await rootBundle.loadString('assets/alphabet/$letter.json');
      setState(() {
        _template = jsonDecode(jsonString);
      });
    } catch (e) {
      debugPrint("Could not find gesture resource profile for: $letter");
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

    await _loadGestureLibrary(targetLetter);
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
    String currentLetter = targetLetter.toUpperCase();
    bool isPassing = _currentScore >= successThreshold;
    final double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: const Color(0xFFFFF9E5),
      
      // --- GLASSMORPHISM APP BAR ---
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.4), 
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: const Text(
          'Continuous Practice',
          style: TextStyle(
            color: Colors.black87, 
            fontSize: 22, 
            fontFamily: 'Inter', 
            fontWeight: FontWeight.w800, 
            letterSpacing: -0.96
          ),
        ),
      ),
      body: Stack(
        children: [
          // Ambient blurred background drops
          Positioned(
            top: -30, right: -30,
            child: Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFB800).withOpacity(0.2))),
          ),
          Positioned(
            bottom: 50, left: -50,
            child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7DC579).withOpacity(0.15))),
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
                      style: const TextStyle(
                        color: Colors.black87, 
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
                                color: Colors.grey.shade300,
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
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  width: 4.0,
                                  color: isPassing ? Colors.green : const Color(0xFFCBD0DC).withOpacity(0.6),
                                ),
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
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.green.withOpacity(0.3), width: 1.5),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  "Success! +$xpReward XP",
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  "Loading next letter...",
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    ] else if (_holdProgress > 0.0) ...[
                      Column(
                        children: [
                          const Text(
                            "Hold steady...",
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 18),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                width: screenWidth * 0.70, 
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.4), 
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 1)
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
                              color: isPassing ? Colors.green.withOpacity(0.2) : Colors.white.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: isPassing ? Colors.green.withOpacity(0.4) : Colors.white.withOpacity(0.8),
                                width: 1.5
                              ),
                            ),
                            child: Text(
                              "Score: ${_currentScore.toStringAsFixed(1)}%",
                              style: TextStyle(
                                color: isPassing ? Colors.green.shade700 : Colors.black54,
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