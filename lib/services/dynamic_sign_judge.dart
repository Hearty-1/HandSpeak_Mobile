import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hand_landmarker/hand_landmarker.dart';

import '/module/alphabet/tutorial_practice.dart'
    show LandmarkPoint, LetterJClassifierService, LetterZClassifierService;
import '/module/numbers/numbers_tutorial_practice.dart' show FSLOnnxService, BaseShapeVerifier;
import 'handspeak_api_service.dart';
import '/providers/language_provider.dart';

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
        ? L.t('Make the J clearer: only the pinky up, move down, then curve.', 'Gawing mas malinaw ang J: kalingkingan lang ang nakataas, pababa, saka ikurba.')
        : L.t('Draw the Z with your index finger: right, diagonally down, then right.', 'Iguhit ang Z gamit ang hintuturo: pakanan, pababang pahilis, saka pakanan.');
    if (_frames.length < 8) {
      return DynamicVerdict(isCorrect: false, score: 0, feedback: L.t('Do the whole movement of Letter $letter in front of the camera.', 'Gawin ang buong galaw ng Letter $letter sa harap ng camera.'), model: model, frames: _frames.length);
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
        feedback: r.accepted ? L.t('Letter $letter is correct!', 'Tama ang Letter $letter!') : hint,
        model: '$model + server letter_${letter.toLowerCase()}',
        predicted: r.accepted ? letter.toUpperCase() : null,
        confidence: r.confidence,
        frames: stroke.length,
      );
    } catch (e) {
      // Server only (as the tutorial): no pass without the server's verdict.
      debugPrint('[DynamicSignJudge] letter $letter server check unavailable: $e');
      return DynamicVerdict(
        isCorrect: false,
        score: 0,
        feedback: L.t('Could not reach the server. Check your internet connection and try again.',
            'Hindi maabot ang server. Tingnan ang koneksyon sa internet at subukang muli.'),
        model: '$model + server letter_${letter.toLowerCase()} (unreachable)',
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

  /// Server verdict for a moving number, or null when the server cannot be
  /// reached (the caller then judges on the phone).
  Future<DynamicVerdict?> _judgeNumberOnServer(int number) =>
      serverNumberVerdict(number, FSLOnnxService.resampleTo24(_trainingClip(_rotation())), frames: _frames.length);

  /// Server verdict for a 24-frame clip of a moving number (rows of 63 values
  /// in the on-phone model's input space), plus the app's start / end
  /// handshape check. Null when the server cannot be reached.
  static Future<DynamicVerdict?> serverNumberVerdict(int number, List<List<double>> clip24, {int frames = 24}) async {
    try {
      final frames24 = [
        for (final f in clip24) [for (var i = 0; i < 21; i++) [f[i * 3], f[i * 3 + 1], f[i * 3 + 2]]]
      ];
      final r = await HandSpeakApiService()
          .predictRawNumbers(targetNumber: number, frames24: frames24)
          .timeout(const Duration(seconds: 12));
      final model = 'server numbers ${r.range.isEmpty ? '' : r.range}'.trim();
      if (r.isCorrect) {
        await BaseShapeVerifier.load();
        final conflict = FSLOnnxService.startBaseConflict(number, clip24);
        final shapes = BaseShapeVerifier.isLoaded ? BaseShapeVerifier.check(number, clip24) : null;
        if (conflict != null || (shapes != null && !shapes.ok)) {
          return DynamicVerdict(
            isCorrect: false,
            score: 45,
            model: model,
            predicted: r.detectedNumber?.toString(),
            frames: frames,
            feedback: conflict ??
                L.t('Start with ${BaseShapeVerifier.shapeNames[shapes!.expected] ?? shapes.expected}. Hold it first before moving.',
                    'Ang simula ay dapat ${BaseShapeVerifier.shapeNames[shapes.expected] ?? shapes.expected}. Hawakan muna ito bago gumalaw.'),
          );
        }
        return DynamicVerdict(
          isCorrect: true,
          score: r.accuracyScore,
          model: model,
          predicted: r.detectedNumber?.toString(),
          frames: frames,
          feedback: L.t('Great job! Correct movement and handshape for Number $number',
              'Mahusay! Wastong kumpas at porma para sa Number $number'),
        );
      }
      final String feedback;
      if (r.rejectionCode == 'static_hand') {
        feedback = L.t('Your hand stayed still. Do the movement of Number $number.',
            'Hindi gumalaw ang kamay. Gawin ang galaw ng Number $number.');
      } else if (r.detectedNumber != null && r.detectedNumber != number) {
        feedback = L.t('That looked like Number ${r.detectedNumber}. Try again for $number.',
            'Mukhang Number ${r.detectedNumber} ang naisagawa. Subukang muli para sa $number.');
      } else {
        feedback = L.t('Not quite. Watch the example and try Number $number again.',
            'Hindi pa tama. Panoorin ang halimbawa at subukang muli ang Number $number.');
      }
      return DynamicVerdict(
        isCorrect: false,
        score: r.accuracyScore,
        model: model,
        predicted: r.detectedNumber?.toString(),
        frames: frames,
        feedback: feedback,
      );
    } catch (e) {
      debugPrint('[DynamicSignJudge] number $number: server unavailable ($e), judging on the phone');
      return null;
    }
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
          feedback: L.t('Too fast. Hold the first shape, move, then hold the last shape.', 'Masyadong mabilis. Hawakan ang unang porma, gumalaw, saka hawakan ang huling porma.'));
    }
    // 1. Server (POST /v1/predict_raw/numbers), with the app's start / end
    //    handshape check on top (the server route has no such check).
    final server = await _judgeNumberOnServer(number);
    if (server != null) return server;
    // Server only (for now): no on-phone verdict when it cannot be reached.
    return DynamicVerdict(isCorrect: false, score: 0, model: 'server numbers', frames: _frames.length,
        feedback: L.t('Could not reach the server. Check your internet connection and try again.', 'Hindi maabot ang server. Tingnan ang koneksyon sa internet at subukang muli.'));
  }

  /// On-phone decade model (kept for when the on-phone fallback returns).
  // ignore: unused_element
  Future<DynamicVerdict> _judgeNumberOnPhone(int number) async {
    final model = modelFileFor(number);
    await prepare(number: number);
    if (!FSLOnnxService.isReadyFor(number)) {
      return DynamicVerdict(isCorrect: false, score: 0, model: model, frames: _frames.length,
          feedback: L.t('Could not load the model for Number $number. Try again.', 'Hindi ma-load ang modelo para sa Number $number. Subukang muli.'));
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
          feedback: L.t('Could not check your sign. Try again.', 'Hindi masuri ang kumpas. Subukang muli.'));
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
    'T': ['M', 'N', 'S', 'A', 'O', 'F', 'X'],
  };
  static const double _rivalMargin = 0.5;

  /// Pairs that need a clearer win than [_rivalMargin]: a real X in T
  /// practice scored T 80-84 vs X 72-81 (2026-10-30 log), leads of 3-8.
  static const Map<String, Map<String, double>> _pairMargin = {
    'T': {'X': 5.0},
  };
  int _lastExtraLogMs = 0;
  static final Map<String, List<dynamic>> _bundled = {};
  static final Set<String> _loading = {};
  static final Set<String> _loaded = {}; // letters whose look-alike load finished

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
        ? (_rivalProblem(hand.landmarks, l) ?? _rivalExtraRule(_selfieView(hand.landmarks, imageWidth, imageHeight, rotation), l))
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
      // Index from 1.05: the G template measures 1.10 (2026-10-29 template check).
      if (ratio(8, 6) < 1.05) return L.t('Straighten your index finger for Letter $letter.', 'Iunat ang hintuturo para sa Letter $letter.');
      if (spec.middleUp && !extended(12, 10)) return L.t('Straighten your middle finger too for Letter $letter.', 'Iunat din ang hinlalato para sa Letter $letter.');
      final mustFold = [
        if (spec.middleFolded && !folded(12, 10)) 'hinlalato',
        if (!folded(16, 14)) 'palasingsingan',
        if (!folded(20, 18)) 'kalingkingan',
      ];
      if (mustFold.isNotEmpty) return L.t('Fold your ${L.fingers(mustFold)} for Letter $letter.', "Itikom ang ${mustFold.join(', ')} para sa Letter $letter.");

      // Pointing direction of the index finger (knuckle -> tip), y points down.
      final dx = p[8].x - p[5].x, dy = p[8].y - p[5].y;
      final ax = dx.abs(), ay = dy.abs();
      const tan50 = 1.19;
      switch (spec.dir) {
        case 'side':
          if (ay > ax * tan50) return L.t('Turn your hand sideways: the index finger should point sideways.', 'Itagilid ang kamay: pahalang dapat ang hintuturo.');
        case 'up':
          if (!(dy < 0 && ax <= ay * tan50)) return L.t('Point your index finger up for Letter $letter.', 'Ituro pataas ang hintuturo para sa Letter $letter.');
        case 'down':
          if (!(dy > 0 && ax <= ay * tan50)) return L.t('Point your index finger down for Letter $letter.', 'Ituro pababa ang hintuturo para sa Letter $letter.');
      }

      final middleOut = d(12, 9); // middle tip -> its knuckle: ~0.4 folded, 0.7+ out
      _log(() => 'Letter $letter shape: middleOut=${middleOut.toStringAsFixed(2)} thumb-midjoint=${d(4, 10).toStringAsFixed(2)} '
          'thumb-ringjoint=${d(4, 14).toStringAsFixed(2)} thumbOut=${d(4, 5).toStringAsFixed(2)}');
      switch (letter) {
        case 'K': // middle out (L, D fold it), thumb on the middle finger (peace sign: on the ring)
          // K template 0.62; L 0.42, D 0.38 (folded middle finger).
          if (middleOut < 0.50) return L.t('Straighten your middle finger too for Letter K.', 'Iunat din ang hinlalato para sa Letter K.');
          if (d(4, 10) > 0.60 || d(4, 10) > d(4, 14)) {
            return L.t('Put your thumb between your index and middle fingers for Letter K.', 'Ilagay ang hinlalaki sa pagitan ng hintuturo at hinlalato para sa Letter K.');
          }
        case 'P': // the middle finger sticks out downward (Q folds it)
          // P template: middle out 2.19, bend 1.43; Q bends it (1.00).
          if (middleOut < 0.65 || ratio(12, 10) < 1.25) return L.t('Point your middle finger down too for Letter P.', 'Iunat din ang hinlalato pababa para sa Letter P.');
          if (d(4, 10) > 0.65) return L.t('Touch your thumb to your middle finger for Letter P.', 'Idikit ang hinlalaki sa hinlalato para sa Letter P.');
        case 'Q': // index and thumb point down together, middle folded (P sticks it out)
          // Q template bends the middle finger (1.00) but it is not tucked
          // in (tip 1.27 from its knuckle), so the bend decides; P is 1.43.
          if (ratio(12, 10) > 1.15) return L.t('Fold your middle finger for Letter Q.', 'Itikom ang hinlalato para sa Letter Q.');
          if (d(4, 5) < 0.55 || p[4].y <= p[2].y) return L.t('Point your thumb down together with your index finger for Letter Q.', 'Ituro pababa ang hinlalaki kasama ang hintuturo para sa Letter Q.');
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
          if (r >= 1.30) toCurve.add(fingers[i].$3);
          if (r < 0.80) toStraighten.add(fingers[i].$3);
      }
    }
    if (toBend.isNotEmpty) return L.t('Bend your ${L.fingers(toBend)} for Letter $letter.', "Ibaluktot ang ${toBend.join(', ')} para sa Letter $letter.");
    if (toStraighten.isNotEmpty) return L.t('Straighten your ${L.fingers(toStraighten)} for Letter $letter.', "Iunat ang ${toStraighten.join(', ')} para sa Letter $letter.");
    if (toCurve.isNotEmpty) return L.t('Slightly bend your ${L.fingers(toCurve)} for Letter $letter.', "Bahagyang ibaluktot ang ${toCurve.join(', ')} para sa Letter $letter.");

    // 2. Thumb / spacing rules that tell look-alikes apart.
    switch (letter) {
      case 'A': // thumb at the side of the index finger, not across / under (S, M, N)
        // A template -0.56; N -0.16, M 0.00, S 0.26 (thumb across / under).
        if (g.thumbAcross > -0.30) return L.t('Put your thumb at the side of your fist for Letter A.', 'Ilagay ang hinlalaki sa gilid ng kamao para sa Letter A.');
      case 'B': // flat, fully straight fingers (C is curved) and the thumb folded in
        if (g.fingerReach < 1.70) return L.t('Keep all fingers straight for Letter B.', 'Iunat nang tuwid ang lahat ng daliri para sa Letter B.');
        if (d(4, 9) > 0.65) return L.t('Fold your thumb across your palm for Letter B.', 'Itiklop ang hinlalaki sa palad para sa Letter B.');
      case 'X': // index raised and hooked (T folds it down over the thumb)
        // Raised hooked index away from the thumb: X thumb-index 0.88; T 0.24
        // (index folded over the thumb).
        if (g.indexRise < 0.25 || thumbIndex < 0.50) return L.t('Raise and hook your index finger for Letter X.', 'Itaas at ikawit ang hintuturo para sa Letter X.');
      case 'C': // open curve: a gap between thumb and fingers
        // Thumb away from the palm: C 0.96; B 0.19, O 0.44, E 0.44.
        if (thumbIndex < 0.40 || d(4, 9) < 0.60) return L.t('Open a little: leave a gap between thumb and fingers (Letter C).', 'Bahagyang ibuka: may puwang dapat ang hinlalaki at mga daliri (Letter C).');
        if (thumbIndex > 1.50) return L.t('Bring your thumb a little closer to your fingers for Letter C.', 'Ilapit nang kaunti ang hinlalaki sa mga daliri para sa Letter C.');
      case 'D': // thumb touches the middle finger
        if (d(4, 12) > 0.55) return L.t('Touch your thumb to your middle finger for Letter D.', 'Idikit ang hinlalaki sa hinlalato para sa Letter D.');
      case 'E': // tips rest on the thumb, not a tight fist (S)
        if ([d(4, 8), d(4, 12), d(4, 16)].reduce(math.min) > 0.55) {
          return L.t('Bring your fingertips down to your thumb for Letter E.', 'Ilapit ang dulo ng mga daliri sa hinlalaki para sa Letter E.');
        }
        if ((d(8, 0) + d(12, 0) + d(16, 0) + d(20, 0)) / 4 < 0.95) {
          return L.t("Don't close a full fist: rest your fingertips on your thumb (Letter E).", 'Huwag isara nang buo ang kamao: nakapatong ang mga daliri sa hinlalaki (Letter E).');
        }
      case 'F': // thumb and index tips touch (the circle)
        if (thumbIndex > 0.35) return L.t('Touch the tips of your thumb and index finger for Letter F.', 'Pagdikitin ang dulo ng hinlalaki at hintuturo para sa Letter F.');
      case 'L':
      case 'Y': // thumb sticks out
        // Thumb tip from the middle knuckle: L 0.75, Y 0.71; I 0.20, D 0.34, X 0.32.
        if (d(4, 9) < 0.55) return L.t('Stick your thumb out for Letter $letter.', 'Iunat palabas ang hinlalaki para sa Letter $letter.');
      case 'O': // thumb and fingertips meet
        if (thumbIndex > 0.40) return L.t('Touch your thumb and fingertips to make a circle (Letter O).', 'Pagdikitin ang hinlalaki at mga daliri para bumuo ng bilog (Letter O).');
      case 'R': // index and middle crossed: the tips swap sides
        if (g.indexMiddleCross > 0.02) return L.t('Cross your index and middle fingers for Letter R.', 'Ipag-krus ang hintuturo at hinlalato para sa Letter R.');
      case 'U': // index and middle straight, together and not crossed
        if (g.indexMiddleAngle > 8.5 || d(8, 12) > 0.235) return L.t('Keep your index and middle fingers together for Letter U.', 'Pagdikitin ang hintuturo at hinlalato para sa Letter U.');
        if (g.indexMiddleCross < -0.02) return L.t("Don't cross your fingers for Letter U.", 'Huwag ipag-krus ang mga daliri para sa Letter U.');
      case 'V': // index and middle apart
        if (g.indexMiddleAngle < 8.5 || d(8, 12) < 0.235) return L.t('Spread your index and middle fingers for Letter V.', 'Ibuka ang hintuturo at hinlalato para sa Letter V.');
    }
    return null;
  }

  /// Templates of the letter and its look-alikes (TemplateStore: Storage,
  /// then bundled), so every compared template comes from one set.
  static Future<void> _loadRivals(String letter) async {
    if (!_loading.add(letter)) return;
    // All at once (one by one took ~4 s from Storage, 2026-10-30 log).
    await Future.wait([
      for (final r in [letter, ...?_rivalLetters[letter]])
        if (!_bundled.containsKey(r))
          TemplateStore.load('alphabet', r).then((t) {
            if (t != null) {
              _bundled[r] = t;
            } else {
              debugPrint('No look-alike template for $r');
            }
          }),
    ]);
    _loaded.add(letter);
    final missing = [for (final r in [letter, ...?_rivalLetters[letter]]) if (!_bundled.containsKey(r)) r];
    debugPrint('[Look-alikes] $letter ready${missing.isEmpty ? '' : ' (missing: ${missing.join(', ')})'}');
  }

  /// Extra finger rule for a look-alike letter, after the template
  /// comparison passed. T: the index folds over the thumb, so its tip sits on
  /// the thumb tip (real T 0.10-0.46, 2026-10-25 logs; T template 0.24);
  /// in X the hooked index is raised away from it (X template 0.88).
  String? _rivalExtraRule(List<LandmarkPoint> p, String letter) {
    if (letter != 'T') return null;
    final palm = p[9].distanceTo(p[0]) + 1e-6;
    final thumbIndex = p[4].distanceTo(p[8]) / palm;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastExtraLogMs > 700) {
      _lastExtraLogMs = now;
      debugPrint('Letter T thumb-index=${thumbIndex.toStringAsFixed(2)} (T needs <= 0.50; X template 0.88)');
    }
    if (thumbIndex > 0.50) {
      return L.t('Fold your index finger over your thumb for Letter T.',
          'Itiklop ang hintuturo sa ibabaw ng hinlalaki para sa Letter T.');
    }
    return null;
  }

  String? _rivalProblem(List<Landmark> lms, String letter) {
    final own = _bundled[letter];
    if (own == null) {
      if (_loaded.contains(letter)) return null; // no template anywhere: skip the comparison
      // Still loading: the letter cannot pass yet (a look-alike shown in
      // these first moments used to slip through).
      unawaited(_loadRivals(letter));
      _log(() => '[Look-alikes] $letter templates still loading');
      return L.t('Getting ready…', 'Inihahanda…');
    }
    final pending = [for (final r in _rivalLetters[letter]!) if (!_bundled.containsKey(r)) r];
    if (pending.isNotEmpty && !_loaded.contains(letter)) {
      // Its own template may already be here as another letter's look-alike;
      // make sure its own look-alike list is requested too.
      unawaited(_loadRivals(letter));
      return L.t('Getting ready…', 'Inihahanda…');
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
    if (bestRival == null) return null;
    // Every look-alike must be beaten by its margin (not only the best one).
    for (final r in _rivalLetters[letter]!) {
      final t = _bundled[r];
      if (t == null) continue;
      final margin = _pairMargin[letter]?[r] ?? _rivalMargin;
      if (target < templateScore(lms, t) + margin) {
        return L.t('This looks like Letter $r. Check the picture of Letter $letter again, especially the thumb.',
            'Mukhang Letter $r ito. Tingnan muli ang larawan ng Letter $letter, lalo na ang hinlalaki.');
      }
    }
    return null;
  }

  /// Template score for the look-alike comparison: like every screen's
  /// _calculateScore (3D, best of the 8 orientations / mirrors), but with the
  /// template scaled to the same size as the live hand.
  static double templateScore(List<Landmark> lms, List<dynamic> template) {
    if (lms.length < 21 || template.length < 21) return 0.0;
    final wrist = lms[0], mBase = lms[9];
    var dist = math.sqrt(math.pow(wrist.x - mBase.x, 2) + math.pow(wrist.y - mBase.y, 2) + math.pow(wrist.z - mBase.z, 2));
    if (dist == 0) dist = 1.0;
    const orientations = [
      [1.0, 0.0, 0.0, 1.0, 1.0], [0.0, -1.0, 1.0, 0.0, 1.0], [-1.0, 0.0, 0.0, -1.0, 1.0], [0.0, 1.0, -1.0, 0.0, 1.0],
      [1.0, 0.0, 0.0, 1.0, -1.0], [0.0, -1.0, 1.0, 0.0, -1.0], [-1.0, 0.0, 0.0, -1.0, -1.0], [0.0, 1.0, -1.0, 0.0, -1.0],
    ];
    // Templates are stored at different sizes (wrist -> middle knuckle
    // 0.875 for A ... 0.959 for B) while the live hand is scaled to 1, which
    // biased the look-alike comparison against small templates: scale the
    // template to 1 as well.
    double tc(int i, String k) => ((template[i][k] ?? 0.0) as num).toDouble();
    final ts = math.sqrt(math.pow(tc(9, 'x') - tc(0, 'x'), 2) + math.pow(tc(9, 'y') - tc(0, 'y'), 2) +
            math.pow(tc(9, 'z') - tc(0, 'z'), 2));
    final tScale = ts > 1e-6 ? ts : 1.0;
    double best = 0.0;
    for (final m in orientations) {
      double total = 0.0;
      for (int i = 0; i < 21; i++) {
        final dx = (lms[i].x - wrist.x) / dist * m[4];
        final dy = (lms[i].y - wrist.y) / dist;
        final dz = (lms[i].z - wrist.z) / dist;
        final rx = dx * m[0] + dy * m[1];
        final ry = dx * m[2] + dy * m[3];
        final tx = (tc(i, 'x') - tc(0, 'x')) / tScale, ty = (tc(i, 'y') - tc(0, 'y')) / tScale, tz = (tc(i, 'z') - tc(0, 'z')) / tScale;
        total += math.sqrt((rx - tx) * (rx - tx) + (ry - ty) * (ry - ty) + (dz - tz) * (dz - tz));
      }
      best = math.max(best, (100.0 - total / 21.0 * 80.0).clamp(0.0, 100.0));
    }
    return best;
  }
}

