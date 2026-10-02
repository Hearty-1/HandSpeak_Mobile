import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:onnxruntime/onnxruntime.dart';

import 'pose_provider.dart';

typedef _Pts = List<List<double>>; // [[x, y], ...] for one hand (21 points)

enum PhraseVerdict {
  tooShort,
  rejectedUnknown,
  uncertain,
  accepted,
  inferenceError,
}

class PhraseEvaluation {
  final PhraseVerdict verdict;
  final int top1Index;
  final int top2Index;
  final String top1Label;
  final String top2Label;
  final double top1Prob;
  final double margin;
  final List<double> probs;
  final String? message;

  const PhraseEvaluation({
    required this.verdict,
    this.top1Index = -1,
    this.top2Index = -1,
    this.top1Label = '',
    this.top2Label = '',
    this.top1Prob = 0.0,
    this.margin = 0.0,
    this.probs = const [],
    this.message,
  });

  double probPercent(int index) =>
      (index >= 0 && index < probs.length) ? probs[index] * 100.0 : 0.0;
}

class PhraseRecognizer {
  static const int sequenceLength = 32;
  static const int baseFeatures = 96;   // Raw extracted features
  static const int modelFeatures = 96;  // Standard sequence (eksaktong 96 para sa server)
  static const int numClasses = 11;
  static const int maskedClassIndex = 8;
  static const int unknownClassIndex = 10;
  static const int minRecordedFrames = 14;

  static const double defaultMinConfidence = 55.0; // percent
  static const double minMargin = 12.0; // percent

  static const int _poseFeatures = 12;
  static const int _handFeatures = 42;
  static const int _numLandmarks = 21;

  static const List<String> _fallbackLabels = [
    'MAGANDANG UMAGA',
    'MAGANDANG HAPON',
    'MAGANDANG GABI',
    'KUMUSTA',
    'KUMUSTA KA',
    'MABUTI',
    'IKINAGAGALAK KONG MAKILALA KA',
    'SALAMAT',
    '[HINDI AKTIBO] WALANG ANUMAN',
    'MAGKITA TAYO BUKAS',
    'HINDI KILALANG SENYAS',
  ];

  /// Flattened model input length: 32 frames x 96 features = 3072.
  static const int flatInputLength = sequenceLength * modelFeatures;

  /// Width / height of the frames the model was trained on. The training
  /// script (live_stable_engine.py) uses a default cv2 webcam = 640x480.
  /// MediaPipe returns x/y normalised by width/height separately, so the
  /// palm/shoulder-normalised features depend on this aspect ratio.
  static const double trainingAspect = 640.0 / 480.0;

  /// English (training script) + Filipino (labels.json) names per class.
  /// Compared with [compactKey], so spacing/punctuation/case don't matter.
  static const Map<int, List<String>> _aliases = {
    0: ['good morning', 'magandang umaga'],
    1: ['good afternoon', 'magandang hapon'],
    2: ['good evening', 'magandang gabi'],
    3: ['hello', 'kumusta', 'kamusta'],
    4: ['how are you', 'kumusta ka', 'kamusta ka'],
    5: ["i'm fine", 'im fine', 'i am fine', 'mabuti'],
    6: ['nice to meet you', 'ikinagagalak kong makilala ka'],
    7: ['thank you', 'salamat'],
    8: ["you're welcome", 'youre welcome', 'walang anuman'],
    9: ['see you tomorrow', 'magkita tayo bukas'],
    10: ['invalid gesture', 'invalid_gesture', 'hindi kilalang senyas'],
  };

  static bool _envReady = false;

  OrtSession? _session;
  String _inputName = 'input_sequence';
  List<String> _labels = List.of(_fallbackLabels);

  /// The model was trained on the RAW (un-flipped) webcam frame: the Python
  /// engine runs Holistic on `frame` and only flips the copy it displays.
  /// The Android front-camera image stream is also un-flipped, so this must
  /// stay false or every x feature gets its sign inverted.
  bool mirrorX = false;

  final List<List<double>?> _lastWrist = [null, null];

  bool get isReady => _session != null;

  /// Lowercase, alphanumerics only ("I'm Fine" / "IM_FINE" / "imFine" -> "imfine").
  static String compactKey(String s) => s
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Class index for a phrase title / server label in English or Filipino,
  /// or -1 when it isn't one of the model's classes.
  static int classIndexFor(String phrase) {
    final key = compactKey(phrase);
    if (key.isEmpty) return -1;
    for (final e in _aliases.entries) {
      if (e.value.any((a) => compactKey(a) == key)) return e.key;
    }
    return -1;
  }

