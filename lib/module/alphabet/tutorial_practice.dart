import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:onnxruntime/onnxruntime.dart';

// =============================================================================
// LANDMARK & RESULT MODELS
// =============================================================================

class LandmarkPoint {
  final double x;
  final double y;
  final double z;

  LandmarkPoint(this.x, this.y, this.z);

  double distanceTo(LandmarkPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  LandmarkPoint subtract(LandmarkPoint other) {
    return LandmarkPoint(x - other.x, y - other.y, z - other.z);
  }
}

class LetterJResult {
  final bool isLetterJ;
  final double confidence;
  final String message;

  LetterJResult({
    required this.isLetterJ,
    required this.confidence,
    required this.message,
  });
}

class LetterZResult {
  final bool isLetterZ;
  final double confidence;
  final String message;

  LetterZResult({
    required this.isLetterZ,
    required this.confidence,
    required this.message,
  });
}

// =============================================================================
// LETTER J CLASSIFIER SERVICE (19 FEATURES - FIXES ONNX DIMENSION MISMATCH)
// =============================================================================

class LetterJClassifierService {
  OrtSession? _session;
  bool _isInitialized = false;

  static const int wrist = 0;
  static const int indexMcp = 5;
  static const int indexTip = 8;
  static const int middleMcp = 9;
  static const int middleTip = 12;
  static const int ringTip = 16;
  static const int pinkyMcp = 17;
  static const int pinkyTip = 20;

  static const int targetFrames = 32;
  static const int featureDim = 19;

  bool get isInitialized => _isInitialized;

  Future<void> initialize({String modelAssetPath = 'assets/alphabet/fsl_letter_j.onnx'}) async {
    try {
      OrtEnv.instance.init();
      final rawAsset = await rootBundle.load(modelAssetPath);
      final bytes = rawAsset.buffer.asUint8List();

      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes, sessionOptions);
      _isInitialized = true;
      debugPrint("LetterJClassifierService initialized successfully with ONNX model.");
    } catch (e) {
      _isInitialized = false;
      debugPrint("Failed to initialize LetterJClassifierService: $e");
      rethrow;
    }
  }

  List<List<LandmarkPoint>> _resampleSequence(List<List<LandmarkPoint>> rawSeq, int targetLen) {
    final int currentLen = rawSeq.length;
    if (currentLen == targetLen) return rawSeq;

    final List<List<LandmarkPoint>> resampled = [];
    for (int t = 0; t < targetLen; t++) {
      final double progress = t / (targetLen - 1);
      final double oldPos = progress * (currentLen - 1);
      final int idx0 = oldPos.floor();
      final int idx1 = math.min(idx0 + 1, currentLen - 1);
      final double alpha = oldPos - idx0;

      final List<LandmarkPoint> frameLms = [];
      for (int i = 0; i < 21; i++) {
        final p0 = rawSeq[idx0][i];
        final p1 = rawSeq[idx1][i];
        frameLms.add(LandmarkPoint(
          p0.x + alpha * (p1.x - p0.x),
          p0.y + alpha * (p1.y - p0.y),
          p0.z + alpha * (p1.z - p0.z),
        ));
      }
      resampled.add(frameLms);
    }
    return resampled;
  }

