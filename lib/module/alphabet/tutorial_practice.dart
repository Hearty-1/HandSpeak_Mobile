import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:onnxruntime/onnxruntime.dart';
import '/services/handspeak_api_service.dart';

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
// STROKE GEOMETRY (shared by J and Z)
// =============================================================================
//
// Strokes are in upright, selfie-mirrored, aspect-corrected coordinates
// (y grows downward), the same view as the Python testers (cv2.flip).

/// Mean-frame finger extensions divided by palm length (wrist -> middle MCP),
/// as in extract_j_features / test_single_j.py.
class _HandShape {
  final double palm, thumbOut, index, middle, ring, pinky;
  const _HandShape(this.palm, this.thumbOut, this.index, this.middle, this.ring, this.pinky);

  factory _HandShape.of(List<List<LandmarkPoint>> seq) {
    final mean = List<LandmarkPoint>.generate(21, (i) {
      double x = 0, y = 0, z = 0;
      for (final f in seq) {
        x += f[i].x;
        y += f[i].y;
        z += f[i].z;
      }
      return LandmarkPoint(x / seq.length, y / seq.length, z / seq.length);
    });
    final palm = mean[9].distanceTo(mean[0]) + 1e-6;
    double ext(int i) => mean[i].distanceTo(mean[0]) / palm;
    return _HandShape(palm, mean[4].distanceTo(mean[9]) / palm, ext(8), ext(12), ext(16), ext(20));
  }
}

/// 2D path of one landmark, relative to its start, in palm units.
List<math.Point<double>> _tipPath(List<List<LandmarkPoint>> seq, int landmark, double palm) {
  final p0 = seq.first[landmark];
  return [for (final f in seq) math.Point((f[landmark].x - p0.x) / palm, (f[landmark].y - p0.y) / palm)];
}

/// Resamples a path to [n] points evenly spaced along its length, so the
/// checks do not depend on drawing speed or camera frame rate.
List<math.Point<double>> _arcResample(List<math.Point<double>> p, int n) {
  final cum = <double>[0];
  for (int i = 1; i < p.length; i++) {
    cum.add(cum.last + p[i].distanceTo(p[i - 1]));
  }
  if (cum.last < 1e-9) return List.filled(n, p.first);
  final out = <math.Point<double>>[];
  int j = 0;
  for (int k = 0; k < n; k++) {
    final t = cum.last * k / (n - 1);
    while (j < p.length - 2 && cum[j + 1] < t) {
      j++;
    }
    final seg = cum[j + 1] - cum[j];
    final w = seg < 1e-12 ? 0.0 : ((t - cum[j]) / seg).clamp(0.0, 1.0);
    out.add(math.Point(p[j].x + (p[j + 1].x - p[j].x) * w, p[j].y + (p[j + 1].y - p[j].y) * w));
  }
  return out;
}

double _wrapAngle(double a) => math.atan2(math.sin(a), math.cos(a));

