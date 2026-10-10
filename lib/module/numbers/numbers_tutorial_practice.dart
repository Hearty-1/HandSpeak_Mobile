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
import '../civic/onnx_env_manager.dart';
import '/services/frame_gate.dart';

import '/services/performance_monitor.dart';


// =============================================================================
// ONNX INFERENCE SERVICE WITH EXACT 78-FEATURE EXTRACTOR
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

/// Start/end handshape verifiers for dynamic numbers (11-100).
///
/// Every number sign goes from a start handshape (its tens "base": L for 2x,
/// '3' for 3x, ..., the unit shape for 11-19, '1' for 100) to an end
/// handshape (its units; 'O' for decades, 'C' for 100). Each decade ONNX
/// model only knows its own 10 numbers, so on its own it maps other-decade
/// signs onto them (18/28/38 -> "58") and, being trained on few clips, it
/// also mixes up neighbours (34 -> 40). These two small classifiers, trained
/// on all 838 clips (assets/numbers/base_shape_verifier.json), are combined
/// with the decade model's score; see FSLOnnxService.evaluateWithModel.
class BaseShapeVerifier {
  static Map<String, dynamic>? _model;

  static Future<void> load() async {
    if (_model != null) return;
    try {
      _model = jsonDecode(await rootBundle.loadString('assets/numbers/base_shape_verifier.json'))
          as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[BaseShapeVerifier] unavailable: $e');
    }
  }

  static bool get isLoaded => _model != null;

  static double param(String key, double fallback) => ((_model?[key]) as num?)?.toDouble() ?? fallback;

  static List<List<int>> get framings =>
      ((_model?['framings'] as List?) ?? const [[0, 0]]).map((f) => (f as List).cast<int>()).toList();

  /// Handshape a number starts in (base_shape() in training).
  static String baseShapeFor(int n) {
    if (n == 100) return '1';
    if (n >= 11 && n <= 19) return '${n - 10}';
    if (n >= 20 && n <= 29) return 'L';
    return '${n ~/ 10}';
  }

  /// Handshape a number ends in (end_shape() in training).
  static String endShapeFor(int n) {
    if (n == 100) return 'C';
    if (n >= 11 && n <= 19) return '${n - 10}';
    if (n == 20) return 'L';
    if (n % 10 == 0) return 'O';
    return '${n % 10}';
  }

  static const Map<String, String> shapeNames = {
    'L': "'L' (hinlalaki at hintuturo)",
    '1': "'1' (hintuturo lang)",
    '2': "'2' (hintuturo at hinlalato)",
    '3': "'3' (hinlalaki, hintuturo, hinlalato)",
    '4': "'4' (apat na daliri, nakatupi ang hinlalaki)",
    '5': "'5' (bukas ang lahat ng daliri)",
    '6': "'6' (hinlalaki sa dulo ng kalingkingan)",
    '7': "'7' (hinlalaki sa dulo ng palasingsingan)",
    '8': "'8' (hinlalaki sa dulo ng hinlalato)",
    '9': "'9' (hinlalaki sa dulo ng hintuturo)",
  };

  static double _d(List<double> f, int a, int b) {
    final dx = f[a * 3] - f[b * 3], dy = f[a * 3 + 1] - f[b * 3 + 1], dz = f[a * 3 + 2] - f[b * 3 + 2];
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// 20 scale/rotation-free handshape features of one frame (handshape.py).
  static List<double> frameFeatures(List<double> f) {
    final palm = _d(f, 0, 9) + 1e-6;
    double r(int a, int b) => _d(f, a, 0) / (_d(f, b, 0) + 1e-6);
    return [
      r(8, 6), r(12, 10), r(16, 14), r(20, 18), // fingertip vs middle joint
      r(4, 2), r(8, 5), r(12, 9), r(16, 13), r(20, 17), // fingertip vs knuckle
      for (final t in [8, 12, 16, 20]) _d(f, 4, t) / palm, // thumb-tip contacts
      _d(f, 4, 5) / palm, _d(f, 4, 17) / palm, _d(f, 4, 9) / palm, _d(f, 4, 6) / palm,
      _d(f, 8, 12) / palm, _d(f, 12, 16) / palm, _d(f, 16, 20) / palm, // spreads
    ];
  }

  /// Probability per handshape for the start (or [end]) part of a 24-frame clip.
  static Map<String, double> probabilities(List<List<double>> clip24, {bool end = false}) {
    final m = _model![end ? 'end' : 'start'] as Map<String, dynamic>;
    final range = (m['frames'] as List).cast<int>();
    final frames = [for (int i = range[0]; i < range[1]; i++) frameFeatures(clip24[i])];
    final nf = frames.first.length;
    final x = <double>[];
    for (int k = 0; k < nf; k++) {
      x.add(FSLOnnxService._median([for (final f in frames) f[k]]));
    }
    for (int k = 0; k < nf; k++) {
      final mean = frames.map((f) => f[k]).reduce((a, b) => a + b) / frames.length;
      final varSum = frames.map((f) => (f[k] - mean) * (f[k] - mean)).reduce((a, b) => a + b);
      x.add(math.sqrt(varSum / frames.length)); // population std, like np.std
    }
    final mean = (m['mean'] as List).cast<num>();
    final scale = (m['scale'] as List).cast<num>();
    final xs = [for (int k = 0; k < x.length; k++) (x[k] - mean[k]) / scale[k]];
    final coef = (m['coef'] as List).map((r) => (r as List).cast<num>()).toList();
    final intercept = (m['intercept'] as List).cast<num>();
    final logits = [
      for (int c = 0; c < coef.length; c++)
        intercept[c] + List.generate(xs.length, (k) => coef[c][k] * xs[k]).reduce((a, b) => a + b)
    ];
    final mx = logits.reduce(math.max);
    final ex = logits.map((v) => math.exp(v - mx)).toList();
    final sum = ex.reduce((a, b) => a + b);
    final classes = (m['classes'] as List).cast<String>();
    return {for (int c = 0; c < classes.length; c++) classes[c]: ex[c] / sum};
  }

  /// True when the clip plausibly starts in [target]'s base handshape: its
  /// probability is at least `relative_threshold` x the best shape's.
  static ({bool ok, String expected, String best, double ratio}) check(int target, List<List<double>> clip24) {
    final expected = baseShapeFor(target);
    if (_model == null) return (ok: true, expected: expected, best: expected, ratio: 1.0);
    final p = probabilities(clip24);
    final best = p.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final ratio = (p[expected] ?? 0.0) / (best.value + 1e-9);
    return (ok: ratio >= param('relative_threshold', 0.2), expected: expected, best: best.key, ratio: ratio);
  }
}

class FSLOnnxService {
  static OrtSession? _session;
  static int _loadedRangeGroup = -1;

