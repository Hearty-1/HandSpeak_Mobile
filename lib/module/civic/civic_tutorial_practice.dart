import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '/services/progress_service.dart';
import '/services/handspeak_api_service.dart';

// =============================================================================
// DATA MODELS
// =============================================================================

/// One captured camera frame, in the raw form /v1/predict_raw expects:
/// pose = 33 x [x, y, visibility], hands = 21 x [x, y, z] (null = not
/// detected), normalised to the upright, UN-mirrored camera image; left =
/// the signer's own left hand (assigned natively from the pose wrists).
class CaptureFrame {
  final List<List<double>>? pose;
  final List<List<double>>? leftHand;
  final List<List<double>>? rightHand;
  final int timeMs;
  const CaptureFrame({this.pose, this.leftHand, this.rightHand, required this.timeMs});

  bool get hasPose => pose != null;
  bool get hasHands => leftHand != null || rightHand != null;

  Map<String, dynamic> toJson(int t0Ms) => {
        't': (timeMs - t0Ms) / 1000.0,
        'pose': pose,
        'left_hand': leftHand,
        'right_hand': rightHand,
      };
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

  // Up to 2 frames in flight: native converts the next camera image while
  // the previous one is still in the pose / hand models (higher capture fps).
  int _nativeInFlight = 0;
  static const int _maxInFlight = 2;


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

  // Manifest and Dynamic JSON Data
  List<Map<String, dynamic>> _phrases = [];
  List<Map<String, dynamic>> _activeQuestions = [];

  bool _isManifestLoaded = false;


  // Live detection state (for on-screen guidance)
  bool _poseVisible = false;
  bool _handsVisible = false;

  // Recording: one whole line per clip, like the training videos.
  bool _isRecording = false;
  bool _isEvaluating = false;
  int _countdown = 0;
  Timer? _countdownTimer;
  Timer? _maxRecordTimer;
  DateTime? _recordStart;
  final List<CaptureFrame> _recorded = [];
  int _imageWidth = 0, _imageHeight = 0; // upright frame size from the native side
  String _serverDebug = ''; // last server reply, shown in debug builds
  String _engineInfo = ''; // native pose/hand models + delegate (diagnostics)
  double _nativeMs = 0; // smoothed native time per frame (conversion + MediaPipe)
  bool _sawHands = false;
  int _lastHandMs = 0;
  static const Duration _maxRecording = Duration(seconds: 10);
  // Hands must be gone this long before auto-stop. Longer than the server's
  // hand memory (up to 2 s for a hand that left through the top edge, e.g.
  // "Ang bituin"), so a hand briefly out of frame does not end the line.
  static const int _autoStopAfterMs = 2200;
  static const int _manualStopTrimMs = 600;

  CameraController? _controller;
  bool _isInitialized = false;

  bool _isSuccessAchieved = false;
  double _currentScore = 0.0;
  String _currentFeedback = "Maghanda at isagawa ang kumpas...";

  /// INVALID_GESTURE is the last of the v4 model's 23 classes.
  static const int _invalidIndex = 22;
  final double successThreshold = 0.70; // UI colour threshold for the score
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
    _updateLoadingStatus("Naglo-load ng manifest at camera...");