/// Total absolute heading change (radians) of a lightly smoothed path:
/// one J bend is ~pi/2..pi, circles and scribbles are far more.
double _totalTurning(List<math.Point<double>> p) {
  final sm = [
    for (int i = 0; i < p.length; i++)
      () {
        final lo = math.max(0, i - 1), hi = math.min(p.length - 1, i + 1);
        double x = 0, y = 0;
        for (int k = lo; k <= hi; k++) {
          x += p[k].x;
          y += p[k].y;
        }
        return math.Point(x / (hi - lo + 1), y / (hi - lo + 1));
      }()
  ];
  final a = _arcResample(sm, 16);
  double turn = 0, prev = double.nan;
  for (int i = 1; i < a.length; i++) {
    final h = math.atan2(a[i].y - a[i - 1].y, a[i].x - a[i - 1].x);
    if (!prev.isNaN) turn += _wrapAngle(h - prev).abs();
    prev = h;
  }
  return turn;
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

  /// The ONNX model alone scores circles, Z strokes and Y-hands about as high
  /// as a real J (~0.55), because its training negatives were only static
  /// I-hands, opened-index clips and Z clips. It is therefore used as a
  /// sanity floor, and the J itself is verified geometrically below.
  static const double modelFloor = 0.30;

  // Pinky-path geometry, in palm lengths. Real Js twist the wrist, so these
  // are deliberately tolerant; false positives are stopped by the shape of
  // the whole J plus the "only positioning outside the J" rule.
  static const double _minDrop = 0.6;
  static const double _maxStartDeg = 55;
  static const double _minSide = 0.30;
  static const double _minHookUp = 0.25;
  static const double _minBendDeg = 35;
  static const double _endBelow = 0.35; // hook may rise at most 65% of the drop
  static const double _maxTurn = 5.0; // radians
  static const double _minCover = 0.40; // J must be >= 40% of the movement
  static const double _outsideSlack = 0.4; // tolerated non-positioning motion
  static const int _minWindow = 8;
  static const int _maxModelChecks = 8;

  static const String _msgHook = 'Kulang ang kurba sa dulo. Ikurba ang kalingkingan pagkababa (hugis J).';

  LetterJResult _fail(String message, [double confidence = 0.0]) =>
      LetterJResult(isLetterJ: false, confidence: confidence, message: message);

  /// Human-readable details of the last [classifyStroke] call (diagnostics).
  String lastReport = '';

  // Finger states are judged per frame WITHOUT palm-size ratios: a finger is
  // folded when its tip is no farther from the wrist than its middle (PIP)
  // joint, and extended when clearly farther. Palm-length ratios on the
  // averaged hand were too strict: tilting/twisting the hand during the J
  // shortens the palm on camera and made folded fingers look open.
  static const double _foldedMax = 1.05;
  static const double _extendedMin = 1.10;
  static const double _minFingerFraction = 0.6; // share of frames that must agree
  static const List<(int, int, String)> _otherFingers = [
    (8, 6, 'hintuturo'),
    (12, 10, 'hinlalato'),
    (16, 14, 'palasingsingan'),
  ];

  static double _tipPipRatio(List<LandmarkPoint> f, int tip, int pip) =>
      f[tip].distanceTo(f[0]) / (f[pip].distanceTo(f[0]) + 1e-6);

  /// Per-frame flags: [pinky up, index folded, middle folded, ring folded].
  static List<bool> _fingerFlags(List<LandmarkPoint> f) => [
        _tipPipRatio(f, pinkyTip, 18) >= _extendedMin,
        for (final (tip, pip, _) in _otherFingers) _tipPipRatio(f, tip, pip) <= _foldedMax,
      ];

  static List<double> _flagFractions(List<List<LandmarkPoint>> frames) {
    final counts = List<double>.filled(4, 0);
    for (final f in frames) {
      final flags = _fingerFlags(f);
      for (int k = 0; k < 4; k++) {
        if (flags[k]) counts[k]++;
      }
    }
    return [for (final c in counts) c / frames.length];
  }

  String? _shapeProblemFromFractions(List<double> frac) {
    if (frac[0] < _minFingerFraction) {
      return 'Maling porma ng kamay! Itaas ang kalingkingan para sa Letter J.';
    }
    final open = [
      for (int k = 0; k < 3; k++)
        if (frac[k + 1] < _minFingerFraction) _otherFingers[k].$3
    ];
    if (open.isNotEmpty) return 'Itikom ang ${open.join(', ')}. Kalingkingan lang ang nakataas.';
    return null;
  }

  String? _shapeProblem(List<List<LandmarkPoint>> frames) =>
      frames.isEmpty ? null : _shapeProblemFromFractions(_flagFractions(frames));

  /// Handshape problem for a few live frames (null = good I-handshape).
  String? handShapeProblem(List<List<LandmarkPoint>> frames) => _shapeProblem(frames);

  /// Measured finger values next to their limits, for diagnostics:
  /// mean tip/middle-joint ratio and the share of frames that pass.
  String handShapeSummary(List<List<LandmarkPoint>> frames) {
    if (frames.isEmpty) return '';
    final frac = _flagFractions(frames);
    double mean(int tip, int pip) =>
        frames.map((f) => _tipPipRatio(f, tip, pip)).reduce((a, b) => a + b) / frames.length;
    String v(String name, double r, String limit, double f) =>
        '$name ${r.toStringAsFixed(2)}$limit ${(f * 100).round()}%${f >= _minFingerFraction ? '✓' : '✗'}';
    return [
      v('pinky', mean(pinkyTip, 18), '≥$_extendedMin', frac[0]),
      v('index', mean(8, 6), '≤$_foldedMax', frac[1]),
      v('middle', mean(12, 10), '≤$_foldedMax', frac[2]),
      v('ring', mean(16, 14), '≤$_foldedMax', frac[3]),
    ].join('  ');
  }

  /// Why a pinky path (palm units, relative to its first point) is not a J,
  /// or null when it is: a drop that starts downward, then bends into a hook
  /// that ends sideways/up, finishing clearly below where it started.
  String? _trajectoryProblem(List<math.Point<double>> p) {
    final a = _arcResample(p, 48);
    int ib = 0;
    for (int i = 1; i < a.length; i++) {
      if (a[i].y > a[ib].y) ib = i;
    }
    final drop = a[ib].y;
    if (drop < _minDrop) return 'Masyadong maliit ang pagbaba. Iguhit ang J nang mas malaki.';
    if (ib / 47 < 0.25) return 'Simulan ang J sa itaas at bumaba muna.';

    final q = a[14] - a[0]; // first 30% of the path
    if (q.y <= 0 || math.atan2(q.x.abs(), q.y) > _maxStartDeg * math.pi / 180) {
      return 'Simulan ang J nang pababa.';
    }

    final e = a.last - a[35]; // last quarter of the path
    if (e.y > e.x.abs()) return _msgHook; // still heading down: no hook

    double side = 0;
    for (int i = ib; i < a.length; i++) {
      side = math.max(side, (a[i].x - a[ib].x).abs());
    }
    double lateMin = double.infinity, lateMax = -double.infinity;
    for (int i = 25; i < a.length; i++) {
      lateMin = math.min(lateMin, a[i].x);
      lateMax = math.max(lateMax, a[i].x);
    }
    final hookUp = a[ib].y - a.last.y;
    final bend = _wrapAngle(math.atan2(e.y, e.x) - math.atan2(q.y, q.x)).abs() * 180 / math.pi;
    if ((math.max(side, lateMax - lateMin) < _minSide && hookUp < _minHookUp) ||
        e.magnitude < 0.2 ||
        bend < _minBendDeg) {
      return _msgHook;
    }
    if (a.last.y < _endBelow * drop) {
      return 'Huwag ibalik pataas ang kamay. Ang J ay pababa na may kurba sa dulo.';
    }
    if (_totalTurning(p) > _maxTurn) return 'Isang tuloy-tuloy na J lang ang iguhit.';
    return null;
  }

  static double _pathLength(List<math.Point<double>> p) {
    double l = 0;
    for (int i = 1; i < p.length; i++) {
      l += p[i].distanceTo(p[i - 1]);
    }
    return l;
  }

  /// Outside the J only positioning is allowed: raising the hand (or nothing)
  /// before it, lowering the hand (or nothing) after it. This is what rejects
  /// U, Z and circles, which contain a J-shaped piece.
  static bool _outsideOk(List<math.Point<double>> full, int i, int j) {
    bool ok(List<math.Point<double>> seg, bool wantUp) {
      if (seg.length < 2) return true;
      final len = _pathLength(seg);
      if (len < _outsideSlack) return true;
      final net = seg.last - seg.first;
      if (net.magnitude < 0.7 * len) return false; // wandering, not one reach
      return wantUp ? net.y <= -0.7 * len : net.y >= 0.7 * len; // clearly vertical
    }

    return ok(full.sublist(0, i + 1), true) && ok(full.sublist(j - 1), false);
  }

  /// True when a recorded movement is just positioning (raising the hand,
  /// small fidgets) and should be ignored without showing feedback.
  bool isPositioningOnly(List<List<LandmarkPoint>> stroke) {
    if (stroke.length < 2) return true;
    final p = _tipPath(stroke, pinkyTip, _HandShape.of(stroke).palm);
    final len = _pathLength(p);
    if (len < 1.2) return true;
    final net = p.last - p.first;
    return net.magnitude >= 0.6 * len && net.y <= -0.5 * len; // just raised the hand
  }

  /// Handshape + trajectory verdict without the model for a whole movement:
  /// null when it contains a valid J, otherwise the feedback to show.
  String? strokeProblem(List<List<LandmarkPoint>> stroke) => _findJCandidates(stroke).problem;

  /// Searches the movement for J-shaped segments: the recording usually also
  /// contains raising the hand before the J and lowering it afterwards.
  ({List<(int, int)> windows, String? problem}) _findJCandidates(List<List<LandmarkPoint>> stroke) {
    final n = stroke.length;
    if (n < _minWindow) {
      return (windows: const <(int, int)>[], problem: 'Masyadong maikli ang galaw. Gawin ang buong kumpas ng Letter J.');
    }
    final palm = _HandShape.of(stroke).palm;
    final full = [for (final f in stroke) math.Point(f[pinkyTip].x / palm, f[pinkyTip].y / palm)];
    final cum = List<double>.filled(n, 0);
    for (int k = 1; k < n; k++) {
      cum[k] = cum[k - 1] + full[k].distanceTo(full[k - 1]);
    }
    final total = cum[n - 1] + 1e-6;

    // Prefix counts of the per-frame finger flags -> any window in O(1).
    final prefix = List.generate(n + 1, (_) => List<int>.filled(4, 0));
    for (int k = 0; k < n; k++) {
      final flags = _fingerFlags(stroke[k]);
      for (int m = 0; m < 4; m++) {
        prefix[k + 1][m] = prefix[k][m] + (flags[m] ? 1 : 0);
      }
    }
    List<double> windowFractions(int i, int j) =>
        [for (int m = 0; m < 4; m++) (prefix[j][m] - prefix[i][m]) / (j - i)];

    final step = n > 70 ? 2 : 1;
    final windows = <(int, int)>[];
    final reasons = <String, int>{};
    for (int i = 0; i + _minWindow <= n; i += step) {
      for (int j = i + _minWindow; j <= n; j += step) {
        if (cum[j - 1] - cum[i] < _minCover * total) continue;
        if (!_outsideOk(full, i, j)) {
          reasons['outside'] = (reasons['outside'] ?? 0) + 1;
          continue;
        }
        final why = _shapeProblemFromFractions(windowFractions(i, j)) ??
            _trajectoryProblem([for (int k = i; k < j; k++) full[k] - full[i]]);
        if (why != null) {
          reasons[why] = (reasons[why] ?? 0) + 1;
          continue;
        }
        windows.add((i, j));
      }
    }
    final ranked = reasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    lastReport = 'segments ${windows.length}; rejected: '
        '${ranked.isEmpty ? '-' : ranked.take(3).map((e) => '${e.key.length > 38 ? '${e.key.substring(0, 38)}…' : e.key} ×${e.value}').join(' | ')}';
    if (windows.isNotEmpty) return (windows: windows, problem: null);

    String problem;
    if (reasons.isEmpty) {
      problem = 'Masyadong maikli ang galaw. Gawin ang buong kumpas ng Letter J.';
    } else {
      final top = reasons.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      problem = top == 'outside' ? 'Isang J lang ang iguhit: itaas ang kamay, iguhit ang J, saka ibaba.' : top;
    }
    // Handshape problems come first: they are what the user must fix first.
    return (windows: const <(int, int)>[], problem: _shapeProblem(stroke) ?? problem);
  }

  double _modelProbability(List<List<LandmarkPoint>> frames) {
    final seq32 = _resampleSequence(frames, targetFrames);
    final Float32List inputFeatures = _extract19Features(seq32);

    final inputOrtValue = OrtValueTensor.createTensorWithDataList(inputFeatures, [1, featureDim]);
    final runOptions = OrtRunOptions();
    final inputName = _session!.inputNames.isNotEmpty ? _session!.inputNames.first : 'float_input';
    final outputs = _session!.run(runOptions, {inputName: inputOrtValue});
    inputOrtValue.release();
    runOptions.release();

    final classOutput = outputs[0]?.value as List<dynamic>?;
    final int predictedClass = classOutput != null ? (classOutput[0] as int) : 0;
    double confidence = predictedClass == 1 ? 0.85 : 0.0;
    if (outputs.length > 1 && outputs[1]?.value != null) {
      final probs = outputs[1]!.value as List<dynamic>;
      if (probs.isNotEmpty && probs[0] is Map) {
        confidence = ((probs[0] as Map)[1] as num?)?.toDouble() ?? 0.0;
      }
    }
    for (final element in outputs) {
      element?.release();
    }
    return confidence;
  }

  LetterJResult classifyStroke(List<List<LandmarkPoint>> recordedFrames) {
    if (!_isInitialized || _session == null) {
      return _fail('Hindi naka-initialize ang model.');
    }

    lastReport = '';
    final found = _findJCandidates(recordedFrames);
    if (found.problem != null) {
      debugPrint('Letter J: no J segment in ${recordedFrames.length} frames (${found.problem})');
      return _fail(found.problem!);
    }

    // Score the segments covering the most movement with the model.
    final windows = [...found.windows]..sort((a, b) => (b.$2 - b.$1).compareTo(a.$2 - a.$1));
    double best = 0.0;
    (int, int)? bestWindow;
    for (final w in windows.take(_maxModelChecks)) {
      final pr = _modelProbability(recordedFrames.sublist(w.$1, w.$2));
      if (pr > best) {
        best = pr;
        bestWindow = w;
      }
    }
    lastReport += '; best $bestWindow model P(J)=${best.toStringAsFixed(2)} (min $modelFloor)';
    debugPrint('Letter J: ${found.windows.length} J-shaped segments in ${recordedFrames.length} frames, '
        'best $bestWindow model P(J)=${best.toStringAsFixed(2)}');

    if (best >= modelFloor) {
      return LetterJResult(
        isLetterJ: true,
        confidence: best,
        message: 'Mahusay! Wastong kumpas at porma para sa Letter J.',
      );
    }
    return _fail('Gawing mas malinaw ang J: kalingkingan lang ang nakataas, pababa, saka ikurba.', best);
  }

  void dispose() {
    _session?.release();
    _session = null;
    _isInitialized = false;
  }
}

