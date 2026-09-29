import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '/services/progress_service.dart';
import 'onnx_env_manager.dart';

// =============================================================================
// DATA MODELS
// =============================================================================

class LandmarkPoint {
  final double x, y, z;
  LandmarkPoint(this.x, this.y, this.z);
}

class FrameLandmarks {
  final List<LandmarkPoint> points; // Expects 68 points per frame
  FrameLandmarks(this.points);
}

// =============================================================================
// WIDGET IMPLEMENTATION
// =============================================================================

class CivicTutorialPractice extends StatefulWidget {
  final String category;
  final List<Map<String, dynamic>>? questions;

  const CivicTutorialPractice({
    super.key,
    this.category = 'lupang_hinirang',
    this.questions,
  });

  @override
  State<CivicTutorialPractice> createState() => _CivicTutorialPracticeState();
}

class _CivicTutorialPracticeState extends State<CivicTutorialPractice> with WidgetsBindingObserver {
  static const MethodChannel _platformChannel = MethodChannel('fsl_holistic_channel');
  
  // Performance and Frame Rate Throttling
  bool _isNativeProcessing = false;
  int _lastFrameTimestamp = 0;
  static const int _frameIntervalMs = 180; // ~5.5 FPS throttle for peak stability

  // Reused across frames instead of allocating a new Uint8List every callback
  Uint8List? _reusableFrameBuffer;
  int? _cachedTotalFrameLength;

  bool _isDisposed = false;

  // Bootup / Loading state tracking
  String _loadingStatus = "Inihahanda ang pagsasanay...";
  bool _isBootstrapping = true;

  int _currentStep = 0;
  int _score = 0;
  bool _progressSaved = false;

  static final Map<String, Uint8List> _templateImageCache = {};
  Uint8List? _templateImageBytes;
  bool _isImageLoading = false;

  // Model and Dynamic JSON Data
  OrtSession? _ortSession;
  List<Map<String, dynamic>> _phrases = [];
  List<Map<String, dynamic>> _activeQuestions = [];
  
  // Dynamic ONNX tensor shape configuration
  List<int> _inputShape = [1, 818];
  int _inputTensorSize = 818; 
  bool _isModelLoaded = false;

  static const int targetFrames = 32;
  static const int totalLandmarks = 68;
  final List<FrameLandmarks> _frameBuffer = [];
  bool _isEvaluating = false;

  CameraController? _controller;
  bool _isInitialized = false;

