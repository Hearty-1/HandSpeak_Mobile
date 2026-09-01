import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RecognitionResult {
  final String label;
  final double confidence; // Percentage 0.0 to 100.0

  RecognitionResult({required this.label, required this.confidence});
}

/// Consumes MediaPipe `Hand` results (via package:hand_landmarker) and runs
/// them through the FSL LSTM model.
class PhraseRecognizer {
  Interpreter? _interpreter;
  List<String> _labels = [];

  static const int _defaultSequenceLength = 30; // default frames per window
  int _sequenceLength = _defaultSequenceLength;
  static const int _numHands = 2;
  static const int _numLandmarks = 21;
  static const int _numCoords = 3;
  static const int _featuresPerHand = _numLandmarks * _numCoords; // 63
  static const int _numFeatures = _numHands * _featuresPerHand; // 126

  /// The model's fixed sequence length.
  int get sequenceLength => _sequenceLength;

  List<Float32List> _frameBuffer = [];

  bool _handsPresentInLastFrame = false;
  bool get handsPresentInLastFrame => _handsPresentInLastFrame;

  List<Landmark?> _lastSlotWrist = List<Landmark?>.filled(_numHands, null);

  void resetHandSlotTracking() {
    _lastSlotWrist = List<Landmark?>.filled(_numHands, null);
  }

  /// Initializes the TFLite interpreter and label mapping from assets or Firestore.
  Future<void> initialize({int? customSequenceLength}) async {
    if (customSequenceLength != null && customSequenceLength > 0) {
      _sequenceLength = customSequenceLength;
    }

    _frameBuffer = List.generate(
      _sequenceLength,
      (_) => Float32List(_numFeatures),
    );

    // 1. Load raw model bytes into memory
    final ByteData rawData =
        await rootBundle.load('assets/phrases/model.tflite');

    if (rawData.lengthInBytes < 1000) {
      throw Exception(
        "Corrupted TFLite file (${rawData.lengthInBytes} bytes). "
        "Your model is a Git LFS text pointer! Download the raw file directly.",
      );
    }

    final Uint8List alignedBytes = Uint8List.fromList(
      rawData.buffer.asUint8List(rawData.offsetInBytes, rawData.lengthInBytes),
    );

    // 2. Initialize TFLite Interpreter
    final options = InterpreterOptions()..threads = 2;
    _interpreter = Interpreter.fromBuffer(alignedBytes, options: options);

    _interpreter!.allocateTensors();
    final inputShape = _interpreter!.getInputTensor(0).shape;
    final expected = [1, _sequenceLength, _numFeatures];
    if (!_shapeMatches(inputShape, expected)) {
      throw Exception(
        "Model input shape mismatch. Expected $expected but "
        "model reports $inputShape.",
      );
    }

    // 3. Load Labels (Firestore First, Fallback to Local Asset)
    try {
      _labels = await _fetchLabelsFromFirestore();
    } catch (e) {
      // Fallback to local JSON if offline or Firestore query fails
      await _loadLocalLabels();
    }

    if (_labels.isEmpty) {
      await _loadLocalLabels();
    }

    if (_labels.isEmpty) {
      throw Exception("Label map loaded but contains no class labels.");
    }

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final expectedOut = [1, _labels.length];
    if (!_shapeMatches(outputShape, expectedOut)) {
      throw Exception(
        "Model output shape $outputShape doesn't match label count "
        "$expectedOut.",
      );
    }
  }

  /// Fetches label definitions directly from `gesture_training_data` collection in Firestore.
  Future<List<String>> _fetchLabelsFromFirestore() async {
    final query = await FirebaseFirestore.instance
        .collection('gesture_training_data')
        .get();

    final List<String> labels = [];
    for (var doc in query.docs) {
      final data = doc.data();
      if (data['status'] == 'active' || doc.id.startsWith('phrases_')) {
        String labelName = data['gestureKey'] ?? 
            doc.id.replaceFirst('phrases_', '').replaceAll('_', ' ');
        if (!labels.contains(labelName)) {
          labels.add(labelName);
        }
      }
    }
    labels.sort();
    return labels;
  }

