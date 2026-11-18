import 'dart:math' as math;
import 'dart:typed_data';

import 'package:hand_landmarker/hand_landmarker.dart';

import '/module/phrases/phrase_recognizer.dart';
import '/module/phrases/pose_provider.dart';
import '/services/handspeak_api_service.dart';

/// Gesture to Text (automatic): reads a greeting from frames of the shared
/// full-body camera, with the same features and checks as the Greetings
/// tutorial practice (32 x 96 -> Cloud Run /v1/predict/greetings,
/// PhraseRecognizer's confidence / margin rule, the Magandang Hapon / Mabuti
/// wrist-height rule).
class GreetingsReader {
  final PhraseRecognizer _recognizer = PhraseRecognizer()
    ..mirrorX = false
    ..handRotation = 0; // frames are upright (CaptureFixer)

  void dispose() => _recognizer.dispose();

  static double? _signingWristTop(List<Float32List> clip) {
    double? best;
    double bestPath = -1;
    for (final xi in const [8, 10]) {
      double path = 0, top = double.infinity;
      double? px, py;
      for (final f in clip) {
        if (f.length < 12 || (f[0] == 0 && f[1] == 0)) continue;
        final x = f[xi], y = f[xi + 1];
        if (px != null) path += math.sqrt((x - px) * (x - px) + (y - py!) * (y - py));
        px = x;
        py = y;
        if (y < top) top = y;
      }
      if (top.isFinite && path > bestPath) {
        bestPath = path;
        best = top;
      }
    }
    return best;
  }

  static String _pretty(String label) => label
      .toLowerCase()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  static List<Landmark> _hand(Object? pts) => [
        for (final p in pts as List)
          Landmark((p[0] as num).toDouble(), (p[1] as num).toDouble(), ((p as List).length > 2 ? p[2] as num : 0).toDouble())
      ];

  /// [frames]: upright frames in the predict_raw format ({'pose' (33),
  /// 'left_hand', 'right_hand'}); [imageWidth] x [imageHeight]: the upright
  /// image size. Returns (phrase, confidence 0..1), or null when it is no
  /// clear greeting.
  Future<(String, double)?> read(List<Map<String, dynamic>> frames, int imageWidth, int imageHeight) async {
    _recognizer.resetTracking();
    final xScale = PhraseRecognizer.aspectXScale(imageWidth, imageHeight);
    final feats = <Float32List>[];
    final hasHands = <bool>[], hasPose = <bool>[];
    final now = DateTime.now();
    for (final f in frames) {
      final hands = <Hand>[
        if (f['left_hand'] != null) Hand(_hand(f['left_hand'])),
        if (f['right_hand'] != null) Hand(_hand(f['right_hand'])),
      ];
      final pose = f['pose'] as List?;
      final snap = (pose != null && pose.length >= 17)
          ? PoseSnapshot([
              for (var i = 11; i <= 16; i++) [(pose[i][0] as num).toDouble(), (pose[i][1] as num).toDouble()]
            ], now)
          : null;
      feats.add(_recognizer.extractFrameFeatures(hands, pose: snap, xScale: xScale));
      hasHands.add(_recognizer.lastFrameHadHands);
      hasPose.add(_recognizer.lastFrameHadPose);
    }
    final window = PhraseRecognizer.trainingWindow(hasHands);
    if (window == null) return null;
    final clip = feats.sublist(window[0], window[1]);
    if (!PhraseRecognizer.fillMissingPose(clip, hasPose.sublist(window[0], window[1]))) return null;
    if (clip.length < PhraseRecognizer.minRecordedFrames) return null;

    final seq = _recognizer.prepareStandardSequence(clip, PhraseRecognizer.sequenceLength);
    final api = HandSpeakApiService();
    PredictResponse r;
    try {
      r = await api.predict(modelId: HandSpeakModels.greetings, features: seq.toList(), topK: PhraseRecognizer.numClasses);
    } on Exception catch (e) {
      if (!e.toString().contains('[4')) rethrow;
      r = await api.predict(modelId: HandSpeakModels.greetings, features: seq.toList());
    }
    final probs = List<double>.filled(PhraseRecognizer.numClasses, 0.0);
    final entries = [r.prediction, ...r.topK];
    final scale = entries.any((p) => p.confidence > 1.0) ? 0.01 : 1.0;
    for (final p in entries) {
      var idx = -1;
      for (final name in [p.label, p.labelEn, p.code]) {
        if (name == null || name.isEmpty) continue;
        idx = PhraseRecognizer.classIndexFor(name);
        if (idx != -1) break;
      }
      if (idx == -1 && p.index >= 0 && p.index < probs.length) idx = p.index;
      if (idx != -1) probs[idx] = p.confidence * scale;
    }
    final eval = _recognizer.classifyProbabilities(probs, minConfidence: PhraseRecognizer.defaultMinConfidence);
    var top = eval.top1Index;
    var verdict = eval.verdict;
    final hapon = PhraseRecognizer.classIndexFor('Magandang Hapon'), mabuti = PhraseRecognizer.classIndexFor('Mabuti');
    final wristTop = _signingWristTop(clip);
    if (wristTop != null && (top == hapon || top == mabuti) && verdict != PhraseVerdict.rejectedUnknown) {
      top = wristTop <= 0.40 ? hapon : mabuti;
      verdict = PhraseVerdict.accepted;
    }
    if (verdict != PhraseVerdict.accepted || top < 0 || _recognizer.isInactiveClass(top)) return null;
    return (_pretty(_recognizer.labelFor(top)), eval.top1Prob / 100.0);
  }
}