// =============================================================================
// LETTER Z CLASSIFIER SERVICE (fsl_letter_z.onnx + STROKE GEOMETRY)
// =============================================================================

class LetterZClassifierService {
  OrtSession? _session;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  static const int wrist = 0;
  static const int indexMcp = 5;
  static const int indexTip = 8;
  static const int middleMcp = 9;
  static const int middleTip = 12;
  static const int ringTip = 16;
  static const int pinkyTip = 20;
  static const int targetFrames = 32;
  static const int featureDim = 23; // labels_letter_z.json

  /// Like the J model, the Z model alone separates poorly (a straight
  /// downward line scores ~0.34, real Zs 0.32-0.59, a still hand ~0.05,
  /// scribbles / horizontal lines ~0.16). It is a sanity floor; the Z itself
  /// is verified geometrically.
  static const double modelFloor = 0.25;

  static const int _minWindow = 8;
  static const int _maxModelChecks = 8;
  static const double _minCover = 0.40; // Z must be >= 40% of the movement

  // Finger states per frame, as for J: tip vs middle (PIP) joint distance to
  // the wrist, which survives tilting the hand.
  static const double _foldedMax = 1.05;
  static const double _extendedMin = 1.10;
  static const double _minIndexFraction = 0.6;
  static const double _minFoldedFraction = 0.5;
  static const List<(int, int, String)> _otherFingers = [
    (12, 10, 'hinlalato'),
    (16, 14, 'palasingsingan'),
    (20, 18, 'kalingkingan'),
  ];

