import 'dart:math' as math;
import 'package:tflite_flutter/tflite_flutter.dart';

class FslClassifierService {
  Interpreter? _interpreter;

  static const Map<int, String> greetingsMap = {
    0: "MAGANDANG UMAGA",
    1: "MAGANDANG HAPON",
    2: "MAGANDANG GABI",
    3: "KUMUSTA",
    4: "KUMUSTA KA",
    5: "MABUTI",
    6: "IKINAGAGALAK KONG MAKILALA KA",
    7: "SALAMAT",
    8: "[HINDI AKTIBO] WALANG ANUMAN",
    9: "MAGKITA TAYO BUKAS",
    10: "HINDI KILALANG SENYAS",
  };

  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        'assets/fsl_model.tflite',
        options: options,
      );
      print("Matagumpay na na-load ang FSL Model.");
    } catch (e) {
      print("May aberya sa pag-load ng FSL Model: $e");
    }
  }

  List<double> extractClean96Features({
    List<Map<String, double>>? poseLandmarks,
    List<Map<String, double>>? leftHandLandmarks,
    List<Map<String, double>>? rightHandLandmarks,
  }) {
    List<double> posePts = List.filled(12, 0.0);

    if (poseLandmarks != null && poseLandmarks.isNotEmpty) {
      final leftSh = poseLandmarks[11];
      final rightSh = poseLandmarks[12];
      
      final midShX = (leftSh['x']! + rightSh['x']!) / 2.0;
      final midShY = (leftSh['y']! + rightSh['y']!) / 2.0;
      
      final dx = leftSh['x']! - rightSh['x']!;
      final dy = leftSh['y']! - rightSh['y']!;
      final shDist = math.sqrt(dx * dx + dy * dy) + 1e-6;

      final targetPoseIndices = [11, 12, 13, 14, 15, 16];
      List<double> tempPose = [];
      for (final idx in targetPoseIndices) {
        final lm = poseLandmarks[idx];
        final normX = (lm['x']! - midShX) / shDist;
        final normY = (lm['y']! - midShY) / shDist;
        tempPose.addAll([normX, normY]);
      }
      posePts = tempPose.sublist(0, 12);
    }

    List<double> lhPts = List.filled(42, 0.0);
    if (leftHandLandmarks != null && leftHandLandmarks.isNotEmpty) {
      final wrist = leftHandLandmarks[0];
      final midMcp = leftHandLandmarks[9];
      
      final pdx = wrist['x']! - midMcp['x']!;
      final pdy = wrist['y']! - midMcp['y']!;
      final palmSize = math.sqrt(pdx * pdx + pdy * pdy) + 1e-6;

      List<double> tempLh = [];
      for (final lm in leftHandLandmarks) {
        tempLh.add((lm['x']! - wrist['x']!) / palmSize);
        tempLh.add((lm['y']! - wrist['y']!) / palmSize);
      }
      lhPts = tempLh.sublist(0, 42);
    }

    List<double> rhPts = List.filled(42, 0.0);
    if (rightHandLandmarks != null && rightHandLandmarks.isNotEmpty) {
      final wrist = rightHandLandmarks[0];
      final midMcp = rightHandLandmarks[9];
      
      final pdx = wrist['x']! - midMcp['x']!;
      final pdy = wrist['y']! - midMcp['y']!;
      final palmSize = math.sqrt(pdx * pdx + pdy * pdy) + 1e-6;

      List<double> tempRh = [];
      for (final lm in rightHandLandmarks) {
        tempRh.add((lm['x']! - wrist['x']!) / palmSize);
        tempRh.add((lm['y']! - wrist['y']!) / palmSize);
      }
      rhPts = tempRh.sublist(0, 42);
    }

    return [...posePts, ...lhPts, ...rhPts];
  }

  List<List<double>> interpolateSequence(List<List<double>> rawSeq, int targetFrames) {
    final int originalFrames = rawSeq.length;
    final int numFeatures = rawSeq[0].length;
    List<List<double>> resampled = List.generate(
      targetFrames, 
      (_) => List.filled(numFeatures, 0.0)
    );

    for (int i = 0; i < targetFrames; i++) {
      double t = (originalFrames > 1) ? i / (targetFrames - 1) : 0.0;
      double origIdxFloat = t * (originalFrames - 1);
      int lowIdx = origIdxFloat.floor();
      int highIdx = origIdxFloat.ceil();
      double weight = origIdxFloat - lowIdx;

      for (int f = 0; f < numFeatures; f++) {
        if (lowIdx == highIdx) {
          resampled[i][f] = rawSeq[lowIdx][f];
        } else {
          resampled[i][f] = rawSeq[lowIdx][f] * (1.0 - weight) + rawSeq[highIdx][f] * weight;
        }
      }
    }
    return resampled;
  }

  Map<String, dynamic> predict(List<List<double>> rawBuffer) {
    if (_interpreter == null) {
      return {"label": "Hindi pa handa ang modelo", "confidence": 0.0, "isSuccess": false};
    }
    if (rawBuffer.length < 14) {
      return {
        "label": "Walang tiyak na hula",
        "confidence": 0.0,
        "subtext": "Masyadong mabilis ang kumpas (<14 frames)",
        "isSuccess": false
      };
    }

    final seq32 = interpolateSequence(rawBuffer, 32);
    var input = [seq32];
    var output = List.filled(1 * 11, 0.0).reshape([1, 11]);

    _interpreter!.run(input, output);
    List<double> logits = List<double>.from(output[0]);

    // HARD MASK SA CLASS 8 (WALANG ANUMAN)
    logits[8] = -1e9;

    double maxLogit = logits.reduce(math.max);
    List<double> exps = logits.map((val) => math.exp(val - maxLogit)).toList();
    double sumExps = exps.reduce((a, b) => a + b);
    List<double> probs = exps.map((val) => val / sumExps).toList();

    List<int> sortedIndices = List.generate(11, (i) => i)
      ..sort((a, b) => probs[b].compareTo(probs[a]));

    int top1 = sortedIndices[0];
    int top2 = sortedIndices[1];
    double top1Prob = probs[top1] * 100.0;
    double margin = (probs[top1] - probs[top2]) * 100.0;

    if (top1 == 10) {
      return {
        "label": "Walang tiyak na hula",
        "confidence": top1Prob,
        "subtext": "Tinanggihan: HINDI KILALANG SENYAS (${top1Prob.toStringAsFixed(1)}%)",
        "isSuccess": false
      };
    } else if (top1Prob < 55.0 || margin < 12.0) {
      return {
        "label": "Walang tiyak na hula",
        "confidence": top1Prob,
        "subtext": "Alanganin: ${greetingsMap[top1]} (${top1Prob.toStringAsFixed(1)}%) | Agwat: ${margin.toStringAsFixed(1)}%",
        "isSuccess": false
      };
    } else {
      return {
        "label": greetingsMap[top1]!,
        "confidence": top1Prob,
        "subtext": "Kumpyansa: ${top1Prob.toStringAsFixed(1)}% | Agwat: ${margin.toStringAsFixed(1)}%",
        "isSuccess": true
      };
    }
  }

  void dispose() {
    _interpreter?.close();
  }
}