  Float32List _extract19Features(List<List<LandmarkPoint>> seq32) {
    final List<LandmarkPoint> meanFrame = [];
    for (int i = 0; i < 21; i++) {
      double mx = 0, my = 0, mz = 0;
      for (int t = 0; t < targetFrames; t++) {
        mx += seq32[t][i].x;
        my += seq32[t][i].y;
        mz += seq32[t][i].z;
      }
      meanFrame.add(LandmarkPoint(mx / targetFrames, my / targetFrames, mz / targetFrames));
    }

    final double palmScale = meanFrame[middleMcp].distanceTo(meanFrame[wrist]) + 1e-6;
    final LandmarkPoint wristPos = meanFrame[wrist];

    final double pkyExt = meanFrame[pinkyTip].distanceTo(wristPos) / palmScale;
    final double idxExt = meanFrame[indexTip].distanceTo(wristPos) / palmScale;
    final double midExt = meanFrame[middleTip].distanceTo(wristPos) / palmScale;
    final double ringExt = meanFrame[ringTip].distanceTo(wristPos) / palmScale;
    final double pkyFold = meanFrame[pinkyTip].distanceTo(meanFrame[pinkyMcp]) / palmScale;
    final double pkyIdxRatio = pkyExt / (idxExt + 1e-6);

    final LandmarkPoint startPt = seq32[0][pinkyTip];
    final List<LandmarkPoint> normTraj = [];
    for (int t = 0; t < targetFrames; t++) {
      final p = seq32[t][pinkyTip];
      normTraj.add(LandmarkPoint(
        (p.x - startPt.x) / palmScale,
        (p.y - startPt.y) / palmScale,
        (p.z - startPt.z) / palmScale,
      ));
    }

    double dispTotal = 0.0;
    final List<LandmarkPoint> velocities = [];
    for (int t = 0; t < targetFrames - 1; t++) {
      final diff = normTraj[t + 1].subtract(normTraj[t]);
      velocities.add(diff);
      dispTotal += math.sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z);
    }

    double yMinDown = normTraj[0].y;
    double minX = normTraj[0].x;
    double maxX = normTraj[0].x;

    for (var p in normTraj) {
      if (p.y > yMinDown) yMinDown = p.y;
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
    }

    final double hookUp = yMinDown - normTraj.last.y;
    final double xSpread = maxX - minX;

    double sumX = 0, sumY = 0, sumZ = 0;
    for (var p in normTraj) {
      sumX += p.x; sumY += p.y; sumZ += p.z;
    }
    final double avgX = sumX / targetFrames;
    final double avgY = sumY / targetFrames;
    final double avgZ = sumZ / targetFrames;

    double varX = 0, varY = 0, varZ = 0;
    for (var p in normTraj) {
      varX += (p.x - avgX) * (p.x - avgX);
      varY += (p.y - avgY) * (p.y - avgY);
      varZ += (p.z - avgZ) * (p.z - avgZ);
    }
    final double stdTrajX = math.sqrt(varX / targetFrames);
    final double stdTrajY = math.sqrt(varY / targetFrames);
    final double stdTrajZ = math.sqrt(varZ / targetFrames);

    double vSumX = 0, vSumY = 0, vSumZ = 0;
    for (var v in velocities) {
      vSumX += v.x; vSumY += v.y; vSumZ += v.z;
    }
    final int vCount = velocities.length;
    final double meanVelX = vSumX / vCount;
    final double meanVelY = vSumY / vCount;
    final double meanVelZ = vSumZ / vCount;

    double vVarX = 0, vVarY = 0, vVarZ = 0;
    for (var v in velocities) {
      vVarX += (v.x - meanVelX) * (v.x - meanVelX);
      vVarY += (v.y - meanVelY) * (v.y - meanVelY);
      vVarZ += (v.z - meanVelZ) * (v.z - meanVelZ);
    }
    final double stdVelX = math.sqrt(vVarX / vCount);
    final double stdVelY = math.sqrt(vVarY / vCount);
    final double stdVelZ = math.sqrt(vVarZ / vCount);

    final Float32List features = Float32List(featureDim);
    features[0] = pkyExt;
    features[1] = idxExt;
    features[2] = midExt;
    features[3] = ringExt;
    features[4] = pkyFold;
    features[5] = pkyIdxRatio;
    features[6] = dispTotal;
    features[7] = yMinDown;
    features[8] = hookUp;
    features[9] = xSpread;
    features[10] = stdTrajX;
    features[11] = stdTrajY;
    features[12] = stdTrajZ;
    features[13] = meanVelX;
    features[14] = meanVelY;
    features[15] = meanVelZ;
    features[16] = stdVelX;
    features[17] = stdVelY;
    features[18] = stdVelZ;