  /// Human-readable details of the last [classifyStroke] call (diagnostics).
  String lastReport = '';

  Future<void> initialize({String modelAssetPath = 'assets/alphabet/fsl_letter_z.onnx'}) async {
    try {
      OrtEnv.instance.init();
      final rawAsset = await rootBundle.load(modelAssetPath);
      _session = OrtSession.fromBuffer(rawAsset.buffer.asUint8List(), OrtSessionOptions());
      _isInitialized = true;
    } catch (e) {
      // The geometric check still works without the model.
      _session = null;
      _isInitialized = true;
      debugPrint('Letter Z model unavailable ($e); using the stroke check only.');
    }
  }

  LetterZResult _fail(String message) =>
      LetterZResult(isLetterZ: false, confidence: 0.0, message: message);

  static double _tipPipRatio(List<LandmarkPoint> f, int tip, int pip) =>
      f[tip].distanceTo(f[0]) / (f[pip].distanceTo(f[0]) + 1e-6);

  /// Per-frame flags: [index extended, middle folded, ring folded, pinky folded].
  static List<bool> _fingerFlags(List<LandmarkPoint> f) => [
        _tipPipRatio(f, indexTip, 6) >= _extendedMin,
        for (final (tip, pip, _) in _otherFingers) _tipPipRatio(f, tip, pip) <= _foldedMax,
      ];

  static List<double> _flagFractions(List<List<LandmarkPoint>> frames) {
    final counts = List<double>.filled(4, 0);
    for (final f in frames) {
      final flags = _fingerFlags(f);
      for (int k = 0; k < 4; k++) {
        if (flags[k]) counts[k]++;
      }
    }
    return [for (final c in counts) c / frames.length];
  }

  String? _shapeProblemFromFractions(List<double> frac) {
    if (frac[0] < _minIndexFraction) return 'Iunat ang hintuturo. Ito ang gamitin sa pagguhit ng Z.';
    final open = [
      for (int k = 0; k < 3; k++)
        if (frac[k + 1] < _minFoldedFraction) _otherFingers[k].$3
    ];
    if (open.isNotEmpty) return 'Itikom ang ${open.join(', ')}. Hintuturo lang ang nakaunat.';
    return null;
  }

  /// Handshape problem for a few live frames (null = index-only handshape).
  String? handShapeProblem(List<List<LandmarkPoint>> frames) =>
      frames.isEmpty ? null : _shapeProblemFromFractions(_flagFractions(frames));

  /// True when a recorded movement is just positioning (raising the hand,
  /// small fidgets) and should be ignored without showing feedback.
  bool isPositioningOnly(List<List<LandmarkPoint>> stroke) {
    if (stroke.length < 2) return true;
    final p = _tipPath(stroke, indexTip, _HandShape.of(stroke).palm);
    final len = LetterJClassifierService._pathLength(p);
    if (len < 1.2) return true;
    final net = p.last - p.first;
    return net.magnitude >= 0.6 * len && net.y <= -0.5 * len; // just raised the hand
  }

  /// Why an index-tip path (selfie view, palm units, relative to its first
  /// point) is not a Z, or null when it is. As the signer sees it: a top
  /// stroke to the right, a diagonal down-left, a bottom stroke to the
  /// right, clearly below the top one. Tolerant of slanted, rounded strokes.
  String? _trajectoryProblem(List<math.Point<double>> p) {
    final a = _arcResample(p, 48);
    double minX = a[0].x, maxX = a[0].x, minY = a[0].y, maxY = a[0].y;
    for (final q in a) {
      minX = math.min(minX, q.x);
      maxX = math.max(maxX, q.x);
      minY = math.min(minY, q.y);
      maxY = math.max(maxY, q.y);
    }
    if (maxX - minX < 0.8 || maxY - minY < 0.6) {
      return 'Masyadong maliit ang iginuhit. Gawing mas malaki ang Z.';
    }
    // Corner 1: right-most point in the first 65% of the path.
    int c1 = 0;
    for (int i = 1; i < 31; i++) {
      if (a[i].x > a[c1].x) c1 = i;
    }
    if (c1 < 4) return 'Simulan ang Z sa guhit pakanan sa itaas.';
    // Corner 2: left-most point after corner 1 (before the last 8%).
    int c2 = c1;
    for (int i = c1 + 1; i < 44; i++) {
      if (c2 == c1 || a[i].x < a[c2].x) c2 = i;
    }
    if (c2 <= c1 + 3 || c2 >= 46) return 'Kulang ang pahilis na guhit pababa-pakaliwa.';

    final s1 = a[c1] - a[0], s2 = a[c2] - a[c1], s3 = a.last - a[c2];
    if (!(s1.x >= 0.5 && s1.y.abs() <= 0.8 * s1.x)) return 'Ang unang guhit ay dapat pakanan sa itaas.';
    if (!(s2.x <= -0.3 && s2.y >= 0.5)) return 'Ang gitnang guhit ay dapat pahilis pababa-pakaliwa.';
    if (!(s3.x >= 0.4 && s3.y.abs() <= 0.8 * s3.x)) return 'Tapusin ang Z sa guhit pakanan sa ibaba.';
    double topY = 0, bottomY = 0;
    for (int i = 0; i <= c1; i++) {
      topY += a[i].y;
    }
    for (int i = c2; i < a.length; i++) {
      bottomY += a[i].y;
    }
    if (bottomY / (a.length - c2) - topY / (c1 + 1) < 0.4) {
      return 'Ang huling guhit ay dapat nasa ibaba ng una.';
    }
    return null;
  }