  Future<void> _loadLocalLabels() async {
    final labelData =
        await rootBundle.loadString('assets/phrases/label_map.json');
    final dynamic decodedJson = json.decode(labelData);

    if (decodedJson is Map<String, dynamic>) {
      final entries = decodedJson.entries.toList();
      entries.sort((a, b) => (a.value as num).compareTo(b.value as num));
      _labels = entries.map((e) => e.key).toList();
    } else if (decodedJson is List) {
      _labels = decodedJson.map((e) => e.toString()).toList();
    }
  }

  bool _shapeMatches(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    for (int i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) return false;
    }
    return true;
  }

  List<double> _normalizeHand(List<Landmark> landmarks) {
    if (landmarks.length != _numLandmarks) {
      return List<double>.filled(_featuresPerHand, 0.0);
    }
    final wrist = landmarks[0];

    double maxDist = 0.0;
    final relative = List<List<double>>.generate(_numLandmarks, (i) {
      final lm = landmarks[i];
      final dx = lm.x - wrist.x;
      final dy = lm.y - wrist.y;
      final dz = lm.z - wrist.z;
      final dist = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (dist > maxDist) maxDist = dist;
      return [dx, dy, dz];
    });

    final double scale = maxDist > 1e-6 ? maxDist : 1.0;

    final out = List<double>.filled(_featuresPerHand, 0.0);
    for (int i = 0; i < _numLandmarks; i++) {
      final base = i * _numCoords;
      out[base] = relative[i][0] / scale;
      out[base + 1] = relative[i][1] / scale;
      out[base + 2] = relative[i][2] / scale;
    }
    return out;
  }

  double _wristDistance(Landmark a, Landmark b) {
    final dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  List<Hand?> _assignHandsToSlots(List<Hand> hands) {
    final capped = hands.length > _numHands ? hands.sublist(0, _numHands) : hands;
    final result = List<Hand?>.filled(_numHands, null);

    if (capped.isEmpty) return result;

    if (capped.length == 1) {
      final wrist = capped[0].landmarks[0];
      int slot = 0;
      final prev0 = _lastSlotWrist[0];
      final prev1 = _lastSlotWrist[1];
      if (prev0 != null && prev1 != null) {
        slot = _wristDistance(wrist, prev1) < _wristDistance(wrist, prev0) ? 1 : 0;
      } else if (prev0 == null && prev1 != null) {
        slot = 1;
      }
      result[slot] = capped[0];
      _lastSlotWrist[slot] = wrist;
      return result;
    }

    final a = capped[0];
    final b = capped[1];
    final aw = a.landmarks[0];
    final bw = b.landmarks[0];
    final prev0 = _lastSlotWrist[0];
    final prev1 = _lastSlotWrist[1];

    Hand slot0Hand, slot1Hand;
    if (prev0 == null || prev1 == null) {
      final sorted = [a, b]..sort((x, y) => x.landmarks[0].x.compareTo(y.landmarks[0].x));
      slot0Hand = sorted[0];
      slot1Hand = sorted[1];
    } else {
      final costStraight = _wristDistance(aw, prev0) + _wristDistance(bw, prev1);
      final costSwapped = _wristDistance(bw, prev0) + _wristDistance(aw, prev1);
      if (costSwapped < costStraight) {
        slot0Hand = b;
        slot1Hand = a;
      } else {
        slot0Hand = a;
        slot1Hand = b;
      }
    }

    result[0] = slot0Hand;
    result[1] = slot1Hand;
    _lastSlotWrist[0] = slot0Hand.landmarks[0];
    _lastSlotWrist[1] = slot1Hand.landmarks[0];
    return result;
  }

  Float32List _extractFeatureVector(List<Hand> hands) {
    final vec = Float32List(_numFeatures);
    if (hands.isEmpty) return vec;

    final assigned = _assignHandsToSlots(hands);
    for (int slot = 0; slot < _numHands; slot++) {
      final hand = assigned[slot];
      if (hand == null) continue;
      final normalized = _normalizeHand(hand.landmarks);
      final start = slot * _featuresPerHand;
      for (int i = 0; i < _featuresPerHand; i++) {
        vec[start + i] = normalized[i];
      }
    }
    return vec;
  }

  RecognitionResult? processFrame(List<Hand> hands) {
    _handsPresentInLastFrame = hands.isNotEmpty;
    final frameVector = _extractFeatureVector(hands);

    _frameBuffer.removeAt(0);
    _frameBuffer.add(frameVector);

    return _predict(_frameBuffer);
  }

  Float32List extractFrameFeatures(List<Hand> hands) {
    _handsPresentInLastFrame = hands.isNotEmpty;
    return _extractFeatureVector(hands);
  }

  RecognitionResult? predictFromRecording(List<Float32List> rawFrames) {
    if (rawFrames.isEmpty) {
      return RecognitionResult(label: "No motion recorded", confidence: 0.0);
    }
    final resampled = _resampleToSequenceLength(rawFrames);
    return _predict(resampled);
  }

  List<Float32List> _resampleToSequenceLength(List<Float32List> frames) {
    if (frames.length == _sequenceLength) return frames;
    return List<Float32List>.generate(_sequenceLength, (i) {
      final double t = frames.length <= 1
          ? 0.0
          : i * (frames.length - 1) / (_sequenceLength - 1);
      final int idx = t.round().clamp(0, frames.length - 1);
      return frames[idx];
    });
  }

  RecognitionResult? _predict(List<Float32List> frames) {
    if (_interpreter == null) {
      return RecognitionResult(label: "Model not loaded", confidence: 0.0);
    }
    if (_labels.isEmpty) {
      return RecognitionResult(label: "Labels not loaded", confidence: 0.0);
    }
    if (frames.length != _sequenceLength) {
      return RecognitionResult(
        label: "ERR: expected $_sequenceLength frames, got ${frames.length}",
        confidence: 0.0,
      );
    }

    final scores = _rawScores(frames);
    if (scores.isEmpty) {
      return RecognitionResult(label: "ERR: inference failed", confidence: 0.0);
    }

    String bestLabel = "Waiting for sign...";
    double bestScore = -1.0;
    scores.forEach((label, score) {
      if (score > bestScore) {
        bestScore = score;
        bestLabel = label;
      }
    });

    return RecognitionResult(
      label: bestLabel,
      confidence: (bestScore * 100.0).clamp(0.0, 100.0),
    );
  }

  Map<String, double> _rawScores(List<Float32List> frames) {
    if (_interpreter == null || _labels.isEmpty || frames.length != _sequenceLength) {
      return {};
    }
    try {
      final Float32List flatInput = Float32List(_sequenceLength * _numFeatures);
      int index = 0;
      for (final frame in frames) {
        flatInput.setRange(index, index + _numFeatures, frame);
        index += _numFeatures;
      }

      final inputTensor = flatInput.reshape([1, _sequenceLength, _numFeatures]);
      final outputTensor =
          List.filled(1 * _labels.length, 0.0).reshape([1, _labels.length]);

      _interpreter!.run(inputTensor, outputTensor);

      final List<dynamic> rawScores = outputTensor[0] as List<dynamic>;
      final Map<String, double> result = {};
      for (int i = 0; i < _labels.length && i < rawScores.length; i++) {
        result[_labels[i]] = (rawScores[i] as num).toDouble();
      }
      return result;
    } catch (e) {
      return {};
    }
  }

  Map<String, double> rawScoresForRecording(
    List<Float32List> rawFrames, {
    bool resample = true,
  }) {
    if (rawFrames.isEmpty) return {};
    final frames = resample
        ? _resampleToSequenceLength(rawFrames)
        : _lastNFramesZeroPadded(rawFrames, _sequenceLength);
    return _rawScores(frames);
  }

  List<Float32List> _lastNFramesZeroPadded(List<Float32List> frames, int n) {
    if (frames.length >= n) return frames.sublist(frames.length - n);
    final pad = List<Float32List>.generate(
      n - frames.length,
      (_) => Float32List(_numFeatures),
    );
    return [...pad, ...frames];
  }

  void resetBuffer() {
    for (int i = 0; i < _sequenceLength; i++) {
      _frameBuffer[i] = Float32List(_numFeatures);
    }
    _handsPresentInLastFrame = false;
    resetHandSlotTracking();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}