import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hand_landmarker/hand_landmarker.dart';

import '/module/alphabet/tutorial_practice.dart'
    show LandmarkPoint, LetterJClassifierService, LetterZClassifierService;
import '/module/numbers/numbers_tutorial_practice.dart' show FSLOnnxService, BaseShapeVerifier;
import 'handspeak_api_service.dart';

/// Result of judging one recorded moving sign.
class DynamicVerdict {
  final bool isCorrect;
  final double score; // 0..100
  final String feedback;

  /// The model file(s) that judged it (gesture_attempts `modelVersion`).
  final String model;
  final String? predicted;
  final double? confidence; // 0..1
  final int frames;

  const DynamicVerdict({
    required this.isCorrect,
    required this.score,
    required this.feedback,
    required this.model,
    this.predicted,
    this.confidence,
    this.frames = 0,
  });
}

/// The tutorial practices' moving-sign checks, for screens that record the
/// last seconds of hand frames and judge them on demand (activities, solo
/// challenge, Arena game):
///  * Letters J / Z: the J / Z stroke checks with assets/alphabet/
///    fsl_letter_j.onnx / fsl_letter_z.onnx (on device), then the server's
///    /v1/predict_raw/letter_j|z, exactly like TutorialPractice.
///  * Numbers 11-100: the decade model assets/numbers/fsl_numbers_*.onnx
///    (+ base-shape check), exactly like NumbersTutorialPractice.
class DynamicSignJudge {
  /// Recent frames: raw hand_landmarker points of the first hand, with time.
  final List<({int t, List<Landmark> lms})> _frames = [];
  int _imageWidth = 0, _imageHeight = 0, _liveRotation = 0;

  static const int _windowMs = 4000;

  static LetterJClassifierService? _j;
  static LetterZClassifierService? _z;
  static Future<void>? _jzLoad;

  bool get hasFrames => _frames.isNotEmpty;
  int get frameCount => _frames.length;

  void clear() => _frames.clear();

  /// Call for every hand_landmarker result while the sign is on screen.
  void addFrame(List<Hand> hands, {required int imageWidth, required int imageHeight, required int rotation}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _imageWidth = imageWidth;
    _imageHeight = imageHeight;
    _liveRotation = rotation;
    final usable = hands.where((h) => h.landmarks.length == 21).toList();
    if (usable.isNotEmpty) _frames.add((t: now, lms: usable.first.landmarks));
    _frames.removeWhere((f) => now - f.t > _windowMs);
  }

  /// Loads the J / Z models ahead of time (and the decade model for [number]).
  static Future<void> prepare({bool letters = false, int? number}) async {
    if (letters) {
      _jzLoad ??= () async {
        final j = LetterJClassifierService(), z = LetterZClassifierService();
        await j.initialize();
        await z.initialize();
        _j = j;
        _z = z;
      }();
      await _jzLoad;
    }
    if (number != null && number >= 11) {
      BaseShapeVerifier.load();
      await FSLOnnxService.loadModelForTarget(number);
    }
  }

  // ---------------------------------------------------------------------------
  // Orientation: hand_landmarker may report points in the sideways sensor
  // frame; the rotation that makes wrist -> middle knuckle point up wins.
  // ---------------------------------------------------------------------------

