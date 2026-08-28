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
///
/// Feature layout matches train_fsl_lstm.py exactly:
///   - Up to 2 hands per frame, sorted by ascending wrist x (this plugin
///     doesn't expose left/right handedness, so "sorted by x" is the
///     deterministic convention used on both the training and inference
///     sides).
///   - Each hand contributes 21 landmarks * 3 coords (x, y, z), normalized
///     wrist-relative: (x_i - x_0, y_i - y_0, z_i - z_0).
///   - A missing hand slot is zero-padded (63 zeros).
///   - Total: 2 * 21 * 3 = 126 features per frame.
class PhraseRecognizer {
  Interpreter? _interpreter;
  List<String> _labels = [];

  static const int _sequenceLength = 30; // frames per window
  static const int _numHands = 2;
  static const int _numLandmarks = 21;
  static const int _numCoords = 3;
  static const int _featuresPerHand = _numLandmarks * _numCoords; // 63
  static const int _numFeatures = _numHands * _featuresPerHand; // 126

  // Fixed-length ring buffer, always exactly _sequenceLength frames long.
  // It starts fully zero-padded so the model can run inference from the
  // very first camera frame instead of waiting to accumulate 30 real ones.
  final List<Float32List> _frameBuffer = List.generate(
    _sequenceLength,
    (_) => Float32List(_numFeatures),
  );

  bool _handsPresentInLastFrame = false;
  bool get handsPresentInLastFrame => _handsPresentInLastFrame;

  /// Initializes the TFLite interpreter and label mapping
  Future<void> initialize() async {
    // 1. Load raw model bytes into memory
    final ByteData rawData =
        await rootBundle.load('assets/phrases/fsl_model.tflite');

    // Sanity Check: Detect if the asset is a Git LFS text pointer instead of
    // a real binary
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

    // 3. Allocate memory buffers and verify the shape the model actually
    // expects, so a mismatched export fails loudly here instead of deep
    // inside a native buffer-size exception during a live demo.
    _interpreter!.allocateTensors();
    final inputShape = _interpreter!.getInputTensor(0).shape;
    final expected = [1, _sequenceLength, _numFeatures];
    if (!_shapeMatches(inputShape, expected)) {
      throw Exception(
        "Model input shape mismatch. Expected $expected but "
        "fsl_model.tflite reports $inputShape. Re-export with "
        "train_fsl_lstm.py (check SEQUENCE_LENGTH / NUM_FEATURES).",
      );
    }

    // 4. Load and Parse Label Map JSON
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

    if (_labels.isEmpty) {
      throw Exception("Label map loaded but contains no class labels.");
    }

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final expectedOut = [1, _labels.length];
    if (!_shapeMatches(outputShape, expectedOut)) {
      throw Exception(
        "Model output shape $outputShape doesn't match label count "
        "$expectedOut. label_map.json and fsl_model.tflite were exported "
        "from different runs -- re-export both together.",
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

  /// Wrist-relative normalization for a single hand's 21 landmarks.
  /// Mirrors normalize_hand() in train_fsl_lstm.py exactly.
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

  /// Builds this frame's 126-length feature vector from whatever hands
  /// MediaPipe detected (0, 1, or 2 of them).
  Float32List _extractFeatureVector(List<Hand> hands) {
    final vec = Float32List(_numFeatures);

    if (hands.isEmpty) return vec; // all zeros -> zero-padded hand frame

    // Deterministic left-to-right ordering since handedness isn't exposed.
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

  /// Feeds one camera frame's detection result into the sliding window and
  /// returns a prediction. Call this on every frame from
  /// `landmarkStream.listen(...)` -- the buffer is always full (zero-padded
  /// at start), so this returns a result on every call, not just once
  /// warmed up.
  RecognitionResult? processFrame(List<Hand> hands) {
    _handsPresentInLastFrame = hands.isNotEmpty;

    final frameVector = _extractFeatureVector(hands);

    // FIFO: drop oldest frame, push new one.
    _frameBuffer.removeAt(0);
    _frameBuffer.add(frameVector);

    return _predict();
  }

  RecognitionResult? _predict() {
    if (_interpreter == null) {
      return RecognitionResult(label: "Model not loaded", confidence: 0.0);
    }
    if (_labels.isEmpty) {
      return RecognitionResult(label: "Labels not loaded", confidence: 0.0);
    }

    try {
      // 1. Flatten the (30, 126) buffer into one Float32List
      final Float32List flatInput = Float32List(_sequenceLength * _numFeatures);
      int index = 0;
      for (final frame in _frameBuffer) {
        flatInput.setRange(index, index + _numFeatures, frame);
        index += _numFeatures;
      }

      // 2. Reshape input tensor [1, 30, 126]
      final inputTensor = flatInput.reshape([1, _sequenceLength, _numFeatures]);

      // 3. Prepare output tensor shape [1, num_classes]
      final outputTensor =
          List.filled(1 * _labels.length, 0.0).reshape([1, _labels.length]);

      // 4. Run TFLite inference
      _interpreter!.run(inputTensor, outputTensor);

      // 5. Extract probabilities
      final List<dynamic> rawScores = outputTensor[0] as List<dynamic>;
      double maxProb = -1.0;
      int maxIndex = -1;
      for (int i = 0; i < rawScores.length; i++) {
        final double score = (rawScores[i] as num).toDouble();
        if (score > maxProb) {
          maxProb = score;
          maxIndex = i;
        }
      }

      if (maxIndex != -1 && maxIndex < _labels.length) {
        return RecognitionResult(
          label: _labels[maxIndex],
          confidence: (maxProb * 100.0).clamp(0.0, 100.0),
        );
      }
    } catch (e) {
      return RecognitionResult(label: "ERR: $e", confidence: 0.0);
    }

    return RecognitionResult(label: "Waiting for sign...", confidence: 0.0);
  }

  /// Resets the buffer back to all-zero frames (e.g. when the user
  /// backs out of a practice attempt). Note this re-fills with zero
  /// vectors, NOT an empty list -- processFrame() assumes the buffer is
  /// always exactly _sequenceLength long.
  void resetBuffer() {
    for (int i = 0; i < _sequenceLength; i++) {
      _frameBuffer[i] = Float32List(_numFeatures);
    }
    _handsPresentInLastFrame = false;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