    return features;
  }

  LetterJResult classifyStroke(List<List<LandmarkPoint>> recordedFrames) {
    if (!_isInitialized || _session == null) {
      return LetterJResult(isLetterJ: false, confidence: 0.0, message: 'Hindi naka-initialize ang model.');
    }

    if (recordedFrames.length < 12) {
      return LetterJResult(isLetterJ: false, confidence: 0.0, message: 'Masyadong maikli ang galaw. Gawin ang buong kumpas ng Letter J.');
    }

    final seq32 = _resampleSequence(recordedFrames, targetFrames);

    final p0 = seq32[0];
    final palm0 = p0[middleMcp].distanceTo(p0[wrist]) + 1e-6;
    final pkyExt0 = p0[pinkyTip].distanceTo(p0[wrist]) / palm0;
    final idxExt0 = p0[indexTip].distanceTo(p0[wrist]) / palm0;

    if (pkyExt0 < 1.05 || idxExt0 > 1.20) {
      return LetterJResult(
        isLetterJ: false,
        confidence: 0.0,
        message: 'Maling porma ng kamay! Itaas ang kalingkingan para sa Letter J.',
      );
    }

    final Float32List inputFeatures = _extract19Features(seq32);

    final inputShape = [1, featureDim];
    final inputOrtValue = OrtValueTensor.createTensorWithDataList(inputFeatures, inputShape);
    final runOptions = OrtRunOptions();
    
    final inputName = _session!.inputNames.isNotEmpty ? _session!.inputNames.first : 'float_input';
    final outputs = _session!.run(runOptions, {inputName: inputOrtValue});

    inputOrtValue.release();
    runOptions.release();

    final classOutput = outputs[0]?.value as List<dynamic>?;
    final int predictedClass = classOutput != null ? (classOutput[0] as int) : 0;

    double confidence = 0.85;
    if (outputs.length > 1 && outputs[1]?.value != null) {
      final probs = outputs[1]!.value as List<dynamic>;
      if (probs.isNotEmpty && probs[0] is Map) {
        final probMap = probs[0] as Map;
        confidence = (probMap[1] as double? ?? 0.0);
      }
    }

    for (var element in outputs) {
      element?.release();
    }

    if (predictedClass == 1 && confidence >= 0.55) {
      return LetterJResult(
        isLetterJ: true,
        confidence: confidence,
        message: 'Mahusay! Wastong kumpas at porma para sa Letter J.',
      );
    } else {
      return LetterJResult(
        isLetterJ: false,
        confidence: confidence,
        message: 'Maling kumpas ang naisagawa para sa Letter J.',
      );
    }
  }

  void dispose() {
    _session?.release();
    _session = null;
    _isInitialized = false;
  }
}

// =============================================================================
// LETTER Z CLASSIFIER SERVICE (TRAJECTORY KINEMATICS)
// =============================================================================

