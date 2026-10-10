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
import '/services/frame_gate.dart';

import '/services/performance_monitor.dart';


// =============================================================================
// ONNX INFERENCE SERVICE WITH 78-FEATURE EXTRACTOR
// =============================================================================

class StudentEvaluationResult {
  final int targetNumber;
  final int? detectedNumber;
  final bool isCorrect;
  final double accuracyScore;
  final String feedback;
  final double kineticEnergy;

  StudentEvaluationResult({
    required this.targetNumber,
    required this.detectedNumber,
    required this.isCorrect,
    required this.accuracyScore,
    required this.feedback,
    required this.kineticEnergy,
  });
}

class FSLOnnxService {
  static OrtSession? _session;
  static int _loadedRangeGroup = -1;

  static Future<void> loadModelForTarget(int targetNumber) async {
    int group = 1;
    String assetPath = 'assets/numbers/fsl_numbers_11_20.onnx';

    if (targetNumber >= 21 && targetNumber <= 30) {
      group = 2;
      assetPath = 'assets/numbers/fsl_numbers_20_30.onnx';
    } else if (targetNumber >= 31 && targetNumber <= 40) {
      group = 3;
      assetPath = 'assets/numbers/fsl_numbers_31_40.onnx';
    } else if (targetNumber >= 41 && targetNumber <= 50) {
      group = 4;
      assetPath = 'assets/numbers/fsl_numbers_41_50.onnx';
    } else if (targetNumber >= 51 && targetNumber <= 60) {
      group = 5;
      assetPath = 'assets/numbers/fsl_numbers_51_60.onnx';
    } else if (targetNumber >= 61 && targetNumber <= 70) {
      group = 6;
      assetPath = 'assets/numbers/fsl_numbers_61_70.onnx';
    } else if (targetNumber >= 71 && targetNumber <= 80) {
      group = 7;
      assetPath = 'assets/numbers/fsl_numbers_71_80.onnx';
    } else if (targetNumber >= 81 && targetNumber <= 90) {
      group = 8;
      assetPath = 'assets/numbers/fsl_numbers_81_90.onnx';
    } else if (targetNumber >= 91 && targetNumber <= 100) {
      group = 9;
      assetPath = 'assets/numbers/fsl_numbers_91_100.onnx';
    }

    if (_session != null && _loadedRangeGroup == group) {
      return;
    }

    try {
      _session?.release();
      OrtEnv.instance.init();
      final rawAsset = await rootBundle.load(assetPath);
      final bytes = rawAsset.buffer.asUint8List();
      _session = OrtSession.fromBuffer(bytes, OrtSessionOptions());
      _loadedRangeGroup = group;
      debugPrint("Loaded ONNX Model for Range Group $group: $assetPath");
    } catch (e) {
      debugPrint("ONNX Initialization Failed for $assetPath: $e");
    }
  }

  static void release() {
    _session?.release();
    _session = null;
    _loadedRangeGroup = -1;
  }

