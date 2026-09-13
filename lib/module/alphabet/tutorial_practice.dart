import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'recognizer.dart';

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

  bool _isRecordingMotion = false;
  DateTime? _startRecordingTime;
  bool _showMotionResult = false;

  final List<Float32List> _recordingFrames = [];

  static const Duration _dropoutGracePeriod = Duration(milliseconds: 1000);
  DateTime? _lastHandsSeenTime;

  static const List<String> _dynamicLetters = ['J', 'Z'];
  bool get _isDynamicLetter =>
      _dynamicLetters.contains(widget.targetLetter.toUpperCase());

  PhraseRecognizer? _dynamicSignRecognizer;
  bool _dynamicModelReady = false;

  int _targetSequenceLength = 30;
  Uint8List? _cloudModelBytes;
  List<String>? _cloudModelLabels;

  List<dynamic>? _template;
  double _currentScore = 0.0;
  double _holdProgress = 0.0;
  DateTime? _startHoldTime;

  double successThreshold = 70.0;
  final double holdDurationSeconds = 1.0;
  final int xpReward = 25;

  static const double minMotionThreshold = 0.05;
  static const double _referenceHandScale = 0.20;
  // Recording used to stop after a fixed 4.0s wall-clock window regardless
  // of how many real hand-detection frames were actually captured in that
  // time. On slower devices (weak/older GPU running the landmarker's GPU
  // delegate, or a camera-graph hiccup mid-capture) that produced as few as
  // 6-9 real frames, which predictFromRecording then nearest-neighbor
  // upsamples to the model's expected _targetSequenceLength (30) —
  // producing a blocky, aliased trajectory that looks nothing like the
  // ~30-real-frame sequences the model was trained on, even when the user
  // performed the gesture correctly. Gate completion on ACTUAL frame count
  // instead, with a time floor (don't end on a rushed burst) and a time
  // ceiling (safety timeout so a lost hand doesn't hang forever).
  static const double _minCaptureDurationSeconds = 1.0;
  static const double _maxCaptureDurationSeconds = 8.0;

  double _handScaleForFrame(Float32List frame) {
    if (frame.length < 30) return _referenceHandScale;
    final double wristX = frame[0];
    final double wristY = frame[1];
    final double midX = frame[9 * 3];
    final double midY = frame[9 * 3 + 1];
    final double dx = midX - wristX;
    final double dy = midY - wristY;
    final double scale = math.sqrt(dx * dx + dy * dy);
    return scale <= 0.0001 ? _referenceHandScale : scale;
  }

  @override
  void initState() {
    super.initState();
    _initializePipeline();
  }

  Future<void> _initializePipeline() async {
    try {
      if (_isDynamicLetter) {
        await _fetchCloudGestureData();

        debugPrint("[DBG] docId=alphabet_${widget.targetLetter.toLowerCase()} "
            "cloudModelBytes=${_cloudModelBytes?.lengthInBytes} "
            "cloudModelLabels=$_cloudModelLabels "
            "targetSequenceLength=$_targetSequenceLength");

        try {
          _dynamicSignRecognizer = PhraseRecognizer(
            sequenceLength: _targetSequenceLength,
          );

          if (_cloudModelBytes != null) {
            await _dynamicSignRecognizer!.initializeFromBuffer(
              _cloudModelBytes!,
              customLabels: _cloudModelLabels,
            );
            _dynamicModelReady = true;
            debugPrint("[DBG] Model loaded from cloud bytes successfully.");
          } else {
            await _dynamicSignRecognizer!.initialize();
            _dynamicModelReady = true;
            debugPrint("[DBG] Cloud bytes were null — fell back to bundled model.");
          }
        } catch (e) {
          debugPrint("[DBG] J/Z model load failed: $e");
          _dynamicModelReady = false;
        }
      } else {
        await _loadGestureLibrary();
      }

      if (!mounted) return;

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

  Future<void> _fetchCloudGestureData() async {
    try {
      final docId = 'alphabet_${widget.targetLetter.toLowerCase()}';

      final docSnapshot = await FirebaseFirestore.instance
          .collection('gesture_training_data')
          .doc(docId)
          .get();

      if (docSnapshot.exists && docSnapshot.data() != null) {
        final data = docSnapshot.data()!;
        if (data['sequenceLength'] != null) {
          _targetSequenceLength = (data['sequenceLength'] as num).toInt();
        }

        // Fetch threshold directly or map from toleranceBounds. Guard
        // against 0/negative values — same fix applied in
        // phrase_tutorial_practice.dart: a trained threshold should never
        // be <= 0, so treat that as "not actually configured" and keep the
        // 70.0 default rather than accepting a bogus 0.
        final num? rawThreshold = data['accuracyThreshold'] as num?;
        final num? rawDistance = data['toleranceBounds'] != null
            ? data['toleranceBounds']['distance'] as num?
            : null;

        if (rawThreshold != null && rawThreshold > 0) {
          successThreshold = rawThreshold.toDouble();
        } else if (rawDistance != null && rawDistance > 0) {
          successThreshold = rawDistance.toDouble();
        } else {
          debugPrint(
            "Doc $docId found but accuracyThreshold/toleranceBounds.distance "
            "was missing or <= 0 — keeping default successThreshold=$successThreshold%.",
          );
        }

        debugPrint(
          "Firestore gesture data loaded: docId=$docId, sequenceLength=$_targetSequenceLength, threshold=$successThreshold%",
        );
      } else {
        debugPrint("No Firestore doc found for '$docId'. Using defaults.");
      }

      final modelSnapshot = await FirebaseFirestore.instance
          .collection('deployed_models')
          .doc(docId)
          .get();

      if (modelSnapshot.exists && modelSnapshot.data() != null) {
        final modelData = modelSnapshot.data()!;
        final String? base64Model = modelData['modelBase64'] as String?;
        if (base64Model != null && base64Model.isNotEmpty) {
          _cloudModelBytes = base64Decode(base64Model);
        }
        if (modelData['labels'] is List) {
          _cloudModelLabels =
              (modelData['labels'] as List).map((e) => e.toString()).toList();
        }
      }
    } catch (e) {
      debugPrint("Cloud gesture data fetch warning: $e");
    }
  }

  Future<void> _loadGestureLibrary() async {
    try {
      String jsonString = await rootBundle
          .loadString('assets/alphabet/${widget.targetLetter}.json');
      _template = jsonDecode(jsonString);
    } catch (e) {
      debugPrint("Gesture resource profile issue: ${widget.targetLetter}");
    }
  }

  void _processCameraFrame(CameraImage image) {
    if (!_isInitialized ||
        _landmarkerPlugin == null ||
        _isSuccessAchieved ||
        !mounted) return;

    try {
      final int sensorOrientation = _controller!.description.sensorOrientation;
      _landmarkerPlugin!.processFrame(image, sensorOrientation);
    } catch (e) {
      debugPrint("Inference error: $e");
    }
  }

  Float32List _fallbackExtractFeatures(List<Hand> detectedHands) {
    final Float32List features = Float32List(126);
    if (detectedHands.isNotEmpty) {
      final landmarks = detectedHands.first.landmarks;
      for (int i = 0; i < landmarks.length && i < 21; i++) {
        features[i * 3] = landmarks[i].x;
        features[i * 3 + 1] = landmarks[i].y;
        features[i * 3 + 2] = landmarks[i].z;
      }
    }
    return features;
  }

  double _calculateTotalDisplacement(
      List<Float32List> frames, double scaleFactor) {
    if (frames.length < 2) return 0.0;

    final int targetLm = widget.targetLetter.toUpperCase() == 'J' ? 20 : 8;
    final int xIdx = targetLm * 3;
    final int yIdx = targetLm * 3 + 1;

    double totalDistance = 0.0;

    for (int i = 0; i < frames.length - 1; i++) {
      if (frames[i].length <= yIdx || frames[i + 1].length <= yIdx) continue;

      double dx = (frames[i + 1][xIdx] - frames[i][xIdx]) * scaleFactor;
      double dy = (frames[i + 1][yIdx] - frames[i][yIdx]) * scaleFactor;

      totalDistance += math.sqrt(dx * dx + dy * dy);
    }

    return totalDistance;
  }

  List<Float32List> _trimStaticFrames(
      List<Float32List> frames, String letter, double scaleFactor) {
    if (frames.length <= 10) return frames;

    final int targetLm = (letter == 'J') ? 20 : 8;
    final int xIdx = targetLm * 3;
    final int yIdx = targetLm * 3 + 1;

    int start = 0;
    int end = frames.length - 1;

    const double motionEpsilon = 0.0015;

    for (int i = 0; i < frames.length - 1; i++) {
      double dx = (frames[i + 1][xIdx] - frames[i][xIdx]) * scaleFactor;
      double dy = (frames[i + 1][yIdx] - frames[i][yIdx]) * scaleFactor;
      if (math.sqrt(dx * dx + dy * dy) > motionEpsilon) {
        start = math.max(0, i - 2);
        break;
      }
    }

    for (int i = frames.length - 1; i > start; i--) {
      double dx = (frames[i][xIdx] - frames[i - 1][xIdx]) * scaleFactor;
      double dy = (frames[i][yIdx] - frames[i - 1][yIdx]) * scaleFactor;
      if (math.sqrt(dx * dx + dy * dy) > motionEpsilon) {
        end = math.min(frames.length - 1, i + 2);
        break;
      }
    }

    if (end - start >= 8) {
      return frames.sublist(start, end + 1);
    }
    return frames;
  }

bool _isValidGestureShape(
      List<Float32List> frames, String letter, double scaleFactor) {
    if (frames.length < 5) return false;

    final int targetLm = (letter == 'J') ? 20 : 8;
    final int xIdx = targetLm * 3;
    final int yIdx = targetLm * 3 + 1;

    if (letter == 'J') {
      // FIX 1: Dynamically find the true highest (minY) and lowest (maxY) points
      double minY = frames.first[yIdx];
      double maxY = frames.first[yIdx];
      int maxIndex = 0;

      for (int i = 0; i < frames.length; i++) {
        if (frames[i][yIdx] < minY) {
          minY = frames[i][yIdx]; // Highest physical point
        }
        if (frames[i][yIdx] > maxY) {
          maxY = frames[i][yIdx]; // Lowest physical point
          maxIndex = i;
        }
      }

      // Calculate distance using the true top and bottom of the stroke
      double downwardDistance = (maxY - minY) * scaleFactor;
      // Relaxed from 0.04 — was rejecting normal-sized downward strokes,
      // especially from users who draw a smaller/tighter J.
      const double minDownwardDistance = 0.025;
      debugPrint("[DBG][shape][J] downwardDistance=$downwardDistance "
          "threshold=$minDownwardDistance");
      if (downwardDistance < minDownwardDistance) {
        debugPrint("[DBG][shape][J] REJECTED: downward stroke too small");
        return false;
      }

      double maxHookX = 0.0;
      double startX = frames[maxIndex][xIdx];

      for (int i = maxIndex; i < frames.length; i++) {
        double dist = (frames[i][xIdx] - startX).abs() * scaleFactor;
        if (dist > maxHookX) {
          maxHookX = dist;
        }
      }

      // Relaxed from 0.015 — was rejecting a shallow-but-real hook.
      const double minHookX = 0.01;
      if (maxHookX < minHookX) {
        double minX = frames.first[xIdx];
        double maxX = frames.first[xIdx];
        for (final f in frames) {
          if (f[xIdx] < minX) minX = f[xIdx];
          if (f[xIdx] > maxX) maxX = f[xIdx];
        }
        maxHookX = (maxX - minX) * scaleFactor;
      }

      debugPrint(
          "[DBG][shape][J] maxHookX=$maxHookX threshold=$minHookX");
      if (maxHookX < minHookX) {
        debugPrint("[DBG][shape][J] REJECTED: hook too narrow/flat");
        return false;
      }

      // NEW: reject zigzag motion (a Z performed on the J screen was
      // scoring as J because the checks above only ask "was there *some*
      // vertical spread and *some* horizontal excursion" — a Z's zigzag
      // easily produces both. A real J's hook is a single, mostly
      // one-directional curl after the lowest point, not a back-and-forth
      // sweep. Count x-direction reversals in the hook segment the same
      // way _isValidGestureShape('Z', ...) counts them for Z, and reject
      // if it looks like a zigzag instead of a single curl.
      int hookReversals = 0;
      int hookDir = 0;
      double hookLastPeakX = frames[maxIndex][xIdx];
      const double hookReversalThreshold = 0.03;
      for (int i = maxIndex + 1; i < frames.length; i++) {
        double diff = (frames[i][xIdx] - hookLastPeakX) * scaleFactor;
        if (hookDir == 0) {
          if (diff.abs() >= hookReversalThreshold) {
            hookDir = diff > 0 ? 1 : -1;
            hookLastPeakX = frames[i][xIdx];
          }
        } else if (hookDir == 1) {
          if (diff < -hookReversalThreshold) {
            hookReversals++;
            hookDir = -1;
            hookLastPeakX = frames[i][xIdx];
          } else if (frames[i][xIdx] > hookLastPeakX) {
            hookLastPeakX = frames[i][xIdx];
          }
        } else {
          if (diff > hookReversalThreshold) {
            hookReversals++;
            hookDir = 1;
            hookLastPeakX = frames[i][xIdx];
          } else if (frames[i][xIdx] < hookLastPeakX) {
            hookLastPeakX = frames[i][xIdx];
          }
        }
      }
      debugPrint("[DBG][shape][J] hookReversals=$hookReversals (must be <= 1)");
      if (hookReversals > 1) {
        debugPrint(
            "[DBG][shape][J] REJECTED: hook zigzags like a Z, not a single curl");
        return false;
      }

      debugPrint("[DBG][shape][J] PASSED");
      return true;
    }

    if (letter == 'Z') {
      List<double> smoothedX = [];
      for (int i = 0; i < frames.length; i++) {
        double sum = frames[i][xIdx];
        int count = 1;
        if (i > 0) {
          sum += frames[i - 1][xIdx];
          count++;
        }
        if (i < frames.length - 1) {
          sum += frames[i + 1][xIdx];
          count++;
        }
        smoothedX.add(sum / count);
      }

      int xReversals = 0;
      int currentDir = 0;
      double lastPeakX = smoothedX[0];

      // Relaxed from 0.045 back down — that was tuned to kill tracking
      // jitter but ended up eating real, moderately-paced Z strokes too.
      const double reversalThreshold = 0.03;

      for (int i = 1; i < smoothedX.length; i++) {
        double diff = (smoothedX[i] - lastPeakX) * scaleFactor;

        if (currentDir == 0) {
          if (diff.abs() >= reversalThreshold) {
            currentDir = diff > 0 ? 1 : -1;
            lastPeakX = smoothedX[i];
          }
        } else if (currentDir == 1) {
          if (diff < -reversalThreshold) {
            xReversals++;
            currentDir = -1;
            lastPeakX = smoothedX[i];
          } else if (smoothedX[i] > lastPeakX) {
            lastPeakX = smoothedX[i];
          }
        } else if (currentDir == -1) {
          if (diff > reversalThreshold) {
            xReversals++;
            currentDir = 1;
            lastPeakX = smoothedX[i];
          } else if (smoothedX[i] < lastPeakX) {
            lastPeakX = smoothedX[i];
          }
        }
      }
      debugPrint("[DBG][shape][Z] xReversals=$xReversals (need >= 2) "
          "reversalThreshold=$reversalThreshold");
      final bool passed = xReversals >= 2;
      debugPrint(passed
          ? "[DBG][shape][Z] PASSED"
          : "[DBG][shape][Z] REJECTED: not enough direction reversals");
      return passed;
    }
    return true;
  }

  void _onHandsDetected(List<Hand> detectedHands) {
    if (_isSuccessAchieved || !mounted) return;

    if (_isDynamicLetter) {
      if (_showMotionResult) return;

      final bool handsPresent = detectedHands.isNotEmpty;
      final now = DateTime.now();

      if (handsPresent) {
        _lastHandsSeenTime = now;

        if (!_isRecordingMotion) {
          _isRecordingMotion = true;
          _startRecordingTime = now;
          _recordingFrames.clear();
        }

        Float32List frameFeatures;
        if (_dynamicSignRecognizer != null) {
          frameFeatures =
              _dynamicSignRecognizer!.extractRawFrameFeatures(detectedHands);
        } else {
          frameFeatures = _fallbackExtractFeatures(detectedHands);
        }
        _recordingFrames.add(frameFeatures);

        final double elapsedSeconds =
            now.difference(_startRecordingTime!).inMilliseconds / 1000.0;

        // DEBUG: raw hand-detection throughput. If framesSoFar stays far
        // below targetFrames well past 2-3 seconds, the camera/landmarker
        // pipeline itself is the bottleneck (slow delegate, camera-graph
        // churn, etc.) — not the gesture logic further down.
        debugPrint("[DBG][capture] framesSoFar=${_recordingFrames.length} "
            "targetFrames=$_targetSequenceLength "
            "elapsedSeconds=${elapsedSeconds.toStringAsFixed(2)}");

        if (mounted) {
          setState(() {
            _holdProgress =
                (_recordingFrames.length / _targetSequenceLength)
                    .clamp(0.0, 1.0);
          });
        }

        final bool haveEnoughFrames =
            _recordingFrames.length >= _targetSequenceLength &&
                elapsedSeconds >= _minCaptureDurationSeconds;
        final bool timedOut = elapsedSeconds >= _maxCaptureDurationSeconds;

        if ((haveEnoughFrames || timedOut) && _recordingFrames.isNotEmpty) {
          if (timedOut && _recordingFrames.length < _targetSequenceLength) {
            debugPrint(
                "[DBG][capture] TIMED OUT with only ${_recordingFrames.length} "
                "of $_targetSequenceLength frames — hand-detection rate is too "
                "low on this device to hit the target within "
                "${_maxCaptureDurationSeconds}s. The resampled sequence fed "
                "to the model will be a poor match for its training data.");
          }
          _isRecordingMotion = false;
          _showMotionResult = true;

          double finalScore = 0.0;
          String letterUpper = widget.targetLetter.toUpperCase();

          final double gestureScale = _recordingFrames.isNotEmpty
              ? _handScaleForFrame(_recordingFrames.first)
              : _referenceHandScale;
          final double scaleFactor = _referenceHandScale / gestureScale;

          List<Float32List> activeFrames =
              _trimStaticFrames(_recordingFrames, letterUpper, scaleFactor);
          double displacement =
              _calculateTotalDisplacement(activeFrames, scaleFactor);

          debugPrint(
              "[DBG][motion] frames=${_recordingFrames.length} trimmed=${activeFrames.length} "
              "gestureScale=$gestureScale scaleFactor=$scaleFactor "
              "displacement=$displacement threshold=$minMotionThreshold");

          if (displacement < minMotionThreshold) {
            debugPrint("[DBG][motion] REJECTED: displacement < threshold");
            finalScore = 0.0;
          } else {
            debugPrint("[DBG][motion] PASSED");
            bool validShape =
                _isValidGestureShape(activeFrames, letterUpper, scaleFactor);

            if (!validShape) {
              // _isValidGestureShape already printed exactly which measured
              // value failed and against what threshold (see [DBG][shape]).
              finalScore = 0.0;
            } else if (_dynamicSignRecognizer != null && _dynamicModelReady) {
              try {
                final result =
                    _dynamicSignRecognizer!.predictFromRecording(activeFrames);

                final Map<String, double> allScores = _dynamicSignRecognizer!
                    .rawScoresForRecording(activeFrames);
                debugPrint("[DBG][confidence] rawScores=$allScores");
                debugPrint("[DBG][confidence] predicted label='${result?.label}' "
                    "confidence=${result?.confidence}");

                final String expectedPositiveLabel = 'ALPHABET_$letterUpper';
                debugPrint(
                    "[DBG][confidence] comparing predicted='${result?.label.toUpperCase()}' "
                    "vs expected='$expectedPositiveLabel'");

                if (result != null &&
                    result.label.toUpperCase() == expectedPositiveLabel) {
                  double rawConfidence = result.confidence;
                  double normalizedConfidence = rawConfidence > 1.0
                      ? rawConfidence
                      : rawConfidence * 100.0;

                  if (normalizedConfidence >= 30.0) {
                    finalScore =
                        (normalizedConfidence * 1.15).clamp(75.0, 98.0);
                  } else {
                    finalScore = normalizedConfidence;
                  }
                  debugPrint(
                      "[DBG][confidence] ACCEPTED: finalScore=$finalScore");
                } else {
                  debugPrint(
                      "[DBG][confidence] REJECTED: predicted label != expected");
                  finalScore = 0.0;
                }
              } catch (e) {
                debugPrint("[DBG][confidence] Prediction error for $letterUpper: $e");
                finalScore = 0.0;
              }
            } else {
              debugPrint(
                  "[DBG][confidence] REJECTED: recognizer null=${_dynamicSignRecognizer == null} "
                  "modelReady=$_dynamicModelReady");
              finalScore = 0.0;
            }
          }

          _recordingFrames.clear();

          if (mounted) {
            setState(() {
              _currentScore = finalScore;
              _holdProgress = 0.0;
            });
          }

          if (_currentScore >= successThreshold) {
            _onSuccess();
          } else {
            Future.delayed(const Duration(milliseconds: 1800), () {
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
        final lastSeen = _lastHandsSeenTime;
        final bool withinGrace = lastSeen != null &&
            now.difference(lastSeen) <= _dropoutGracePeriod;

        debugPrint("[DBG][dropout] hand lost — "
            "elapsedSinceLastSeen=${lastSeen != null ? now.difference(lastSeen).inMilliseconds : -1}ms "
            "gracePeriod=${_dropoutGracePeriod.inMilliseconds}ms withinGrace=$withinGrace");

        if (!withinGrace) {
          debugPrint("[DBG][dropout] grace period exceeded — recording cancelled");
          if (mounted) {
            setState(() {
              _isRecordingMotion = false;
              _startRecordingTime = null;
              _holdProgress = 0.0;
            });
          }
          _recordingFrames.clear();
        }
      }
      return;
    }

    if (_template == null) return;

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
    if (liveLms.isEmpty || template.length < 21 || liveLms.length < 21) {
      return 0.0;
    }

    final String letter = widget.targetLetter.toUpperCase();

    if (['G', 'H', 'K', 'P', 'Q'].contains(letter)) {
      final Landmark wrist = liveLms[0];
      final Landmark mBase = liveLms[9];
      final Landmark indexTip = liveLms[8];

      double dist = math.sqrt(math.pow(wrist.x - mBase.x, 2) +
          math.pow(wrist.y - mBase.y, 2));

      double distIndex = math.sqrt(math.pow(wrist.x - indexTip.x, 2) +
          math.pow(wrist.y - indexTip.y, 2));
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

          double pointDiff = math.sqrt(math.pow(rx - tx, 2) + math.pow(ry - ty, 2));

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

      double dist = math.sqrt(math.pow(wrist.x - mBase.x, 2) +
          math.pow(wrist.y - mBase.y, 2) +
          math.pow(wrist.z - mBase.z, 2));

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

          double pointDiff = math.sqrt(math.pow(rx - tx, 2) +
              math.pow(ry - ty, 2) +
              math.pow(dz - tz, 2));
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
        final difference =
            now.difference(_startHoldTime!).inMilliseconds / 1000.0;
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
        final docRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);

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
                border: Border.all(
                    color: theme.primaryColor.withOpacity(0.6), width: 2),
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
                        child: Icon(visuals.mainBadgeIcon,
                            color: theme.primaryColor, size: 64),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Icon(visuals.secondaryIcon,
                            color: theme.primaryColor.withOpacity(0.7),
                            size: 22),
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
                        fontWeight: FontWeight.w500),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.green.withOpacity(0.4), width: 2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(visuals.secondaryIcon,
                                color: Colors.green, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              "+$xpReward XP Earned!",
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.green),
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      minimumSize: const Size(double.infinity, 54),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context);
                    },
                    child: const Text("Continue",
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18)),
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
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller?.stopImageStream().catchError((e) {
        debugPrint("Error stopping image stream: $e");
      });
    }
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
              letterSpacing: -0.96),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -20,
            right: -20,
            child: Opacity(
              opacity: 0.12,
              child: Transform.rotate(
                angle: -0.2,
                child: Icon(visuals.ambientIcon1,
                    size: 220, color: theme.primaryColor),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: -30,
            child: Opacity(
              opacity: 0.10,
              child: Transform.rotate(
                angle: 0.3,
                child: Icon(visuals.ambientIcon2,
                    size: 240, color: theme.colorScheme.secondary),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20.0, vertical: 10.0),
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
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                color: isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade300,
                                child: const Icon(Icons.broken_image,
                                    color: Colors.grey, size: 50),
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
                                  color: isPassing
                                      ? Colors.greenAccent
                                      : theme.dividerColor.withOpacity(0.6),
                                ),
                                boxShadow: [
                                  if (isPassing)
                                    BoxShadow(
                                      color:
                                          Colors.greenAccent.withOpacity(0.6),
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
                                          width: _controller!
                                                  .value.previewSize?.height ??
                                              1,
                                          height: _controller!
                                                  .value.previewSize?.width ??
                                              1,
                                          child: CameraPreview(_controller!),
                                        ),
                                      )
                                    : Center(
                                        child: CircularProgressIndicator(
                                            color: theme.primaryColor),
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
                                      color: isPassing
                                          ? Colors.greenAccent.withOpacity(0.9)
                                          : Colors.white54,
                                      width: isPassing ? 4.0 : 3.0,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                            sigmaX: 3, sigmaY: 3),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          color: Colors.black45,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              if (isPassing) ...[
                                                Icon(visuals.mainBadgeIcon,
                                                    color: Colors.greenAccent,
                                                    size: 12),
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                isPassing
                                                    ? "Hold!"
                                                    : (_isDynamicLetter
                                                        ? "Draw Gesture"
                                                        : "Position Hand"),
                                                style: TextStyle(
                                                  color: isPassing
                                                      ? Colors.greenAccent
                                                      : Colors.white,
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
                              Icon(visuals.secondaryIcon,
                                  color: Colors.green, size: 20),
                              const SizedBox(width: 6),
                              Text(
                                _isDynamicLetter
                                    ? "Recording motion..."
                                    : "Hold steady...",
                                style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18),
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
                                    color: theme.colorScheme.surface
                                        .withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: theme.colorScheme.surface
                                            .withOpacity(0.5),
                                        width: 1)),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: _holdProgress,
                                    child: Container(
                                      decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                              colors: [
                                                Colors.greenAccent,
                                                Colors.green
                                              ]),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                                color: Colors.greenAccent
                                                    .withOpacity(0.5),
                                                blurRadius: 10)
                                          ]),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: isPassing
                                  ? Colors.green.withOpacity(0.2)
                                  : theme.cardColor.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                  color: isPassing
                                      ? Colors.greenAccent.withOpacity(0.6)
                                      : theme.colorScheme.surface
                                          .withOpacity(0.8),
                                  width: 1.5),
                            ),
                            child: Text(
                              "Score: ${_currentScore.toStringAsFixed(1)}%",
                              style: TextStyle(
                                color: isPassing
                                    ? (isDark
                                        ? Colors.greenAccent
                                        : Colors.green.shade700)
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.7),
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