import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class RecognitionResult {
  final String label;
  final double confidence; // Percentage 0.0 to 100.0

  RecognitionResult({required this.label, required this.confidence});
}

class PhraseRecognizer {
  Interpreter? _interpreter;
  List<String> _labels = [];
  
  final List<List<double>> _frameBuffer = [];
  final int _sequenceLength = 30; // 30 frames
  final int _numFeatures = 42;    // 21 hand landmarks * 2 coordinates (X, Y)

  /// Initializes the TFLite interpreter and label mapping
  Future<void> initialize() async {
    try {
      // 1. Load raw model bytes into memory
      final ByteData rawData = await rootBundle.load('assets/phrases/fsl_model.tflite');
      
      // Sanity Check: Detect if the asset is a Git LFS text pointer instead of a real binary
      if (rawData.lengthInBytes < 1000) {
        throw Exception(
          "Corrupted TFLite file (${rawData.lengthInBytes} bytes). "
          "Your model is a Git LFS text pointer! Download the raw file directly."
        );
      }

      final Uint8List alignedBytes = Uint8List.fromList(
        rawData.buffer.asUint8List(rawData.offsetInBytes, rawData.lengthInBytes),
      );

      // 2. Initialize TFLite Interpreter
      final options = InterpreterOptions()..threads = 2;
      _interpreter = Interpreter.fromBuffer(alignedBytes, options: options);

      // 3. Allocate memory buffers
      _interpreter!.allocateTensors();

      // 4. Load and Parse Label Map JSON
      final labelData = await rootBundle.loadString('assets/phrases/label_map.json');
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
    } catch (e) {
      rethrow;
    }
  }

  /// Processes incoming normalized hand landmarks (42 values) frame by frame
  RecognitionResult? processFrame(List<double> normalizedLandmarks) {
    if (normalizedLandmarks.length != _numFeatures) return null;

    // Deep copy landmarks to avoid frame-by-frame reference mutation
    _frameBuffer.add(List<double>.from(normalizedLandmarks));

    // Maintain a rolling buffer of exactly 30 frames (FIFO)
    if (_frameBuffer.length > _sequenceLength) {
      _frameBuffer.removeAt(0);
    }

    // Run prediction once buffer reaches full sequence length
    if (_frameBuffer.length == _sequenceLength) {
      return _predict();
    }
    
    return null;
  }

  RecognitionResult _predict() {
    if (_interpreter == null) {
      return RecognitionResult(label: "Model not loaded", confidence: 0.0);
    }

    if (_labels.isEmpty) {
      return RecognitionResult(label: "Labels not loaded", confidence: 0.0);
    }

    try {
      // 1. Flatten 2D frame buffer into Float32List
      final Float32List flatInput = Float32List(_sequenceLength * _numFeatures);
      int index = 0;
      for (var frame in _frameBuffer) {
        for (var val in frame) {
          flatInput[index++] = val;
        }
      }

      // 2. Reshape input tensor [1, 30, 42]
      final inputTensor = flatInput.reshape([1, _sequenceLength, _numFeatures]);

      // 3. Prepare output tensor shape [1, num_classes]
      final outputTensor = List.filled(1 * _labels.length, 0.0).reshape([1, _labels.length]);

      // 4. Run TFLite inference engine
      _interpreter!.run(inputTensor, outputTensor);

      // 5. Extract probabilities safely
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
      return RecognitionResult(
        label: "ERR: $e", 
        confidence: 0.0,
      );
    }

    return RecognitionResult(label: "Waiting for sign...", confidence: 0.0);
  }

  void resetBuffer() {
    _frameBuffer.clear();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _frameBuffer.clear();
  }
}