  // Tracks the load actually in flight, so a second overlapping call to
  // loadModelForTarget (e.g. triggered by fast navigation between numbers)
  // waits for the SAME load instead of racing it with a second one.
  static Future<void>? _loadInFlight;

static int get debugLoadedGroup => _loadedRangeGroup;

  /// Single source of truth for which decade-group a number belongs to —
  /// used by both the loader and (below) the readiness check, so they can
  /// never drift out of sync with each other.
  static int groupForNumber(int targetNumber) {
    if (targetNumber >= 21 && targetNumber <= 30) return 2;
    if (targetNumber >= 31 && targetNumber <= 40) return 3;
    if (targetNumber >= 41 && targetNumber <= 50) return 4;
    if (targetNumber >= 51 && targetNumber <= 60) return 5;
    if (targetNumber >= 61 && targetNumber <= 70) return 6;
    if (targetNumber >= 71 && targetNumber <= 80) return 7;
    if (targetNumber >= 81 && targetNumber <= 90) return 8;
    if (targetNumber >= 91 && targetNumber <= 100) return 9;
    return 1; // 11-20
  }

  static String _assetPathForGroup(int group) {
    const paths = {
      1: 'assets/numbers/fsl_numbers_11_20.onnx',
      2: 'assets/numbers/fsl_numbers_20_30.onnx',
      3: 'assets/numbers/fsl_numbers_31_40.onnx',
      4: 'assets/numbers/fsl_numbers_41_50.onnx',
      5: 'assets/numbers/fsl_numbers_51_60.onnx',
      6: 'assets/numbers/fsl_numbers_61_70.onnx',
      7: 'assets/numbers/fsl_numbers_71_80.onnx',
      8: 'assets/numbers/fsl_numbers_81_90.onnx',
      9: 'assets/numbers/fsl_numbers_91_100.onnx',
    };
    return paths[group]!;
  }

  /// True only when the model actually loaded (and finished loading) for
  /// THIS specific number's decade group. The evaluation path below must
  /// check this before calling evaluateWithModel — this is what closes
  /// the race that let evaluation run against a stale, wrong-decade model
  /// (e.g. target 58 being scored by whatever model happened to still be
  /// loaded from a previous number) if the camera/hand-tracking pipeline
  /// started producing frames before loadModelForTarget's await chain for
  /// the NEW target had actually finished.
  static bool isReadyFor(int targetNumber) {
    return _session != null && _loadedRangeGroup == groupForNumber(targetNumber);
  }

