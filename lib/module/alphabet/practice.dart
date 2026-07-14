import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart'; // Native MediaPipe Task bridge for Flutter

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

  // --- GAME SYSTEM CONTROL METRICS ---
  final String _alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  int _currentIdx = 0;
  
  Map<String, List<dynamic>> _gestureLibrary = {};
  double _currentScore = 0.0;
  double _holdProgress = 0.0;
  DateTime? _startHoldTime;

  // Configuration Constants matched with your Python script
  final double successThreshold = 78.0;
  final double holdDurationSeconds = 2.0;

  @override
  void initState() {
    super.initState();
    _initializePipeline();
  }

  Future<void> _initializePipeline() async {
    try {
      // 1. Load your asset-based gesture reference profiles
      await _loadGestureLibrary();

      // 2. Initialize the Local MediaPipe Task Engine (No modelPath param used here)
      _landmarkerPlugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.gpu, // Force GPU processing for real-time tracking
      );

      // 3. Set up your front camera stream
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        frontCamera, 
        ResolutionPreset.low, // Lower resolution optimizes inference execution speeds
        enableAudio: false,
      );

      await _controller!.initialize();
      
      // Begin on-device frame analysis callback loop
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
    for (int i = 0; i < _alphabet.length; i++) {
      String letter = _alphabet[i];
      try {
        String jsonString = await rootBundle.loadString('assets/alphabet/$letter.json');
        _gestureLibrary[letter] = jsonDecode(jsonString);
      } catch (e) {
        debugPrint("Could not find gesture resource profile for: $letter");
      }
    }
  }