  /// Multiplier for x so that features computed on an upright frame of
  /// [width] x [height] match the aspect ratio used during training.
  static double aspectXScale(int width, int height) {
    if (width <= 0 || height <= 0) return 1.0;
    return (width / height) / trainingAspect;
  }

  static String normalizeKey(String key) {
    final noTag = key.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    final camelSplit = noTag.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (m) => '${m[1]}_${m[2]}',
    );
    return camelSplit
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String labelFor(int index) {
    if (index < 0 || index >= _labels.length) return '';
    return _labels[index].replaceAll(RegExp(r'\[[^\]]*\]\s*'), '').trim();
  }

  int indexOfPhrase(String phrase) {
    final byAlias = classIndexFor(phrase);
    if (byAlias != -1) return byAlias;
    final target = compactKey(phrase);
    for (int i = 0; i < _labels.length; i++) {
      if (compactKey(_labels[i]) == target) return i;
    }
    return -1;
  }

  bool isInactiveClass(int index) =>
      index == maskedClassIndex || index == unknownClassIndex;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> initialize({
    String modelAssetPath = 'assets/phrases/fsl_model.onnx',
    String labelsAssetPath = 'assets/phrases/labels.json',
  }) async {
    if (_session != null) return;

    await _loadLabels(labelsAssetPath);

    if (!_envReady) {
      OrtEnv.instance.init();
      _envReady = true;
    }

    final ByteData raw;
    try {
      raw = await rootBundle.load(modelAssetPath);
    } catch (e) {
      throw Exception("ONNX model asset '$modelAssetPath' not found.");
    }

    final options = OrtSessionOptions()..setIntraOpNumThreads(2);
    final session = OrtSession.fromBuffer(
      raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
      options,
    );
    _session = session;
    _inputName = session.inputNames.first;

    try {
      _runLogits(Float32List(sequenceLength * modelFeatures));
    } catch (e) {
      _session?.release();
      _session = null;
      throw Exception('ONNX warm-up failed.');
    }
  }

  Future<void> _loadLabels(String path) async {
    List<String>? loaded;
    try {
      final decoded = json.decode(await rootBundle.loadString(path));
      if (decoded is Map) {
        final entries = decoded.entries.toList();
        final allIntKeys = entries.every((e) => int.tryParse(e.key.toString()) != null);
        if (allIntKeys) {
          entries.sort((a, b) => int.parse(a.key.toString()).compareTo(int.parse(b.key.toString())));
          loaded = entries.map((e) => e.value.toString()).toList();
        } else {
          entries.sort((a, b) => (a.value as num).compareTo(b.value as num));
          loaded = entries.map((e) => e.key.toString()).toList();
        }
      } else if (decoded is List) {
        loaded = decoded.map((e) => e.toString()).toList();
      }
    } catch (e) {
      debugPrint('labels.json load failed ($e). Using built-in labels.');
    }

    if (loaded == null || loaded.length != numClasses) {
      loaded = List.of(_fallbackLabels);
    }
    _labels = loaded;
  }

  // ---------------------------------------------------------------------------
  // Feature extraction (per camera frame)
  // ---------------------------------------------------------------------------

  /// Clockwise rotation that maps hand_landmarker output to the upright frame.
  /// The plugin returns landmarks in the RAW sensor frame (its example
  /// painter rotates the canvas by sensorOrientation), while ML Kit pose is
  /// already upright -- so set this to the camera's sensorOrientation.
  /// It is double-checked at runtime against the pose wrists.
  int handRotation = 0;

  /// In every training template the hands are absent while the arms hang at
  /// rest (wrist ~2.3 shoulder-widths below the shoulders); Holistic only
  /// picked them up once raised. Hands lower than this are ignored.
  static const double restHandY = 2.0;

  final Map<int, double> _rotationError = {0: 0, 90: 0, 180: 0, 270: 0};
  int _rotationSamples = 0;
  int? _detectedRotation;

  /// Whether the last [extractFrameFeatures] call had a pose / a raised hand.
  bool lastFrameHadPose = false;
  bool lastFrameHadHands = false;

  int get effectiveHandRotation => _detectedRotation ?? handRotation;

  void resetTracking() {
    _lastWrist[0] = null;
    _lastWrist[1] = null;
  }

