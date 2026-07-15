import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for HapticFeedback
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

class TutorialPractice extends StatefulWidget {
  final String targetLetter;

  const TutorialPractice({super.key, required this.targetLetter});

  @override
  _TutorialPracticeState createState() => _TutorialPracticeState();
}

class _TutorialPracticeState extends State<TutorialPractice> {
  CameraController? _controller;
  HandLandmarkerPlugin? _landmarkerPlugin;
  
  bool _isInitialized = false;
  bool _isDetecting = false;
  bool _isSuccessAchieved = false;

  List<dynamic>? _template;
  double _currentScore = 0.0;
  double _holdProgress = 0.0;
  DateTime? _startHoldTime;

  final double successThreshold = 78.0;
  final double holdDurationSeconds = 2.0;

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
        ResolutionPreset.low, 
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

  // --- IMMEDIATE PHYSICAL FEEDBACK ADDED HERE ---
  void _onSuccess() async {
    _isSuccessAchieved = true;
    _startHoldTime = null;
    _holdProgress = 0.0;
    
    HapticFeedback.heavyImpact(); 
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.heavyImpact(); 
    
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Success! ⭐⭐⭐"),
        content: Text("You have mastered the letter ${widget.targetLetter}!"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); 
              Navigator.pop(context); 
            },
            child: const Text("Back to Tutorial"),
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
    String currentLetter = widget.targetLetter.toUpperCase();
    bool isPassing = _currentScore >= successThreshold;

    const double baseWidth = 393;
    const double baseHeight = 852;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double scaleX = constraints.maxWidth / baseWidth;
            final double scaleY = constraints.maxHeight / baseHeight;
            final double scale = math.min(scaleX, scaleY);

            return Container(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              color: const Color(0xFFFFF9E5),
              child: Stack(
                children: [
                  Positioned(
                    left: 0, 
                    top: 0,
                    child: Container(
                      width: constraints.maxWidth, 
                      height: 59 * scaleY, 
                      decoration: const BoxDecoration(color: Colors.black)
                    ),
                  ),
                  Positioned(
                    left: 0, 
                    top: 59 * scaleY,
                    child: Container(
                      width: constraints.maxWidth, 
                      height: 50 * scaleY, 
                      decoration: const BoxDecoration(color: Color(0xFFFFB800))
                    ),
                  ),
                  Positioned(
                    left: 0, 
                    top: 109 * scaleY,
                    child: Container(
                      width: constraints.maxWidth, 
                      height: 50 * scaleY, 
                      decoration: const BoxDecoration(color: Color(0xCCF39C12))
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 116 * scaleY,
                    child: Center(
                      child: Text(
                        'Practice', 
                        style: TextStyle(
                          color: Colors.black, 
                          fontSize: 16 * scale, 
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                        )
                      ),
                    ),
                  ),
                  
                  Positioned(
                    left: 16 * scaleX, 
                    top: 62 * scaleY,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 44 * scale, 
                        height: 44 * scale,
                        decoration: BoxDecoration(
                          color: const Color(0x33FFF8E7), 
                          borderRadius: BorderRadius.circular(14 * scale)
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.black, size: 20 * scale),
                      ),
                    ),
                  ),

                  Positioned(
                    left: 0,
                    right: 0,
                    top: 185 * scaleY,
                    child: Center(
                      child: Text(
                        '$currentLetter${currentLetter.toLowerCase()}',
                        style: TextStyle(
                          color: Colors.black, 
                          fontSize: 36 * scale, 
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                  
                  Positioned(
                    left: (constraints.maxWidth - (280 * scaleX)) / 2, 
                    top: 220 * scaleY,
                    child: Container(
                      width: 280 * scaleX, 
                      height: 265 * scaleY,
                      decoration: ShapeDecoration(
                        image: DecorationImage(
                          image: AssetImage("assets/pictures/$currentLetter.png"),
                          fit: BoxFit.cover,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14 * scale)
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: (constraints.maxWidth - (314 * scaleX)) / 2, 
                    top: 520 * scaleY,
                    child: SizedBox(
                      width: 314 * scaleX,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 314 * scaleX, 
                            height: 220 * scaleY,
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                side: BorderSide(
                                  width: 6.0 * scale,
                                  color: isPassing ? Colors.green : const Color(0xFFCBD0DC),
                                ),
                                borderRadius: BorderRadius.circular(20 * scale),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14 * scale),
                              child: _isInitialized && _controller != null
                                  ? CameraPreview(_controller!)
                                  : const Center(child: CircularProgressIndicator(color: Colors.amber)),
                            ),
                          ),
                          SizedBox(height: 12 * scaleY),
                          
                          if (_holdProgress > 0.0)
                            Container(
                              width: 314 * scaleX, 
                              height: 12 * scaleY,
                              decoration: BoxDecoration(
                                color: Colors.grey[300], 
                                borderRadius: BorderRadius.circular(6 * scale)
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: _holdProgress,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.green, 
                                      borderRadius: BorderRadius.circular(6 * scale)
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            Text(
                              "On-Device Accuracy: ${_currentScore.toStringAsFixed(1)}%",
                              style: TextStyle(
                                color: isPassing ? Colors.green : Colors.black54,
                                fontWeight: FontWeight.bold,
                                fontSize: 15 * scale,
                                fontFamily: 'Inter',
                              ),
                            ),
                            
                          SizedBox(height: 8 * scaleY),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 10 * scaleX, vertical: 4 * scaleY),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(6 * scale),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  "Status: ${_isInitialized ? 'Pipeline Ready' : 'Initializing Engine...'}",
                                  style: TextStyle(
                                    fontSize: 11 * scale, 
                                    color: _isInitialized ? Colors.blue : Colors.red, 
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                                Text(
                                  _template == null ? "Loading template..." : "Template Loaded: $currentLetter",
                                  style: TextStyle(
                                    fontSize: 10 * scale, 
                                    color: Colors.black45,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}