  int _rotation() {
    final votes = {0: 0.0, 90: 0.0, 180: 0.0, 270: 0.0};
    var n = 0;
    for (final f in _frames) {
      final dx = f.lms[9].x - f.lms[0].x, dy = f.lms[9].y - f.lms[0].y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) continue;
      votes[0] = votes[0]! + dy / len;
      votes[90] = votes[90]! + dx / len;
      votes[180] = votes[180]! - dy / len;
      votes[270] = votes[270]! - dx / len;
      n++;
    }
    if (n < 6) return _liveRotation;
    final best = votes.entries.reduce((a, b) => a.value <= b.value ? a : b);
    return best.value / n < -0.5 ? best.key : _liveRotation;
  }

  static (double, double) _upright(double u, double v, int degrees) => switch (((degrees % 360) + 360) % 360) {
        90 => (1.0 - v, u),
        180 => (1.0 - u, 1.0 - v),
        270 => (v, 1.0 - u),
        _ => (u, v),
      };

  (double w, double h) _uprightSize(int rotation) {
    final swap = rotation == 90 || rotation == 270;
    return ((swap ? _imageHeight : _imageWidth).toDouble(), (swap ? _imageWidth : _imageHeight).toDouble());
  }

  // ---------------------------------------------------------------------------
  // Letters J / Z
  // ---------------------------------------------------------------------------

  /// Same view as TutorialPractice._toSelfieView: upright, mirrored like a
  /// selfie, x scaled to true pixel proportions.
  List<List<LandmarkPoint>> _selfieStroke(int rotation) {
    final (w, h) = _uprightSize(rotation);
    final s = (w > 0 && h > 0) ? w / h : 1.0;
    return [
      for (final f in _frames)
        [
          for (final lm in f.lms)
            () {
              final (ux, uy) = _upright(lm.x, lm.y, rotation);
              return LandmarkPoint(0.5 + ((1.0 - ux) - 0.5) * s, uy, lm.z * s);
            }()
        ]
    ];
  }

  Future<DynamicVerdict> judgeLetter(String letter) async {
    final isJ = letter.toUpperCase() == 'J';
    final model = isJ ? 'assets/alphabet/fsl_letter_j.onnx' : 'assets/alphabet/fsl_letter_z.onnx';
    final hint = isJ
        ? 'Gawing mas malinaw ang J: kalingkingan lang ang nakataas, pababa, saka ikurba.'
        : 'Iguhit ang Z gamit ang hintuturo: pakanan, pababang pahilis, saka pakanan.';
    if (_frames.length < 8) {
      return DynamicVerdict(isCorrect: false, score: 0, feedback: 'Gawin ang buong galaw ng Letter $letter sa harap ng camera.', model: model, frames: _frames.length);
    }
    await prepare(letters: true);
    final rotation = _rotation();
    final stroke = _selfieStroke(rotation);

    // 1. On-device check with the letter's ONNX model (as in the tutorial).
    double localConf = 0;
    if (isJ) {
      final local = _j!.classifyStroke(stroke);
      if (!local.isLetterJ) {
        return DynamicVerdict(isCorrect: false, score: local.confidence * 60, feedback: local.message, model: model,
            confidence: local.confidence, frames: stroke.length);
      }
      localConf = local.confidence;
    } else {
      final problem = _z!.strokeProblem(stroke);
      if (problem != null) {
        return DynamicVerdict(isCorrect: false, score: 20, feedback: problem, model: model, frames: stroke.length);
      }
      localConf = _z!.classifyStroke(stroke).confidence;
    }

    // 2. Server check (POST /v1/predict_raw/letter_j|z), as in the tutorial.
    final (w, h) = _uprightSize(rotation);
    final s = (w > 0 && h > 0) ? w / h : 1.0;
    final frames = [
      for (final f in stroke) [for (final p in f) [0.5 + (p.x - 0.5) / s, p.y, p.z / s]]
    ];
    try {
      final api = HandSpeakApiService();
      final r = isJ
          ? await api.predictRawLetterJ(frames: frames, imageWidth: w > 0 ? w.round() : 1, imageHeight: h > 0 ? h.round() : 1)
          : await api.predictRawLetterZ(frames: frames, imageWidth: w > 0 ? w.round() : 1, imageHeight: h > 0 ? h.round() : 1);
      return DynamicVerdict(
        isCorrect: r.accepted,
        score: r.accepted ? (r.confidence * 100).clamp(75.0, 99.0).toDouble() : r.confidence * 60,
        feedback: r.accepted ? 'Tama ang Letter $letter!' : hint,
        model: '$model + server letter_${letter.toLowerCase()}',
        predicted: r.accepted ? letter.toUpperCase() : null,
        confidence: r.confidence,
        frames: stroke.length,
      );
    } catch (e) {
      // Offline / no session: the on-device model already passed the stroke.
      debugPrint('[DynamicSignJudge] letter $letter server check unavailable: $e');
      return DynamicVerdict(
        isCorrect: true,
        score: (localConf * 100).clamp(75.0, 99.0).toDouble(),
        feedback: 'Tama ang Letter $letter!',
        model: model,
        predicted: letter.toUpperCase(),
        confidence: localConf,
        frames: stroke.length,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Numbers 11-100
  // ---------------------------------------------------------------------------

  static const double _trainingAspect = 1.6; // NumbersTutorialPractice._trainingAspect

  /// Same space as NumbersTutorialPractice._toTrainingSpace: upright, not
  /// mirrored, x / z rescaled to the landscape training frame.
  List<List<double>> _trainingClip(int rotation) {
    final (w, h) = _uprightSize(rotation);
    final s = (w > 0 && h > 0) ? (w / h) / _trainingAspect : 1.0;
    return [
      for (final f in _frames)
        [
          for (final lm in f.lms) ...() {
            final (ux, uy) = _upright(lm.x, lm.y, rotation);
            return [0.5 + (ux - 0.5) * s, uy, lm.z * s];
          }()
        ]
    ];
  }

  static String modelFileFor(int number) {
    final g = FSLOnnxService.groupForNumber(number);
    const files = {
      1: 'fsl_numbers_11_20.onnx', 2: 'fsl_numbers_20_30.onnx', 3: 'fsl_numbers_31_40.onnx', 4: 'fsl_numbers_41_50.onnx',
      5: 'fsl_numbers_51_60.onnx', 6: 'fsl_numbers_61_70.onnx', 7: 'fsl_numbers_71_80.onnx', 8: 'fsl_numbers_81_90.onnx',
      9: 'fsl_numbers_91_100.onnx',
    };
    return 'assets/numbers/${files[g]}';
  }

  Future<DynamicVerdict> judgeNumber(int number) async {
    final model = modelFileFor(number);
    if (_frames.length < 12) {
      return DynamicVerdict(isCorrect: false, score: 0, model: model, frames: _frames.length,
          feedback: 'Masyadong mabilis. Hawakan ang unang porma, gumalaw, saka hawakan ang huling porma.');
    }
    await prepare(number: number);
    if (!FSLOnnxService.isReadyFor(number)) {
      return DynamicVerdict(isCorrect: false, score: 0, model: model, frames: _frames.length,
          feedback: 'Hindi ma-load ang modelo para sa Number $number. Subukang muli.');
    }
    try {
      final clip24 = FSLOnnxService.resampleTo24(_trainingClip(_rotation()));
      final r = FSLOnnxService.evaluateWithModel(
        targetNumber: number,
        window24Frames: clip24,
        kineticEnergy: FSLOnnxService.computeKineticEnergy(clip24),
      );
      return DynamicVerdict(
        isCorrect: r.isCorrect,
        score: r.accuracyScore,
        feedback: r.feedback,
        model: model,
        predicted: r.detectedNumber?.toString(),
        frames: _frames.length,
      );
    } catch (e) {
      debugPrint('[DynamicSignJudge] number $number: $e');
      return DynamicVerdict(isCorrect: false, score: 0, model: model, frames: _frames.length,
          feedback: 'Hindi masuri ang kumpas. Subukang muli.');
    }
  }
}

// =============================================================================
// STATIC LETTER CHECKS (shared by tutorial practice, activities and games)
// =============================================================================

double _wrap(double a) => math.atan2(math.sin(a), math.cos(a));

/// Hand measurements for the static letter rules (selfie-view points, palm
/// = wrist -> middle knuckle). Mirror-independent.
class _HandGeometry {
  final List<LandmarkPoint> p;
  late final double palm = p[9].distanceTo(p[0]) + 1e-6;
  _HandGeometry(this.p);

  /// Where the thumb tip sits across the knuckles: 0 = index knuckle,
  /// 1 = pinky knuckle, < 0 = beside the index (A).
  late final double thumbAcross = () {
    final ax = p[17].x - p[5].x, ay = p[17].y - p[5].y;
    final len2 = ax * ax + ay * ay + 1e-9;
    return ((p[4].x - p[5].x) * ax + (p[4].y - p[5].y) * ay) / len2;
  }();

  /// Camera depth of the thumb vs the middle finger (logged only: measured
  /// +-0.05 for every sign on a phone, 2026-10-25).
  late final double thumbFront = (p[10].z - p[4].z) / palm;

  /// Angle between the index and middle fingers (degrees): U ~0-8, V 20+.
  late final double indexMiddleAngle = () {
    final a = math.atan2(p[8].y - p[5].y, p[8].x - p[5].x);
    final b = math.atan2(p[12].y - p[9].y, p[12].x - p[9].x);
    return (_wrap(a - b).abs()) * 180 / math.pi;
  }();

  /// Index tip minus middle tip along the knuckle line (index side
  /// positive), in palm units: < 0 means the fingers are crossed (R).
  late final double indexMiddleCross = () {
    final ax = p[5].x - p[17].x, ay = p[5].y - p[17].y;
    final len = math.sqrt(ax * ax + ay * ay) + 1e-9;
    return ((p[8].x - p[12].x) * ax + (p[8].y - p[12].y) * ay) / len / palm;
  }();

  /// Mean fingertip distance from the wrist: flat B ~1.9, curved C ~1.5.
  late final double fingerReach =
      (p[8].distanceTo(p[0]) + p[12].distanceTo(p[0]) + p[16].distanceTo(p[0]) + p[20].distanceTo(p[0])) / 4 / palm;

  /// How far the index middle joint rises past its knuckle (X ~0.4+, T ~0.1).
  late final double indexRise = (p[6].distanceTo(p[0]) - p[5].distanceTo(p[0])) / palm;
}

/// Checks on top of the template match that stop look-alike letters from
/// passing (B for C, E for F, K for the peace sign, M for N, ...). One
/// instance per screen; it follows the letter being judged.
///
///  * G, H, K, P, Q: finger states and pointing direction (+ K / P / Q
///    look-alike rules);
///  * A-Y in [_fingerStates]: finger states plus a thumb / spacing rule;
///  * M, N, S, T: the hand must match the target's template better than its
///    look-alikes' templates (no single distance separates them).
///
/// A letter passes the check when most of the last 5 frames are right, so
/// one noisy frame does not reset a hold.
class StaticLetterChecker {
  final List<bool> _history = [];
  String _letter = '';
  String? _lastProblem;
  int _lastLogMs = 0;

  static const Map<String, ({bool middleUp, bool middleFolded, String dir})> _trickyShapes = {
    'G': (middleUp: false, middleFolded: true, dir: 'side'),
    'H': (middleUp: true, middleFolded: false, dir: 'side'),
    'K': (middleUp: false, middleFolded: false, dir: 'up'),
    'P': (middleUp: false, middleFolded: false, dir: 'down'),
    'Q': (middleUp: false, middleFolded: true, dir: 'down'),
  };

  /// Finger states per letter, index-middle-ring-pinky: S = straight,
  /// B = bent / folded, C = curved (half bent), - = any.
  static const Map<String, String> _fingerStates = {
    'A': 'BBBB', 'B': 'SSSS', 'C': 'CCCC', 'D': 'SBBB', 'E': 'BBBB', 'F': 'BSSS',
    'I': 'BBBS', 'L': 'SBBB', 'O': 'CCCC', 'R': 'SSBB',
    'U': 'SSBB', 'V': 'SSBB', 'W': 'SSSB', 'X': 'CBBB',
    'Y': 'BBBS',
  };

  /// M, N, S, T and the look-alikes their template must beat. Template
  /// scores against each other: M-N 93.5, S-A 91.7, T vs the rest <= 77.
  static const Map<String, List<String>> _rivalLetters = {
    'M': ['N', 'S', 'A', 'T', 'E'],
    'N': ['M', 'S', 'A', 'T', 'E'],
    'S': ['M', 'N', 'A', 'T', 'E', 'O'],
    'T': ['M', 'N', 'S', 'A', 'O', 'F'],
  };
  static const double _rivalMargin = 0.5;
  static final Map<String, List<dynamic>> _bundled = {};
  static final Set<String> _loading = {};

  static bool appliesTo(String letter) {
    final l = letter.toUpperCase();
    return _trickyShapes.containsKey(l) || _fingerStates.containsKey(l) || _rivalLetters.containsKey(l);
  }

  void reset() {
    _history.clear();
    _lastProblem = null;
  }

  /// Feedback when the hand is not [letter] yet (null = fine), smoothed over
  /// the last 5 frames. [rotation] / image size: as given to processFrame.
  String? check(Hand hand, String letter, {required int imageWidth, required int imageHeight, required int rotation}) {
    final l = letter.toUpperCase();
    if (l != _letter) {
      _letter = l;
      reset();
    }
    if (!appliesTo(l) || hand.landmarks.length < 21) return null;
    final problem = _rivalLetters.containsKey(l)
        ? _rivalProblem(hand.landmarks, l)
        : _shapeProblem(_selfieView(hand.landmarks, imageWidth, imageHeight, rotation), l);
    if (problem != null) _lastProblem = problem;
    _history.add(problem == null);
    if (_history.length > 5) _history.removeAt(0);
    final ok = _history.where((v) => v).length;
    return ok * 2 <= _history.length ? _lastProblem : null;
  }

  // ---------------------------------------------------------------------------

  /// Upright, selfie-mirrored, aspect-corrected points (the view the rules
  /// were measured in).
  static List<LandmarkPoint> _selfieView(List<Landmark> lms, int imageWidth, int imageHeight, int rotation) {
    final r = ((rotation % 360) + 360) % 360;
    final swap = r == 90 || r == 270;
    final w = (swap ? imageHeight : imageWidth).toDouble();
    final h = (swap ? imageWidth : imageHeight).toDouble();
    final s = (w > 0 && h > 0) ? w / h : 1.0;
    return [
      for (final lm in lms)
        () {
          final (ux, uy) = switch (r) {
            90 => (1.0 - lm.y, lm.x),
            180 => (1.0 - lm.x, 1.0 - lm.y),
            270 => (lm.y, 1.0 - lm.x),
            _ => (lm.x, lm.y),
          };
          final x = 1.0 - ux;
          return LandmarkPoint(0.5 + (x - 0.5) * s, uy, lm.z * s);
        }()
    ];
  }

  void _log(String Function() text) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastLogMs < 700) return;
    _lastLogMs = now;
    debugPrint(text());
  }

  String? _shapeProblem(List<LandmarkPoint> p, String letter) {
    double ratio(int tip, int pip) => p[tip].distanceTo(p[0]) / (p[pip].distanceTo(p[0]) + 1e-6);
    final palm = p[9].distanceTo(p[0]) + 1e-6;
    double d(int a, int b) => p[a].distanceTo(p[b]) / palm;

    final spec = _trickyShapes[letter];
    if (spec != null) {
      bool extended(int tip, int pip) => ratio(tip, pip) >= 1.10;
      bool folded(int tip, int pip) => ratio(tip, pip) <= 1.05;
      if (!extended(8, 6)) return 'Iunat ang hintuturo para sa Letter $letter.';
      if (spec.middleUp && !extended(12, 10)) return 'Iunat din ang hinlalato para sa Letter $letter.';
      final mustFold = [
        if (spec.middleFolded && !folded(12, 10)) 'hinlalato',
        if (!folded(16, 14)) 'palasingsingan',
        if (!folded(20, 18)) 'kalingkingan',
      ];
      if (mustFold.isNotEmpty) return 'Itikom ang ${mustFold.join(', ')} para sa Letter $letter.';

      // Pointing direction of the index finger (knuckle -> tip), y points down.
      final dx = p[8].x - p[5].x, dy = p[8].y - p[5].y;
      final ax = dx.abs(), ay = dy.abs();
      const tan50 = 1.19;
      switch (spec.dir) {
        case 'side':
          if (ay > ax * tan50) return 'Itagilid ang kamay: pahalang dapat ang hintuturo.';
        case 'up':
          if (!(dy < 0 && ax <= ay * tan50)) return 'Ituro pataas ang hintuturo para sa Letter $letter.';
        case 'down':
          if (!(dy > 0 && ax <= ay * tan50)) return 'Ituro pababa ang hintuturo para sa Letter $letter.';
      }

      final middleOut = d(12, 9); // middle tip -> its knuckle: ~0.4 folded, 0.7+ out
      _log(() => 'Letter $letter shape: middleOut=${middleOut.toStringAsFixed(2)} thumb-midjoint=${d(4, 10).toStringAsFixed(2)} '
          'thumb-ringjoint=${d(4, 14).toStringAsFixed(2)} thumbOut=${d(4, 5).toStringAsFixed(2)}');
      switch (letter) {
        case 'K': // middle out (L, D fold it), thumb on the middle finger (peace sign: on the ring)
          if (middleOut < 0.65) return 'Iunat din ang hinlalato para sa Letter K.';
          if (d(4, 10) > 0.60 || d(4, 10) > d(4, 14)) {
            return 'Ilagay ang hinlalaki sa pagitan ng hintuturo at hinlalato para sa Letter K.';
          }
        case 'P': // the middle finger sticks out downward (Q folds it)
          if (middleOut < 0.65) return 'Iunat din ang hinlalato pababa para sa Letter P.';
          if (d(4, 10) > 0.65) return 'Idikit ang hinlalaki sa hinlalato para sa Letter P.';
        case 'Q': // index and thumb point down together, middle folded (P sticks it out)
          if (middleOut > 0.55) return 'Itikom ang hinlalato para sa Letter Q.';
          if (d(4, 5) < 0.55 || p[4].y <= p[2].y) return 'Ituro pababa ang hinlalaki kasama ang hintuturo para sa Letter Q.';
      }
      return null;
    }

    final states = _fingerStates[letter];
    if (states == null) return null;
    const fingers = [(8, 6, 'hintuturo'), (12, 10, 'hinlalato'), (16, 14, 'palasingsingan'), (20, 18, 'kalingkingan')];
    final thumbIndex = d(4, 8);
    final thumbOut = d(4, 5); // thumb tip -> index knuckle
    final g = _HandGeometry(p);
    _log(() => 'Letter $letter shape: idx=${ratio(8, 6).toStringAsFixed(2)} mid=${ratio(12, 10).toStringAsFixed(2)} '
        'ring=${ratio(16, 14).toStringAsFixed(2)} pinky=${ratio(20, 18).toStringAsFixed(2)} '
        'thumb-index=${thumbIndex.toStringAsFixed(2)} thumb-out=${thumbOut.toStringAsFixed(2)} '
        'thumb-midjoint=${d(4, 10).toStringAsFixed(2)} index-middle=${d(8, 12).toStringAsFixed(2)} '
        'thumbAcross=${g.thumbAcross.toStringAsFixed(2)} thumbFront=${g.thumbFront.toStringAsFixed(2)} '
        'spread=${g.indexMiddleAngle.toStringAsFixed(0)}deg cross=${g.indexMiddleCross.toStringAsFixed(2)} '
        'reach=${g.fingerReach.toStringAsFixed(2)} idxRise=${g.indexRise.toStringAsFixed(2)}');

    // 1. Finger states. A finger's bend is tip-to-wrist / middle-joint-to-
    // wrist: > 1.10 straight, < 1.0 bent.
    final toStraighten = <String>[], toBend = <String>[], toCurve = <String>[];
    for (int i = 0; i < 4; i++) {
      final r = ratio(fingers[i].$1, fingers[i].$2);
      switch (states[i]) {
        case 'S':
          if (r < 1.10) toStraighten.add(fingers[i].$3);
        case 'B':
          if (r > 1.0) toBend.add(fingers[i].$3);
        case 'C':
          if (r >= 1.18) toCurve.add(fingers[i].$3);
          if (r < 0.85) toStraighten.add(fingers[i].$3);
      }
    }
    if (toBend.isNotEmpty) return 'Ibaluktot ang ${toBend.join(', ')} para sa Letter $letter.';
    if (toStraighten.isNotEmpty) return 'Iunat ang ${toStraighten.join(', ')} para sa Letter $letter.';
    if (toCurve.isNotEmpty) return 'Bahagyang ibaluktot ang ${toCurve.join(', ')} para sa Letter $letter.';

    // 2. Thumb / spacing rules that tell look-alikes apart.
    switch (letter) {
      case 'A': // thumb at the side of the index finger, not across / under (S, M, N)
        if (d(4, 10) < 0.45 || g.thumbAcross > 0.12) return 'Ilagay ang hinlalaki sa gilid ng kamao para sa Letter A.';
      case 'B': // flat, fully straight fingers (C is curved) and the thumb folded in
        if (g.fingerReach < 1.70) return 'Iunat nang tuwid ang lahat ng daliri para sa Letter B.';
        if (d(4, 9) > 0.65) return 'Itiklop ang hinlalaki sa palad para sa Letter B.';
      case 'X': // index raised and hooked (T folds it down over the thumb)
        if (g.indexRise < 0.30) return 'Itaas at ikawit ang hintuturo para sa Letter X.';
      case 'C': // open curve: a gap between thumb and fingers
        if (thumbIndex < 0.40) return 'Bahagyang ibuka: may puwang dapat ang hinlalaki at mga daliri (Letter C).';
        if (thumbIndex > 1.50) return 'Ilapit nang kaunti ang hinlalaki sa mga daliri para sa Letter C.';
      case 'D': // thumb touches the middle finger
        if (d(4, 12) > 0.55) return 'Idikit ang hinlalaki sa hinlalato para sa Letter D.';
      case 'E': // tips rest on the thumb, not a tight fist (S)
        if ([d(4, 8), d(4, 12), d(4, 16)].reduce(math.min) > 0.55) {
          return 'Ilapit ang dulo ng mga daliri sa hinlalaki para sa Letter E.';
        }
        if ((d(8, 0) + d(12, 0) + d(16, 0) + d(20, 0)) / 4 < 0.95) {
          return 'Huwag isara nang buo ang kamao: nakapatong ang mga daliri sa hinlalaki (Letter E).';
        }
      case 'F': // thumb and index tips touch (the circle)
        if (thumbIndex > 0.35) return 'Pagdikitin ang dulo ng hinlalaki at hintuturo para sa Letter F.';
      case 'L':
      case 'Y': // thumb sticks out
        if (thumbOut < 0.75) return 'Iunat palabas ang hinlalaki para sa Letter $letter.';
      case 'O': // thumb and fingertips meet
        if (thumbIndex > 0.40) return 'Pagdikitin ang hinlalaki at mga daliri para bumuo ng bilog (Letter O).';
      case 'R': // index and middle crossed: the tips swap sides
        if (g.indexMiddleCross > 0.02) return 'Ipag-krus ang hintuturo at hinlalato para sa Letter R.';
      case 'U': // index and middle straight, together and not crossed
        if (g.indexMiddleAngle > 12 || d(8, 12) > 0.40) return 'Pagdikitin ang hintuturo at hinlalato para sa Letter U.';
        if (g.indexMiddleCross < 0.0) return 'Huwag ipag-krus ang mga daliri para sa Letter U.';
      case 'V': // index and middle apart
        if (g.indexMiddleAngle < 18 || d(8, 12) < 0.45) return 'Ibuka ang hintuturo at hinlalato para sa Letter V.';
    }
    return null;
  }

  /// Bundled templates (assets/alphabet/<L>.json) of the letter and its
  /// look-alikes, so every compared template comes from one set (offline).
  static Future<void> _loadRivals(String letter) async {
    if (!_loading.add(letter)) return;
    for (final r in [letter, ...?_rivalLetters[letter]]) {
      if (_bundled.containsKey(r)) continue;
      try {
        _bundled[r] = jsonDecode(await rootBundle.loadString('assets/alphabet/$r.json')) as List<dynamic>;
      } catch (e) {
        debugPrint('No look-alike template for $r: $e');
      }
    }
  }

  String? _rivalProblem(List<Landmark> lms, String letter) {
    final own = _bundled[letter];
    if (own == null) {
      unawaited(_loadRivals(letter)); // ready in a moment; until then no extra check
      return null;
    }
    final target = templateScore(lms, own);
    String? bestRival;
    double rivalScore = 0;
    for (final r in _rivalLetters[letter]!) {
      final t = _bundled[r];
      if (t == null) continue;
      final sc = templateScore(lms, t);
      if (sc > rivalScore) {
        rivalScore = sc;
        bestRival = r;
      }
    }
    _log(() => 'Letter $letter rivals: target=${target.toStringAsFixed(1)} best rival=$bestRival ${rivalScore.toStringAsFixed(1)}');
    if (bestRival == null || target >= rivalScore + _rivalMargin) return null;
    return 'Mukhang Letter $bestRival ito. Tingnan muli ang larawan ng Letter $letter, lalo na ang hinlalaki.';
  }

  /// The regular (non G / H / K / P / Q) template score, as in every
  /// screen's _calculateScore: 3D, best of the 8 orientations / mirrors.
  static double templateScore(List<Landmark> lms, List<dynamic> template) {
    if (lms.length < 21 || template.length < 21) return 0.0;
    final wrist = lms[0], mBase = lms[9];
    var dist = math.sqrt(math.pow(wrist.x - mBase.x, 2) + math.pow(wrist.y - mBase.y, 2) + math.pow(wrist.z - mBase.z, 2));
    if (dist == 0) dist = 1.0;
    const orientations = [
      [1.0, 0.0, 0.0, 1.0, 1.0], [0.0, -1.0, 1.0, 0.0, 1.0], [-1.0, 0.0, 0.0, -1.0, 1.0], [0.0, 1.0, -1.0, 0.0, 1.0],
      [1.0, 0.0, 0.0, 1.0, -1.0], [0.0, -1.0, 1.0, 0.0, -1.0], [-1.0, 0.0, 0.0, -1.0, -1.0], [0.0, 1.0, -1.0, 0.0, -1.0],
    ];
    double best = 0.0;
    for (final m in orientations) {
      double total = 0.0;
      for (int i = 0; i < 21; i++) {
        final dx = (lms[i].x - wrist.x) / dist * m[4];
        final dy = (lms[i].y - wrist.y) / dist;
        final dz = (lms[i].z - wrist.z) / dist;
        final rx = dx * m[0] + dy * m[1];
        final ry = dx * m[2] + dy * m[3];
        final t = template[i];
        final tx = (t['x'] as num).toDouble(), ty = (t['y'] as num).toDouble(), tz = ((t['z'] ?? 0.0) as num).toDouble();
        total += math.sqrt((rx - tx) * (rx - tx) + (ry - ty) * (ry - ty) + (dz - tz) * (dz - tz));
      }
      best = math.max(best, (100.0 - total / 21.0 * 80.0).clamp(0.0, 100.0));
    }
    return best;
  }
}