  static Float32List extract78Features(List<List<double>> window24Frames) {
    const tips = [4, 8, 12, 16, 20];
    const mcps = [2, 5, 9, 13, 17];
    const pips = [3, 6, 10, 14, 18];

    List<List<List<double>>> norm = [];
    for (int f = 0; f < 24; f++) {
      final fData = window24Frames[f];
      final wX = fData[0], wY = fData[1], wZ = fData[2];
      final mX = fData[9 * 3], mY = fData[9 * 3 + 1], mZ = fData[9 * 3 + 2];
      final palmScale = math.sqrt(math.pow(mX - wX, 2) + math.pow(mY - wY, 2) + math.pow(mZ - wZ, 2)) + 1e-6;

      List<List<double>> framePts = [];
      for (int i = 0; i < 21; i++) {
        framePts.add([
          (fData[i * 3] - wX) / palmScale,
          (fData[i * 3 + 1] - wY) / palmScale,
          (fData[i * 3 + 2] - wZ) / palmScale,
        ]);
      }
      norm.add(framePts);
    }

    double totalEnergy = 0.0;
    List<double> speedProfile = [];
    for (int f = 1; f < 24; f++) {
      double frameSpeed = 0.0;
      for (int tip in tips) {
        final dX = norm[f][tip][0] - norm[f - 1][tip][0];
        final dY = norm[f][tip][1] - norm[f - 1][tip][1];
        final dZ = norm[f][tip][2] - norm[f - 1][tip][2];
        final speed = math.sqrt(dX * dX + dY * dY + dZ * dZ);
        if (speed > 0.018) {
          frameSpeed += speed;
          totalEnergy += speed;
        }
      }
      speedProfile.add(frameSpeed / 5.0);
    }

    int maxSpeedIdx = 0;
    double maxSpeedVal = 0.0;
    for (int i = 0; i < speedProfile.length; i++) {
      if (speedProfile[i] > maxSpeedVal) {
        maxSpeedVal = speedProfile[i];
        maxSpeedIdx = i;
      }
    }

    double initialThumbDist = (math.sqrt(math.pow(norm[0][8][0] - norm[0][4][0], 2) + math.pow(norm[0][8][1] - norm[0][4][1], 2)) +
                               math.sqrt(math.pow(norm[0][12][0] - norm[0][4][0], 2) + math.pow(norm[0][12][1] - norm[0][4][1], 2))) / 2.0;
    double finalThumbDist = (math.sqrt(math.pow(norm[23][8][0] - norm[23][4][0], 2) + math.pow(norm[23][8][1] - norm[23][4][1], 2)) +
                             math.sqrt(math.pow(norm[23][12][0] - norm[23][4][0], 2) + math.pow(norm[23][12][1] - norm[23][4][1], 2))) / 2.0;
    double contractionDelta = finalThumbDist - initialThumbDist;

    int horizCount = 0;
    for (int f = 0; f < 24; f++) {
      if (norm[f][9][0].abs() > norm[f][9][1].abs()) horizCount++;
    }
    double isHorizontal = horizCount / 24.0;

    int splitIdx = (maxSpeedIdx + 1).clamp(6, 18);

    List<double> getPhaseGeometry(int start, int end) {
      List<List<double>> medPts = [];
      for (int i = 0; i < 21; i++) {
        List<double> xs = [], ys = [], zs = [];
        for (int f = start; f < end; f++) {
          xs.add(norm[f][i][0]);
          ys.add(norm[f][i][1]);
          zs.add(norm[f][i][2]);
        }
        xs.sort(); ys.sort(); zs.sort();
        medPts.add([xs[xs.length ~/ 2], ys[ys.length ~/ 2], zs[zs.length ~/ 2]]);
      }

      double d3(List<double> a, List<double> b) =>
          math.sqrt(math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2) + math.pow(a[2] - b[2], 2));

      const origin = [0.0, 0.0, 0.0];
      List<double> feats = [];

      for (int i = 0; i < 5; i++) {
        feats.add(d3(medPts[tips[i]], origin) / (d3(medPts[mcps[i]], origin) + 1e-6));
      }
      for (int i = 0; i < 5; i++) {
        feats.add(medPts[tips[i]][0] - medPts[pips[i]][0]);
      }
      for (int i = 0; i < 5; i++) {
        feats.add(medPts[pips[i]][1] - medPts[tips[i]][1]);
      }
      feats.add(d3(medPts[4], medPts[5]));
      feats.add(d3(medPts[4], medPts[17]));
      feats.add(d3(medPts[8], medPts[4]));
      feats.add(d3(medPts[12], medPts[4]));
      feats.add(d3(medPts[16], medPts[4]));
      feats.add(d3(medPts[20], medPts[4]));
      feats.add(d3(medPts[8], medPts[12]));
      feats.add(d3(medPts[12], medPts[16]));
      feats.add(d3(medPts[16], medPts[20]));

      return feats;
    }

    final p1Feats = getPhaseGeometry(0, splitIdx);
    final p2Feats = getPhaseGeometry(splitIdx, 24);

    double morphSum = 0.0;
    List<double> deltaPose = [];
    for (int i = 0; i < p1Feats.length; i++) {
      double diff = p2Feats[i] - p1Feats[i];
      deltaPose.add(diff);
      morphSum += diff * diff;
    }
    double postureMorph = math.sqrt(morphSum);

    List<double> full78 = [];
    full78.addAll(p1Feats);
    full78.addAll(p2Feats);
    full78.addAll(deltaPose);
    full78.addAll([
      totalEnergy,
      maxSpeedVal,
      maxSpeedIdx / 24.0,
      contractionDelta,
      postureMorph,
      isHorizontal,
    ]);