class LetterZClassifierService {
  static const int wrist = 0;
  static const int indexTip = 8;
  static const int middleMcp = 9;
  static const int targetFrames = 32;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    _isInitialized = true;
  }

  List<List<LandmarkPoint>> _resampleSequence(List<List<LandmarkPoint>> rawSeq, int targetLen) {
    final int currentLen = rawSeq.length;
    if (currentLen == targetLen) return rawSeq;

    final List<List<LandmarkPoint>> resampled = [];
    for (int t = 0; t < targetLen; t++) {
      final double progress = t / (targetLen - 1);
      final double oldPos = progress * (currentLen - 1);
      final int idx0 = oldPos.floor();
      final int idx1 = math.min(idx0 + 1, currentLen - 1);
      final double alpha = oldPos - idx0;

      final List<LandmarkPoint> frameLms = [];
      for (int i = 0; i < 21; i++) {
        final p0 = rawSeq[idx0][i];
        final p1 = rawSeq[idx1][i];
        frameLms.add(LandmarkPoint(
          p0.x + alpha * (p1.x - p0.x),
          p0.y + alpha * (p1.y - p0.y),
          p0.z + alpha * (p1.z - p0.z),
        ));
      }
      resampled.add(frameLms);
    }
    return resampled;
  }

  LetterZResult classifyStroke(List<List<LandmarkPoint>> recordedFrames) {
    if (recordedFrames.length < 8) {
      return LetterZResult(
        isLetterZ: false,
        confidence: 0.0,
        message: 'Masyadong maikli ang galaw. Gawin ang buong kumpas ng Letter Z.',
      );
    }

    final seq32 = _resampleSequence(recordedFrames, targetFrames);

    double palmSum = 0.0;
    for (int t = 0; t < targetFrames; t++) {
      palmSum += seq32[t][middleMcp].distanceTo(seq32[t][wrist]);
    }
    final double palmScale = (palmSum / targetFrames) + 1e-6;

    final List<LandmarkPoint> traj = [];
    for (int t = 0; t < targetFrames; t++) {
      traj.add(seq32[t][indexTip]);
    }

    double minX = traj[0].x, maxX = traj[0].x;
    double minY = traj[0].y, maxY = traj[0].y;
    for (var p in traj) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final double xSpan = (maxX - minX) / palmScale;
    final double ySpan = (maxY - minY) / palmScale;

    if (xSpan < 0.20 || ySpan < 0.20) {
      return LetterZResult(
        isLetterZ: false,
        confidence: 0.0,
        message: 'Masyadong maliit ang galaw para sa Letter Z.',
      );
    }

    int topCornerIdx = 0;
    double maxTopX = -double.infinity;
    
    for (int t = 2; t < (targetFrames * 0.65).toInt(); t++) {
      if (traj[t].x > maxTopX) {
        maxTopX = traj[t].x;
        topCornerIdx = t;
      }
    }

    int bottomCornerIdx = topCornerIdx;
    double minBottomX = double.infinity;
    
    for (int t = topCornerIdx + 1; t < targetFrames - 2; t++) {
      if (traj[t].x < minBottomX) {
        minBottomX = traj[t].x;
        bottomCornerIdx = t;
      }
    }

    final double stroke1Dx = traj[topCornerIdx].x - traj[0].x;                      
    final double stroke2Dx = traj[bottomCornerIdx].x - traj[topCornerIdx].x;        
    final double stroke2Dy = traj[bottomCornerIdx].y - traj[topCornerIdx].y;        
    final double stroke3Dx = traj[targetFrames - 1].x - traj[bottomCornerIdx].x;   

    final bool isTopRight = (stroke1Dx / palmScale) > 0.04 || (traj[topCornerIdx].x > traj[0].x);
    final bool isDiagDownLeft = (stroke2Dx / palmScale) < -0.03 && (stroke2Dy / palmScale) > 0.04;
    final bool isBottomRight = (stroke3Dx / palmScale) > 0.04 || (traj[targetFrames - 1].x > traj[bottomCornerIdx].x);

    if (isTopRight && isDiagDownLeft && isBottomRight) {
      final double score = math.min(98.0, 80.0 + (xSpan + ySpan) * 10.0);
      return LetterZResult(
        isLetterZ: true,
        confidence: score,
        message: 'Mahusay! Wastong kumpas at porma para sa Letter Z.',
      );
    } else {
      return LetterZResult(
        isLetterZ: false,
        confidence: 0.0,
        message: 'Maling kumpas! I-trace ang paitaas-pakanan, pahilis pababa-pakaliwa, at pakanan.',
      );
    }
  }

  void dispose() {
    _isInitialized = false;
  }
}

// =============================================================================
// THEME VISUAL MAPPING
// =============================================================================

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

    if (primary.blue > 160 && primary.red < 120) {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.water_drop_rounded,
        secondaryIcon: Icons.waves_rounded,
        ambientIcon1: Icons.bubble_chart_rounded,
        ambientIcon2: Icons.sailing_rounded,
      );
    } else if (primary.green > 160 && primary.red < 120) {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.eco_rounded,
        secondaryIcon: Icons.forest_rounded,
        ambientIcon1: Icons.park_rounded,
        ambientIcon2: Icons.energy_savings_leaf_rounded,
      );
    } else if (isDark) {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.auto_awesome_rounded,
        secondaryIcon: Icons.nights_stay_rounded,
        ambientIcon1: Icons.star_border_rounded,
        ambientIcon2: Icons.wb_twilight_rounded,
      );
    } else {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.stars_rounded,
        secondaryIcon: Icons.workspace_premium_rounded,
        ambientIcon1: Icons.wb_sunny_rounded,
        ambientIcon2: Icons.auto_awesome_rounded,
      );
    }
  }
}