  /// Searches the movement for Z-shaped segments: the recording usually also
  /// contains raising the hand before the Z and lowering it afterwards.
  ({List<(int, int)> windows, String? problem}) _findZCandidates(List<List<LandmarkPoint>> stroke) {
    final n = stroke.length;
    const short = 'Masyadong maikli ang galaw. Gawin ang buong kumpas ng Letter Z.';
    if (n < _minWindow) return (windows: const <(int, int)>[], problem: short);
    final palm = _HandShape.of(stroke).palm;
    final full = [for (final f in stroke) math.Point(f[indexTip].x / palm, f[indexTip].y / palm)];
    final cum = List<double>.filled(n, 0);
    for (int k = 1; k < n; k++) {
      cum[k] = cum[k - 1] + full[k].distanceTo(full[k - 1]);
    }
    final total = cum[n - 1] + 1e-6;

    final prefix = List.generate(n + 1, (_) => List<int>.filled(4, 0));
    for (int k = 0; k < n; k++) {
      final flags = _fingerFlags(stroke[k]);
      for (int m = 0; m < 4; m++) {
        prefix[k + 1][m] = prefix[k][m] + (flags[m] ? 1 : 0);
      }
    }

    final step = n > 70 ? 2 : 1;
    final windows = <(int, int)>[];
    final reasons = <String, int>{};
    for (int i = 0; i + _minWindow <= n; i += step) {
      for (int j = i + _minWindow; j <= n; j += step) {
        if (cum[j - 1] - cum[i] < _minCover * total) continue;
        if (!LetterJClassifierService._outsideOk(full, i, j)) {
          reasons['outside'] = (reasons['outside'] ?? 0) + 1;
          continue;
        }
        final why = _shapeProblemFromFractions([for (int m = 0; m < 4; m++) (prefix[j][m] - prefix[i][m]) / (j - i)]) ??
            _trajectoryProblem([for (int k = i; k < j; k++) full[k] - full[i]]);
        if (why != null) {
          reasons[why] = (reasons[why] ?? 0) + 1;
          continue;
        }
        windows.add((i, j));
      }
    }
    final ranked = reasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    lastReport = 'segments ${windows.length}; rejected: '
        '${ranked.isEmpty ? '-' : ranked.take(3).map((e) => '${e.key.length > 38 ? '${e.key.substring(0, 38)}…' : e.key} ×${e.value}').join(' | ')}';
    if (windows.isNotEmpty) return (windows: windows, problem: null);
    if (ranked.isEmpty) return (windows: const <(int, int)>[], problem: short);
    final top = ranked.first.key;
    final shape = handShapeProblem(stroke);
    return (
      windows: const <(int, int)>[],
      problem: shape ?? (top == 'outside' ? 'Isang Z lang ang iguhit: itaas ang kamay, iguhit ang Z, saka ibaba.' : top),
    );
  }

  List<List<LandmarkPoint>> _resample(List<List<LandmarkPoint>> raw) {
    final n = raw.length;
    return [
      for (int t = 0; t < targetFrames; t++)
        () {
          final pos = t / (targetFrames - 1) * (n - 1);
          final i0 = pos.floor(), i1 = math.min(i0 + 1, n - 1);
          final w = pos - i0;
          return [
            for (int k = 0; k < 21; k++)
              LandmarkPoint(
                raw[i0][k].x + w * (raw[i1][k].x - raw[i0][k].x),
                raw[i0][k].y + w * (raw[i1][k].y - raw[i0][k].y),
                raw[i0][k].z + w * (raw[i1][k].z - raw[i0][k].z),
              )
          ];
        }()
    ];
  }

  /// The model's 23 features, mirroring the J extractor's layout: finger
  /// extensions, path length, extents, the four stroke deltas, trajectory
  /// spread, mean velocity and velocity spread of the index tip. The model
  /// was trained on the raw (un-mirrored) camera view, where the signer's
  /// rightward top stroke runs towards -x, so x is flipped back here.
  Float32List _extractFeatures(List<List<LandmarkPoint>> frames) {
    final seq = [
      for (final f in _resample(frames)) [for (final p in f) LandmarkPoint(-p.x, p.y, p.z)]
    ];
    final mean = List<LandmarkPoint>.generate(21, (i) {
      double x = 0, y = 0, z = 0;
      for (final f in seq) {
        x += f[i].x;
        y += f[i].y;
        z += f[i].z;
      }
      return LandmarkPoint(x / targetFrames, y / targetFrames, z / targetFrames);
    });
    final palm = mean[middleMcp].distanceTo(mean[wrist]) + 1e-6;
    double ext(int i) => mean[i].distanceTo(mean[wrist]) / palm;
    final idx = ext(indexTip), mid = ext(middleTip), ring = ext(ringTip), pky = ext(pinkyTip);

    final p0 = seq[0][indexTip];
    final traj = [
      for (final f in seq)
        LandmarkPoint((f[indexTip].x - p0.x) / palm, (f[indexTip].y - p0.y) / palm, (f[indexTip].z - p0.z) / palm)
    ];
    final vel = [for (int t = 0; t < targetFrames - 1; t++) traj[t + 1].subtract(traj[t])];
    double disp = 0;
    for (final v in vel) {
      disp += math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    }
    double span(double Function(LandmarkPoint) c) =>
        traj.map(c).reduce(math.max) - traj.map(c).reduce(math.min);
    List<double> meanStd(List<LandmarkPoint> pts, double Function(LandmarkPoint) c) {
      final m = pts.map(c).reduce((a, b) => a + b) / pts.length;
      final v = pts.map((p) => (c(p) - m) * (c(p) - m)).reduce((a, b) => a + b) / pts.length;
      return [m, math.sqrt(v)];
    }

    double cx(LandmarkPoint p) => p.x;
    double cy(LandmarkPoint p) => p.y;
    double cz(LandmarkPoint p) => p.z;
    final f = Float32List(featureDim);
    final values = <double>[
      idx, mid, ring, pky,
      mean[indexTip].distanceTo(mean[indexMcp]) / palm,
      idx / (mid + 1e-6),
      disp,
      span(cx), span(cy),
      math.sqrt(math.pow(traj.last.x, 2) + math.pow(traj.last.y, 2) + math.pow(traj.last.z, 2)),
      traj[9].x - traj[0].x,
      traj[21].x - traj[9].x,
      traj[21].y - traj[9].y,
      traj[31].x - traj[21].x,
      meanStd(traj, cx)[1], meanStd(traj, cy)[1], meanStd(traj, cz)[1],
      meanStd(vel, cx)[0], meanStd(vel, cy)[0], meanStd(vel, cz)[0],
      meanStd(vel, cx)[1], meanStd(vel, cy)[1], meanStd(vel, cz)[1],
    ];
    for (int i = 0; i < featureDim; i++) {
      f[i] = values[i];
    }
    return f;
  }

