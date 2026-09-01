import 'dart:convert';
import 'dart:math' as math;
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

  // True when the loaded model has a single sigmoid output neuron (shape
  // [1, 1]) rather than one softmax unit per label (shape [1, labels.length]).
  // scripts/train_gesture_lstm.py produces this for isolated binary models
  // (`--target alphabet_j`), which is how the J/Z models are trained: the
  // model emits P(positive class) only, while `_labels` still has 2 entries
  // (out_labels = [f"not_{target}", target]) so downstream code that expects
  // a label per class keeps working unchanged.
  bool _binarySigmoidOutput = false;

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

  /// Initializes the TFLite interpreter from local assets
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

    await _loadInterpreterFromBytes(alignedBytes);
  }

  /// Initializes the TFLite interpreter directly from an in-memory byte buffer
  Future<void> initializeFromBuffer(Uint8List modelBytes, {List<String>? customLabels}) async {
    if (modelBytes.lengthInBytes < 1000) {
      throw Exception("Invalid or corrupted TFLite byte buffer length.");
    }

    await _loadInterpreterFromBytes(modelBytes, customLabels: customLabels);
  }

  Future<void> _loadInterpreterFromBytes(Uint8List modelBytes, {List<String>? customLabels}) async {
    final options = InterpreterOptions()..threads = 2;
    _interpreter = Interpreter.fromBuffer(modelBytes, options: options);

    _interpreter!.allocateTensors();
    final inputShape = _interpreter!.getInputTensor(0).shape;
    final expected = [1, sequenceLength, _numFeatures];
    if (!_shapeMatches(inputShape, expected)) {
      throw Exception(
        "Model input shape mismatch. Expected $expected but reports $inputShape.",
      );
    }

    if (customLabels != null && customLabels.isNotEmpty) {
      _labels = customLabels;
    } else {
      final labelData = await rootBundle.loadString(labelAssetPath);
      final dynamic decodedJson = json.decode(labelData);

      if (decodedJson is Map<String, dynamic>) {
        final entries = decodedJson.entries.toList();
        entries.sort((a, b) => (a.value as num).compareTo(b.value as num));
        _labels = entries.map((e) => e.key).toList();
      } else if (decodedJson is List) {
        _labels = decodedJson.map((e) => e.toString()).toList();
      }
    }

    if (_labels.isEmpty) {
      throw Exception("Label map loaded but contains no class labels.");
    }

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final expectedOut = [1, _labels.length];

    if (_shapeMatches(outputShape, expectedOut)) {
      _binarySigmoidOutput = false;
    } else if (_labels.length == 2 && _shapeMatches(outputShape, [1, 1])) {
      // Binary classifier with a single sigmoid output neuron: the model
      // reports P(positive class) only, and P(negative) = 1 - that value.
      // See the class-level comment on _binarySigmoidOutput.
      _binarySigmoidOutput = true;
    } else {
      throw Exception(
        "Model output shape $outputShape doesn't match label count $expectedOut "
        "(and isn't a [1, 1] binary-sigmoid output for the 2 labels provided).",
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

  /// Extracts raw screen landmark coordinates without wrist normalization
  Float32List extractRawFrameFeatures(List<Hand> hands) {
    final vec = Float32List(_numFeatures);
    if (hands.isEmpty) return vec;

    final sorted = List<Hand>.from(hands)
      ..sort((a, b) => a.landmarks[0].x.compareTo(b.landmarks[0].x));

    for (int slot = 0; slot < _numHands && slot < sorted.length; slot++) {
      final landmarks = sorted[slot].landmarks;
      final start = slot * _featuresPerHand;
      for (int i = 0; i < _numLandmarks && i < landmarks.length; i++) {
        final base = start + i * _numCoords;
        vec[base] = landmarks[i].x;
        vec[base + 1] = landmarks[i].y;
        vec[base + 2] = landmarks[i].z;
      }
    }
    return vec;
  }

  // Landmark index of the middle-finger MCP, used as the scale reference —
  // must match MIDDLE_MCP in the web's lib/posture-metrics.ts.
  static const int _middleMcpIdx = 9;

  /// Converts a raw feature vector into wrist-centered, scale-normalized
  /// coordinates. This MUST exactly match
  /// lib/posture-metrics.ts:normalizeFeatureVector on the web, because that
  /// is the transform applied to every training sample before it reaches
  /// the LSTM (see scripts/export-training-dataset.js and
  /// train_gesture_lstm.py). Previously this only re-centered on the wrist
  /// and never divided by scale, so live predictions were fed feature
  /// vectors on a completely different scale than the ones the model was
  /// trained on — the model saw out-of-distribution input on every frame,
  /// which is why confidence stayed near 0 even for a correctly-performed
  /// sign.
  ///
  /// Both hand slots are normalized using hand slot 0's (the primary hand's)
  /// wrist and scale — never each hand's own — again to match the web,
  /// since for two-handed signs hand 2's position relative to hand 1 can be
  /// part of what the sign means.
  Float32List normalizeFrameVector(Float32List rawVec) {
    final Float32List normVec = Float32List(_numFeatures);

    final wristX = rawVec[0];
    final wristY = rawVec[1];
    final wristZ = rawVec[2];

    final midX = rawVec[_middleMcpIdx * _numCoords];
    final midY = rawVec[_middleMcpIdx * _numCoords + 1];
    final dx = midX - wristX;
    final dy = midY - wristY;
    final rawScale = math.sqrt(dx * dx + dy * dy);
    // Falls back to 1 when no primary hand is present (an all-zero vector),
    // matching the web's `|| 1` — keeps the vector all-zero instead of
    // dividing by zero.
    final scale = rawScale == 0.0 ? 1.0 : rawScale;

    for (int slot = 0; slot < _numHands; slot++) {
      final start = slot * _featuresPerHand;
      for (int i = 0; i < _numLandmarks; i++) {
        final base = start + i * _numCoords;
        normVec[base] = (rawVec[base] - wristX) / scale;
        normVec[base + 1] = (rawVec[base + 1] - wristY) / scale;
        normVec[base + 2] = (rawVec[base + 2] - wristZ) / scale;
      }
    }
    return normVec;
  }

  Float32List extractFrameFeatures(List<Hand> hands) {
    _handsPresentInLastFrame = hands.isNotEmpty;
    return extractRawFrameFeatures(hands);
  }

  RecognitionResult? processFrame(List<Hand> hands) {
    _handsPresentInLastFrame = hands.isNotEmpty;
    final rawVector = extractRawFrameFeatures(hands);
    final normVector = normalizeFrameVector(rawVector);

    _frameBuffer.removeAt(0);
    _frameBuffer.add(normVector);

    return _predict(_frameBuffer);
  }

  RecognitionResult? predictFromRecording(List<Float32List> rawFrames) {
    if (rawFrames.isEmpty) {
      return RecognitionResult(label: "No motion recorded", confidence: 0.0);
    }
    final resampled = _resampleToSequenceLength(rawFrames);
    final normalized = resampled.map((f) => normalizeFrameVector(f)).toList();
    return _predict(normalized);
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

      if (_binarySigmoidOutput) {
        final outputTensor = List.filled(1, 0.0).reshape([1, 1]);
        _interpreter!.run(inputTensor, outputTensor);

        final double p = (outputTensor[0][0] as num).toDouble();
        // _labels == [f"not_{target}", target] (see train_gesture_lstm.py),
        // so index 0 is the negative class and index 1 is the positive one.
        return {
          _labels[0]: 1.0 - p,
          _labels[1]: p,
        };
      }

      final outputTensor = List.filled(1 * _labels.length, 0.0).reshape([1, _labels.length]);
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
    final normalized = frames.map((f) => normalizeFrameVector(f)).toList();
    return _rawScores(normalized);
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