// =============================================================================
// STATIC LETTERS (A-Y) / NUMBERS (1-10) ON THE SERVER
// =============================================================================

/// Result of [StaticServerCheck.verify].
class StaticServerVerdict {
  final bool ok;
  final String? feedback; // shown when not ok
  final String model; // for gesture_attempts.modelVersion
  final String? predicted;
  final double confidence;
  const StaticServerVerdict({required this.ok, this.feedback, required this.model, this.predicted, this.confidence = 0});
}

/// Collects the held handshape and asks the server's static model
/// (POST /v1/predict_raw/static_letters | static_numbers) to confirm it when
/// the on-phone check is satisfied. The sign passes when the server's top
/// label is the target with at least its threshold (0.7).
class StaticServerCheck {
  final List<({int t, List<Landmark> lms})> _frames = [];
  int _w = 0, _h = 0, _rotation = 0;
  static const int _windowMs = 1500;
  static const int _sendFrames = 10;

  /// target -> server labels its veto is ignored for (see verify).
  static const Map<String, Set<String>> _phoneSeparates = {
    'K': {'U', 'V', 'D'},
    'X': {'T', 'D'},
    'U': {'R', 'V'},
    'V': {'U', 'K'},
    'R': {'U'},
  };

  void clear() => _frames.clear();
  bool get hasFrames => _frames.isNotEmpty;