// =============================================================================
// MAIN PRACTICE WIDGET
// =============================================================================

class TutorialPractice extends StatefulWidget {
  final String targetLetter;

  const TutorialPractice({super.key, required this.targetLetter});

  @override
  _TutorialPracticeState createState() => _TutorialPracticeState();
}

class _TutorialPracticeState extends State<TutorialPractice> with WidgetsBindingObserver {
  CameraController? _controller;
  HandLandmarkerPlugin? _landmarkerPlugin;
  StreamSubscription<List<Hand>>? _handSub;

  final LetterJClassifierService _letterJService = LetterJClassifierService();
  final LetterZClassifierService _letterZService = LetterZClassifierService();

  static final Map<String, List<dynamic>> _templateCache = {};

  bool _isProcessingFrame = false;
  final List<List<LandmarkPoint>> _frameBuffer = [];
  DateTime _lastSampleTime = DateTime.now();

  bool _isInitialized = false;
  bool _isSuccessAchieved = false;

  List<dynamic>? _template;
  double _currentScore = 0.0;
  double _holdProgress = 0.0;
  DateTime? _startHoldTime;
  String _currentFeedback = "Ipuwesto ang kamay sa tapat ng camera";

  int _bufferFrameCount = 0;
  static const int _requiredBufferFrames = 24;

  static const List<String> _dynamicLetters = ['J', 'Z'];
  bool get _isDynamicLetter => _dynamicLetters.contains(widget.targetLetter.toUpperCase());