void _processCameraFrame(CameraImage image) {
    if (_isDetecting || !_isInitialized || _landmarkerPlugin == null) return;
    _isDetecting = true;

    try {
      // Let the native sensor orientation find the hand first
      int sensorOrientation = _controller!.description.sensorOrientation;
      final List<Hand> detectedHands = _landmarkerPlugin!.detect(image, sensorOrientation);

      if (detectedHands.isNotEmpty) {
        final String targetLetter = _alphabet[_currentIdx];

        if (_gestureLibrary.containsKey(targetLetter)) {
          double highestScoreAcrossAllHands = 0.0;
          int bestHandIdx = 0;

          for (int handIdx = 0; handIdx < detectedHands.length; handIdx++) {
            final double score = _calculateScore(
              detectedHands[handIdx].landmarks, 
              _gestureLibrary[targetLetter]!,
            );
            if (score > highestScoreAcrossAllHands) {
              highestScoreAcrossAllHands = score;
              bestHandIdx = handIdx;
            }
          }
          
          // Debug logging to understand scores
          if (highestScoreAcrossAllHands > 5) {
            final wrist = detectedHands[bestHandIdx].landmarks[0];
            debugPrint('Letter: $targetLetter | Score: ${highestScoreAcrossAllHands.toStringAsFixed(1)}% | '
              'Wrist: (${wrist.x.toStringAsFixed(2)}, ${wrist.y.toStringAsFixed(2)})');
          }
          
          _updateGameLogic(highestScoreAcrossAllHands);
        }
      } else {
        setState(() {
          _currentScore = 0.0;
          _holdProgress = 0.0;
          _startHoldTime = null;
        });
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
  final Landmark mBase = liveLms[9]; // Middle finger MCP joint
  
  // Compute the hand scale (distance from wrist to middle finger base)
  double dist = math.sqrt(
    math.pow(wrist.x - mBase.x, 2) + 
    math.pow(wrist.y - mBase.y, 2) + 
    math.pow(wrist.z - mBase.z, 2)
  );
  
  if (dist == 0) dist = 1.0;
  
  double bestScore = 0.0;

  // All 8 transformation combinations: 4 rotations x 2 X-flips
  final orientationMatrices = [
    [1.0, 0.0, 0.0, 1.0, 1.0],     // 0 Degrees
    [0.0, -1.0, 1.0, 0.0, 1.0],    // 90 Degrees CCW
    [-1.0, 0.0, 0.0, -1.0, 1.0],   // 180 Degrees
    [0.0, 1.0, -1.0, 0.0, 1.0],    // 270 Degrees CW
    [1.0, 0.0, 0.0, 1.0, -1.0],    // 0 Degrees + X flip
    [0.0, -1.0, 1.0, 0.0, -1.0],   // 90 Degrees CCW + X flip
    [-1.0, 0.0, 0.0, -1.0, -1.0],  // 180 Degrees + X flip
    [0.0, 1.0, -1.0, 0.0, -1.0],   // 270 Degrees CW + X flip
  ];

  // Try all 8 transformations
  for (var matrix in orientationMatrices) {
    double xx = matrix[0];
    double xy = matrix[1];
    double yx = matrix[2];
    double yy = matrix[3];
    double flipX = matrix[4];

    double totalDifference = 0.0;

    for (int i = 0; i < 21; i++) {
      // Get live landmark relative to wrist, scale normalized
      double dx = (liveLms[i].x - wrist.x) / dist;
      double dy = (liveLms[i].y - wrist.y) / dist;
      double dz = (liveLms[i].z - wrist.z) / dist;

      // Apply X-flip FIRST
      dx = dx * flipX;

      // Then apply rotation transformation
      double rx = dx * xx + dy * xy;
      double ry = dx * yx + dy * yy;

      // Get template values
      double tx = template[i]['x'];
      double ty = template[i]['y'];
      double tz = template[i]['z'];

      // Calculate 3D Euclidean distance difference
      double pointDiff = math.sqrt(
        math.pow(rx - tx, 2) + 
        math.pow(ry - ty, 2) + 
        math.pow(dz - tz, 2)
      );
      totalDifference += pointDiff;
    }

    // More lenient scoring formula to reach 80%+
    // 100 - (meanDiff * 80) instead of * 100
    double meanDiff = totalDifference / 21.0;
    double score = (100.0 - (meanDiff * 80.0)).clamp(0.0, 100.0);
    
    if (score > bestScore) {
      bestScore = score;
    }
  }

  return bestScore;
}

  void _updateGameLogic(double score) {
    final now = DateTime.now();

    setState(() {
      _currentScore = score;

      if (_currentScore >= successThreshold) {
        _startHoldTime ??= now;
        final difference = now.difference(_startHoldTime!).inMilliseconds / 1000.0;
        _holdProgress = (difference / holdDurationSeconds).clamp(0.0, 1.0);

        if (difference >= holdDurationSeconds) {
          _advanceToNextLetter();
        }
      } else {
        _startHoldTime = null;
        _holdProgress = 0.0;
      }
    });
  }

  void _advanceToNextLetter() {
    _startHoldTime = null;
    _holdProgress = 0.0;

    if (_currentIdx < _alphabet.length - 1) {
      _currentIdx++;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Correct! Next letter: ${_alphabet[_currentIdx]}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Success!"),
          content: const Text("You have mastered the complete ASL Alphabet list dynamically!"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _currentIdx = 0);
              },
              child: const Text("Reset Challenge"),
            )
          ],
        ),
      );
    }
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
    String currentLetter = _alphabet[_currentIdx];
    bool isPassing = _currentScore >= successThreshold;

    return Column(
      children: [
        Container(
          width: 393,
          height: 852,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFFFFF9E5)),
          child: Stack(
            children: [
              // --- SYSTEM COMPONENT WATERMARK HEADER BACKGROUNDS ---
              Positioned(
                left: 0, top: 0,
                child: Container(width: 393, height: 59, decoration: const BoxDecoration(color: Colors.black)),
              ),
              Positioned(
                left: 0, top: 59,
                child: Container(width: 393, height: 50, decoration: const BoxDecoration(color: Color(0xFFFFB800))),
              ),
              Positioned(
                left: 0, top: 109,
                child: Container(width: 393, height: 50, decoration: const BoxDecoration(color: Color(0xCCF39C12))),
              ),
              Positioned(
                left: 162, top: 116,
                child: const Text('Practice', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              
              // --- MAIN INTERACTIVE DISPLAY TARGET ---
              Positioned(
                left: 168, top: 185,
                child: Text(
                  '$currentLetter${currentLetter.toLowerCase()}',
                  style: const TextStyle(color: Colors.black, fontSize: 36, fontWeight: FontWeight.w800),
                ),
              ),
              
              Positioned(
                left: 53, top: 220,
                child: Container(
                  width: 280, height: 265,
                  decoration: ShapeDecoration(
                    image: DecorationImage(
                      image: AssetImage("assets/pictures/$currentLetter.png"),
                      fit: BoxFit.cover,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),

              // --- ON-DEVICE LIVE VIEW OVERLAY LAYOUT ---
              Positioned(
                left: 39.50, top: 540,
                child: Column(
                  children: [
                    Container(
                      width: 314, height: 240,
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            width: 6.0,
                            color: isPassing ? Colors.green : const Color(0xFFCBD0DC),
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _isInitialized && _controller != null
                            ? CameraPreview(_controller!)
                            : const Center(child: CircularProgressIndicator(color: Colors.amber)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // --- HOLD TIMING FEEDBACK METRIC UI BAR ---
                    if (_holdProgress > 0.0)
                      Container(
                        width: 314, height: 12,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(6)),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _holdProgress,
                            child: Container(decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(6))),
                          ),
                        ),
                      )
                    else
                      Text(
                        "On-Device Accuracy: ${_currentScore.toStringAsFixed(1)}%",
                        style: TextStyle(
                          color: isPassing ? Colors.green : Colors.black54,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      
                    // --- LIVE PIPELINE DIAGNOSTIC HUD ---
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        children: [
                          Text(
                            "Status: ${_isInitialized ? 'Pipeline Ready' : 'Initializing Engine...'}",
                            style: TextStyle(fontSize: 11, color: _isInitialized ? Colors.blue : Colors.red, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            "Templates Loaded: ${_gestureLibrary.length} / 26",
                            style: const TextStyle(fontSize: 10, color: Colors.black45),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}