  /// Call with the hand being judged on every frame of the hold.
  void add(Hand hand, {required int imageWidth, required int imageHeight, required int rotation}) {
    if (hand.landmarks.length != 21) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _w = imageWidth;
    _h = imageHeight;
    _rotation = rotation;
    _frames.add((t: now, lms: hand.landmarks));
    _frames.removeWhere((f) => now - f.t > _windowMs);
  }

  /// Server verdict for [target] ("A".."Y" without J / Z, or "1".."10"), or
  /// null when the server cannot be reached (the caller keeps the on-phone
  /// verdict).
  Future<StaticServerVerdict?> verify(String target, {required bool number}) async {
    if (_frames.isEmpty || _w <= 0 || _h <= 0) return null;
    final r = ((_rotation % 360) + 360) % 360;
    final swap = r == 90 || r == 270;
    final upW = swap ? _h : _w, upH = swap ? _w : _h;
    final picked = _frames.length <= _sendFrames ? _frames : _frames.sublist(_frames.length - _sendFrames);
    final frames = [
      for (final f in picked)
        [
          for (final lm in f.lms)
            () {
              final (ux, uy) = switch (r) {
                90 => (1.0 - lm.y, lm.x),
                180 => (1.0 - lm.x, 1.0 - lm.y),
                270 => (lm.y, 1.0 - lm.x),
                _ => (lm.x, lm.y),
              };
              return [ux, uy, lm.z];
            }()
        ]
    ];
    final model = number ? 'server static_numbers' : 'server static_letters';
    try {
      // A hung request must not freeze the screen on "Checking..." forever.
      final res = await HandSpeakApiService()
          .predictRawStatic(numbers: number, frames: frames, imageWidth: upW, imageHeight: upH)
          .timeout(const Duration(seconds: 10));
      final t = target.trim().toUpperCase();
      final top = res.label.trim().toUpperCase();
      debugPrint('[StaticServerCheck] $t -> ${res.label} ${(res.confidence * 100).toStringAsFixed(0)}% '
          '(accepted ${res.accepted}, ${frames.length} frames)');
      // The on-phone template and finger rules have already passed when this
      // runs, so the server acts as a confident veto: its static model is
      // weakest on U / R / V / S and not yet tuned on real signers, and a
      // strict "top label >= 0.7" rejected correct signs (2026-10-29).
      final inTopK = res.topK.any((p) => p.label.trim().toUpperCase() == t);
      if (top.isEmpty) {
        // No prediction in the reply: the server did not decide (logged to
        // find out why); the phone's checks have already passed.
        debugPrint('[StaticServerCheck] $t: reply without a prediction: ${res.raw}');
        return StaticServerVerdict(ok: true, model: '$model (no prediction)', confidence: 0);
      }
      // Known confusions of the server's static model on real hands, which
      // the phone's finger rules already tell apart (they ran before this):
      // a real K reads as U (78 %, 2026-10-30 logs) and the template pairs
      // R/U, U/V, T/X are its closest classes. M/N and A/S keep the veto.
      final phoneDecides = _phoneSeparates[t]?.contains(top) ?? false;
      final confidentOther = top != t && res.confidence >= res.threshold && !phoneDecides;
      if (top == t || phoneDecides || (!confidentOther && inTopK)) {
        return StaticServerVerdict(ok: true, model: model, predicted: res.label, confidence: res.confidence);
      }
      final what = number ? 'Number' : 'Letter';
      return StaticServerVerdict(
        ok: false,
        model: model,
        predicted: res.label,
        confidence: res.confidence,
        feedback: confidentOther
            ? L.t('This looks like $what ${res.label}. Check the picture of $what $t again.',
                'Mukhang $what ${res.label} ito. Tingnan muli ang larawan ng $what $t.')
            : L.t('Almost! Hold $what $t steady and clear.', 'Malapit na! Hawakan nang malinaw at matatag ang $what $t.'),
      );
    } catch (e) {
      debugPrint('[StaticServerCheck] server unavailable ($e); keeping the on-phone verdict');
      return null;
    }
  }
}