    return Float32List.fromList(full78);
  }

  static double computeKineticEnergy(List<List<double>> window24Frames) {
    const tips = [4, 8, 12, 16, 20];
    double totalEnergy = 0.0;
    for (int f = 1; f < window24Frames.length; f++) {
      for (int tip in tips) {
        final dx = window24Frames[f][tip * 3] - window24Frames[f - 1][tip * 3];
        final dy = window24Frames[f][tip * 3 + 1] - window24Frames[f - 1][tip * 3 + 1];
        final dz = window24Frames[f][tip * 3 + 2] - window24Frames[f - 1][tip * 3 + 2];
        totalEnergy += math.sqrt(dx * dx + dy * dy + dz * dz);
      }
    }
    return totalEnergy;
  }

  static StudentEvaluationResult evaluateWithModel({
    required int targetNumber,
    required List<List<double>> window24Frames,
    required double kineticEnergy,
  }) {
    if (_session == null) {
      throw Exception("ONNX Session not initialized for target $targetNumber");
    }

    final features78 = extract78Features(window24Frames);
    final shape = [1, 78];

    final inputTensor = OrtValueTensor.createTensorWithDataList(features78, shape);
    final runOptions = OrtRunOptions();
    final inputs = {'float_input': inputTensor};
    final outputs = _session!.run(runOptions, inputs);

    final labelTensor = outputs[0]?.value as List;
    int predictedNumber = int.parse(labelTensor[0].toString());

    double targetProbability = 0.0;
    if (outputs.length > 1 && outputs[1]?.value != null) {
      final probSequence = outputs[1]?.value as List;
      if (probSequence.isNotEmpty && probSequence[0] is Map) {
        final probMap = probSequence[0] as Map;
        dynamic rawProb = probMap[targetNumber] ?? probMap[targetNumber.toInt()] ?? probMap[targetNumber.toString()];
        targetProbability = (rawProb ?? 0.0).toDouble();
      }
    }

    inputTensor.release();
    runOptions.release();
    for (var element in outputs) {
      element?.release();
    }

    final p1 = window24Frames[4];
    final p2 = window24Frames[21];

    double dist3D(List<double> f, int p1, int p2) {
      final dx = f[p1 * 3] - f[p2 * 3];
      final dy = f[p1 * 3 + 1] - f[p2 * 3 + 1];
      final dz = f[p1 * 3 + 2] - f[p2 * 3 + 2];
      return math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    final p2Scale = dist3D(p2, 0, 9) + 1e-6;
    double ext(List<double> f, int tip, int mcp) => dist3D(f, 0, tip) / (dist3D(f, 0, mcp) + 1e-6);

    final p1Idx = ext(p1, 8, 5);
    final p1Mid = ext(p1, 12, 9);
    final p1Ring = ext(p1, 16, 13);
    final p1Pnk = ext(p1, 20, 17);

    if (targetNumber >= 31 && targetNumber <= 39) {
      bool isBase3 = p1Idx > 1.20 && p1Mid > 1.20 && p1Ring < 1.15 && p1Pnk < 1.12;
      if (!isBase3) {
        return StudentEvaluationResult(
          targetNumber: targetNumber,
          detectedNumber: null,
          isCorrect: false,
          accuracyScore: 30.0,
          feedback: "Maling simula! Dapat magsimula sa Base '3' (Ring at Pinky nakatupi).",
          kineticEnergy: kineticEnergy,
        );
      }
    } else if (targetNumber == 40) {
      bool isBase4 = p1Idx > 1.20 && p1Mid > 1.20 && p1Ring > 1.20 && p1Pnk > 1.15;
      final contractionDelta = (dist3D(window24Frames[23], 4, 8) - dist3D(window24Frames[0], 4, 8)) / p2Scale;
      if (!isBase4 || contractionDelta >= -0.05) {
        return StudentEvaluationResult(
          targetNumber: targetNumber,
          detectedNumber: null,
          isCorrect: false,
          accuracyScore: 35.0,
          feedback: "Maling galaw para sa 40! Kailangang mag-pulse o mag-contract papuntang 'O' shape.",
          kineticEnergy: kineticEnergy,
        );
      }
    }

    double baseScore = (predictedNumber == targetNumber) ? 70.0 : (targetProbability * 60.0);
    double motionBonus = (kineticEnergy / 0.40).clamp(0.0, 1.0) * 30.0;
    double finalAccuracy = (baseScore + motionBonus).clamp(0.0, 100.0);

    bool isCorrect = (predictedNumber == targetNumber) && (finalAccuracy >= 70.0);

    return StudentEvaluationResult(
      targetNumber: targetNumber,
      detectedNumber: predictedNumber,
      isCorrect: isCorrect,
      accuracyScore: finalAccuracy,
      feedback: isCorrect
          ? "Mahusay! Wastong kumpas at porma para sa Number $targetNumber (${finalAccuracy.toStringAsFixed(1)}%)"
          : "Maling sign ang naisagawa (${finalAccuracy.toStringAsFixed(1)}%). Na-detect: Number $predictedNumber.",
      kineticEnergy: kineticEnergy,
    );
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
// CONTINUOUS PRACTICE WIDGET
// =============================================================================

class NumbersPractice extends StatefulWidget {
  const NumbersPractice({super.key});

  @override
  _NumbersPracticeState createState() => _NumbersPracticeState();
}

class _NumbersPracticeState extends State<NumbersPractice> {
  CameraController? _controller;
  HandLandmarkerPlugin? _landmarkerPlugin;
  StreamSubscription<List<Hand>>? _landmarkSubscription;

  static final Map<String, List<dynamic>> _templateCache = {};

  bool _isInitialized = false;
  bool _isSuccessAchieved = false;
  bool _isProcessingFrame = false;

  final List<List<double>> _frameBuffer = [];
  DateTime _lastSampleTime = DateTime.now();
  int _bufferFrameCount = 0;
  static const int _requiredBufferFrames = 24;

  final List<String> _numbers = List.generate(100, (index) => (index + 1).toString());
  int _currentIdx = 0;
  String get targetNumber => _numbers[_currentIdx];

  List<dynamic>? _template;
  double _currentScore = 0.0;
  double _holdProgress = 0.0;
  DateTime? _startHoldTime;
  String _currentFeedback = "Ipuwesto ang kamay sa tapat ng camera";

  final double successThreshold = 70.0;
  final double holdDurationSeconds = 1.0;
  final int xpReward = 10;

  bool get _isStaticSign {
    final num = int.tryParse(targetNumber) ?? 0;
    return num >= 1 && num <= 10;
  }

  @override
  void initState() {
    super.initState();
    _checkAndLoadOnnxForCurrentTarget();
    _initializePipeline();
  }

  Future<void> _checkAndLoadOnnxForCurrentTarget() async {
    if (!_isStaticSign) {
      final target = int.tryParse(targetNumber) ?? 0;
      await FSLOnnxService.loadModelForTarget(target);
    }
  }

  Future<void> _initializePipeline() async {
    try {
      if (_isStaticSign) {
        await _loadGestureLibrary(targetNumber);
      }

      _landmarkerPlugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.gpu,
      );

      _landmarkSubscription = _landmarkerPlugin!.landmarkStream.listen(_onHandsDetected);

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

  Future<void> _loadGestureLibrary(String number) async {
    if (_templateCache.containsKey(number)) {
      if (mounted) {
        setState(() {
          _template = _templateCache[number];
        });
      }
      return;
    }

    try {
      final ref = FirebaseStorage.instance.ref().child('numbers/$number.json');
      final data = await ref.getData();
      if (data != null) {
        final jsonString = utf8.decode(data);
        final List<dynamic> parsed = jsonDecode(jsonString);
        _templateCache[number] = parsed;

        if (mounted) {
          setState(() {
            _template = parsed;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint("Cloud Storage fetch failed for $number, using asset fallback: $e");
    }

    try {
      String jsonString = await rootBundle.loadString('assets/numbers/$number.json');
      final List<dynamic> parsed = jsonDecode(jsonString);
      _templateCache[number] = parsed;

      if (mounted) {
        setState(() {
          _template = parsed;
        });
      }
    } catch (e) {
      debugPrint("Could not find gesture resource profile for: $number");
    }
  }

  final FrameGate _frameGate = FrameGate();

  void _processCameraFrame(CameraImage image) {
    if (!_isInitialized || _landmarkerPlugin == null || _isSuccessAchieved) return;
    if (_isStaticSign && _template == null) return;
    if (_isProcessingFrame) return;

    try {
      int sensorOrientation = _cameraImageRotation(_controller); // live device rotation
      if (!_frameGate.tryEnter()) return; // one frame in flight (services/frame_gate.dart)
      _landmarkerPlugin!.processFrame(image, sensorOrientation);
    } catch (e) {
      debugPrint("Frame processing error: $e");
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
    _frameGate.done();
    if (!mounted || _isSuccessAchieved || _isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      if (detectedHands.isNotEmpty) {
        double score = 0.0;
        String feedback = "Ipuwesto ang kamay sa tapat ng camera";

        if (_isStaticSign) {
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
                : "I-adjust ang posisyon para sa Sign $targetNumber.";
          }
        } else {
          final hand = detectedHands.first;

          final List<double> flattenedLms = [];
          for (var lm in hand.landmarks) {
            flattenedLms.addAll([1.0 - lm.x, lm.y, lm.z]);
          }

          final now = DateTime.now();
          if (now.difference(_lastSampleTime).inMilliseconds >= 45) {
            _lastSampleTime = now;
            _frameBuffer.add(flattenedLms);
            if (_frameBuffer.length > 24) {
              _frameBuffer.removeAt(0);
            }
            _bufferFrameCount = _frameBuffer.length;

            if (_frameBuffer.length == 24) {
              final currentEnergy = FSLOnnxService.computeKineticEnergy(_frameBuffer);

              if (currentEnergy < 0.26) {
                score = 15.0;
                feedback = "Static hand detected! Gawin ang tamang galaw o transition.";
              } else {
                try {
                  final evalResult = FSLOnnxService.evaluateWithModel(
                    targetNumber: int.tryParse(targetNumber) ?? 0,
                    window24Frames: _frameBuffer,
                    kineticEnergy: currentEnergy,
                  );

                  score = evalResult.accuracyScore;
                  feedback = evalResult.feedback;
                } catch (e) {
                  debugPrint("ONNX Inference Error: $e");
                  feedback = "Model Inference Error.";
                }
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
        if (_isStaticSign) {
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
    setState(() {});

    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    final nextIdx = (_currentIdx + 1) % _numbers.length;
    final nextTargetNum = int.tryParse(_numbers[nextIdx]) ?? 0;

    _frameBuffer.clear();
    _bufferFrameCount = 0;

    if (nextTargetNum > 10) {
      await FSLOnnxService.loadModelForTarget(nextTargetNum);
    }

    setState(() {
      _currentIdx = nextIdx;
      _isSuccessAchieved = false;
      _currentScore = 0.0;
      _currentFeedback = "Ipuwesto ang kamay sa tapat ng camera";
    });

    if (_isStaticSign) {
      await _loadGestureLibrary(targetNumber);
    }
  }

  @override
  void dispose() {
    _landmarkSubscription?.cancel();
    _controller?.stopImageStream();
    _controller?.dispose();
    _landmarkerPlugin?.dispose();
    FSLOnnxService.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String currentNumber = targetNumber;
    bool isPassing = _currentScore >= successThreshold;
    final bool landscape = _isLandscape(context);
    // Landscape: the tutorial pane is ~45% of the screen, camera on the right.
    final double screenWidth = MediaQuery.of(context).size.width * (landscape ? 0.45 : 1.0);
    final theme = Theme.of(context);
    final visuals = _ThemeVisuals.fromTheme(theme);
    final isDark = theme.brightness == Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    // Camera box (with its overlays): inline in portrait, right pane in landscape.
    final Widget cameraPane = Stack(
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
                                    ? _CameraView(controller: _controller!)
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
                                                isPassing 
                                                  ? (_isStaticSign ? "Hold!" : "Correct!")
                                                  : "Position Hand",
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      currentNumber,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 48,
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
                              "assets/pictures/$currentNumber.png",
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

                    if (!landscape)
                      SizedBox(
                        width: screenWidth * 0.60,
                        child: AspectRatio(aspectRatio: 1 / 1, child: cameraPane),
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

                    if (_isSuccessAchieved) ...[
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(visuals.secondaryIcon, color: Colors.green, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                "Success! +$xpReward XP",
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Loading next number...",
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      )
                    ] else if (_isStaticSign && _holdProgress > 0.0) ...[
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
                            child: SmartBlur(
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
                    ] else if (!_isStaticSign && _bufferFrameCount > 0 && _bufferFrameCount < _requiredBufferFrames) ...[
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
                            child: SmartBlur(
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
                        child: SmartBlur(
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
                if (landscape)
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 16, 16),
                      child: cameraPane,
                    ),
                  ),
              ],
            ),
          ),
        ],
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