  static Future<void> loadModelForTarget(int targetNumber) async {
    final group = groupForNumber(targetNumber);
    final assetPath = _assetPathForGroup(group);

    if (_session != null && _loadedRangeGroup == group) {
      return;
    }

    // If a load for this same group is already in flight, wait for it
    // instead of starting a redundant second one.
    if (_loadInFlight != null) {
      await _loadInFlight;
      if (_loadedRangeGroup == group) return;
    }

    final completer = Completer<void>();
    _loadInFlight = completer.future;

    try {
      // Deliberately NOT releasing the old session or clearing
      // _loadedRangeGroup until the NEW one has successfully loaded —
      // otherwise there is a window where _session is null/stale while a
      // frame could still be evaluated against it. See isReadyFor() above,
      // which is the actual gate the UI checks before evaluating.
      OnnxEnvManager.ensureInitialized();
      final rawAsset = await rootBundle.load(assetPath);
      final bytes = rawAsset.buffer.asUint8List();
      final newSession = OrtSession.fromBuffer(bytes, OrtSessionOptions());

      _session?.release();
      _session = newSession;
      _loadedRangeGroup = group;
      debugPrint("[FSLOnnxService] Loaded model for group $group ($assetPath) — target was $targetNumber");
    } catch (e) {
      // Loading failed — leave whatever was previously loaded (if
      // anything) in place, but crucially _loadedRangeGroup was never
      // updated to this new `group`, so isReadyFor(targetNumber) will
      // correctly report false rather than silently evaluating this
      // target against a wrong-decade model.
      debugPrint("[FSLOnnxService] Load FAILED for $assetPath (group $group, target $targetNumber): $e");
    } finally {
      completer.complete();
      _loadInFlight = null;
    }
  }

  static void release() {
    _session?.release();
    _session = null;
    _loadedRangeGroup = -1;
  }

  /// np.median: the mean of the two middle values for even-sized lists.
  static double _median(List<double> v) {
    final s = [...v]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2.0;
  }

