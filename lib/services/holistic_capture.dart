import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'performance_monitor.dart';

/// One captured camera frame in the raw form the v4 server pipeline
/// (/v1/predict_raw/{model}) expects: pose = 33 x [x, y, visibility],
/// hands = 21 x [x, y, z] (null = not detected), normalised to the upright,
/// UN-mirrored camera image; left = the signer's own left hand (assigned
/// natively from the pose wrists, like MediaPipe Holistic).
class RawFrame {
  final List<List<double>>? pose;
  final List<List<double>>? leftHand;
  final List<List<double>>? rightHand;
  final int timeMs;
  const RawFrame({this.pose, this.leftHand, this.rightHand, required this.timeMs});

  bool get hasPose => pose != null;
  bool get hasHands => leftHand != null || rightHand != null;

  Map<String, dynamic> toJson(int t0Ms) => {
        't': (timeMs - t0Ms) / 1000.0,
        'pose': pose,
        'left_hand': leftHand,
        'right_hand': rightHand,
      };
}

/// Result of processing one camera image natively.
class HolisticResult {
  final RawFrame frame;
  final int imageWidth;
  final int imageHeight;
  final String engine; // e.g. "pose_landmarker_full/GPU, hands/GPU"
  /// Body in view (also true on frames where native skipped the pose model
  /// for speed; those frames carry pose = null and the server interpolates).
  final bool poseVisible;
  const HolisticResult(this.frame, this.imageWidth, this.imageHeight, this.engine,
      {this.poseVisible = false});
}

/// Raw Pose + Hands capture through the native "fsl_holistic_channel"
/// (MainActivity.kt), shared by every screen that uses a v4 server model
/// (Lupang Hinirang, Calendar).
class HolisticCapture {
  static const MethodChannel _channel = MethodChannel('fsl_holistic_channel');

  static List<List<double>>? _points(dynamic v) => v is List
      ? [for (final p in v) [for (final c in p as List) (c as num).toDouble()]]
      : null;

  /// Sends the camera planes to native code (converted there once) and
  /// returns the raw landmarks, or null when the frame could not be read.
  static Future<HolisticResult?> process(CameraImage image, int rotation) async {
    final planes = image.planes;
    if (planes.length < 3) return null;
    // Capture time, not result time: frames are processed in a pipeline, so
    // the result arrives a variable ~100-200 ms later.
    final capturedMs = DateTime.now().millisecondsSinceEpoch;
    final dynamic res = await _channel.invokeMethod('processFrame', {
      'y': planes[0].bytes,
      'u': planes[1].bytes,
      'v': planes[2].bytes,
      'yRowStride': planes[0].bytesPerRow,
      'uvRowStride': planes[1].bytesPerRow,
      'uvPixelStride': planes[1].bytesPerPixel ?? 1,
      'width': image.width,
      'height': image.height,
      'rotation': rotation,
    });
    if (res is! Map) return null;
    PerformanceMonitor.instance.reportCameraResult(DateTime.now().millisecondsSinceEpoch - capturedMs);
    return HolisticResult(
      RawFrame(
        pose: _points(res['pose33']),
        leftHand: _points(res['leftHand']),
        rightHand: _points(res['rightHand']),
        timeMs: capturedMs,
      ),
      (res['imageWidth'] as num?)?.toInt() ?? 0,
      (res['imageHeight'] as num?)?.toInt() ?? 0,
      (res['engine'] as String?) ?? '',
      poseVisible: res['hasPose'] == true,
    );
  }

  /// Training clips are cut close around the sign (calendar_common.py even
  /// trims still edges: trim_still=True). Holds longer than [maxHoldMs] at
  /// either end are cut back to that length, so a motionless start / end does
  /// not trip the PHASE_IMBALANCE gate; a short final pose is kept.
  static List<RawFrame> trimIdleHolds(
    List<RawFrame> frames,
    int imageWidth,
    int imageHeight, {
    int maxHoldMs = 600,
    double holdSpeed = 0.35, // shoulder spans per second
  }) {
    if (frames.length < 4) return frames;
    final aspect = (imageWidth > 0 && imageHeight > 0) ? imageWidth / imageHeight : 1.0;

    List<List<double>>? wrists(RawFrame f) {
      final p = f.pose;
      if (p == null || p.length < 17) return null;
      final dx = (p[11][0] - p[12][0]) * aspect, dy = p[11][1] - p[12][1];
      final span = sqrt(dx * dx + dy * dy);
      if (span < 1e-3) return null;
      List<double> at(List<double> pt) => [pt[0] * aspect / span, pt[1] / span];
      return [
        at(f.leftHand != null ? f.leftHand![0] : p[15]),
        at(f.rightHand != null ? f.rightHand![0] : p[16]),
      ];
    }

    final moving = List<bool>.filled(frames.length, false);
    // Compared with the last frame that had a pose (native may run the pose
    // model on every other frame only).
    List<List<double>>? a;
    int aMs = 0;
    for (int i = 0; i < frames.length; i++) {
      final b = wrists(frames[i]);
      if (b == null) continue;
      final prev = a, prevMs = aMs;
      a = b;
      aMs = frames[i].timeMs;
      final dt = (aMs - prevMs) / 1000.0;
      if (prev == null || dt <= 0) continue;
      final a0 = prev;
      double d = 0;
      for (int k = 0; k < 2; k++) {
        d = max(d, sqrt(pow(b[k][0] - a0[k][0], 2) + pow(b[k][1] - a0[k][1], 2)));
      }
      moving[i] = d / dt > holdSpeed;
    }
    final first = moving.indexOf(true), last = moving.lastIndexOf(true);
    if (first == -1) return frames; // no clear motion: let the server judge it

    int start = 0, end = frames.length;
    while (start < first && frames[first].timeMs - frames[start].timeMs > maxHoldMs) {
      start++;
    }
    while (end - 1 > last && frames[end - 1].timeMs - frames[last].timeMs > maxHoldMs) {
      end--;
    }
    return frames.sublist(start, end);
  }

  /// v4 rejection codes (lupang_common.REJECT_TEXT) -> what to do differently.
  static const Map<String, String> rejectAdvice = {
    'NO_HANDS': "Walang nakitang kamay. Ipakita ang katawan at mga kamay sa camera.",
    'TOO_SHORT': "Masyadong maikli. Isagawa ang buong senyas.",
    'FRAGMENT_DURATION': "Kulang pa ang haba ng kumpas. Isagawa nang buo at hindi nagmamadali.",
    'LOW_MOTION': "Kulang ang galaw. Isagawa nang buo ang kumpas.",
    'PHASE_IMBALANCE': "Simulan agad ang kumpas at ibaba ang kamay pagkatapos; huwag tumigil nang matagal.",
    'SINGLE_STROKE': "Isang galaw lang ang nakita. Isagawa ang lahat ng bahagi ng senyas.",
    'INVALID_CLASS': "Hindi makilala ang senyas. Sundan ang halimbawa.",
    'LOW_CONFIDENCE': "Hindi pa tiyak ang kumpas. Gawin nang mas malinaw at buo.",
    'SMALL_MARGIN': "Hindi pa tiyak ang kumpas. Gawin nang mas malinaw at buo.",
    'HIGH_ENTROPY': "Hindi pa tiyak ang kumpas. Gawin nang mas malinaw at buo.",
  };
}