    await Future.wait([
      _loadManifestAndLabels(),
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

  Future<void> _loadManifestAndLabels() async {
    final key = _normalizeCategoryKey(widget.category);
    try {
      final labelPath = 'assets/civic/labels_$key.json';
      final jsonStr = await rootBundle.loadString(labelPath);
      final manifest = jsonDecode(jsonStr);

      _phrases = List<Map<String, dynamic>>.from(manifest['phrases']);
      // Class order of the model = sorted training folders = manifest "index".
      _phrases.sort((a, b) => ((a['index'] as num?) ?? 0).compareTo((b['index'] as num?) ?? 0));

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

      if (!_isDisposed && mounted) {
        _isManifestLoaded = true;
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
        // "low" (320x240) is too small for reliable hand landmarks.
        ResolutionPreset.medium,
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
    _cancelRecording();
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

  // ---------------------------------------------------------------------------
  // Frame capture (native Pose + Hands, raw landmarks for the v4 server)
  // ---------------------------------------------------------------------------

  static List<List<double>>? _points(dynamic v) => v is List
      ? [for (final p in v) [for (final c in p as List) (c as num).toDouble()]]
      : null;

  void _processCameraFrame(CameraImage image) async {
    if (!_isManifestLoaded || _isSuccessAchieved || _isEvaluating || _nativeInFlight >= _maxInFlight || _isDisposed) return;
    _nativeInFlight++;
    // Capture time, not result time: results arrive a variable ~100-200 ms later.
    final capturedMs = DateTime.now().millisecondsSinceEpoch;

    try {
      // Raw camera planes go straight to native code (converted once there,
      // instead of a per-pixel NV21 loop in Dart that slows capture down).
      final planes = image.planes;
      final dynamic res = await _platformChannel.invokeMethod('processFrame', {
        'y': planes[0].bytes,
        'u': planes[1].bytes,
        'v': planes[2].bytes,
        'yRowStride': planes[0].bytesPerRow,
        'uvRowStride': planes[1].bytesPerRow,
        'uvPixelStride': planes[1].bytesPerPixel ?? 1,
        'width': image.width,
        'height': image.height,
        'rotation': _controller?.description.sensorOrientation ?? 0,
      });
      if (_isDisposed || res is! Map) return;

      _imageWidth = (res['imageWidth'] as num?)?.toInt() ?? _imageWidth;
      _imageHeight = (res['imageHeight'] as num?)?.toInt() ?? _imageHeight;
      _engineInfo = (res['engine'] as String?) ?? _engineInfo;
      final procMs = ((res['processMs'] as num?) ?? 0) + ((res['convertMs'] as num?) ?? 0);
      _nativeMs = _nativeMs == 0 ? procMs.toDouble() : 0.8 * _nativeMs + 0.2 * procMs;
      _onHolisticFrame(CaptureFrame(
        pose: _points(res['pose33']),
        leftHand: _points(res['leftHand']),
        rightHand: _points(res['rightHand']),
        timeMs: capturedMs,
      ));
    } catch (e) {
      debugPrint("Platform Channel Error: $e");
    } finally {
      _nativeInFlight--;
    }
  }

  void _onHolisticFrame(CaptureFrame frame) {
    if (_isDisposed || !mounted) return;

    final changed = frame.hasPose != _poseVisible || frame.hasHands != _handsVisible;
    _poseVisible = frame.hasPose;
    _handsVisible = frame.hasHands;

    if (!_isRecording) {
      if (changed) setState(() {});
      return;
    }

    _recorded.add(frame);
    if (frame.hasHands) {
      _sawHands = true;
      _lastHandMs = frame.timeMs;
    } else if (_sawHands && frame.timeMs - _lastHandMs > _autoStopAfterMs) {
      // Hands lowered after signing -> the line is finished.
      unawaited(_stopAndEvaluate());
      return;
    }
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Recording flow
  // ---------------------------------------------------------------------------

  void _toggleRecording() {
    if (!_isInitialized || _isSuccessAchieved || _isEvaluating) return;
    if (_countdown > 0) {
      _cancelRecording();
    } else if (_isRecording) {
      _stopAndEvaluate(manual: true);
    } else {
      _startCountdown();
    }
  }

  /// Each training video is one whole line performed from a ready position,
  /// so give the user time to get into position after tapping the screen.
  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdown = 3;
      _currentScore = 0.0;
      _currentFeedback = "Ibaba ang mga kamay at pumwesto...";
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _isDisposed) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        _startRecording();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _startRecording() {
    _recorded.clear();
    _sawHands = false;
    _lastHandMs = 0;
    _maxRecordTimer?.cancel();
    _maxRecordTimer = Timer(_maxRecording, () => _stopAndEvaluate());
    setState(() {
      _countdown = 0;
      _isRecording = true;
      _recordStart = DateTime.now();
      _currentFeedback = "Isagawa ang buong linya, saka ibaba ang mga kamay.";
    });
  }

  void _cancelRecording() {
    _countdownTimer?.cancel();
    _maxRecordTimer?.cancel();
    _recorded.clear();
    final wasActive = _countdown > 0 || _isRecording;
    _countdown = 0;
    _isRecording = false;
    _recordStart = null;
    if (wasActive && mounted && !_isDisposed) {
      setState(() => _currentFeedback = "Kinansela. Pindutin ang RECORD para ulitin.");
    }
  }

  // ---------------------------------------------------------------------------
  // Class resolution
  // ---------------------------------------------------------------------------

  /// "05_Lupang_hinirang" / "Lupang hinirang" / "Nang dahil sa 'yo" -> compact key
  static String _compact(String s) => s
      .toLowerCase()
      .replaceFirst(RegExp(r'^\s*\d+[_\s-]+'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Model class index for a label / folder code, or -1.
  int _classIndexForName(String? name) {
    if (name == null || name.trim().isEmpty) return -1;
    final key = _compact(name);
    for (int i = 0; i < _phrases.length; i++) {
      final p = _phrases[i];
      if (_compact('${p['folder_code'] ?? ''}') == key || _compact('${p['label'] ?? ''}') == key) {
        return ((p['index'] as num?) ?? i).toInt();
      }
    }
    return -1;
  }

  /// Class index the current step expects. Questions may come from Firestore
  /// with their own fields, so try them all, then fall back to step order.
  int _expectedClassIndex() {
    final q = _activeQuestions[_currentStep];
    for (final field in ['folder_code', 'label', 'id', 'question', 'title', 'answer']) {
      final idx = _classIndexForName(q[field]?.toString());
      if (idx != -1) return idx;
    }
    return _currentStep < _phrases.length ? _currentStep : -1;
  }

  String _labelForIndex(int idx) {
    for (final p in _phrases) {
      if ((p['index'] as num?)?.toInt() == idx) return '${p['label']}';
    }
    return 'Linya ${idx + 1}';
  }

  static bool _isInvalidLabel(Prediction p) =>
      p.label.toUpperCase().contains('INVALID') || p.index == _invalidIndex;

  /// Server prediction -> class index (-1 = INVALID_GESTURE / unknown).
  /// Names first (the v4 names differ only in punctuation from labels.json).
  int _indexOf(Prediction p) {
    if (_isInvalidLabel(p)) return -1;
    for (final name in [p.label, p.labelEn, p.code]) {
      final idx = _classIndexForName(name);
      if (idx != -1) return idx;
    }
    return (p.index >= 0 && p.index < _phrases.length) ? p.index : -1;
  }

  /// v4 rejection codes (lupang_common.REJECT_TEXT) -> what to do differently.
  static const Map<String, String> _rejectAdvice = {
    'NO_HANDS': "Walang nakitang kamay. Ipakita ang katawan at mga kamay sa camera.",
    'TOO_SHORT': "Masyadong maikli ang kumpas. Isagawa ang buong galaw.",
    'FRAGMENT_DURATION': "Kulang pa ang haba ng kumpas para sa senyas na ito. Isagawa nang buo at huwag magmadali.",
    'LOW_MOTION': "Kulang ang galaw. Isagawa nang buo ang kumpas.",
    'PHASE_IMBALANCE': "Simulan sa unang bahagi ng kumpas; huwag magsimula o tumigil sa huling porma.",
    'SINGLE_STROKE': "Isang galaw lang ang nakita. Isagawa ang lahat ng bahagi ng linya.",
    'INVALID_CLASS': "Hindi makilala bilang linya ng Lupang Hinirang. Sundan ang halimbawa.",
    'LOW_CONFIDENCE': "Hindi pa tiyak ang kumpas. Gawin nang mas malinaw at buo.",
    'SMALL_MARGIN': "Hindi pa tiyak ang kumpas. Gawin nang mas malinaw at buo.",
    'HIGH_ENTROPY': "Hindi pa tiyak ang kumpas. Gawin nang mas malinaw at buo.",
  };

  // ---------------------------------------------------------------------------
  // Evaluation via Cloud Run (/v1/predict_raw: full v4 pipeline server-side)
  // ---------------------------------------------------------------------------

  void _showFeedback(String text, {double score = 0.0}) {
    if (!mounted || _isDisposed) return;
    setState(() {
      _currentFeedback = text;
      _currentScore = score;
    });
  }

  // Still-edge trimming = lupang_common._trim_still_edges (training pipeline).
  static const double _stillSpeed = 0.25; // shoulder spans per second
  static const double _stillMinS = 0.20; // a still run must last this long to be cut
  static const double _speedWindowS = 0.3; // speed measured over 0.3 s: tracking jitter averages out
  static const int _minActiveFrames = 8;

  /// Cuts hands held still before the line starts / after it ends.
  ///
  /// The Lupang Hinirang server gate does NOT trim still edges (trim_still is
  /// off in palm_lupang_best.json), while the training clips are pure
  /// signing. Replaying the 363 training clips through the model showed what
  /// a typical phone recording does to it: hands held still 1 s before and
  /// 1.5 s after the line drop correct + accepted results from 81% to 21%.
  /// This is the training pipeline's own trim rule (wrist speed below 0.25
  /// shoulder spans / s for >= 0.2 s at either end), applied here before
  /// upload; with it the same recordings pass 78% again, and clean
  /// recordings are unaffected.
  List<CaptureFrame> _trimStillEdges(List<CaptureFrame> frames) {
    final first = frames.indexWhere((f) => f.hasHands);
    final last = frames.lastIndexWhere((f) => f.hasHands);
    if (first == -1) return frames;
    final f = frames.sublist(first, last + 1);
    final n = f.length;
    if (n < _minActiveFrames) return f;
    final aspect = (_imageWidth > 0 && _imageHeight > 0) ? _imageWidth / _imageHeight : 1.0;

    // Median shoulder width (aspect-corrected), the speed unit.
    final spans = <double>[
      for (final fr in f)
        if (fr.pose != null && fr.pose!.length > 16)
          sqrt(pow((fr.pose![11][0] - fr.pose![12][0]) * aspect, 2) + pow(fr.pose![11][1] - fr.pose![12][1], 2))
    ]..sort();
    if (spans.length < 2) return f;
    final span = spans[spans.length ~/ 2] + 1e-6;

    // Wrist per side: the hand's own wrist when tracked, else the pose wrist.
    List<double>? wrist(CaptureFrame fr, bool left) {
      final h = left ? fr.leftHand : fr.rightHand;
      if (h != null && h.isNotEmpty) return [h[0][0] * aspect, h[0][1]];
      final p = fr.pose;
      if (p == null || p.length <= 16) return null;
      final w = p[left ? 15 : 16];
      return [w[0] * aspect, w[1]];
    }

    final speed = List<double>.filled(n, 0);
    for (final left in [true, false]) {
      int j = 0;
      for (int i = 1; i < n; i++) {
        while (j < i - 1 && (f[i].timeMs - f[j + 1].timeMs) / 1000.0 >= _speedWindowS) {
          j++;
        }
        final a = wrist(f[j], left), b = wrist(f[i], left);
        if (a == null || b == null) continue;
        final dt = max((f[i].timeMs - f[j].timeMs) / 1000.0, 1e-3);
        final v = sqrt(pow(b[0] - a[0], 2) + pow(b[1] - a[1], 2)) / dt / span;
        if (v > speed[i]) speed[i] = v;
      }
    }

    final moving = [for (int i = 0; i < n; i++) if (speed[i] >= _stillSpeed) i];
    if (moving.isEmpty) return f; // all still: leave it to the server's motion gate
    int a = max(moving.first - 1, 0), b = moving.last;
    if ((f[a].timeMs - f[0].timeMs) / 1000.0 < _stillMinS) a = 0;
    if ((f[n - 1].timeMs - f[b].timeMs) / 1000.0 < _stillMinS) b = n - 1;
    if (b - a + 1 < _minActiveFrames) return f;
    return f.sublist(a, b + 1);
  }

  Future<void> _stopAndEvaluate({bool manual = false}) async {
    if (!_isRecording || _isDisposed) return;
    _isRecording = false; // stop collecting immediately (no re-entry)
    _maxRecordTimer?.cancel();
    var frames = List<CaptureFrame>.of(_recorded)..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    _recorded.clear();
    if (mounted) setState(() => _recordStart = null);

    if (_phrases.isEmpty || _isSuccessAchieved) return;

    if (_normalizeCategoryKey(widget.category) != 'lupang_hinirang') {
      _showFeedback("Wala pang naka-deploy na modelo para sa kategoryang ito.");
      return;
    }

    // A manual STOP means the last moment is the reach to the screen, which
    // is not part of the sign. (Idle edges without hands are trimmed by the
    // server, exactly as in training.)
    if (manual && frames.isNotEmpty) {
      final cutoff = frames.last.timeMs - _manualStopTrimMs;
      frames = frames.where((f) => f.timeMs <= cutoff).toList();
    }
    if (!frames.any((f) => f.hasHands)) {
      _showFeedback(_rejectAdvice['NO_HANDS']!);
      return;
    }
    final before = frames.length;
    frames = _trimStillEdges(frames);
    if (frames.length != before) {
      debugPrint("Civic v4: trimmed ${before - frames.length} still frame(s) at the edges");
    }

    final expected = _expectedClassIndex();
    final t0 = frames.first.timeMs;
    // Same form as the desktop engine: upright landmarks + hands assigned to
    // the pose wrists (CaptureFixer, in handspeak_api_service.dart).
    final fixed = CaptureFixer.fix([for (final f in frames) f.toJson(t0)], _imageWidth, _imageHeight);
    debugPrint("Civic v4: ${frames.length} frames over ${((frames.last.timeMs - t0) / 1000).toStringAsFixed(2)} s, "
        "pose ${frames.where((f) => f.hasPose).length}, L ${frames.where((f) => f.leftHand != null).length}, "
        "R ${frames.where((f) => f.rightHand != null).length}, image ${_imageWidth}x$_imageHeight | ${fixed.report}");

    setState(() {
      _isEvaluating = true;
      _currentFeedback = "Sinusuri ang kumpas...";
    });

    try {
      final result = await HandSpeakApiService().predictRaw(
        modelId: HandSpeakModels.lupangHinirang,
        frames: fixed.frames,
        imageWidth: fixed.imageWidth,
        imageHeight: fixed.imageHeight,
      );
      if (_isDisposed || _isSuccessAchieved) return;
      final rawText = jsonEncode(result.raw);
      debugPrint("Civic v4 response: $rawText");

      final top = result.prediction;
      final topIdx = top == null ? -1 : _indexOf(top);
      double confFor(int idx) {
        for (final p in [if (top != null) top, ...result.topK]) {
          if (_indexOf(p) == idx) return p.confidence > 1.0 ? p.confidence / 100.0 : p.confidence;
        }
        return 0.0;
      }

      final targetConf = confFor(expected);
      // Accepted = the server says so; if the reply has no explicit verdict,
      // a real (non-INVALID) top-1 with no failed gate counts as accepted.
      final accepted = result.accepted;
      if (kDebugMode && mounted) {
        final checks = result.raw['checks'];
        final checkLines = checks is List
            ? [
                for (final c in checks)
                  if (c is Map) "${c['passed'] == true ? '✓' : '✗'} ${c['label']}: ${c['text']}"
              ].join('\n')
            : '';
        final secs = (frames.last.timeMs - t0) / 1000.0;
        setState(() => _serverDebug = 'expected #$expected ${_labelForIndex(expected)} | '
            'top=#$topIdx (${top?.label} ${top?.confidence.toStringAsFixed(2)}) | failed=${result.failed}\n'
            'capture: ${frames.length} frames / ${secs.toStringAsFixed(1)} s = '
            '${(frames.length / (secs > 0 ? secs : 1)).toStringAsFixed(1)} fps | ${fixed.report} | '
            '${_engineInfo.isEmpty ? 'OLD NATIVE BUILD - stop the app and run "flutter run" again (hot reload does not update Android code)' : '$_engineInfo, ${_nativeMs.toStringAsFixed(0)} ms/frame'}\n'
            '${checkLines.isNotEmpty ? checkLines : (rawText.length > 600 ? '${rawText.substring(0, 600)}…' : rawText)}');
      }

      // Pass only when the capture is accepted (all v4 gates passed) and its
      // top-1 line is the one being practised.
      if (accepted && topIdx == expected) {
        if (mounted) setState(() => _currentScore = targetConf > 0 ? targetConf : 0.9);
        _onSuccess();
        return;
      }

      if (accepted && topIdx != -1) {
        _showFeedback("Mukhang \"${_labelForIndex(topIdx)}\" ang naisagawa. Subukang muli.", score: targetConf);
        return;
      }

      final code = result.failed.firstWhere(_rejectAdvice.containsKey, orElse: () => result.failed.isNotEmpty ? result.failed.first : '');
      var advice = _rejectAdvice[code] ??
          (result.message != null && result.message!.trim().isNotEmpty
              ? "Hindi tinanggap: ${result.message}"
              : "Hindi makilala ang kumpas. Ulitin nang mas malinaw.");
      if (topIdx != -1 && !const {'NO_HANDS', 'TOO_SHORT', 'LOW_MOTION'}.contains(code)) {
        advice = topIdx == expected
            ? "Halos tama! $advice"
            : "$advice (Pinakamalapit: \"${_labelForIndex(topIdx)}\")";
      }
      _showFeedback(advice, score: targetConf);
    } on ArgumentError catch (e) {
      // Rejected by the API client before upload (e.g. no pose in most frames).
      debugPrint("Civic v4 capture rejected client-side: ${e.message}");
      _showFeedback("${e.message}".contains('Pose')
          ? "Hindi makita ang katawan. Ipakita ang balikat, katawan at mga kamay sa camera."
          : "Hindi maipadala ang kumpas. Subukang muli.");
    } catch (e, stack) {
      debugPrint("API Inference Error: $e\n$stack");
      _showFeedback("Error sa server. Subukang muli.");
    } finally {
      if (mounted) {
        setState(() => _isEvaluating = false);
      } else {
        _isEvaluating = false;
      }
    }
  }

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

    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted || _isDisposed) return;
    _handleNextStep();
  }

  void _resetStepState() {
    _cancelRecording();
    _isSuccessAchieved = false;
    _currentScore = 0.0;
    _currentFeedback = "Maghanda at isagawa ang kumpas...";
  }

  void _handlePreviousStep() {
    if (_currentStep > 0) {
      setState(() {
        _resetStepState();
        _currentStep--;
        _loadCurrentStepData();
      });
    }
  }

  void _handleNextStep() {
    setState(() {
      _resetStepState();

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
    _countdownTimer?.cancel();
    _maxRecordTimer?.cancel();

    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller?.stopImageStream();
    }
    _controller?.dispose();

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
    final bool busy = _isRecording || _countdown > 0;
    final double elapsed = (_isRecording && _recordStart != null)
        ? DateTime.now().difference(_recordStart!).inMilliseconds / 1000.0
        : 0.0;

    return SingleChildScrollView(
      child: Column(
        children: [
          // Step Counter Header & Test Navigation Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: _currentStep > 0 ? _handlePreviousStep : null,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text("Prev"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
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
              ElevatedButton.icon(
                onPressed: _currentStep < _activeQuestions.length - 1 ? _handleNextStep : null,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text("Next"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ],
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
                border: Border.all(
                  width: 4,
                  color: _isSuccessAchieved || isPassing
                      ? Colors.green
                      : (_isRecording ? Colors.redAccent : theme.dividerColor),
                ),
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
          const SizedBox(height: 8),
          if (_countdown > 0)
            Text(
              'Ihanda ang sarili… $_countdown',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            )
          else if (_isRecording)
            Text('Nagre-record… ${_recorded.length} frames • ${elapsed.toStringAsFixed(1)}s'
                '${elapsed > 0.5 ? ' • ${(_recorded.length / elapsed).toStringAsFixed(1)} fps' : ''}')
          else
            Text(
              !_poseVisible
                  ? 'Lumayo nang kaunti para makita ang balikat at mga kamay'
                  : 'Nakikita ang katawan ✓  Pindutin ang RECORD',
              textAlign: TextAlign.center,
              style: TextStyle(color: _poseVisible ? Colors.green : Colors.orange),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            width: 64,
            child: FloatingActionButton(
              heroTag: 'civic_record_button',
              backgroundColor: busy ? Colors.red : Colors.white,
              foregroundColor: busy ? Colors.white : Colors.black,
              onPressed: (_isSuccessAchieved || _isEvaluating || !_isInitialized) ? null : _toggleRecording,
              child: _isEvaluating
                  ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3))
                  : Icon(
                      _countdown > 0 ? Icons.close : (_isRecording ? Icons.stop : Icons.fiber_manual_record),
                      size: 32,
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _currentFeedback,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _isSuccessAchieved || isPassing ? Colors.green : theme.primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (kDebugMode && _serverDebug.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              _serverDebug,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ],
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _isRecording
                ? (elapsed / _maxRecording.inSeconds).clamp(0.0, 1.0).toDouble()
                : _currentScore.clamp(0.0, 1.0).toDouble(),
            color: _isSuccessAchieved || isPassing ? Colors.green : theme.primaryColor,
          ),
          const SizedBox(height: 12),
          Text(
            // On a miss this is the model's vote share for the target line.
            "${_isSuccessAchieved ? 'Katiyakan' : 'Tugma sa linyang ito'}: "
            "${(_currentScore * 100).toStringAsFixed(1)}%",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

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