  bool _isSuccessAchieved = false;
  double _currentScore = 0.0;
  String _currentFeedback = "Maghanda at isagawa ang kumpas...";
  final double successThreshold = 0.70; // 70% passing threshold
  final int xpReward = 15;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapPipeline();
    });
  }

  Future<void> _bootstrapPipeline() async {
    OnnxEnvManager.ensureInitialized();

    _updateLoadingStatus("Naglo-load ng modelo at camera...");

    await Future.wait([
      _loadOnnxModelAndLabels(),
      _initializePipeline(),
    ]);

    if (mounted) {
      setState(() {
        _isBootstrapping = false;
      });
    }
  }

  void _updateLoadingStatus(String status) {
    if (mounted) {
      setState(() => _loadingStatus = status);
    }
  }

  String _normalizeCategoryKey(String cat) {
    final lower = cat.toLowerCase();
    if (lower.contains('lupang') || lower.contains('hinirang')) return 'lupang_hinirang';
    if (lower.contains('panata')) return 'panata';
    if (lower.contains('panunumpa')) return 'panunumpa';
    return lower.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  Future<void> _loadOnnxModelAndLabels() async {
    final key = _normalizeCategoryKey(widget.category);
    try {
      final labelPath = 'assets/civic/labels_$key.json';
      final jsonStr = await rootBundle.loadString(labelPath);
      final manifest = jsonDecode(jsonStr);

      _phrases = List<Map<String, dynamic>>.from(manifest['phrases']);
      
      // Parse tensor shape dynamically from manifest
      if (manifest['input_tensor_shape'] != null && manifest['input_tensor_shape'] is List) {
        _inputShape = List<int>.from((manifest['input_tensor_shape'] as List).map((e) => (e as num).toInt()));
        _inputTensorSize = _inputShape.fold<int>(1, (acc, val) => acc * val);
      }

      if (widget.questions != null && widget.questions!.isNotEmpty) {
        _activeQuestions = widget.questions!;
      } else {
        _activeQuestions = _phrases.map((p) => {
          'id': p['label'],
          'question': p['label'],
          'instruction': p['instruction'] ?? '',
          'folder_code': p['folder_code'] ?? '',
        }).toList();
      }

      final modelPath = 'assets/civic/fsl_$key.onnx';
      final rawModel = await rootBundle.load(modelPath);

      await Future.delayed(Duration.zero);
      _ortSession = OrtSession.fromBuffer(rawModel.buffer.asUint8List(), OrtSessionOptions());

      if (!_isDisposed && mounted) {
        _isModelLoaded = true;
        _loadCurrentStepData();
      }
    } catch (e) {
      debugPrint("Error loading assets for $key: $e");
    }
  }

  Future<void> _loadCurrentStepData() async {
    if (_isDisposed || _activeQuestions.isEmpty || _currentStep >= _activeQuestions.length) return;
    
    final categoryKey = _normalizeCategoryKey(widget.category);
    final normalizedKey = '${categoryKey}_line_${_currentStep + 1}';
    
    if (_templateImageCache.containsKey(normalizedKey)) {
      if (mounted) setState(() => _templateImageBytes = _templateImageCache[normalizedKey]);
      return;
    }

    if (mounted) setState(() => _isImageLoading = true);
    try {
      final ref = FirebaseStorage.instance.ref().child('civic_templates/$normalizedKey.jpg');
      
      final Uint8List? data = await ref.getData(1024 * 1024).timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );

      if (data != null) {
        _templateImageCache[normalizedKey] = data;
        if (mounted) setState(() => _templateImageBytes = data);
      } else {
        if (mounted) setState(() => _templateImageBytes = null);
      }
    } catch (e) {
      debugPrint("Template image unavailable ($normalizedKey): $e");
      if (mounted) setState(() => _templateImageBytes = null);
    } finally {
      if (mounted) setState(() => _isImageLoading = false);
    }
  }

  Future<void> _initializePipeline() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty || _isDisposed) return;

      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front, 
        orElse: () => cameras.first,
      );
      
      _controller = CameraController(
        frontCamera, 
        ResolutionPreset.low, 
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      
      await _controller!.initialize();

      if (_isDisposed) {
        await _controller?.dispose();
        return;
      }

      if (mounted) setState(() => _isInitialized = true);

      if (mounted && _controller != null && _controller!.value.isInitialized) {
        await _controller!.startImageStream(_processCameraFrame);
      }
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  Future<void> _pauseCamera() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await controller.dispose();
    _controller = null;
    if (mounted) setState(() => _isInitialized = false);
  }

  Future<void> _resumeCamera() async {
    if (_isDisposed || _controller != null) return;
    await _initializePipeline();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _pauseCamera();
        break;
      case AppLifecycleState.resumed:
        _resumeCamera();
        break;
      default:
        break;
    }
  }

  // Interleaves Flutter YUV420 planes into standard Android NV21 byte order[cite: 28]
  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = ySize ~/ 2;
    
    if (_cachedTotalFrameLength != ySize + uvSize || _reusableFrameBuffer == null) {
      _cachedTotalFrameLength = ySize + uvSize;
      _reusableFrameBuffer = Uint8List(ySize + uvSize);
    }
    final Uint8List nv21 = _reusableFrameBuffer!;

    final yPlane = image.planes[0];
    final yBytes = yPlane.bytes;
    final yRowStride = yPlane.bytesPerRow;
    
    if (yRowStride == width) {
      nv21.setRange(0, ySize, yBytes);
    } else {
      for (int r = 0; r < height; r++) {
        nv21.setRange(r * width, (r + 1) * width, 
            yBytes.sublist(r * yRowStride, r * yRowStride + width));
      }
    }

    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;
    
    int nv21Index = ySize;
    final int halfHeight = height ~/ 2;
    final int halfWidth = width ~/ 2;

    for (int r = 0; r < halfHeight; r++) {
      int uIndex = r * uPlane.bytesPerRow;
      int vIndex = r * vPlane.bytesPerRow;
      for (int c = 0; c < halfWidth; c++) {
        nv21[nv21Index++] = vBytes[vIndex];
        nv21[nv21Index++] = uBytes[uIndex];
        uIndex += uPlane.bytesPerPixel ?? 1;
        vIndex += vPlane.bytesPerPixel ?? 1;
      }
    }
    
    return nv21;
  }

  void _processCameraFrame(CameraImage image) async {
    if (!_isModelLoaded || _isSuccessAchieved || _isEvaluating || _isNativeProcessing || _isDisposed) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFrameTimestamp < _frameIntervalMs) return;
    
    _lastFrameTimestamp = now;
    _isNativeProcessing = true;

    try {
      final Uint8List nv21Bytes = _convertYUV420ToNV21(image);

      final dynamic res = await _platformChannel.invokeMethod('processFrame', {
        'yuvBytes': nv21Bytes, 
        'width': image.width, 
        'height': image.height,
        'rotation': _controller?.description.sensorOrientation ?? 0,
      });

      if (_isDisposed) return; 

      if (res is List) {
        final List<double> rawFloats = (res as List)
            .map((e) => (e as num).toDouble())
            .toList();

        if (rawFloats.length >= totalLandmarks * 3) {
          final List<LandmarkPoint> pts = List.generate(
            totalLandmarks, 
            (i) => LandmarkPoint(rawFloats[i * 3], rawFloats[i * 3 + 1], rawFloats[i * 3 + 2]),
          );

          final bool hasLandmarks = pts.any((p) => p.x != 0.0 || p.y != 0.0 || p.z != 0.0);
          if (hasLandmarks) {
            _onHolisticLandmarksDetected(FrameLandmarks(pts));
          } else if (mounted && !_isSuccessAchieved) {
            setState(() {
              _currentFeedback = "Ipakita ang kamay sa camera...";
              _currentScore = 0.0;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Platform Channel Error: $e");
    } finally {
      _isNativeProcessing = false;
    }
  }

  void _onHolisticLandmarksDetected(FrameLandmarks frameData) {
    if (_isDisposed) return;
    if (mounted) setState(() => _frameBuffer.add(frameData));
    if (_frameBuffer.length >= targetFrames) {
      final sequence = List<FrameLandmarks>.from(_frameBuffer);
      _frameBuffer.removeAt(0);
      _evaluateSequence(sequence);
    }
  }

  // Multi-model Feature Extractor Router
  Float32List _extractFeatures(List<FrameLandmarks> seq) {
    final catKey = _normalizeCategoryKey(widget.category);
    if (catKey == 'lupang_hinirang' || _inputTensorSize == 818) {
      return _extractFeatures818(seq);
    } else {
      return _extractFeatures842(seq);
    }
  }

  // Normalizes landmarks by center torso & shoulder distance, then extracts
  // 818 holistic features matching Python train_lupang_hinirang.py
  Float32List _extractFeatures818(List<FrameLandmarks> seq) {
    List<List<List<double>>> normClip = List.generate(
      targetFrames,
      (_) => List.generate(totalLandmarks, (_) => [0.0, 0.0, 0.0]),
    );

    for (int t = 0; t < targetFrames; t++) {
      final pts = seq[t].points;
      if (pts.length < totalLandmarks) continue;

      double cX = (pts[0].x + pts[1].x) / 2.0;
      double cY = (pts[0].y + pts[1].y) / 2.0;
      double cZ = (pts[0].z + pts[1].z) / 2.0;

      double dx = pts[0].x - pts[1].x;
      double dy = pts[0].y - pts[1].y;
      double dz = pts[0].z - pts[1].z;
      double shoulderDist = sqrt(dx * dx + dy * dy + dz * dz) + 1e-6;

      for (int i = 0; i < totalLandmarks; i++) {
        if (i < pts.length) {
          normClip[t][i][0] = (pts[i].x - cX) / shoulderDist;
          normClip[t][i][1] = (pts[i].y - cY) / shoulderDist;
          normClip[t][i][2] = (pts[i].z - cZ) / shoulderDist;
        }
      }
    }

    double totalEnergyLh = 0.0;
    double totalEnergyRh = 0.0;

    for (int t = 0; t < targetFrames - 1; t++) {
      for (int i = 14; i <= 34; i++) {
        double dX = normClip[t + 1][i][0] - normClip[t][i][0];
        double dY = normClip[t + 1][i][1] - normClip[t][i][1];
        double dZ = normClip[t + 1][i][2] - normClip[t][i][2];
        totalEnergyLh += sqrt(dX * dX + dY * dY + dZ * dZ);
      }
      for (int i = 35; i <= 55; i++) {
        double dX = normClip[t + 1][i][0] - normClip[t][i][0];
        double dY = normClip[t + 1][i][1] - normClip[t][i][1];
        double dZ = normClip[t + 1][i][2] - normClip[t][i][2];
        totalEnergyRh += sqrt(dX * dX + dY * dY + dZ * dZ);
      }
    }

    List<double> computePhaseMean(int startFrame, int endFrame) {
      List<double> phase = List.filled(totalLandmarks * 3, 0.0);
      int count = endFrame - startFrame;
      for (int t = startFrame; t < endFrame; t++) {
        int idx = 0;
        for (int i = 0; i < totalLandmarks; i++) {
          phase[idx++] += normClip[t][i][0];
          phase[idx++] += normClip[t][i][1];
          phase[idx++] += normClip[t][i][2];
        }
      }
      for (int k = 0; k < phase.length; k++) {
        phase[k] /= count;
      }
      return phase;
    }

    List<double> pStart = computePhaseMean(0, 4);   // 204
    List<double> pMid = computePhaseMean(14, 18);   // 204
    List<double> pEnd = computePhaseMean(28, 32);   // 204

    List<double> deltaMovement = List.filled(204, 0.0);
    for (int k = 0; k < 204; k++) {
      deltaMovement[k] = pEnd[k] - pStart[k];
    }

    List<double> features = [];
    features.addAll(pStart);        // 204
    features.addAll(pMid);          // 204
    features.addAll(pEnd);          // 204
    features.addAll(deltaMovement); // 204
    features.add(totalEnergyLh);    // 1
    features.add(totalEnergyRh);    // 1

    return Float32List.fromList(features);
  }

  // Extracts 842 advanced features matching train_panata_final_2.py & train_panunumpa_final_2.py
  Float32List _extractFeatures842(List<FrameLandmarks> seq) {
    List<List<List<double>>> normClip = List.generate(
      targetFrames,
      (_) => List.generate(totalLandmarks, (_) => [0.0, 0.0, 0.0]),
    );

    for (int t = 0; t < targetFrames; t++) {
      final pts = seq[t].points;
      if (pts.length < totalLandmarks) continue;

      double cX = (pts[0].x + pts[1].x) / 2.0;
      double cY = (pts[0].y + pts[1].y) / 2.0;
      double cZ = (pts[0].z + pts[1].z) / 2.0;

      double dx = pts[0].x - pts[1].x;
      double dy = pts[0].y - pts[1].y;
      double dz = pts[0].z - pts[1].z;
      double shoulderDist = sqrt(dx * dx + dy * dy + dz * dz) + 1e-6;

      for (int i = 0; i < totalLandmarks; i++) {
        if (i < pts.length) {
          normClip[t][i][0] = (pts[i].x - cX) / shoulderDist;
          normClip[t][i][1] = (pts[i].y - cY) / shoulderDist;
          normClip[t][i][2] = (pts[i].z - cZ) / shoulderDist;
        }
      }
    }

    List<double> computeSliceMean(int startFrame, int endFrame) {
      List<double> slice = List.filled(totalLandmarks * 3, 0.0);
      int count = endFrame - startFrame;
      for (int t = startFrame; t < endFrame; t++) {
        int idx = 0;
        for (int i = 0; i < totalLandmarks; i++) {
          slice[idx++] += normClip[t][i][0];
          slice[idx++] += normClip[t][i][1];
          slice[idx++] += normClip[t][i][2];
        }
      }
      for (int k = 0; k < slice.length; k++) {
        slice[k] /= count;
      }
      return slice;
    }

    // 4 Dynamic Slices (4 * 204 = 816)
    List<double> slice0 = computeSliceMean(0, 8);
    List<double> slice1 = computeSliceMean(8, 16);
    List<double> slice2 = computeSliceMean(16, 24);
    List<double> slice3 = computeSliceMean(24, 32);

    double dist3d(List<double> p1, List<double> p2) {
      double dx = p1[0] - p2[0];
      double dy = p1[1] - p2[1];
      double dz = p1[2] - p2[2];
      return sqrt(dx * dx + dy * dy + dz * dz);
    }

    // Finger Curl Geometry
    const fingerTips = [4, 8, 12, 16, 20];
    List<double> rhCurls = [];
    List<double> lhCurls = [];

    for (final tip in fingerTips) {
      List<double> dRh = [];
      List<double> dLh = [];
      for (int t = 0; t < targetFrames; t++) {
        dRh.add(dist3d(normClip[t][35 + tip], normClip[t][35]));
        dLh.add(dist3d(normClip[t][14 + tip], normClip[t][14]));
      }
      double meanRh = dRh.reduce((a, b) => a + b) / targetFrames;
      double rangeRh = dRh.reduce(max) - dRh.reduce(min);
      rhCurls.addAll([meanRh, rangeRh]);

      double meanLh = dLh.reduce((a, b) => a + b) / targetFrames;
      double rangeLh = dLh.reduce(max) - dLh.reduce(min);
      lhCurls.addAll([meanLh, rangeLh]);
    }

    // Elevation relative to Nose (idx 56) & Chest ([0,0,0])
    List<double> rhToNose = [];
    List<double> rhToChest = [];
    for (int t = 0; t < targetFrames; t++) {
      rhToNose.add(dist3d(normClip[t][35], normClip[t][56]));
      rhToChest.add(dist3d(normClip[t][35], [0.0, 0.0, 0.0]));
    }

    double rhNoseMean = rhToNose.reduce((a, b) => a + b) / targetFrames;
    double rhNoseMin = rhToNose.reduce(min);
    double rhChestMean = rhToChest.reduce((a, b) => a + b) / targetFrames;
    double rhChestMin = rhToChest.reduce(min);

    // Speeds & Total Energy
    double totalSpeedRH = 0.0;
    double totalSpeedLH = 0.0;

    for (int t = 0; t < targetFrames - 1; t++) {
      for (int k = 35; k <= 55; k++) {
        totalSpeedRH += dist3d(normClip[t + 1][k], normClip[t][k]);
      }
      for (int k = 14; k <= 34; k++) {
        totalSpeedLH += dist3d(normClip[t + 1][k], normClip[t][k]);
      }
    }

    List<double> features = [];
    features.addAll(slice0);    // 204
    features.addAll(slice1);    // 204
    features.addAll(slice2);    // 204
    features.addAll(slice3);    // 204
    features.addAll(rhCurls);   // 10
    features.addAll(lhCurls);   // 10
    features.add(rhNoseMean);   // 1
    features.add(rhNoseMin);    // 1
    features.add(rhChestMean);  // 1
    features.add(rhChestMin);   // 1
    features.add(totalSpeedLH); // 1
    features.add(totalSpeedRH); // 1

    return Float32List.fromList(features);
  }

  List<double> _softmax(List<double> logits) {
    if (logits.isEmpty) return [];
    double maxLogit = logits.reduce(max);
    List<double> expValues = logits.map((e) => exp(e - maxLogit)).toList();
    double sumExp = expValues.reduce((a, b) => a + b);
    return expValues.map((e) => e / sumExp).toList();
  }

  Future<void> _evaluateSequence(List<FrameLandmarks> sequence) async {
    if (_ortSession == null || _phrases.isEmpty || _isDisposed || _isSuccessAchieved) return;
    _isEvaluating = true;

    OrtValueTensor? inputTensor;
    OrtRunOptions? runOptions;
    List<OrtValue?>? outputs;

    try {
      final features = _extractFeatures(sequence);

      // Dynamically read total energies from the last two elements of the feature vector
      final double totalEnergyLh = features[features.length - 2];
      final double totalEnergyRh = features[features.length - 1];
      final double totalEnergy = totalEnergyLh + totalEnergyRh;

      // Ignore gesture evaluation if total hand kinetic energy is too low
      if (totalEnergy < 0.15) {
        if (mounted && !_isSuccessAchieved) {
          setState(() {
            _currentFeedback = "Igalaw ang kamay para isagawa ang kumpas...";
            _currentScore = 0.0;
          });
        }
        return;
      }
      
      // Apply exact shape expected by the model manifest
      inputTensor = OrtValueTensor.createTensorWithDataList(features, _inputShape);
      runOptions = OrtRunOptions();
      
      final inputName = _ortSession!.inputNames.isNotEmpty 
          ? _ortSession!.inputNames.first 
          : 'float_input';

      outputs = await _ortSession!.runAsync(runOptions, {inputName: inputTensor});

      if (_isDisposed || _isSuccessAchieved) return;

      if (outputs != null && outputs.isNotEmpty) {
        final rawVal = outputs[0]?.value;
        int predIdx = 0;
        double maxProb = 0.0;

        if (rawVal is List && rawVal.isNotEmpty) {
          List<double> logits = [];
          var firstElem = rawVal[0];

          if (firstElem is List) {
            logits = firstElem.map((e) => (e as num).toDouble()).toList();
          } else if (firstElem is num) {
            logits = rawVal.map((e) => (e as num).toDouble()).toList();
          }

          if (logits.isNotEmpty) {
            debugPrint("Raw ONNX Output Logits: $logits");

            List<double> probs = _softmax(logits);
            for (int i = 0; i < probs.length; i++) {
              if (probs[i] > maxProb) {
                maxProb = probs[i];
                predIdx = i;
              }
            }
          }
        }

        if (predIdx >= _phrases.length) predIdx = 0;

        final currentQ = _activeQuestions[_currentStep];
        final String expectedLabel = (currentQ['id'] ?? currentQ['question'] ?? currentQ['label'] ?? '').toString().toLowerCase();
        final String predictedLabel = (_phrases[predIdx]['label'] ?? _phrases[predIdx]['folder_code'] ?? '').toString().toLowerCase();

        final cleanExpected = expectedLabel.replaceAll(RegExp(r'^\d+_'), '').replaceAll('_', ' ').trim();
        final cleanPredicted = predictedLabel.replaceAll(RegExp(r'^\d+_'), '').replaceAll('_', ' ').trim();

        final bool isMatch = cleanPredicted == cleanExpected || 
                             cleanExpected.contains(cleanPredicted) || 
                             cleanPredicted.contains(cleanExpected);

        debugPrint("Inference -> Predicted: '$cleanPredicted' | Expected: '$cleanExpected' | Score: $maxProb");

        if (mounted && !_isSuccessAchieved) {
          setState(() {
            _currentScore = maxProb;
            if (isMatch) {
              if (maxProb >= successThreshold) {
                _onSuccess();
              } else {
                _currentFeedback = "Tama ang kumpas! Mas lakasan pa ang galaw.";
              }
            } else {
              _currentFeedback = "Maling kumpas ($cleanPredicted). Subukang muli.";
            }
          });
        }
      }
    } catch (e, stack) {
      debugPrint("Inference Error: $e\n$stack");
    } finally {
      inputTensor?.release();
      runOptions?.release();
      if (outputs != null) {
        for (final out in outputs) {
          out?.release();
        }
      }
      _isEvaluating = false;
    }
  }

  // CONTINUOUS TRANSITION LOGIC[cite: 28]
  void _onSuccess() async {
    if (_isSuccessAchieved) return;
    _isSuccessAchieved = true; 
    _score++;
    HapticFeedback.heavyImpact();

    if (!mounted) return;

    final isLastStep = _currentStep >= _activeQuestions.length - 1;

    setState(() {
      _currentFeedback = isLastStep 
          ? "Mahusay! Kumpleto na ang lahat ng linya!" 
          : "Mahusay! Tumpak ang kumpas! Lumilipat...";
    });

    // 1.5 second brief pause so user sees the green confirmation before auto-advancing
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted || _isDisposed) return;
    _handleNextStep();
  }

  void _handleNextStep() {
    setState(() {
      _isSuccessAchieved = false; 
      _currentScore = 0.0; 
      _frameBuffer.clear();
      _currentFeedback = "Maghanda at isagawa ang kumpas...";

      if (_currentStep < _activeQuestions.length - 1) {
        _currentStep++; 
        _loadCurrentStepData();
      } else {
        _currentStep++; // Moves past activeQuestions.length to trigger completion screen
        _saveUserProgress();
      }
    });
  }

  Future<void> _saveUserProgress() async {
    if (_progressSaved) return;
    _progressSaved = true;
    try {
      dynamic service = ProgressService();
      await service.updateUserProgress(
        levelKey: 'civic_practice_${_normalizeCategoryKey(widget.category)}', 
        stars: _score == _activeQuestions.length ? 3 : 2, 
        xpEarned: _score * xpReward, 
        xpCategoryKey: 'civicXp',
      );
    } catch (e) {
      debugPrint("Progress save error: $e");
    }
  }

  @override
  void dispose() {
    _isDisposed = true;

    WidgetsBinding.instance.removeObserver(this);
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller?.stopImageStream();
    }
    _controller?.dispose();

    _ortSession?.release(); 
    _ortSession = null;

    _reusableFrameBuffer = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Pagsasanay: ${_normalizeCategoryKey(widget.category).replaceAll('_', ' ').toUpperCase()}', 
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true, 
        elevation: 0,
      ),
      body: SafeArea(
        child: _isBootstrapping
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    _loadingStatus,
                    style: TextStyle(
                      fontSize: 16, 
                      fontWeight: FontWeight.w600, 
                      color: theme.colorScheme.onSurface.withOpacity(0.8)
                    ),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: _currentStep >= _activeQuestions.length 
                ? _buildCompletionView(theme) 
                : _buildPracticeUI(theme),
            ),
      ),
    );
  }

  Widget _buildPracticeUI(ThemeData theme) {
    bool isPassing = _currentScore >= successThreshold;
    final currentItem = _activeQuestions[_currentStep];

    return SingleChildScrollView(
      child: Column(
        children: [
          // Step Counter Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Linya ${_currentStep + 1} sa ${_activeQuestions.length}', 
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.primaryColor),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            currentItem['question'] ?? '', 
            textAlign: TextAlign.center, 
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          if (currentItem['instruction'] != null && currentItem['instruction'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                currentItem['instruction'], 
                textAlign: TextAlign.center, 
                style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.8), fontStyle: FontStyle.italic),
              ),
            ),
          ],
          const SizedBox(height: 16),
          
          // Reference Image
          SizedBox(
            width: 220, 
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _isImageLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : _templateImageBytes != null 
                    ? Image.memory(_templateImageBytes!, fit: BoxFit.cover) 
                    : Container(
                        color: Colors.grey.shade300, 
                        child: const Icon(Icons.image, size: 50, color: Colors.grey),
                      ),
            ),
          ),
          const SizedBox(height: 20),

          // Camera Preview Box with Dynamic Success Highlight
          SizedBox(
            width: 220, 
            height: 220,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(width: 4, color: _isSuccessAchieved ? Colors.green : (isPassing ? Colors.green : theme.dividerColor)), 
                borderRadius: BorderRadius.circular(20),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _isInitialized && _controller != null 
                  ? CameraPreview(_controller!) 
                  : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _currentFeedback, 
            style: TextStyle(
              color: _isSuccessAchieved || isPassing ? Colors.green : theme.primaryColor, 
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _frameBuffer.length / targetFrames, 
            color: _isSuccessAchieved || isPassing ? Colors.green : theme.primaryColor,
          ),
          const SizedBox(height: 12),
          Text(
            "Katiyakan: ${(_currentScore * 100).toStringAsFixed(1)}%", 
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  // Completion view shown only after all lines are completed[cite: 28]
  Widget _buildCompletionView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified, size: 90, color: Colors.green),
          const SizedBox(height: 20),
          const Text(
            'Tapos na ang Pagsasanay!', 
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Lahat ng ${_activeQuestions.length} na linya ay matagumpay mong naisagawa.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface.withOpacity(0.8)),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              '+${_score * xpReward} Civic XP Earned', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: theme.primaryColor),
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(200, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Tapusin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}