  /// Rotates a normalised point by [degrees] clockwise (image rotation).
  static List<double> rotateNormalized(double u, double v, int degrees) {
    switch (((degrees % 360) + 360) % 360) {
      case 90:
        return [1.0 - v, u];
      case 180:
        return [1.0 - u, 1.0 - v];
      case 270:
        return [v, 1.0 - u];
      default:
        return [u, v];
    }
  }

  /// Mirrors `extract_palm_relative` in live_stable_engine.py:
  /// [pose 12 | left hand 42 | right hand 42], where "left"/"right" are the
  /// signer's own hands (MediaPipe Holistic semantics).
  ///
  /// [xScale] corrects for the camera aspect ratio (see [aspectXScale]).
  Float32List extractFrameFeatures(
    List<Hand> hands, {
    PoseSnapshot? pose,
    double xScale = 1.0,
  }) {
    final out = Float32List(baseFeatures);

    // Pose points in the same (aspect-corrected) space as the hands.
    final _Pts? posePts = (pose != null && pose.points.length == 6)
        ? [for (final p in pose.points) [p[0] * xScale, p[1]]]
        : null;
    lastFrameHadPose = posePts != null;

    if (posePts != null && hands.isNotEmpty) {
      _calibrateRotation(hands, posePts, xScale);
    }

    // --- pose (12) ---
    double midX = 0, midY = 0, shDist = 1;
    if (posePts != null) {
      final ls = posePts[0];
      final rs = posePts[1];
      midX = (ls[0] + rs[0]) / 2.0;
      midY = (ls[1] + rs[1]) / 2.0;
      final dx = ls[0] - rs[0];
      final dy = ls[1] - rs[1];
      shDist = math.sqrt(dx * dx + dy * dy) + 1e-6;
      for (int i = 0; i < 6; i++) {
        out[i * 2] = (posePts[i][0] - midX) / shDist;
        out[i * 2 + 1] = (posePts[i][1] - midY) / shDist;
      }
    }

    // --- hands (42 + 42) ---
    final pts = <_Pts>[];
    for (final h in hands) {
      final p = _toPoints(h, xScale, effectiveHandRotation);
      if (p == null) continue;
      if (posePts != null && (p[0][1] - midY) / shDist > restHandY) continue;
      pts.add(p);
    }
    lastFrameHadHands = pts.isNotEmpty;
    if (pts.isNotEmpty) {
      final slots = _assignSlots(pts, posePts, xScale);
      for (int slot = 0; slot < 2; slot++) {
        final p = slots[slot];
        if (p == null) continue;
        final norm = _normalizeHand(p);
        final offset = _poseFeatures + slot * _handFeatures;
        for (int i = 0; i < _handFeatures; i++) {
          out[offset + i] = norm[i];
        }
      }
    }
    return out;
  }

  /// Accumulates, for each candidate rotation, how far the hand wrists land
  /// from the nearest pose wrist; after a few frames the best one wins.
  void _calibrateRotation(List<Hand> hands, _Pts posePts, double xScale) {
    if (_detectedRotation != null) return;
    for (final r in _rotationError.keys.toList()) {
      double err = 0;
      for (final h in hands) {
        if (h.landmarks.isEmpty) continue;
        final up = rotateNormalized(
            h.landmarks[0].x.toDouble(), h.landmarks[0].y.toDouble(), r);
        final w = [(mirrorX ? 1.0 - up[0] : up[0]) * xScale, up[1]];
        err += math.min(_dist(w, posePts[4]), _dist(w, posePts[5]));
      }
      _rotationError[r] = _rotationError[r]! + err;
    }
    if (++_rotationSamples < 10) return;

    final best = _rotationError.entries
        .reduce((a, b) => a.value <= b.value ? a : b);
    final configured = _rotationError[handRotation] ?? double.infinity;
    _detectedRotation =
        best.value < 0.6 * configured ? best.key : handRotation;
    debugPrint('PhraseRecognizer: hand rotation = $_detectedRotation '
        '(configured $handRotation, errors $_rotationError)');
  }

  _Pts? _toPoints(Hand hand, double xScale, int rotation) {
    final lms = hand.landmarks;
    if (lms.length != _numLandmarks) return null;
    return List<List<double>>.generate(_numLandmarks, (i) {
      final up =
          rotateNormalized(lms[i].x.toDouble(), lms[i].y.toDouble(), rotation);
      return [(mirrorX ? 1.0 - up[0] : up[0]) * xScale, up[1]];
    });
  }