  /// np.linspace(0, n - 1, 24).astype(int): how the training videos were
  /// reduced to 24 frames (index sampling over the WHOLE sign).
  static List<List<double>> resampleTo24(List<List<double>> clip) {
    final n = clip.length;
    return List.generate(24, (i) => clip[n == 1 ? 0 : (i * (n - 1) / 23).floor()]);
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
        if (speed > 0.015) { // train_*.py deadzone
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

    // 3D distances, as in train_*.py (tip_to_thumb uses np.linalg.norm on xyz).
    double d3n(int f, int a, int b) => math.sqrt(math.pow(norm[f][a][0] - norm[f][b][0], 2) +
        math.pow(norm[f][a][1] - norm[f][b][1], 2) +
        math.pow(norm[f][a][2] - norm[f][b][2], 2));
    double initialThumbDist = (d3n(0, 8, 4) + d3n(0, 12, 4)) / 2.0;
    double finalThumbDist = (d3n(23, 8, 4) + d3n(23, 12, 4)) / 2.0;
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
        medPts.add([_median(xs), _median(ys), _median(zs)]);
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

  /// One ONNX run: probability per number of the loaded decade model.
  static Map<int, double> _decadeProbabilities(List<List<double>> clip24) {
    final inputTensor = OrtValueTensor.createTensorWithDataList(extract78Features(clip24), [1, 78]);
    final runOptions = OrtRunOptions();
    final outputs = _session!.run(runOptions, {'float_input': inputTensor});
    final probs = <int, double>{};
    try {
      if (outputs.length > 1 && outputs[1]?.value != null) {
        final seq = outputs[1]!.value as List;
        if (seq.isNotEmpty && seq[0] is Map) {
          (seq[0] as Map).forEach((k, v) => probs[int.parse(k.toString())] = (v as num).toDouble());
        }
      }
      if (probs.isEmpty) {
        final label = int.parse((outputs[0]!.value as List)[0].toString());
        probs[label] = 1.0;
      }
    } finally {
      inputTensor.release();
      runOptions.release();
      for (final o in outputs) {
        o?.release();
      }
    }
    return probs;
  }

  /// Start-handshape check for the 3x / 9x decades, independent of
  /// base_shape_verifier.json (which is missing from assets, so the general
  /// check below never runs). Each decade model only knows its own ten
  /// numbers: a 9x sign scored by the 31-40 model lands on the nearest 3x
  /// number and was accepted. The two bases differ in the ring and pinky:
  /// '3' = thumb, index, middle up with ring + pinky folded; '9' = thumb tip
  /// on the index tip with middle, ring + pinky up. The clip starts with the
  /// held base, so its first frames are judged. Returns feedback when the
  /// sign clearly starts in the other base, otherwise null.
  static String? startBaseConflict(int target, List<List<double>> clip24) {
    final base = BaseShapeVerifier.baseShapeFor(target);
    if (base != '3' && base != '9') return null;
    final start = clip24.sublist(0, math.min(5, clip24.length));
    double ratio(List<double> f, int tip, int pip) =>
        BaseShapeVerifier._d(f, tip, 0) / (BaseShapeVerifier._d(f, pip, 0) + 1e-6);
    final ring = _median([for (final f in start) ratio(f, 16, 14)]);
    final pinky = _median([for (final f in start) ratio(f, 20, 18)]);
    final ringPinkyUp = ring >= 1.10 && pinky >= 1.10;
    final ringPinkyFolded = ring <= 1.0 && pinky <= 1.0;
    debugPrint('[Numbers] start base $base: ring ${ring.toStringAsFixed(2)}, pinky ${pinky.toStringAsFixed(2)}');
    if (base == '3' && ringPinkyUp) {
      return "Nagsimula ka sa '9' (nakataas ang palasingsingan at kalingkingan). "
          "Ang $target ay nagsisimula sa ${BaseShapeVerifier.shapeNames['3']}: itikom ang palasingsingan at kalingkingan.";
    }
    if (base == '9' && ringPinkyFolded) {
      return "Ang $target ay nagsisimula sa ${BaseShapeVerifier.shapeNames['9']}, "
          "nakataas ang hinlalato, palasingsingan at kalingkingan.";
    }
    return null;
  }

  static StudentEvaluationResult evaluateWithModel({
    required int targetNumber,
    required List<List<double>> window24Frames,
    required double kineticEnergy,
  }) {
    if (_session == null) {
      throw Exception("ONNX Session not initialized for target $targetNumber");
    }

    final conflict = startBaseConflict(targetNumber, window24Frames);
    if (conflict != null) {
      return StudentEvaluationResult(
        targetNumber: targetNumber,
        detectedNumber: null,
        isCorrect: false,
        accuracyScore: 40.0,
        feedback: conflict,
        kineticEnergy: kineticEnergy,
      );
    }

    // 1) Decade model, averaged over a few slightly cropped framings of the
    //    captured sign: it was trained on few clips and is sensitive to how
    //    the sign is framed in time (+1..4% held-out accuracy).
    final framings = BaseShapeVerifier.isLoaded ? BaseShapeVerifier.framings : const [[0, 0]];
    final avg = <int, double>{};
    for (final f in framings) {
      final cut = window24Frames.sublist(f[0], 24 - f[1]);
      _decadeProbabilities(cut.length == 24 ? cut : resampleTo24(cut))
          .forEach((k, v) => avg[k] = (avg[k] ?? 0) + v / framings.length);
    }
    final classes = avg.keys.toList()..sort();
    final targetProbability = avg[targetNumber] ?? 0.0;

    if (!BaseShapeVerifier.isLoaded) {
      final predicted = classes.reduce((a, b) => avg[a]! >= avg[b]! ? a : b);
      final ok = predicted == targetNumber;
      return StudentEvaluationResult(
        targetNumber: targetNumber,
        detectedNumber: predicted,
        isCorrect: ok,
        accuracyScore: ok ? (72.0 + 27.0 * targetProbability).clamp(72.0, 99.0) : targetProbability * 60.0,
        feedback: ok
            ? "Mahusay! Wastong kumpas at porma para sa Number $targetNumber"
            : "Mukhang Number $predicted ang naisagawa. Subukang muli para sa $targetNumber.",
        kineticEnergy: kineticEnergy,
      );
    }

    // 2) Fuse with how well the start and end handshapes fit each number:
    //    score(m) = log P_decade(m) + ws log P_start(base(m)) + we log P_end(end(m)).
    //    Held-out: correct signs accepted 55.0% -> 64.3% with no extra
    //    other-decade false positives (see base_shape_verifier.json).
    final ps = BaseShapeVerifier.probabilities(window24Frames);
    final pe = BaseShapeVerifier.probabilities(window24Frames, end: true);
    final eps = BaseShapeVerifier.param('eps', 0.02);
    final ws = BaseShapeVerifier.param('start_weight', 0.5);
    final we = BaseShapeVerifier.param('end_weight', 0.5);
    double fused(int m) =>
        math.log(avg[m]! + eps) +
        ws * math.log((ps[BaseShapeVerifier.baseShapeFor(m)] ?? 0) + eps) +
        we * math.log((pe[BaseShapeVerifier.endShapeFor(m)] ?? 0) + eps);
    final scores = {for (final m in classes) m: fused(m)};
    final best = classes.reduce((a, b) => scores[a]! >= scores[b]! ? a : b);
    final targetScore = scores[targetNumber] ?? double.negativeInfinity;

    // 3) Accept the target when it is the best fit or a close second (the
    //    learner already knows which number they are signing)...
    final closeEnough = targetScore >= scores[best]! - BaseShapeVerifier.param('tolerance', 0.75);
    // ...and only if the sign plausibly STARTS in the target's tens handshape:
    // the decade model cannot see other decades (18 vs 58).
    final base = BaseShapeVerifier.check(targetNumber, window24Frames);
    debugPrint('[Numbers] target $targetNumber: best $best, '
        'P_decade(target)=${targetProbability.toStringAsFixed(2)}, '
        'score gap ${(scores[best]! - targetScore).toStringAsFixed(2)}, '
        'start ${base.expected}->${base.best} (${base.ratio.toStringAsFixed(2)}), '
        'end ${BaseShapeVerifier.endShapeFor(targetNumber)}');

    if (!closeEnough) {
      return StudentEvaluationResult(
        targetNumber: targetNumber,
        detectedNumber: best,
        isCorrect: false,
        accuracyScore: (targetProbability * 60.0).clamp(0.0, 60.0),
        feedback: "Mukhang Number $best ang naisagawa. Subukang muli para sa $targetNumber.",
        kineticEnergy: kineticEnergy,
      );
    }
    if (!base.ok) {
      return StudentEvaluationResult(
        targetNumber: targetNumber,
        detectedNumber: null,
        isCorrect: false,
        accuracyScore: 45.0,
        feedback: "Ang simula ay dapat ${BaseShapeVerifier.shapeNames[base.expected] ?? base.expected}. "
            "Hawakan muna ito bago gumalaw.",
        kineticEnergy: kineticEnergy,
      );
    }

    final double score = (72.0 + 27.0 * targetProbability).clamp(72.0, 99.0);
    return StudentEvaluationResult(
      targetNumber: targetNumber,
      detectedNumber: targetNumber,
      isCorrect: true,
      accuracyScore: score,
      feedback: "Mahusay! Wastong kumpas at porma para sa Number $targetNumber (${score.toStringAsFixed(1)}%)",
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
// MAIN PRACTICE WIDGET
// =============================================================================

/// Whole-sign capture for dynamic numbers: hold base -> move -> hold end.
enum _SignPhase { waitBase, baseHeld, moving }

class NumbersTutorialPractice extends StatefulWidget {
  final String targetNumber;

  const NumbersTutorialPractice({super.key, required this.targetNumber});

  @override
  _NumbersTutorialPracticeState createState() => _NumbersTutorialPracticeState();
}

class _NumbersTutorialPracticeState extends State<NumbersTutorialPractice> with WidgetsBindingObserver {
  CameraController? _controller;
  HandLandmarkerPlugin? _landmarkerPlugin;
  StreamSubscription<List<Hand>>? _handSub;

  static final Map<String, List<dynamic>> _templateCache = {};

  bool _isProcessingFrame = false;
  final List<List<double>> _frameBuffer = [];

  // ---- Dynamic numbers (11-100): whole-sign capture -------------------------
  // The models were trained on WHOLE sign videos (all frames, resampled to 24)
  // that start in the base handshape and end in the final one. The old fixed
  // ~1.1 s window usually caught only the end of the sign, whose shape is the
  // START of the next decade number: on the training clips that alone turns
  // 34 -> 40, 89 -> 90, 23 -> 30, 74/78 -> 80, exactly the reported errors.
  final List<int> _frameTimesMs = [];
  _SignPhase _phase = _SignPhase.waitBase;
  int _stillSinceMs = 0; // start of the current still stretch (0 = moving)
  int _baseStillStartMs = 0; // when the held base handshape began
  int _moveStartMs = 0;
  int _fastFrames = 0;
  double _motion = 0.0; // smoothed fingertip speed, palm lengths / second
  List<double>? _prevFrame;
  int _prevFrameMs = 0;
  int _cooldownUntilMs = 0;
  static const double _moveSpeed = 1.6;
  static const double _stillSpeed = 0.7;
  static const int _baseHoldMs = 500;
  static const int _endHoldMs = 600;
  static const int _preMotionMs = 1500; // base hold kept before the movement
  static const int _maxSignMs = 4500;
  static const int _maxBufferMs = 7000;

  // Landmark orientation and aspect (see _toTrainingSpace).
  int _imageWidth = 0, _imageHeight = 0;
  final Map<int, double> _uprightVotes = {0: 0, 90: 0, 180: 0, 270: 0};
  int _orientationFrames = 0;
  int? _lockedRotation;

  /// Width / height of the training videos, inferred from the training data
  /// (palm proportions stay most constant at ~1.5-1.8, i.e. landscape).
  static const double _trainingAspect = 1.6;

  bool _isInitialized = false;
  bool _isSuccessAchieved = false;

  List<dynamic>? _template;
  double _currentScore = 0.0;
  double _holdProgress = 0.0;
  DateTime? _startHoldTime;
  String _currentFeedback = "Ipuwesto ang kamay sa tapat ng camera";

  int _bufferFrameCount = 0;
  static const int _requiredBufferFrames = 24;

  final double successThreshold = 70.0;
  final double holdDurationSeconds = 1.0;
  final int xpReward = 10;

  bool get _isStaticSign {
    final num = int.tryParse(widget.targetNumber) ?? 0;
    return num >= 1 && num <= 10;
  }

  // Tracks whether the CORRECT decade-group model has actually finished
  // loading for THIS screen's target number. Previously loadModelForTarget
  // was fired with `.then()` and never awaited by anything — the camera
  // stream and hand landmarker started immediately in parallel, so if a
  // hand was already in frame and the 24-frame buffer filled before the
  // new model's asset load + OrtSession.fromBuffer finished, evaluation
  // would run against whatever model was PREVIOUSLY loaded (e.g. a
  // different decade's model, if this screen was reached by quickly
  // navigating from a different number). That's the direct cause of
  // results like target 58 scoring against labels "18"/"28" — those
  // aren't even in the 51-60 model's label space; they're leftovers from
  // the 11-20/21-30 model that hadn't been replaced yet.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (!_isStaticSign) {
      final target = int.tryParse(widget.targetNumber) ?? 0;
      BaseShapeVerifier.load();
      FSLOnnxService.loadModelForTarget(target).then((_) {
        final ready = FSLOnnxService.isReadyFor(target);
        debugPrint(
            "[DBG] Model load finished for target $target — ready=$ready");
        if (mounted) {
        }
      });
    }

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
      await _loadGestureLibrary();

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
      debugPrint("Pipeline setup failed: $e");
    }
  }

  Future<void> _loadGestureLibrary() async {
    final number = widget.targetNumber;

    if (_templateCache.containsKey(number)) {
      if (mounted) setState(() { _template = _templateCache[number]; });
      return;
    }

    try {
      final ref = FirebaseStorage.instance.ref().child('numbers/$number.json');
      final data = await ref.getData();
      if (data != null) {
        final jsonString = utf8.decode(data);
        final List<dynamic> parsed = jsonDecode(jsonString);
        _templateCache[number] = parsed;

        if (mounted) setState(() { _template = parsed; });
        debugPrint("Loaded cloud template for sign $number");
        return;
      }
    } catch (e) {
      debugPrint("Cloud Storage fetch failed for $number, using local asset fallback: $e");
    }

    try {
      String jsonString = await rootBundle.loadString('assets/numbers/$number.json');
      final List<dynamic> parsed = jsonDecode(jsonString);
      _templateCache[number] = parsed;

      if (mounted) setState(() { _template = parsed; });
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
      final int sensorOrientation = _cameraImageRotation(_controller); // live device rotation
      _imageWidth = image.width;
      _imageHeight = image.height;
      if (!_frameGate.tryEnter()) return; // one frame in flight (services/frame_gate.dart)
      _landmarkerPlugin!.processFrame(image, sensorOrientation);
    } catch (e) {
      debugPrint("Inference Error: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Dynamic numbers: coordinates
  // ---------------------------------------------------------------------------

  static List<double> _rotateUpright(double u, double v, int degrees) {
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

  /// Live rotation (portrait / landscape) plus the correction learned from
  /// the hand when it was locked (kept as an offset from the rotation at
  /// that moment, so turning the phone afterwards stays correct).
  int get _handRotation {
    final live = _cameraImageRotation(_controller);
    final locked = _lockedRotation;
    return locked == null ? live : (locked + live - _lockBase + 360) % 360;
  }
  int _lockBase = 0;

  /// hand_landmarker may report landmarks in the raw (sideways) sensor frame;
  /// 95% of training frames have the hand pointing up, so the rotation that
  /// makes the wrist -> middle knuckle vector point up is the right one.
  void _voteOrientation(Hand hand) {
    if (_lockedRotation != null) return;
    final dx = hand.landmarks[9].x - hand.landmarks[0].x;
    final dy = hand.landmarks[9].y - hand.landmarks[0].y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return;
    _uprightVotes[0] = _uprightVotes[0]! + dy / len;
    _uprightVotes[90] = _uprightVotes[90]! + dx / len;
    _uprightVotes[180] = _uprightVotes[180]! - dy / len;
    _uprightVotes[270] = _uprightVotes[270]! - dx / len;
    if (++_orientationFrames < 12) return;
    final best = _uprightVotes.entries.reduce((a, b) => a.value <= b.value ? a : b);
    if (best.value / _orientationFrames < -0.5) {
      _lockedRotation = best.key;
      _lockBase = _cameraImageRotation(_controller);
      debugPrint('[Numbers] hand rotation locked at ${best.key}°');
    }
  }

  /// Puts landmarks in the same space as the training videos: upright,
  /// NOT mirrored (training clips are raw camera video; 76% show the thumb on
  /// the image's right = a right hand palm-out, un-flipped), and with x/z
  /// rescaled from the portrait phone frame to the landscape training frame.
  /// The old code mirrored sideways sensor coordinates instead.
  List<double> _toTrainingSpace(Hand hand) {
    final rotation = _handRotation;
    final bool swap = rotation == 90 || rotation == 270;
    final double w = (swap ? _imageHeight : _imageWidth).toDouble();
    final double h = (swap ? _imageWidth : _imageHeight).toDouble();
    final double s = (w > 0 && h > 0) ? (w / h) / _trainingAspect : 1.0;
    final out = <double>[];
    for (final lm in hand.landmarks) {
      final up = _rotateUpright(lm.x, lm.y, rotation);
      out.addAll([0.5 + (up[0] - 0.5) * s, up[1], lm.z * s]);
    }
    return out;
  }

  static double _palmLen(List<double> f) => math.sqrt(math.pow(f[27] - f[0], 2) + math.pow(f[28] - f[1], 2)) + 1e-6;

  // ---------------------------------------------------------------------------
  // Dynamic numbers: whole-sign segmentation
  // ---------------------------------------------------------------------------

  void _resetSign({bool keepCooldown = true}) {
    _frameBuffer.clear();
    _frameTimesMs.clear();
    _phase = _SignPhase.waitBase;
    _stillSinceMs = 0;
    _baseStillStartMs = 0;
    _fastFrames = 0;
    _bufferFrameCount = 0;
    if (!keepCooldown) _cooldownUntilMs = 0;
  }

  void _setStatus(String text) {
    if (mounted && _currentFeedback != text && _currentScore < successThreshold) {
      setState(() => _currentFeedback = text);
    }
  }

  /// Hold the first handshape, move, hold the final handshape: then the whole
  /// sign is evaluated once.
  void _trackDynamicSign(List<Hand> hands) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final usable = hands.where((h) => h.landmarks.length == 21).toList();
    if (usable.isEmpty) {
      _prevFrame = null;
      _resetSign();
      if (mounted && _currentFeedback != "Walang kamay na nakikita") {
        setState(() {
          _currentScore = 0.0;
          _holdProgress = 0.0;
          _currentFeedback = "Walang kamay na nakikita";
        });
      }
      return;
    }
    if (now < _cooldownUntilMs) return;
    if (_phase == _SignPhase.waitBase) _voteOrientation(usable.first);

    final frame = _toTrainingSpace(usable.first);
    // Fingertip speed in palm lengths per second (includes whole-hand bounces,
    // which is the movement of doubles like 44 / 99).
    if (_prevFrame != null && now > _prevFrameMs) {
      final palm = _palmLen(frame);
      double sp = 0;
      for (final t in const [4, 8, 12, 16, 20]) {
        sp += math.sqrt(math.pow(frame[t * 3] - _prevFrame![t * 3], 2) + math.pow(frame[t * 3 + 1] - _prevFrame![t * 3 + 1], 2));
      }
      final raw = sp / 5 / palm / ((now - _prevFrameMs) / 1000.0);
      _motion = 0.5 * _motion + 0.5 * raw;
    }
    _prevFrame = frame;
    _prevFrameMs = now;

    _frameBuffer.add(frame);
    _frameTimesMs.add(now);
    while (_frameTimesMs.isNotEmpty && now - _frameTimesMs.first > _maxBufferMs) {
      _frameTimesMs.removeAt(0);
      _frameBuffer.removeAt(0);
    }

    final bool still = _motion < _stillSpeed;
    if (still) {
      if (_stillSinceMs == 0) _stillSinceMs = now;
    } else {
      _stillSinceMs = 0;
    }
    _fastFrames = _motion > _moveSpeed ? _fastFrames + 1 : 0;

    switch (_phase) {
      case _SignPhase.waitBase:
        if (still && now - _stillSinceMs >= _baseHoldMs) {
          _phase = _SignPhase.baseHeld;
          _baseStillStartMs = _stillSinceMs;
        }
        _setStatus("Ipakita at hawakan ang unang porma ng ${widget.targetNumber}...");
        break;
      case _SignPhase.baseHeld:
        if (_fastFrames >= 2) {
          _phase = _SignPhase.moving;
          _moveStartMs = now;
          _setStatus("Ginagawa ang galaw...");
        } else {
          _setStatus("Handa na ✓ Gawin ang galaw ng ${widget.targetNumber}, saka hawakan ang huling porma.");
        }
        break;
      case _SignPhase.moving:
        final settled = still && now - _stillSinceMs >= _endHoldMs;
        if (settled || now - _moveStartMs >= _maxSignMs) {
          _evaluateSign(now);
          return;
        }
        break;
    }
    if (mounted) {
      final progress = _phase == _SignPhase.moving
          ? math.min(_requiredBufferFrames - 1, 6 + ((now - _moveStartMs) / 120).round())
          : 0;
      if (progress != _bufferFrameCount) setState(() => _bufferFrameCount = progress);
    }
  }

  void _evaluateSign(int now) {
    // The sign: the held base just before the movement, the movement, and
    // the final hold.
    final startMs = math.max(_baseStillStartMs, _moveStartMs - _preMotionMs);
    final clip = [
      for (int i = 0; i < _frameBuffer.length; i++)
        if (_frameTimesMs[i] >= startMs) _frameBuffer[i]
    ];
    _resetSign();
    _cooldownUntilMs = now + 1200;

    final targetInt = int.tryParse(widget.targetNumber) ?? 0;
    double score = 0.0;
    String feedback;
    if (clip.length < 12) {
      // extract_*_landmarks.py discards clips with fewer than 12 frames.
      feedback = "Masyadong mabilis. Hawakan ang unang porma, gumalaw, saka hawakan ang huling porma.";
    } else if (!FSLOnnxService.isReadyFor(targetInt)) {
      // Never score against a stale model from another decade.
      feedback = "Naglo-load pa ang modelo para sa Number ${widget.targetNumber}...";
      debugPrint("[DBG] Skipped evaluation: model not ready for target $targetInt "
          "(loaded group=${FSLOnnxService.debugLoadedGroup}, expected=${FSLOnnxService.groupForNumber(targetInt)})");
    } else {
      try {
        final clip24 = FSLOnnxService.resampleTo24(clip);
        final evalResult = FSLOnnxService.evaluateWithModel(
          targetNumber: targetInt,
          window24Frames: clip24,
          kineticEnergy: FSLOnnxService.computeKineticEnergy(clip24),
        );
        score = evalResult.accuracyScore;
        feedback = evalResult.feedback;
        debugPrint('[Numbers] clip ${clip.length} frames, rotation $_handRotation -> '
            '${evalResult.isCorrect ? 'PASS' : 'fail'} (${evalResult.detectedNumber})');
      } catch (e) {
        debugPrint("ONNX Inference Error: $e");
        feedback = "Model Inference Error.";
      }
    }
    _updateGameLogic(score, feedback);
  }

  double _calculateScore(List<Landmark> liveLms, List<dynamic> template, Size imageSize) {
    if (liveLms.isEmpty || template.length < 21 || liveLms.length < 21) return 0.0;

    final double w = imageSize.width;
    final double h = imageSize.height;

    List<List<double>> standardizeHand(List<List<double>> rawPts) {
      double wx = rawPts[0][0], wy = rawPts[0][1], wz = rawPts[0][2];
      List<List<double>> translated = rawPts.map((p) => [p[0] - wx, p[1] - wy, p[2] - wz]).toList();

      double mx = translated[9][0], my = translated[9][1], mz = translated[9][2];
      double scale = math.sqrt(mx * mx + my * my + mz * mz) + 1e-6;

      double angle = math.atan2(my, mx);
      double targetAngle = math.pi / 2;
      double theta = targetAngle - angle;
      
      double cosT = math.cos(theta);
      double sinT = math.sin(theta);

      List<List<double>> aligned = [];
      for (var p in translated) {
        double sx = p[0] / scale;
        double sy = p[1] / scale;
        double sz = p[2] / scale; 

        double rx = (sx * cosT) - (sy * sinT);
        double ry = (sx * sinT) + (sy * cosT);
        aligned.add([rx, ry, sz]);
      }
      return aligned;
    }

    List<List<double>> livePts = liveLms.map((lm) => [lm.x * w, lm.y * h, lm.z * w]).toList();
    List<List<double>> tempPts = template.map((t) {
      return [
        (t['x'] as num).toDouble() * w,
        (t['y'] as num).toDouble() * h,
        ((t['z'] ?? 0.0) as num).toDouble() * w
      ];
    }).toList();

    var normLive = standardizeHand(livePts);
    var normTemp = standardizeHand(tempPts);

    double bestScore = 0.0;
    bool isFistSign = widget.targetNumber == "10";
    
    double zWeight = isFistSign ? 0.2 : 1.0;
    double meanPenalty = isFistSign ? 65.0 : 90.0;
    double maxPenalty = isFistSign ? 10.0 : 35.0;

    for (double flipX in [1.0, -1.0]) {
      double totalDiff = 0.0;
      double maxDiff = 0.0;

      for (int i = 0; i < 21; i++) {
        double dx = (normLive[i][0] * flipX) - normTemp[i][0];
        double dy = normLive[i][1] - normTemp[i][1];
        double dz = (normLive[i][2] - normTemp[i][2]) * zWeight;

        double pointDiff = math.sqrt(dx * dx + dy * dy + dz * dz);
        
        totalDiff += pointDiff;
        if (pointDiff > maxDiff && i != 0) {
          maxDiff = pointDiff;
        }
      }

      double meanDiff = totalDiff / 21.0;
      double score = (100.0 - (meanDiff * meanPenalty) - (maxDiff * maxPenalty)).clamp(0.0, 100.0);
      
      if (score > bestScore) {
        bestScore = score;
      }
    }

    return bestScore;
  }

  void _onHandsDetected(List<Hand> detectedHands) async {
    _frameGate.done();
    if (_isSuccessAchieved || _isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      if (!_isStaticSign) {
        _trackDynamicSign(detectedHands);
        return;
      }
      if (detectedHands.isNotEmpty) {
        double score = 0.0;
        String feedback = "Ipuwesto ang kamay sa tapat ng camera";

        if (_isStaticSign) {
          if (_template != null) {
            double highestScoreAcrossAllHands = 0.0;
            Size imageSize = _controller?.value.previewSize ?? const Size(480, 640);

            for (int handIdx = 0; handIdx < detectedHands.length; handIdx++) {
              final double handScore = _calculateScore(
                detectedHands[handIdx].landmarks,
                _template!,
                imageSize,
              );
              if (handScore > highestScoreAcrossAllHands) {
                highestScoreAcrossAllHands = handScore;
              }
            }

            score = highestScoreAcrossAllHands;
            feedback = score >= successThreshold
                ? "Tama ang posisyon! Hawakan ang kamay."
                : "I-adjust ang posisyon para sa Sign ${widget.targetNumber}.";
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

    final theme = Theme.of(context);
    final visuals = _ThemeVisuals.fromTheme(theme);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SmartBlur(
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
                    "Outstanding job! You have successfully mastered the number ${widget.targetNumber}!",
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

    FSLOnnxService.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      widget.targetNumber,
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
                              "assets/pictures/${widget.targetNumber}.png",
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

                    if (_isStaticSign && _holdProgress > 0.0) ...[
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