  final double successThreshold = 70.0;
  final double holdDurationSeconds = 1.0;
  final int xpReward = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePipeline();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _controller?.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller != null && !_controller!.value.isStreamingImages) {
        _controller?.startImageStream(_processCameraFrame);
      }
    }
  }

  Future<void> _initializePipeline() async {
    try {
      final letter = widget.targetLetter.toUpperCase();

      if (letter == 'J') {
        await _letterJService.initialize();
      } else if (letter == 'Z') {
        await _letterZService.initialize();
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
      debugPrint("Pipeline setup error: $e");
    }
  }

  Future<void> _loadGestureLibrary() async {
    final letter = widget.targetLetter.toUpperCase();

    if (_templateCache.containsKey(letter)) {
      if (mounted) {
        setState(() {
          _template = _templateCache[letter];
        });
      }
      return;
    }

    try {
      final ref = FirebaseStorage.instance.ref('alphabet/$letter.json');
      final bytes = await ref.getData();

      if (bytes != null) {
        final jsonString = utf8.decode(bytes);
        final decodedJson = jsonDecode(jsonString) as List<dynamic>;

        _templateCache[letter] = decodedJson;

        if (mounted) {
          setState(() {
            _template = decodedJson;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading cloud gesture template for $letter: $e");
    }
  }

  void _processCameraFrame(CameraImage image) {
    if (!_isInitialized || _landmarkerPlugin == null || _isSuccessAchieved) return;
    if (!_isDynamicLetter && _template == null) return;
    if (_isProcessingFrame) return;

    try {
      final int sensorOrientation = _controller!.description.sensorOrientation;
      _landmarkerPlugin!.processFrame(image, sensorOrientation);
    } catch (e) {
      debugPrint("Landmark processing error: $e");
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

  void _onHandsDetected(List<Hand> detectedHands) async {
    if (_isSuccessAchieved || _isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      if (detectedHands.isNotEmpty) {
        double score = 0.0;
        String feedback = "Ipuwesto ang kamay sa tapat ng camera";
        final letter = widget.targetLetter.toUpperCase();

        if (!_isDynamicLetter) {
          if (_template != null) {
            double highestScoreAcrossAllHands = 0.0;

            for (int handIdx = 0; handIdx < detectedHands.length; handIdx++) {
              final double handScore = _calculateScore(
                detectedHands[handIdx].landmarks,
                _template!,
              );
              if (handScore > highestScoreAcrossAllHands) {
                highestScoreAcrossAllHands = handScore;
              }
            }

            score = highestScoreAcrossAllHands;
            feedback = score >= successThreshold
                ? "Tama ang posisyon! Hawakan ang kamay."
                : "I-adjust ang posisyon para sa Letter $letter.";
          }
        } else {
          final hand = detectedHands.first;

          final List<LandmarkPoint> framePoints = hand.landmarks.map((lm) {
            return LandmarkPoint(1.0 - lm.x, lm.y, lm.z);
          }).toList();

          final now = DateTime.now();
          if (now.difference(_lastSampleTime).inMilliseconds >= 45) {
            _lastSampleTime = now;
            _frameBuffer.add(framePoints);
            if (_frameBuffer.length > 24) {
              _frameBuffer.removeAt(0);
            }
            _bufferFrameCount = _frameBuffer.length;

            if (_frameBuffer.length >= 16) {
              if (letter == 'J') {
                final result = _letterJService.classifyStroke(_frameBuffer);
                score = result.isLetterJ ? (result.confidence * 100.0) : 30.0;
                feedback = result.message;
              } else if (letter == 'Z') {
                final result = _letterZService.classifyStroke(_frameBuffer);
                score = result.isLetterZ ? result.confidence : 25.0;
                feedback = result.message;
              }
            }
          } else {
            return;
          }
        }

        _updateGameLogic(score, feedback);
      } else {
        _frameBuffer.clear();
        _bufferFrameCount = 0;
        if (mounted) {
          setState(() {
            _currentScore = 0.0;
            _holdProgress = 0.0;
            _startHoldTime = null;
            _currentFeedback = "Walang kamay na nakikita";
          });
        }
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _updateGameLogic(double score, String feedback) {
    if (!mounted) return;
    final now = DateTime.now();

    setState(() {
      _currentScore = score;
      _currentFeedback = feedback;

      if (_currentScore >= successThreshold) {
        if (!_isDynamicLetter) {
          _startHoldTime ??= now;
          final difference = now.difference(_startHoldTime!).inMilliseconds / 1000.0;
          _holdProgress = (difference / holdDurationSeconds).clamp(0.0, 1.0);

          if (difference >= holdDurationSeconds) {
            _onSuccess();
          }
        } else {
          _holdProgress = 1.0;
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
                      fontWeight: FontWeight.w500,
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
    WidgetsBinding.instance.removeObserver(this);
    _handSub?.cancel();
    _controller?.stopImageStream();
    _controller?.dispose();
    _landmarkerPlugin?.dispose();

    _letterJService.dispose();
    _letterZService.dispose();
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
          'Tutorial Practice',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 22,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w800,
            letterSpacing: -0.96,
          ),
        ),
      ),
      body: Stack(
        children: [
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
                                                isPassing 
                                                  ? (!_isDynamicLetter ? "Hold!" : "Correct!") 
                                                  : "Frame Hand",
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
                    const SizedBox(height: 16),

                    Text(
                      _currentFeedback,
                      style: TextStyle(
                        color: isPassing ? Colors.green : theme.colorScheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),

                    if (!_isDynamicLetter && _holdProgress > 0.0) ...[
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
                            borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                width: screenWidth * 0.70,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: theme.colorScheme.surface.withOpacity(0.5), width: 1),
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
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    ] else if (_isDynamicLetter && _bufferFrameCount > 0 && _bufferFrameCount < _requiredBufferFrames) ...[
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Analyzing motion... ($_bufferFrameCount/$_requiredBufferFrames)",
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
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
                                height: 14,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: theme.colorScheme.surface.withOpacity(0.5), width: 1),
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: _bufferFrameCount / _requiredBufferFrames,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        borderRadius: BorderRadius.circular(12),
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
                                width: 1.5,
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