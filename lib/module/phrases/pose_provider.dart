import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Six upper-body points in the SAME order the model was trained with
/// (MediaPipe pose indices 11..16):
///   0: left shoulder   1: right shoulder
///   2: left elbow      3: right elbow
///   4: left wrist      5: right wrist
/// Each point is [x, y] normalised to 0..1 in the upright frame
/// (raw, un-mirrored camera frame -- same as the training script; x is only
/// mirrored when [PoseProvider.mirrorX] is true).
class PoseSnapshot {
  final List<List<double>> points;
  final DateTime timestamp;
  const PoseSnapshot(this.points, this.timestamp);
}

/// The `hand_landmarker` plugin only returns hands, but fsl_model.onnx also
/// expects 12 pose features (shoulders, elbows, wrists). This class produces
/// them from the same camera stream using ML Kit pose detection.
///
/// Frames are processed one at a time (busy-guard); the most recent result is
/// exposed through [latest].
class PoseProvider {
  PoseProvider({this.mirrorX = false});

  /// Mirror x (x = 1 - x). Keep false: the model was trained on un-flipped
  /// frames and must match [PhraseRecognizer.mirrorX].
  bool mirrorX;

  final PoseDetector _detector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );

  bool _busy = false;
  bool _closed = false;
  PoseSnapshot? _latest;

  /// Latest pose, or null when none was found recently.
  PoseSnapshot? latest({Duration maxAge = const Duration(milliseconds: 400)}) {
    final snap = _latest;
    if (snap == null) return null;
    if (DateTime.now().difference(snap.timestamp) > maxAge) return null;
    return snap;
  }

  Future<void> process(CameraImage image, int rotationDegrees) async {
    if (_busy || _closed) return;
    _busy = true;
    try {
      final input = _toInputImage(image, rotationDegrees);
      if (input == null) return;

      final poses = await _detector.processImage(input);
      if (_closed) return;
      if (poses.isEmpty) {
        _latest = null;
        return;
      }

      final lm = poses.first.landmarks;
      final ordered = <PoseLandmarkType>[
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.rightWrist,
      ];

      // ML Kit returns pixel coordinates of the upright (rotated) image.
      final bool swap = rotationDegrees == 90 || rotationDegrees == 270;
      final double w = (swap ? image.height : image.width).toDouble();
      final double h = (swap ? image.width : image.height).toDouble();

      final points = <List<double>>[];
      for (final type in ordered) {
        final p = lm[type];
        if (p == null) {
          _latest = null;
          return;
        }
        final double nx = p.x / w;
        points.add([mirrorX ? 1.0 - nx : nx, p.y / h]);
      }
      _latest = PoseSnapshot(points, DateTime.now());
    } catch (e) {
      debugPrint('PoseProvider: frame skipped: $e');
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image, int rotationDegrees) {
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
    if (rotation == null) return null;

    final Uint8List bytes;
    final InputImageFormat format;
    final int bytesPerRow;

    if (Platform.isAndroid) {
      if (image.planes.length == 1) {
        bytes = image.planes.first.bytes; // already NV21
      } else if (image.planes.length == 3) {
        bytes = _yuv420ToNv21(image);
      } else {
        return null;
      }
      format = InputImageFormat.nv21;
      bytesPerRow = image.width;
    } else {
      if (image.planes.length != 1) return null;
      bytes = image.planes.first.bytes;
      format = InputImageFormat.bgra8888;
      bytesPerRow = image.planes.first.bytesPerRow;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  /// Stride-aware YUV_420_888 -> NV21 conversion.
  Uint8List _yuv420ToNv21(CameraImage image) {
    final int w = image.width;
    final int h = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final out = Uint8List(w * h + (w * h) ~/ 2);
    int idx = 0;

    for (int row = 0; row < h; row++) {
      final int start = row * yPlane.bytesPerRow;
      out.setRange(idx, idx + w, yPlane.bytes, start);
      idx += w;
    }

    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;
    for (int row = 0; row < h ~/ 2; row++) {
      for (int col = 0; col < w ~/ 2; col++) {
        final int uvIndex = row * uvRowStride + col * uvPixelStride;
        out[idx++] = vPlane.bytes[uvIndex];
        out[idx++] = uPlane.bytes[uvIndex];
      }
    }
    return out;
  }

  Future<void> dispose() async {
    _closed = true;
    await _detector.close();
  }
}