// =============================================================================
// SIGN TEMPLATES: Firebase Storage first (models/alphabet|numbers/<key>.json)
// =============================================================================

/// One place that loads a letter / number template for every screen:
/// Firebase Storage `models/{alphabet|numbers}/<key>.json` first, then the
/// app's bundled copy if it still exists (offline, or a file not uploaded).
/// Cached for the session. Lets the bundled assets/alphabet|numbers/*.json
/// be deleted once Storage has them.
class TemplateStore {
  static final Map<String, List<dynamic>> _cache = {};
  static final Map<String, String> _source = {};
  static final Map<String, Future<List<dynamic>?>> _loading = {};

  static String _id(String folder, String key) => '$folder/${key.trim().toUpperCase()}';

  /// Tests: put a template in the cache (no Firebase in unit tests).
  @visibleForTesting
  static void debugPut(String folder, String key, List<dynamic> template) {
    _cache[_id(folder, key)] = template;
    _source[_id(folder, key)] = 'test';
  }

  /// Where the last load of [key] came from (for gesture_attempts.modelVersion).
  static String? sourceOf(String folder, String key) => _source[_id(folder, key)];

  /// Template of [key] in [folder] ('alphabet' or 'numbers'), or null.
  static Future<List<dynamic>?> load(String folder, String key) {
    final id = _id(folder, key);
    final cached = _cache[id];
    if (cached != null) return Future.value(cached);
    // Note: the whenComplete callback must not return the removed future
    // (whenComplete awaits a returned future: the load waited for itself and
    // never finished, 2026-10-29).
    return _loading[id] ??= _fetch(folder, key.trim().toUpperCase(), id).whenComplete(() {
      _loading.remove(id);
    });
  }

  static Future<List<dynamic>?> _fetch(String folder, String key, String id) async {
    final path = 'models/$folder/$key.json';
    try {
      final bytes = await FirebaseStorage.instance.ref(path).getData().timeout(const Duration(seconds: 12));
      if (bytes != null) {
        final t = jsonDecode(utf8.decode(bytes)) as List<dynamic>;
        _cache[id] = t;
        _source[id] = path;
        return t;
      }
    } catch (e) {
      debugPrint('[TemplateStore] Storage $path unavailable ($e); trying the bundled copy');
    }
    try {
      final asset = 'assets/$folder/$key.json';
      final t = jsonDecode(await rootBundle.loadString(asset)) as List<dynamic>;
      _cache[id] = t;
      _source[id] = asset;
      return t;
    } catch (_) {
      debugPrint('[TemplateStore] no template for $folder/$key (not in Storage, not bundled)');
      return null;
    }
  }
}
