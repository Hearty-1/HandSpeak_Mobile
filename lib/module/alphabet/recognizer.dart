import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

class RecognitionResult {
  final String label;
  final double confidence; // Percentage 0.0 to 100.0

  RecognitionResult({required this.label, required this.confidence});
}

/// Consumes MediaPipe `Hand` results (via package:hand_landmarker) and runs
/// them through the FSL LSTM model.
class PhraseRecognizer {
  PhraseRecognizer({
    this.modelAssetPath = 'assets/phrases/fsl_model.tflite',
    this.labelAssetPath = 'assets/phrases/label_map.json',
    this.sequenceLength = 30,
  });

  final String modelAssetPath;
  final String labelAssetPath;
  final int sequenceLength;

  Interpreter? _interpreter;
  List<String> _labels = [];

  static const int _numHands = 2;
  static const int _numLandmarks = 21;
  static const int _numCoords = 3;
  static const int _featuresPerHand = _numLandmarks * _numCoords; // 63
  static const int _numFeatures = _numHands * _featuresPerHand; // 126

  late final List<Float32List> _frameBuffer = List.generate(
    sequenceLength,
    (_) => Float32List(_numFeatures),
  );

  bool _handsPresentInLastFrame = false;
  bool get handsPresentInLastFrame => _handsPresentInLastFrame;

  /// Initializes the TFLite interpreter and label mapping
  Future<void> initialize() async {
    final ByteData rawData = await rootBundle.load(modelAssetPath);

    if (rawData.lengthInBytes < 1000) {
      throw Exception(
        "Corrupted TFLite file (${rawData.lengthInBytes} bytes). "
        "Your model is a Git LFS text pointer! Download the raw file directly.",
      );
    }

    final Uint8List alignedBytes = Uint8List.fromList(
      rawData.buffer.asUint8List(rawData.offsetInBytes, rawData.lengthInBytes),
    );

    final options = InterpreterOptions()..threads = 2;
    _interpreter = Interpreter.fromBuffer(alignedBytes, options: options);

    _interpreter!.allocateTensors();
    final inputShape = _interpreter!.getInputTensor(0).shape;
    final expected = [1, sequenceLength, _numFeatures];
    if (!_shapeMatches(inputShape, expected)) {
      throw Exception(
        "Model input shape mismatch. Expected $expected but "
        "$modelAssetPath reports $inputShape. Re-export with "
        "train_lstm.py (check --sequence_length / feature count).",
      );
    }

    final labelData = await rootBundle.loadString(labelAssetPath);
    final dynamic decodedJson = json.decode(labelData);

    if (decodedJson is Map<String, dynamic>) {
      final entries = decodedJson.entries.toList();
      entries.sort((a, b) => (a.value as num).compareTo(b.value as num));
      _labels = entries.map((e) => e.key).toList();
    } else if (decodedJson is List) {
      _labels = decodedJson.map((e) => e.toString()).toList();
    }

    if (_labels.isEmpty) {
      throw Exception("Label map loaded but contains no class labels.");
    }

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final expectedOut = [1, _labels.length];
    if (!_shapeMatches(outputShape, expectedOut)) {
      throw Exception(
        "Model output shape $outputShape doesn't match label count "
        "$expectedOut. label_map.json and model were exported from "
        "different runs -- re-export both together.",
      );
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
    final out = List<double>.filled(_featuresPerHand, 0.0);
    for (int i = 0; i < _numLandmarks; i++) {
      final lm = landmarks[i];
      final base = i * _numCoords;
      out[base] = lm.x - wrist.x;
      out[base + 1] = lm.y - wrist.y;
      out[base + 2] = lm.z - wrist.z;
    }
    return out;
  }

  Float32List _extractFeatureVector(List<Hand> hands) {
    final vec = Float32List(_numFeatures);

    if (hands.isEmpty) return vec;

    final sorted = List<Hand>.from(hands)
      ..sort((a, b) => a.landmarks[0].x.compareTo(b.landmarks[0].x));

    for (int slot = 0; slot < _numHands && slot < sorted.length; slot++) {
      final normalized = _normalizeHand(sorted[slot].landmarks);
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
    if (frames.length == sequenceLength) return frames;
    return List<Float32List>.generate(sequenceLength, (i) {
      final double t = frames.length <= 1
          ? 0.0
          : i * (frames.length - 1) / (sequenceLength - 1);
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
    if (frames.length != sequenceLength) {
      return RecognitionResult(
        label: "ERR: expected $sequenceLength frames, got ${frames.length}",
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
    if (_interpreter == null || _labels.isEmpty || frames.length != sequenceLength) {
      return {};
    }
    try {
      final Float32List flatInput = Float32List(sequenceLength * _numFeatures);
      int index = 0;
      for (final frame in frames) {
        flatInput.setRange(index, index + _numFeatures, frame);
        index += _numFeatures;
      }

      final inputTensor = flatInput.reshape([1, sequenceLength, _numFeatures]);
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
        : _lastNFramesZeroPadded(rawFrames, sequenceLength);
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
    for (int i = 0; i < sequenceLength; i++) {
      _frameBuffer[i] = Float32List(_numFeatures);
    }
    _handsPresentInLastFrame = false;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}