  List<double> _normalizeHand(_Pts pts) {
    final wrist = pts[0];
    final mid = pts[9];
    final pdx = wrist[0] - mid[0];
    final pdy = wrist[1] - mid[1];
    final palm = math.sqrt(pdx * pdx + pdy * pdy) + 1e-6;

    final out = List<double>.filled(_handFeatures, 0.0);
    for (int i = 0; i < _numLandmarks; i++) {
      out[i * 2] = (pts[i][0] - wrist[0]) / palm;
      out[i * 2 + 1] = (pts[i][1] - wrist[1]) / palm;
    }
    return out;
  }

  double _dist(List<double> a, List<double> b) {
    final dx = a[0] - b[0];
    final dy = a[1] - b[1];
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Slot 0 = signer's LEFT hand, slot 1 = signer's RIGHT hand.
  ///
  /// Holistic assigns hands from the pose wrists (landmarks 15/16), so the
  /// pose is used first. Without a pose we fall back to temporal tracking,
  /// then to image position: in an un-mirrored frame the signer's left hand
  /// is on the right side of the image (larger x).
  List<_Pts?> _assignSlots(List<_Pts> hands, _Pts? posePts, double xScale) {
    final result = List<_Pts?>.filled(2, null);
    final prev0 = _lastWrist[0];
    final prev1 = _lastWrist[1];
    final List<double>? poseLw = posePts?[4];
    final List<double>? poseRw = posePts?[5];
    final double centerX = 0.5 * xScale;

    bool isLeftByPosition(List<double> wrist) =>
        mirrorX ? wrist[0] < centerX : wrist[0] > centerX;

    if (hands.length == 1) {
      final wrist = hands[0][0];
      int slot;
      if (poseLw != null && poseRw != null) {
        slot = _dist(wrist, poseLw) <= _dist(wrist, poseRw) ? 0 : 1;
      } else if (prev0 != null && prev1 != null) {
        slot = _dist(wrist, prev1) < _dist(wrist, prev0) ? 1 : 0;
      } else if (prev0 != null) {
        slot = 0;
      } else if (prev1 != null) {
        slot = 1;
      } else {
        slot = isLeftByPosition(wrist) ? 0 : 1;
      }
      result[slot] = hands[0];
      _lastWrist[slot] = wrist;
      return result;
    }

    final a = hands[0];
    final b = hands[1];
    final aw = a[0];
    final bw = b[0];

    // swap == true  ->  b is the left hand (slot 0)
    bool swap;
    if (poseLw != null && poseRw != null) {
      final straight = _dist(aw, poseLw) + _dist(bw, poseRw);
      final swapped = _dist(bw, poseLw) + _dist(aw, poseRw);
      swap = swapped < straight;
    } else if (prev0 != null && prev1 != null) {
      final straight = _dist(aw, prev0) + _dist(bw, prev1);
      final swapped = _dist(bw, prev0) + _dist(aw, prev1);
      swap = swapped < straight;
    } else {
      // Left hand is the one further toward the signer's left side.
      swap = mirrorX ? bw[0] < aw[0] : bw[0] > aw[0];
    }

    result[0] = swap ? b : a;
    result[1] = swap ? a : b;
    _lastWrist[0] = result[0]![0];
    _lastWrist[1] = result[1]![0];
    return result;
  }

  // ---------------------------------------------------------------------------
  // Feature Preprocessing (Standard 96 Features)
  // ---------------------------------------------------------------------------

  Float32List prepareStandardSequence(List<Float32List> raw, int targetFrames) {
    final orig = raw.length;
    final out = Float32List(targetFrames * modelFeatures);
    
    // Linear Interpolation lamang - walang velocity o weights
    for (int i = 0; i < targetFrames; i++) {
      final double t = orig > 1 ? i / (targetFrames - 1) : 0.0;
      final double pos = t * (orig - 1);
      final int lo = pos.floor();
      final int hi = pos.ceil();
      final double w = pos - lo;
      final a = raw[lo];
      final b = raw[hi];
      
      final baseIndex = i * modelFeatures;
      for (int k = 0; k < modelFeatures; k++) {
        out[baseIndex + k] = lo == hi ? a[k] : a[k] * (1.0 - w) + b[k] * w;
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Training templates (diagnostics)
  // ---------------------------------------------------------------------------

  static Map<int, Float32List>? _templates;
  static Map<int, double> _templateThresholds = {};

  /// Loads the per-class mean training sequences (greetings_templates.npy,
  /// exported to JSON). Safe to call repeatedly; failures are non-fatal.
  static Future<void> loadTemplates({
    String path = 'assets/phrases/greetings_templates.json',
  }) async {
    if (_templates != null) return;
    try {
      final data = json.decode(await rootBundle.loadString(path)) as Map;
      _templates = {
        for (final e in (data['templates'] as Map).entries)
          int.parse(e.key.toString()): Float32List.fromList(
              (e.value as List).map((v) => (v as num).toDouble()).toList()),
      };
      _templateThresholds = {
        for (final e in (data['thresholds'] as Map).entries)
          int.parse(e.key.toString()): (e.value as num).toDouble(),
      };
    } catch (e) {
      debugPrint('Phrase templates unavailable: $e');
    }
  }

  /// Distance of a flattened 32x96 clip to a class template, split into
  /// [total, pose, left hand, right hand]; null if templates aren't loaded.
  /// Comparing the parts shows which features drift from training.
  static List<double>? templateDistance(Float32List flat, int classIndex) {
    final t = _templates?[classIndex];
    if (t == null || t.length != flat.length) return null;
    final parts = [0.0, 0.0, 0.0];
    for (int i = 0; i < flat.length; i++) {
      final f = i % modelFeatures;
      final part = f < _poseFeatures ? 0 : (f < _poseFeatures + _handFeatures ? 1 : 2);
      final d = flat[i] - t[i];
      parts[part] += d * d;
    }
    final total = math.sqrt(parts[0] + parts[1] + parts[2]);
    return [total, for (final p in parts) math.sqrt(p)];
  }

  /// One-line report: distance to the target template and the nearest one.
  static String templateReport(Float32List flat, int targetIndex) {
    if (_templates == null) return 'templates not loaded';
    int nearest = -1;
    double best = double.infinity;
    for (final k in _templates!.keys) {
      final d = templateDistance(flat, k)![0];
      if (d < best) {
        best = d;
        nearest = k;
      }
    }
    String fmt(int k) {
      final d = templateDistance(flat, k);
      if (d == null) return '$k: n/a';
      final th = _templateThresholds[k];
      return '$k: ${d[0].toStringAsFixed(1)}'
          '${th != null ? '/${th.toStringAsFixed(1)}' : ''} '
          '(pose ${d[1].toStringAsFixed(1)}, L ${d[2].toStringAsFixed(1)}, '
          'R ${d[3].toStringAsFixed(1)})';
    }

    return 'target ${targetIndex >= 0 ? fmt(targetIndex) : 'n/a'} | '
        'nearest ${fmt(nearest)}';
  }

  /// Pose is present in every training frame, so a frame where ML Kit had no
  /// result must not become zeros. Fills those frames' 12 pose values by
  /// linear interpolation between the nearest frames that had a pose.
  /// Returns false when no frame had a pose at all.
  static bool fillMissingPose(List<Float32List> frames, List<bool> hasPose) {
    final valid = <int>[
      for (int i = 0; i < frames.length; i++)
        if (i < hasPose.length && hasPose[i]) i
    ];
    if (valid.isEmpty) return false;

    int next = 0; // index into [valid] of the first valid frame >= i
    for (int i = 0; i < frames.length; i++) {
      while (next < valid.length && valid[next] < i) {
        next++;
      }
      if (next < valid.length && valid[next] == i) continue;

      final int? lo = next > 0 ? valid[next - 1] : null;
      final int? hi = next < valid.length ? valid[next] : null;
      for (int k = 0; k < _poseFeatures; k++) {
        if (lo != null && hi != null) {
          final w = (i - lo) / (hi - lo);
          frames[i][k] = frames[lo][k] * (1 - w) + frames[hi][k] * w;
        } else {
          frames[i][k] = frames[lo ?? hi!][k];
        }
      }
    }
    return true;
  }

  /// Crops a recording so its timing resembles the training clips: in the
  /// templates the wrists rise above the rest line around frame 9 of 32 and
  /// come back down around frame 30, i.e. ~40% lead-in before the hands
  /// come up and ~8% after they drop.
  /// Returns [start, end) or null when no raised hand was seen.
  static List<int>? trainingWindow(List<bool> hasHands) {
    final first = hasHands.indexOf(true);
    if (first == -1) return null;
    final last = hasHands.lastIndexOf(true);
    final active = last - first + 1;
    final start = math.max(0, first - (active * 0.40).round());
    final end = math.min(hasHands.length, last + 1 + (active * 0.08).round());
    return [start, end];
  }

  // ---------------------------------------------------------------------------
  // Evaluation (whole recorded gesture)
  // ---------------------------------------------------------------------------

  PhraseEvaluation evaluate(
    List<Float32List> frames, {
    double minConfidence = defaultMinConfidence,
  }) {
    if (_session == null) {
      return const PhraseEvaluation(
        verdict: PhraseVerdict.inferenceError,
        message: 'Model not loaded',
      );
    }
    if (frames.length < minRecordedFrames) {
      return PhraseEvaluation(
        verdict: PhraseVerdict.tooShort,
        message: 'Too fast: ${frames.length} frames (need $minRecordedFrames+)',
      );
    }

    try {
      final flatFeatures = prepareStandardSequence(frames, sequenceLength);
      final logits = _runLogits(flatFeatures);
      logits[maskedClassIndex] = -1e9;
      return classifyProbabilities(_softmax(logits),
          minConfidence: minConfidence);
    } catch (e) {
      return PhraseEvaluation(
        verdict: PhraseVerdict.inferenceError,
        message: 'Inference failed: $e',
      );
    }
  }

  /// Same decision rules as live_stable_engine.py, applied to an 11-class
  /// probability vector (local ONNX or Cloud Run; unknown classes = 0).
  /// softmax with logit[8] = -1e9 equals p[i] / (1 - p[8]), so class 8 is
  /// removed and the rest rescaled -- exact even for a partial top-k.
  PhraseEvaluation classifyProbabilities(
    List<double> rawProbs, {
    double minConfidence = defaultMinConfidence,
  }) {
    final probs = List<double>.generate(
      numClasses,
      (i) => i < rawProbs.length ? math.max(0.0, rawProbs[i]) : 0.0,
    );
    final double denom = 1.0 - math.min(0.999, probs[maskedClassIndex]);
    probs[maskedClassIndex] = 0.0;
    for (int i = 0; i < numClasses; i++) {
      probs[i] = probs[i] / denom;
    }

    final sorted = List<int>.generate(numClasses, (i) => i)
      ..sort((a, b) => probs[b].compareTo(probs[a]));
    final top1 = sorted[0];
    final top2 = sorted[1];
    final top1Prob = probs[top1] * 100.0;
    final margin = (probs[top1] - probs[top2]) * 100.0;

    PhraseVerdict verdict;
    if (top1 == unknownClassIndex) {
      verdict = PhraseVerdict.rejectedUnknown;
    } else if (top1Prob < minConfidence || margin < minMargin) {
      verdict = PhraseVerdict.uncertain;
    } else {
      verdict = PhraseVerdict.accepted;
    }

    return PhraseEvaluation(
      verdict: verdict,
      top1Index: top1,
      top2Index: top2,
      top1Label: labelFor(top1),
      top2Label: labelFor(top2),
      top1Prob: top1Prob,
      margin: margin,
      probs: probs,
    );
  }

  List<double> _runLogits(Float32List flat) {
    final session = _session;
    if (session == null) throw StateError('ONNX session is not initialised');

    OrtValueTensor? input;
    OrtRunOptions? runOptions;
    List<OrtValue?>? outputs;
    try {
      input = OrtValueTensor.createTensorWithDataList(
        flat,
        [1, sequenceLength, modelFeatures],
      );
      runOptions = OrtRunOptions();
      outputs = session.run(runOptions, {_inputName: input});

      final first = (outputs.isEmpty) ? null : outputs.first;
      if (first == null) throw StateError('Model returned no output');

      final values = <double>[];
      void walk(dynamic v) {
        if (v is num) {
          values.add(v.toDouble());
        } else if (v is Iterable) {
          for (final e in v) {
            walk(e);
          }
        }
      }

      walk(first.value);
      if (values.length != numClasses) {
        throw StateError(
          'Expected $numClasses logits, got ${values.length}',
        );
      }
      return values;
    } finally {
      input?.release();
      runOptions?.release();
      if (outputs != null) {
        for (final o in outputs) {
          o?.release();
        }
      }
    }
  }

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((v) => math.exp(v - maxLogit)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((v) => v / sum).toList();
  }

  void dispose() {
    _session?.release();
    _session = null;
  }
}