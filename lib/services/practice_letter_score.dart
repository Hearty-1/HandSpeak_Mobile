import 'dart:math' as math;

import 'package:hand_landmarker/hand_landmarker.dart';

/// The letter / number template score of the tutorial practice (0-100;
/// 70 passes), shared so every screen judges a handshape the same way
/// (TutorialPractice, Translate). Moved here unchanged from
/// module/alphabet/tutorial_practice.dart.
class PracticeLetterScore {
  PracticeLetterScore._();

  /// The practice's pass mark.
  static const double pass = 70.0;

  /// G, H, K, P, Q: tricky letters (horizontal or crossing fingers). Scored in
  /// 2D only (no z noise), scale from wrist->middle base or the index reach,
  /// fingertips weighted 1.5x, a relaxed curve, and G/H/P/Q locked to the
  /// sideways orientations.
  static const List<String> trickyLetters = ['G', 'H', 'K', 'P', 'Q'];

  /// Score of the raw hand_landmarker points [liveLms] against [template]
  /// for [key] (a letter "A".."Y" or a number "1".."10").
  static double score(List<Landmark> liveLms, List<dynamic> template, String key) {
    if (liveLms.isEmpty || template.length < 21 || liveLms.length < 21) return 0.0;
    final letter = key.toUpperCase();
    if (trickyLetters.contains(letter)) return trickyScore(liveLms, template, letter);

    final Landmark wrist = liveLms[0];
    final Landmark mBase = liveLms[9];

    double dist = math.sqrt(
      math.pow(wrist.x - mBase.x, 2) + math.pow(wrist.y - mBase.y, 2) + math.pow(wrist.z - mBase.z, 2),
    );

    if (dist == 0) dist = 1.0;

    double bestScore = 0.0;

    const orientationMatrices = [
      [1.0, 0.0, 0.0, 1.0, 1.0],
      [0.0, -1.0, 1.0, 0.0, 1.0],
      [-1.0, 0.0, 0.0, -1.0, 1.0],
      [0.0, 1.0, -1.0, 0.0, 1.0],
      [1.0, 0.0, 0.0, 1.0, -1.0],
      [0.0, -1.0, 1.0, 0.0, -1.0],
      [-1.0, 0.0, 0.0, -1.0, -1.0],
      [0.0, 1.0, -1.0, 0.0, -1.0],
    ];

    for (final matrix in orientationMatrices) {
      final double xx = matrix[0];
      final double xy = matrix[1];
      final double yx = matrix[2];
      final double yy = matrix[3];
      final double flipX = matrix[4];

      double totalDifference = 0.0;

      for (int i = 0; i < 21; i++) {
        double dx = (liveLms[i].x - wrist.x) / dist;
        final double dy = (liveLms[i].y - wrist.y) / dist;
        final double dz = (liveLms[i].z - wrist.z) / dist;

        dx = dx * flipX;

        final double rx = dx * xx + dy * xy;
        final double ry = dx * yx + dy * yy;

        final double tx = (template[i]['x'] as num).toDouble();
        final double ty = (template[i]['y'] as num).toDouble();
        final double tz = ((template[i]['z'] ?? 0.0) as num).toDouble();

        final double pointDiff = math.sqrt(math.pow(rx - tx, 2) + math.pow(ry - ty, 2) + math.pow(dz - tz, 2));
        totalDifference += pointDiff;
      }

      final double meanDiff = totalDifference / 21.0;
      final double score = (100.0 - (meanDiff * 80.0)).clamp(0.0, 100.0);

      if (score > bestScore) {
        bestScore = score;
      }
    }

    return bestScore;
  }

  static double trickyScore(List<Landmark> liveLms, List<dynamic> template, String letter) {
    final Landmark wrist = liveLms[0];
    final Landmark mBase = liveLms[9];
    final Landmark indexTip = liveLms[8];

    // Stable scale factor to prevent small-fist error inflation
    double dist = math.sqrt(math.pow(wrist.x - mBase.x, 2) + math.pow(wrist.y - mBase.y, 2));
    final double distIndex = math.sqrt(math.pow(wrist.x - indexTip.x, 2) + math.pow(wrist.y - indexTip.y, 2));
    dist = math.max(dist, distIndex * 0.55);
    if (dist < 0.05) dist = 0.05; // Safety floor

    // High priority weighting on action fingertips: thumb, index, middle tips
    const List<int> highPriorityLandmarks = [4, 8, 12];

    const orientationMatrices = [
      [1.0, 0.0, 0.0, 1.0, 1.0], // 0: Upright Normal
      [0.0, -1.0, 1.0, 0.0, 1.0], // 1: 90 deg
      [-1.0, 0.0, 0.0, -1.0, 1.0], // 2: 180 deg
      [0.0, 1.0, -1.0, 0.0, 1.0], // 3: 270 deg
      [1.0, 0.0, 0.0, 1.0, -1.0], // 4: Upright Mirrored
      [0.0, -1.0, 1.0, 0.0, -1.0], // 5: 90 deg Mirrored
      [-1.0, 0.0, 0.0, -1.0, -1.0], // 6: 180 deg Mirrored
      [0.0, 1.0, -1.0, 0.0, -1.0], // 7: 270 deg Mirrored
    ];

    double bestScore = 0.0;
    for (int mIdx = 0; mIdx < orientationMatrices.length; mIdx++) {
      // Directional Lock: horizontal letters use the sideways matrices only ('K' excluded)
      if (letter != 'K' && mIdx.isEven) continue;

      final matrix = orientationMatrices[mIdx];
      final double xx = matrix[0], xy = matrix[1], yx = matrix[2], yy = matrix[3], flipX = matrix[4];

      double totalWeightedDifference = 0.0;
      double totalWeight = 0.0;
      for (int i = 0; i < 21; i++) {
        final double dx = ((liveLms[i].x - wrist.x) / dist) * flipX;
        final double dy = (liveLms[i].y - wrist.y) / dist;
        final double rx = dx * xx + dy * xy;
        final double ry = dx * yx + dy * yy;
        final double tx = (template[i]['x'] as num).toDouble();
        final double ty = (template[i]['y'] as num).toDouble();

        // Purely 2D comparison to eliminate Z-depth noise
        final double pointDiff = math.sqrt(math.pow(rx - tx, 2) + math.pow(ry - ty, 2));
        final double weight = highPriorityLandmarks.contains(i) ? 1.5 : 1.0;
        totalWeightedDifference += pointDiff * weight;
        totalWeight += weight;
      }

      // Relaxed scoring curve for G, H, K, P, Q
      final double score = (100.0 - (totalWeightedDifference / totalWeight * 45.0)).clamp(0.0, 100.0);
      if (score > bestScore) bestScore = score;
    }
    return bestScore;
  }
}
