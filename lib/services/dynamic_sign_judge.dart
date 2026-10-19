import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