  /// P(Letter Z) from the model, or null when it is unavailable.
  double? _modelProbability(List<List<LandmarkPoint>> frames) {
    final session = _session;
    if (session == null) return null;
    try {
      final input = OrtValueTensor.createTensorWithDataList(_extractFeatures(frames), [1, featureDim]);
      final runOptions = OrtRunOptions();
      final inputName = session.inputNames.isNotEmpty ? session.inputNames.first : 'float_input';
      final outputs = session.run(runOptions, {inputName: input});
      input.release();
      runOptions.release();
      double p = 0.0;
      if (outputs.length > 1 && outputs[1]?.value is List) {
        final probs = outputs[1]!.value as List<dynamic>;
        if (probs.isNotEmpty && probs[0] is Map) p = ((probs[0] as Map)[1] as num?)?.toDouble() ?? 0.0;
      } else if (outputs.isNotEmpty && outputs[0]?.value is List) {
        p = ((outputs[0]!.value as List)[0] as int) == 1 ? 1.0 : 0.0;
      }
      for (final o in outputs) {
        o?.release();
      }
      return p;
    } catch (e) {
      debugPrint('Letter Z model error: $e');
      return null;
    }
  }

  /// Handshape + Z-shape verdict for a whole movement, without the model:
  /// null when it contains a Z, otherwise the feedback to show.
  String? strokeProblem(List<List<LandmarkPoint>> stroke) {
    lastReport = '';
    return _findZCandidates(stroke).problem;
  }

  LetterZResult classifyStroke(List<List<LandmarkPoint>> recordedFrames) {
    lastReport = '';
    final found = _findZCandidates(recordedFrames);
    if (found.problem != null) return _fail(found.problem!);

    // Score the segments covering the most movement with the model.
    final windows = [...found.windows]..sort((a, b) => (b.$2 - b.$1).compareTo(a.$2 - a.$1));
    double? best;
    (int, int)? bestWindow;
    for (final w in windows.take(_maxModelChecks)) {
      final pr = _modelProbability(recordedFrames.sublist(w.$1, w.$2));
      if (pr == null) break;
      if (best == null || pr > best) {
        best = pr;
        bestWindow = w;
      }
    }
    lastReport += best == null
        ? '; model unavailable'
        : '; best $bestWindow model P(Z)=${best.toStringAsFixed(2)} (min $modelFloor)';
    debugPrint('Letter Z: ${found.windows.length} Z-shaped segments in ${recordedFrames.length} frames$lastReport');

    if (best != null && best < modelFloor) {
      return _fail('Gawing mas malinaw ang Z: hintuturo lang ang nakaunat, pakanan, pahilis pababa, saka pakanan.');
    }
    final score = best == null ? 85.0 : (75.0 + best * 50.0).clamp(80.0, 98.0).toDouble();
    return LetterZResult(
      isLetterZ: true,
      confidence: score,
      message: 'Mahusay! Wastong kumpas at porma para sa Letter Z.',
    );
  }

  void dispose() {
    _session?.release();
    _session = null;
    _isInitialized = false;
  }
}

// =============================================================================
// THEME VISUAL MAPPING
// =============================================================================

/// Thrown to skip the server when the local stroke check already failed.
class _LocalReject implements Exception {
  const _LocalReject();
}

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
  final List<List<LandmarkPoint>> _frameBuffer = []; // current J/Z stroke

  // Dynamic letters (J, Z) are judged once per stroke, like test_single_j.py:
  // a stroke starts when the tracked fingertip moves deliberately and ends
  // when it stays still. (Scoring a sliding window ~20x per second let any
  // movement eventually slip through.)
  final List<List<LandmarkPoint>> _preRoll = [];
  bool _isStroking = false;
  math.Point<double>? _prevTip;
  int _prevTipMs = 0;
  double _tipSpeed = 0.0; // smoothed, palm lengths per second
  int _fastFrames = 0;
  int _idleSinceMs = 0;
  int _strokeStartMs = 0;
  int _lastHandMs = 0;
  int _cooldownUntilMs = 0;
  int _lastResultMs = 0;
  final List<List<LandmarkPoint>> _recentFrames = []; // live handshape check
  String _debugDetails = ''; // shown in debug builds under the feedback
  int _imageWidth = 0, _imageHeight = 0; // raw camera frame size

  // J / Z strokes are judged on Cloud Run (POST /v1/predict_raw/letter_j|z).
  final HandSpeakApiService _api = HandSpeakApiService();
  bool _isEvaluatingStroke = false; // one server request at a time
  static const String _rejectHintJ = "Iguhit ang buong kurba ng J gamit ang hinliliit.";
  static const String _rejectHintZ = "Iguhit ang zig-zag ng Z gamit ang hintuturo.";

  // Orientation of the landmarks, learned from the hand itself: a raised hand
  // points up (wrist -> middle knuckle), so the rotation that makes it point
  // up is the right one. Avoids depending on how a device/plugin reports it.
  final Map<int, double> _uprightVotes = {0: 0, 90: 0, 180: 0, 270: 0};
  int _orientationFrames = 0;
  int? _lockedRotation;

  // Practice-speed signing is slow; Python's start threshold assumes 30 fps
  // quick strokes. Values are palm lengths per second (smoothed).
  static const double _strokeStartSpeed = 1.5;
  static const double _strokeIdleSpeed = 0.7;
  static const int _strokeIdleMs = 450;
  static const int _maxStrokeMs = 3500;
  static const int _handLossMs = 350;
  static const int _preRollFrames = 4;

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
      _imageWidth = image.width;
      _imageHeight = image.height;
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

  // ---------------------------------------------------------------------------
  // Dynamic letters (J, Z)
  // ---------------------------------------------------------------------------

  /// Clockwise image rotation applied to a normalised point.
  static math.Point<double> _rotateUpright(double u, double v, int degrees) {
    switch (((degrees % 360) + 360) % 360) {
      case 90:
        return math.Point(1.0 - v, u);
      case 180:
        return math.Point(1.0 - u, 1.0 - v);
      case 270:
        return math.Point(v, 1.0 - u);
      default:
        return math.Point(u, v);
    }
  }

  int get _handRotation =>
      _lockedRotation ?? (_controller?.description.sensorOrientation ?? 0);

  /// Votes for the rotation under which the hand points up. hand_landmarker
  /// may report landmarks in the raw sensor frame (its example rotates the
  /// canvas by sensorOrientation); this confirms the right rotation per device.
  void _voteOrientation(Hand hand) {
    if (_lockedRotation != null) return;
    final dx = hand.landmarks[9].x - hand.landmarks[0].x;
    final dy = hand.landmarks[9].y - hand.landmarks[0].y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return;
    // Upright y-component of wrist -> middle knuckle for each rotation
    // (negative = pointing up).
    _uprightVotes[0] = _uprightVotes[0]! + dy / len;
    _uprightVotes[90] = _uprightVotes[90]! + dx / len;
    _uprightVotes[180] = _uprightVotes[180]! - dy / len;
    _uprightVotes[270] = _uprightVotes[270]! - dx / len;
    if (++_orientationFrames < 12) return;
    final best = _uprightVotes.entries.reduce((a, b) => a.value <= b.value ? a : b);
    if (best.value / _orientationFrames < -0.5) {
      _lockedRotation = best.key;
      debugPrint('Dynamic letter: hand rotation locked at ${best.key}° '
          '(sensorOrientation ${_controller?.description.sensorOrientation})');
    }
  }

  /// Converts landmarks to the view the Python testers used: upright and
  /// mirrored like a selfie (cv2.flip). x is scaled to true pixel proportions
  /// (x and y are normalised by different frame sides), which is what the
  /// stroke checks are calibrated on.
  List<LandmarkPoint> _toSelfieView(Hand hand) {
    final rotation = _handRotation;
    final bool swap = rotation == 90 || rotation == 270;
    final double w = (swap ? _imageHeight : _imageWidth).toDouble();
    final double h = (swap ? _imageWidth : _imageHeight).toDouble();
    final double s = (w > 0 && h > 0) ? w / h : 1.0;
    return [
      for (final lm in hand.landmarks)
        () {
          final up = _rotateUpright(lm.x, lm.y, rotation);
          final x = 1.0 - up.x;
          return LandmarkPoint(0.5 + (x - 0.5) * s, up.y, lm.z * s);
        }()
    ];
  }

  static double _palm2d(List<LandmarkPoint> pts) =>
      math.sqrt(math.pow(pts[9].x - pts[0].x, 2) + math.pow(pts[9].y - pts[0].y, 2)) + 1e-6;

  void _trackDynamicStroke(List<Hand> hands) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final bool isJ = widget.targetLetter.toUpperCase() == 'J';
    final int tipIdx = isJ ? 20 : 8; // pinky tip draws J, index tip draws Z

    final usable = hands.where((h) => h.landmarks.length == 21).toList();
    if (usable.isEmpty) {
      if (_isStroking) {
        // Tolerate brief tracking drops mid-stroke.
        if (now - _lastHandMs > _handLossMs) _finishStroke(now);
        return;
      }
      _prevTip = null;
      _fastFrames = 0;
      _preRoll.clear();
      if (mounted && _currentScore == 0.0 && _currentFeedback != "Walang kamay na nakikita") {
        setState(() => _currentFeedback = "Walang kamay na nakikita");
      }
      return;
    }
    _lastHandMs = now;
    if (!_isStroking) _voteOrientation(usable.first);

    // Track the closest (largest) hand.
    List<LandmarkPoint> pts = _toSelfieView(usable.first);
    for (final h in usable.skip(1)) {
      final cand = _toSelfieView(h);
      if (_palm2d(cand) > _palm2d(pts)) pts = cand;
    }
    final palm = _palm2d(pts);
    final tip = math.Point(pts[tipIdx].x, pts[tipIdx].y);
    if (_prevTip != null && now > _prevTipMs) {
      final raw = tip.distanceTo(_prevTip!) / palm / ((now - _prevTipMs) / 1000.0);
      _tipSpeed = 0.5 * _tipSpeed + 0.5 * raw;
    }
    _prevTip = tip;
    _prevTipMs = now;

    if (!_isStroking) {
      _preRoll.add(pts);
      if (_preRoll.length > _preRollFrames) _preRoll.removeAt(0);
      if (now < _cooldownUntilMs || _isEvaluatingStroke) return; // wait for the server's verdict
      _fastFrames = _tipSpeed > _strokeStartSpeed ? _fastFrames + 1 : 0;
      if (_fastFrames >= 2) {
        _isStroking = true;
        _strokeStartMs = now;
        _idleSinceMs = 0;
        _frameBuffer
          ..clear()
          ..addAll(_preRoll);
        _preRoll.clear();
        if (mounted) {
          setState(() {
            _currentScore = 0.0;
            _bufferFrameCount = _frameBuffer.length;
            _currentFeedback = isJ ? "Ginuguhit ang J..." : "Ginuguhit ang Z...";
          });
        }
      } else if (mounted && now - _lastResultMs > 2500) {
        // Live status, so it is clear the hand is seen and whether the
        // handshape is accepted before drawing.
        String ready;
        if (isJ) {
          _recentFrames.add(pts);
          if (_recentFrames.length > 8) _recentFrames.removeAt(0);
          final problem = _letterJService.handShapeProblem(_recentFrames);
          ready = problem == null ? "I-handshape ✓  Iguhit na ang J." : "Porma: $problem";
          if (kDebugMode) {
            final live = 'live: ${_letterJService.handShapeSummary(_recentFrames)}\n'
                'rotation $_handRotation${_lockedRotation == null ? ' (checking)' : ' ✓'}';
            if (!_debugDetails.startsWith('attempt') || now - _lastResultMs > 6000) {
              _debugDetails = live;
            }
          }
        } else {
          _recentFrames.add(pts);
          if (_recentFrames.length > 8) _recentFrames.removeAt(0);
          final problem = _letterZService.handShapeProblem(_recentFrames);
          ready = problem == null ? "Hintuturo ✓  Iguhit na ang Z." : "Porma: $problem";
        }
        if (_currentFeedback != ready || kDebugMode) setState(() => _currentFeedback = ready);
      }
      return;
    }

    _frameBuffer.add(pts);
    if (_tipSpeed < _strokeIdleSpeed) {
      if (_idleSinceMs == 0) _idleSinceMs = now;
    } else {
      _idleSinceMs = 0;
    }
    if ((_idleSinceMs != 0 && now - _idleSinceMs >= _strokeIdleMs) ||
        now - _strokeStartMs >= _maxStrokeMs) {
      _finishStroke(now);
      return;
    }
    if (mounted) {
      setState(() => _bufferFrameCount = math.min(_frameBuffer.length, _requiredBufferFrames - 1));
    }
  }

  /// Judges one complete stroke exactly once.
  void _finishStroke(int now) {
    _isStroking = false;
    _fastFrames = 0;
    _cooldownUntilMs = now + 700;
    final stroke = List<List<LandmarkPoint>>.of(_frameBuffer);
    _frameBuffer.clear();
    _bufferFrameCount = 0;

    final bool isJ = widget.targetLetter.toUpperCase() == 'J';
    // Just raising the hand / fidgeting (local check): wait for the real stroke silently.
    if (isJ ? _letterJService.isPositioningOnly(stroke) : _letterZService.isPositioningOnly(stroke)) {
      _cooldownUntilMs = 0;
      if (mounted) setState(() {});
      return;
    }
    if (kDebugMode && isJ) {
      // Full recording (selfie-view coordinates) so the attempt can be replayed offline.
      debugPrint('J_STROKE ${jsonEncode([
            for (final f in stroke) [for (final p in f) ...[p.x, p.y, p.z].map((v) => double.parse(v.toStringAsFixed(4)))]
          ])}');
    }
    unawaited(_evaluateStrokeOnServer(stroke, isJ));
  }

  /// Undoes [_toSelfieView]'s aspect stretch so the server receives plain
  /// MediaPipe-normalised coordinates of the upright frame, plus that frame's
  /// size (the server applies the aspect correction itself; sending the
  /// already-stretched x would apply it twice). The selfie mirror is kept:
  /// the jz-v2 features are identical for mirrored and unmirrored strokes.
  ({List<List<List<double>>> frames, int width, int height}) _strokeForServer(List<List<LandmarkPoint>> stroke) {
    final rotation = _handRotation;
    final bool swap = rotation == 90 || rotation == 270;
    final int w = swap ? _imageHeight : _imageWidth;
    final int h = swap ? _imageWidth : _imageHeight;
    final double s = (w > 0 && h > 0) ? w / h : 1.0;
    return (
      frames: [
        for (final f in stroke) [for (final p in f) [0.5 + (p.x - 0.5) / s, p.y, p.z / s]]
      ],
      width: w > 0 ? w : 1,
      height: h > 0 ? h : 1,
    );
  }

  /// Sends one finished J / Z stroke to POST /v1/predict_raw/letter_j|z.
  /// accepted (P(letter) >= 0.25) -> success; otherwise the letter's hint.
  Future<void> _evaluateStrokeOnServer(List<List<LandmarkPoint>> stroke, bool isJ) async {
    if (_isEvaluatingStroke || _isSuccessAchieved) return;
    _isEvaluatingStroke = true;
    final letter = isJ ? 'J' : 'Z';
    final hint = isJ ? _rejectHintJ : _rejectHintZ;
    if (mounted) setState(() => _currentFeedback = "Sinusuri ang Letter $letter...");
    double score = 0.0;
    String feedback = hint;
    try {
      // The server model alone accepts almost any index-finger movement for
      // Z (threshold 0.25). The stroke must first contain an actual Z with an
      // index-only handshape; only then is the server asked.
      if (!isJ) {
        final problem = _letterZService.strokeProblem(stroke);
        if (problem != null) {
          feedback = problem;
          _debugDetails = 'attempt: ${stroke.length} frames -> local Z check fail\n${_letterZService.lastReport}';
          throw const _LocalReject();
        }
      }
      final req = _strokeForServer(stroke);
      final r = isJ
          ? await _api.predictRawLetterJ(frames: req.frames, imageWidth: req.width, imageHeight: req.height)
          : await _api.predictRawLetterZ(frames: req.frames, imageWidth: req.width, imageHeight: req.height);
      if (r.accepted) {
        // Display score as before (clip(prob * 100, 75, 99)); >= successThreshold triggers success.
        score = (r.confidence * 100.0).clamp(75.0, 99.0).toDouble();
        feedback = "Tama ang Letter $letter!";
      }
      _debugDetails = 'attempt: ${stroke.length} frames (${req.width}x${req.height}), rotation $_handRotation'
          '${_lockedRotation == null ? ' (unconfirmed)' : ''} -> server ${r.accepted ? 'PASS' : 'fail'} '
          'P($letter)=${r.confidence.toStringAsFixed(3)} (threshold ${r.threshold})'
          '${isJ ? '' : '\nlocal: ${_letterZService.lastReport}'}';
    } on _LocalReject {
      // feedback / _debugDetails already set by the local check.
    } on ArgumentError catch (e) {
      // Rejected by the API client before upload (e.g. too few frames).
      _debugDetails = 'attempt: ${stroke.length} frames, not sent: ${e.message}';
    } on HandSpeakApiException catch (e) {
      feedback = e.isAuthError ? "Mag-sign in muli para masuri ang kumpas." : "Hindi masuri ang kumpas. Subukang muli.";
      _debugDetails = 'server error: $e';
    } catch (e) {
      feedback = "Walang koneksyon sa server. Subukang muli.";
      _debugDetails = 'network error: $e';
    } finally {
      _isEvaluatingStroke = false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastResultMs = now;
    _cooldownUntilMs = now + 700;
    debugPrint('Dynamic letter $letter: ${stroke.length} frames -> ${score > 0 ? 'PASS' : 'fail'} ($feedback)');
    if (!mounted || _isSuccessAchieved) return;
    _updateGameLogic(score, feedback);
  }

  void _onHandsDetected(List<Hand> detectedHands) async {
    if (_isSuccessAchieved || _isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      if (_isDynamicLetter) {
        _trackDynamicStroke(detectedHands);
        return;
      }
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
                    if (kDebugMode && _isDynamicLetter && _debugDetails.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _debugDetails,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
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