import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:convert';
import 'dart:io' show Directory, File;
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '/services/lighting_monitor.dart';
import '/services/progress_service.dart';
import '/services/xp_rewards.dart';
import 'civic_tutorial_interface.dart' show LupangLines;
import '/services/handspeak_api_service.dart';
import '/services/holistic_capture.dart' show HolisticResult;
import '/services/performance_monitor.dart';
import '/services/role_service.dart';
import '/widgets/practice_feedback.dart';


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

  /// Continuous practice (civic_practice.dart): the lines loop, the first
  /// success on each line gives XpRewards.civicPractice, and an inline
  /// success card replaces the "Mastered!" dialog.
  final bool continuous;

  const CivicTutorialPractice({
    super.key,
    this.category = 'lupang_hinirang',
    this.questions,
    this.continuous = false,
  });

  @override
  State<CivicTutorialPractice> createState() => _CivicTutorialPracticeState();
}

class _CivicTutorialPracticeState extends State<CivicTutorialPractice> with WidgetsBindingObserver {
  static const MethodChannel _platformChannel = MethodChannel('fsl_holistic_channel');
  /// Native landmark engine of the last frame (MainActivity.kt).
  String _engine = '';

  // Up to 2 frames in flight: native converts the next camera image while
  // the previous one is still in the pose / hand models (higher capture fps).
  int _nativeInFlight = 0;
  static const int _maxInFlight = 2;


  bool _isDisposed = false;

  // Bootup / Loading state tracking
  String _loadingStatus = "Inihahanda ang pagsasanay...";
  bool _isBootstrapping = true;

  int _currentStep = 0;
  int _xpEarned = 0; // XP actually awarded this session (first masteries only)
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

  /// palm_lupang_v9_switch merged "Sa paglayang minamahal" (class 11) into
  /// line 11 "May dilag ang tula at awit sa paglayang minamahal" (class 10);
  /// class 11 is retired and never predicted as a line of its own.
  /// Lines the v9 gate rejects correct signs on most ("not sure"):
  /// 6 Sa manlulupig, 7 Di ka pasisiil, 18 Aming ligaya, 20 Ang mamatay.
  /// See lenientPass().
  static const Set<int> _lenientLines = {6, 7, 18, 20};
  static const Set<String> _uncertainChecks = {
    'LOW_CONFIDENCE', 'SMALL_MARGIN', 'HIGH_ENTROPY', 'UNSTABLE', 'INVALID_CLASS',
  };
  static const double _lenientMinConf = 0.15;
  static const double _lenientMinLead = 0.05; // over the next line
  /// Sa manlulupig (6) passed random hand movement at 15 % / 5 points
  /// (false positives), so it needs a clearer win: still far below the
  /// server's own gate, but the model must lean toward the line, and a
  /// capture the model calls "not a line" (INVALID on top) does not pass.
  static const Map<int, (double, double)> _lenientPerLine = {6: (0.30, 0.12)};
  static const Set<int> _rejectInvalidTop = {6};

  static const int _mergedIndex = 10;
  static const int _retiredIndex = 11;
  static final Set<String> _mergedAliases = {
    _compact('May dilag ang tula at awit'),
    _compact('Sa paglayang minamahal'),
    _compact('11_May_dilag_ang_tula_at_awit'),
    _compact('12_Sa_paglayang_minamahal'),
  };
  final double successThreshold = 0.70; // UI colour threshold for the score
  final int xpReward = LupangLines.xpPerLine;

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
        _activeQuestions = key == 'lupang_hinirang' ? _mergeRetiredSteps(widget.questions!) : widget.questions!;
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
    // Single-line lessons (civic tutorial list) carry their own line number.
    final lineNumber = (_activeQuestions[_currentStep]['line_number'] as num?)?.toInt() ?? _currentStep + 1;
    final normalizedKey = '${categoryKey}_line_$lineNumber';

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
    LightingMonitor.instance.onImage(image); // low-light warning
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
        'rotation': _cameraImageRotation(_controller), // live device rotation
      });
      if (_isDisposed || res is! Map) return;
      PerformanceMonitor.instance.reportCameraResult(DateTime.now().millisecondsSinceEpoch - capturedMs);

      _imageWidth = (res['imageWidth'] as num?)?.toInt() ?? _imageWidth;
      _imageHeight = (res['imageHeight'] as num?)?.toInt() ?? _imageHeight;
      _engine = (res['engine'] as String?) ?? _engine;
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
    // Redraw at most ~4x per second while recording (frame counter / timer):
    // a rebuild per camera frame competes with MediaPipe for the GPU.
    if (changed || frame.timeMs - _lastUiMs > 250) {
      _lastUiMs = frame.timeMs;
      setState(() {});
    }
  }
  int _lastUiMs = 0;

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
    // Old 22-line names (Firestore lessons, previous server labels) and the
    // retired class label "Sa paglayang minamahal (merged into line 11)".
    if (_mergedAliases.contains(key) || key.contains('mergedintoline')) return _mergedIndex;
    for (int i = 0; i < _phrases.length; i++) {
      final p = _phrases[i];
      if (_compact('${p['folder_code'] ?? ''}') == key || _compact('${p['label'] ?? ''}') == key) {
        return ((p['index'] as num?) ?? i).toInt();
      }
    }
    return -1;
  }

  /// Class index named by a question's own fields (Firestore questions carry
  /// their own field names), or -1.
  int _questionClassIndex(Map<String, dynamic> q) {
    for (final field in ['folder_code', 'label', 'id', 'question', 'title', 'answer']) {
      final idx = _classIndexForName(q[field]?.toString());
      if (idx != -1) return idx;
    }
    return -1;
  }

  /// Class index the current step expects; falls back to the manifest order
  /// (step order != class index after line 11, since class 11 is retired).
  int _expectedClassIndex() {
    final idx = _questionClassIndex(_activeQuestions[_currentStep]);
    if (idx != -1) return idx;
    return _currentStep < _phrases.length
        ? ((_phrases[_currentStep]['index'] as num?) ?? _currentStep).toInt()
        : -1;
  }

  /// Firestore lessons may still list the 22 original lines: "May dilag ang
  /// tula at awit" and "Sa paglayang minamahal" are now ONE line (class 10),
  /// so the second of them is dropped and the first shows the merged label.
  List<Map<String, dynamic>> _mergeRetiredSteps(List<Map<String, dynamic>> questions) {
    final mergedLabel = _labelForIndex(_mergedIndex);
    final out = <Map<String, dynamic>>[];
    bool seenMerged = false;
    for (final q in questions) {
      if (_questionClassIndex(q) != _mergedIndex) {
        out.add(q);
      } else if (!seenMerged) {
        seenMerged = true;
        out.add({...q, 'question': mergedLabel, 'label': mergedLabel});
      }
    }
    return out;
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
    // By index: only manifest lines (0-10, 12-21); retired 11 counts as line 11.
    if (p.index == _retiredIndex) return _mergedIndex;
    return _phrases.any((ph) => (ph['index'] as num?)?.toInt() == p.index) ? p.index : -1;
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
    // Reliability abstention: not enough evidence -> no prediction (never a forced guess).
    'LOW_LANDMARKS': "Hindi sapat ang nakikitang katawan o kamay. Ipakita ang balikat at parehong kamay sa camera.",
    'OUT_OF_FRAME': "Lumalabas ang kamay sa camera. Umatras nang kaunti para makita ang buong galaw.",
    'UNSTABLE': "Hindi pa sapat ang ebidensya para makilala ang senyas. Ulitin nang buo, malinaw, at tuloy-tuloy.",
  };

  // ---------------------------------------------------------------------------
  // Evaluation via Cloud Run (/v1/predict_raw: full v4 pipeline server-side)
  // ---------------------------------------------------------------------------

  /// Feedback colour, same scheme as the other tutorial practices.
  FeedbackTone get _feedbackTone {
    if (_isSuccessAchieved) return FeedbackTone.success;
    if (_isRecording || _isEvaluating || _countdown > 0 || _currentScore <= 0) return FeedbackTone.info;
    return _currentScore >= 0.4 ? FeedbackTone.almost : FeedbackTone.tryAgain;
  }

  void _showFeedback(String text, {double score = 0.0}) {
    if (!mounted || _isDisposed) return;
    setState(() {
      _currentFeedback = text;
      _currentScore = score;
    });
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
    // No client-side trimming: the v9 gate trims still edges itself
    // (trim_still), exactly as in training and in webcam_test_staging.py.

    final expected = _expectedClassIndex();
    final t0 = frames.first.timeMs;
    // Same form as the desktop engine: upright landmarks + hands assigned to
    // the pose wrists (CaptureFixer, in handspeak_api_service.dart).
    final fixed = CaptureFixer.fix([for (final f in frames) f.toJson(t0)], _imageWidth, _imageHeight,
        reassignHands: !HolisticResult.isHolisticEngine(_engine));

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
        topK: 5, // the practice check below compares the target with the next line
      );
      if (_isDisposed || _isSuccessAchieved) return;
      // One short line per attempt (the full reply is cut off by logcat), and
      // in debug builds the whole attempt is saved for offline replay:
      // adb exec-out run-as <package> ls code_cache/civic_dumps
      final guesses = [
        for (final p in result.topK)
          '#${p.index} ${(p.confidence > 1.0 ? p.confidence : p.confidence * 100).toStringAsFixed(0)}%'
      ].join(', ');
      debugPrint('Lupang #$expected ${_labelForIndex(expected)}: accepted=${result.accepted} '
          'failed=${result.failed} top=[$guesses]');
      if (!kReleaseMode) {
        try {
          final dir = Directory('${Directory.systemTemp.path}/civic_dumps')..createSync(recursive: true);
          File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_line$expected.json').writeAsStringSync(jsonEncode({
            'target_index': expected,
            'target_line': _labelForIndex(expected),
            'image_width': fixed.imageWidth,
            'image_height': fixed.imageHeight,
            'frames': fixed.frames,
            'response': result.raw,
          }));
        } catch (e) {
          debugPrint('Lupang dump failed: $e');
        }
      }

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

      // Practice leniency for the lines the v9 gate is strictest on (correct
      // signs rejected only as "not sure"): pass when the ONLY failed checks
      // are the uncertainty ones, and the model's best LINE (INVALID left
      // out) is the target with a clear lead over the next line. Duration,
      // motion, hands and framing checks still apply, so half-finished signs
      // still fail. Replayed on the 145 recorded webcam attempts with the
      // deployed v9 model (2026-10-19, lines 6 / 18 / 20 at >= 15 % and a
      // 5-point lead): +3 wrong-line passes in 435 and +5 half-sign passes in
      // 290 compared with the server alone; Ang mamatay 1/3 -> 2/3.
      bool lenientPass() {
        if (accepted || !_lenientLines.contains(expected)) return false;
        if (result.failed.isEmpty || !result.failed.every(_uncertainChecks.contains)) return false;
        final lines = [
          for (final p in result.topK)
            if (_indexOf(p) != -1) (idx: _indexOf(p), conf: p.confidence > 1.0 ? p.confidence / 100.0 : p.confidence),
        ]..sort((a, b) => b.conf.compareTo(a.conf));
        if (lines.isEmpty || lines.first.idx != expected) return false;
        if (_rejectInvalidTop.contains(expected) && top != null && _isInvalidLabel(top)) return false;
        final next = lines.length > 1 ? lines[1].conf : 0.0;
        final (minConf, minLead) = _lenientPerLine[expected] ?? (_lenientMinConf, _lenientMinLead);
        return lines.first.conf >= minConf && lines.first.conf - next >= minLead;
      }

      // Pass when the capture is accepted (all v4 gates passed) and its top-1
      // line is the one being practised, or by the practice leniency above.
      if ((accepted && topIdx == expected) || lenientPass()) {
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
    HapticFeedback.heavyImpact();

    if (!mounted) return;

    if (widget.continuous) {
      // Inline success card (see _buildContinuousUI), then the next line.
      setState(() => _currentFeedback = "Mahusay! Tumpak ang kumpas!");
      await _awardPracticeXp();
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted && !_isDisposed) _advanceContinuous();
      return;
    }

    final line = '${_activeQuestions[_currentStep]['question'] ?? _labelForIndex(_expectedClassIndex())}';
    setState(() => _currentFeedback = "Mahusay! Tumpak ang kumpas!");
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.heavyImpact();

    // XP per line: awarded only the first time this line is mastered.
    final gained = await _awardLineXp(_expectedClassIndex());
    if (!mounted || _isDisposed) return;
    _xpEarned += gained;
    await _showMasteredDialog(line, gained);
    if (!mounted || _isDisposed) return;

    // One line opened from the tutorial list: back to its lesson, like the
    // other categories. A full run moves on to the next line.
    if (_activeQuestions.length == 1) {
      Navigator.pop(context);
    } else {
      _handleNextStep();
    }
  }

  /// Same reward dialog as the alphabet / numbers / phrases tutorials.
  Future<void> _showMasteredDialog(String line, int gained) {
    final theme = Theme.of(context);
    final visuals = _ThemeVisuals.fromTheme(theme);
    final rewardColor = gained > 0 ? Colors.green : theme.colorScheme.onSurface.withOpacity(0.6);

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => SmartBlur(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: TweenAnimationBuilder(
            tween: Tween<double>(begin: 0.5, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: theme.primaryColor.withOpacity(0.6), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.35),
                    blurRadius: 40,
                    spreadRadius: 8,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(visuals.mainBadgeIcon, color: theme.primaryColor, size: 64),
                      ),
                      Positioned(
                        right: 0, top: 0,
                        child: Icon(visuals.secondaryIcon, color: theme.primaryColor.withOpacity(0.7), size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    !context.rolesRead.isStudent ? "Great signing!" : "Mastered!",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    !context.rolesRead.isStudent
                        ? "You signed the line \"$line\" correctly. Keep practising!"
                        : "Outstanding job! You have successfully mastered the line \"$line\"!",
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TweenAnimationBuilder(
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) => Transform.scale(scale: value, child: child),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: rewardColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: rewardColor.withOpacity(0.4), width: 2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(gained > 0 && context.rolesRead.isStudent ? visuals.secondaryIcon : Icons.check_circle_rounded, color: rewardColor, size: 22),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                // XP is given once per line; a repeat earns none.
                                gained > 0 ? "+$gained XP Earned!" : (context.rolesRead.isStudent ? "Daily XP limit reached" : "Correct sign!"),
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: rewardColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: theme.colorScheme.onPrimary,
                      elevation: 4,
                      shadowColor: theme.primaryColor.withOpacity(0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      minimumSize: const Size(double.infinity, 54),
                    ),
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text("Continue", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

  /// Session end. XP is already awarded per line in [_awardLineXp]; this only
  /// marks the civic module as recently used.
  Future<void> _saveUserProgress() async {
    if (_progressSaved) return;
    _progressSaved = true;
    await ProgressService().trackRecentModule('civic');
  }

  /// Awards the line's XP the first time it is mastered (Lupang Hinirang
  /// only; one mastery record per model class). Returns the XP awarded.
  Future<int> _awardLineXp(int classIndex) async {
    if (classIndex < 0 || _normalizeCategoryKey(widget.category) != LupangLines.category) return 0;
    return ProgressService().awardTutorialLineXp(
      moduleKey: LupangLines.moduleKey,
      lineKey: LupangLines.lineKey(classIndex),
      xp: xpReward,
      xpField: LupangLines.xpField,
    );
  }

  // ---------------------------------------------------------------------------
  // Continuous practice (civic_practice.dart)
  // ---------------------------------------------------------------------------

  /// Practice XP for every success (not once per line like the tutorial).
  Future<void> _awardPracticeXp() async {
    // Once per line: repeating a line in practice earns no more XP.
    // Faculty / Parent (guest): 0 XP; the mastery is kept on the device.
    _practiceXpGained = await ProgressService().awardFirstMastery(
      moduleKey: XpRewards.practiceKey('civic'),
      itemKey: LupangLines.lineKey(_expectedClassIndex()),
      xp: XpRewards.civicPractice,
      xpField: LupangLines.xpField,
      countsAsLesson: false,
    );
  }

  int _practiceXpGained = 0;

  /// Next line (after the last one: the first again). Used by success and Skip.
  void _advanceContinuous() {
    if (_activeQuestions.isEmpty) return;
    setState(() {
      _resetStepState();
      _currentStep = (_currentStep + 1) % _activeQuestions.length;
      _loadCurrentStepData();
    });
  }

  /// Same layout as the alphabet / numbers / phrases continuous practice.
  Widget _buildContinuousUI(ThemeData theme) {
    final visuals = _ThemeVisuals.fromTheme(theme);
    final isDark = theme.brightness == Brightness.dark;
    final bool landscape = _isLandscape(context);
    final double screenWidth = MediaQuery.of(context).size.width * (landscape ? 0.45 : 1.0);
    final bool ready = !_isBootstrapping && _activeQuestions.isNotEmpty && _currentStep < _activeQuestions.length;
    final currentItem = ready ? _activeQuestions[_currentStep] : const <String, dynamic>{};
    final bool busy = _isRecording || _countdown > 0;
    final double elapsed = (_isRecording && _recordStart != null)
        ? DateTime.now().difference(_recordStart!).inMilliseconds / 1000.0
        : 0.0;
    // Same frame colours as the numbers practice: green = correct, soft grey
    // otherwise; while recording the theme colour (no alarming red).
    final Color borderColor = _isSuccessAchieved
        ? Colors.greenAccent
        : (_isRecording || _isEvaluating ? theme.primaryColor : theme.dividerColor.withOpacity(0.6));

    final Widget cameraPane = Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(width: 4.0, color: borderColor),
            boxShadow: [
              if (_isSuccessAchieved || _isRecording)
                BoxShadow(color: borderColor.withOpacity(0.6), blurRadius: 25, spreadRadius: 2)
              else
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _isInitialized && _controller != null
                ? _CameraView(controller: _controller!)
                : Center(child: CircularProgressIndicator(color: theme.primaryColor)),
          ),
        ),
        if (_isInitialized && !_isSuccessAchieved)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SmartBlur(
                filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: Colors.black45,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isRecording) ...[
                        Icon(Icons.fiber_manual_record, color: theme.colorScheme.primary, size: 12),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        _isRecording ? "Recording" : (_isEvaluating ? "Evaluating..." : "Frame Body"),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final List<Widget> content = !ready
        ? [
            const SizedBox(height: 120),
            CircularProgressIndicator(color: theme.primaryColor),
            const SizedBox(height: 20),
            Text(_loadingStatus,
                style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.8))),
          ]
        : [
            // Progress chip + Skip (same header as the other continuous practices).
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Line ${_currentStep + 1} of ${_activeQuestions.length}',
                      style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton.icon(
                    onPressed: (busy || _isEvaluating || _isSuccessAchieved) ? null : _advanceContinuous,
                    icon: const Icon(Icons.skip_next_rounded, size: 18),
                    label: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurface.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
            Text(
              '${currentItem['question'] ?? ''}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                fontFamily: 'Inter',
                height: 1.15,
              ),
            ),
            if ('${currentItem['instruction'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${currentItem['instruction']}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.7), fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: screenWidth * 0.60,
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _isImageLoading
                        ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                        : _templateImageBytes != null
                            ? Image.memory(_templateImageBytes!, fit: BoxFit.cover)
                            : Container(
                                color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                                child: Icon(visuals.ambientIcon1, color: Colors.grey, size: 50),
                              ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Same camera size as the civic tutorial (220 x 220).
            if (!landscape) SizedBox(width: 220, height: 220, child: cameraPane),
            const SizedBox(height: 16),
            if (_isSuccessAchieved)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SmartBlur(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: TweenAnimationBuilder(
                    tween: Tween<double>(begin: 0.8, end: 1.0),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.elasticOut,
                    builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.withOpacity(0.3), width: 1.5),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(visuals.mainBadgeIcon, color: Colors.green, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                !context.rolesRead.isStudent ? "Mahusay! Tumpak ang kumpas" : (_practiceXpGained > 0 ? "Mahusay! +$_practiceXpGained XP" : "Mahusay! (naabot na ang XP ngayong araw)"),
                                style: const TextStyle(
                                    color: Colors.green, fontWeight: FontWeight.w900, fontSize: 20, fontFamily: 'Inter'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Susunod na linya...",
                            style: TextStyle(
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else ...[
              _RecordControls(
                heroTag: 'civic_practice_record_button',
                countdown: _countdown,
                isRecording: _isRecording,
                isEvaluating: _isEvaluating,
                elapsed: elapsed,
                recordProgress: elapsed / _maxRecording.inSeconds,
                bodyVisible: _poseVisible,
                showButton: _isInitialized,
                onRecord: _toggleRecording,
                width: 220,
              ),
              const SizedBox(height: 16),
              PracticeFeedback(message: _currentFeedback, tone: _feedbackTone),
            ],
          ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.cardColor.withOpacity(0.4),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        flexibleSpace: ClipRRect(
          child: SmartBlur(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text(
          'Continuous Practice',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 22,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w800,
            letterSpacing: -0.96,
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -20,
            right: -20,
            child: Opacity(
              opacity: 0.12,
              child: Transform.rotate(angle: -0.2, child: Icon(visuals.ambientIcon1, size: 220, color: theme.primaryColor)),
            ),
          ),
          Positioned(
            bottom: 40,
            left: -30,
            child: Opacity(
              opacity: 0.10,
              child: Transform.rotate(
                  angle: 0.3, child: Icon(visuals.ambientIcon2, size: 240, color: theme.colorScheme.secondary)),
            ),
          ),
          SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: content),
                    ),
                  ),
                ),
                if (landscape && ready)
                  Expanded(
                    flex: 6,
                    child: Padding(padding: const EdgeInsets.fromLTRB(0, 10, 16, 16), child: cameraPane),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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
    if (widget.continuous) return _buildContinuousUI(theme);

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
    final double elapsed = (_isRecording && _recordStart != null)
        ? DateTime.now().difference(_recordStart!).inMilliseconds / 1000.0
        : 0.0;

    // Landscape: the line, reference and controls on the left, camera on the right.
    final bool landscape = _isLandscape(context);
    final Widget cameraPane = Container(
      decoration: BoxDecoration(
        border: Border.all(
          width: 4,
          color: _isSuccessAchieved || isPassing
              ? Colors.green
              : (_isRecording || _isEvaluating ? theme.primaryColor : theme.dividerColor),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _isInitialized && _controller != null
            ? _CameraView(controller: _controller!)
            : const Center(child: CircularProgressIndicator()),
      ),
    );

    final Widget tutorial = SingleChildScrollView(
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
                  _activeQuestions.length == 1 && currentItem['line_number'] != null
                      ? 'Linya ${currentItem['line_number']}${context.rolesRead.isStudent ? ' • +$xpReward XP' : ''}'
                      : 'Linya ${_currentStep + 1} sa ${_activeQuestions.length}',
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
          if (!landscape) SizedBox(width: 220, height: 220, child: cameraPane),
          const SizedBox(height: 8),
          _RecordControls(
            heroTag: 'civic_record_button',
            countdown: _countdown,
            isRecording: _isRecording,
            isEvaluating: _isEvaluating,
            elapsed: elapsed,
            recordProgress: elapsed / _maxRecording.inSeconds,
            bodyVisible: _poseVisible,
            showButton: _isInitialized && !_isSuccessAchieved,
            onRecord: _toggleRecording,
            width: 220,
          ),
          const SizedBox(height: 16),
          PracticeFeedback(message: _currentFeedback, tone: _feedbackTone),
        ],
      ),
    );
    if (!landscape) return tutorial;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: tutorial),
        const SizedBox(width: 16),
        Expanded(flex: 6, child: Padding(padding: const EdgeInsets.only(bottom: 8), child: cameraPane)),
      ],
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
            _activeQuestions.length == 1
                ? 'Naisagawa mo nang tama ang "${_activeQuestions.first['question'] ?? ''}".'
                : 'Lahat ng ${_activeQuestions.length} na linya ay matagumpay mong naisagawa.',
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
              !context.rolesRead.isStudent
                  ? 'Magaling! Natapos mo ang pagsasanay.'
                  : (_xpEarned > 0 ? '+$_xpEarned Civic XP Earned' : 'Na-master na dati (walang dagdag XP)'),
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

// =============================================================================
// REWARD DIALOG VISUALS (same as the other categories' tutorial practice)
// =============================================================================
class _ThemeVisuals {
  final IconData mainBadgeIcon;
  final IconData secondaryIcon;
  final IconData ambientIcon1;
  final IconData ambientIcon2;

  const _ThemeVisuals({
    required this.mainBadgeIcon,
    required this.secondaryIcon,
    required this.ambientIcon1,
    required this.ambientIcon2,
  });

  factory _ThemeVisuals.fromTheme(ThemeData theme) {
    final primary = theme.primaryColor;
    final isDark = theme.brightness == Brightness.dark;

    if (primary.blue > 160 && primary.red < 120) {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.water_drop_rounded,
        secondaryIcon: Icons.waves_rounded,
        ambientIcon1: Icons.bubble_chart_rounded,
        ambientIcon2: Icons.sailing_rounded,
      );
    } else if (primary.green > 160 && primary.red < 120) {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.eco_rounded,
        secondaryIcon: Icons.forest_rounded,
        ambientIcon1: Icons.park_rounded,
        ambientIcon2: Icons.energy_savings_leaf_rounded,
      );
    } else if (isDark) {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.auto_awesome_rounded,
        secondaryIcon: Icons.nights_stay_rounded,
        ambientIcon1: Icons.star_border_rounded,
        ambientIcon2: Icons.wb_twilight_rounded,
      );
    } else {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.stars_rounded,
        secondaryIcon: Icons.workspace_premium_rounded,
        ambientIcon1: Icons.wb_sunny_rounded,
        ambientIcon2: Icons.auto_awesome_rounded,
      );
    }
  }
}

// =============================================================================
// CAMERA HELPERS (local to this screen)
// =============================================================================

/// Clockwise rotation that makes the camera image upright for the current
/// device orientation (front: sensor + deviceCCW, back: sensor - deviceCCW).
int _cameraImageRotation(CameraController? c) {
  if (c == null) return 0;
  final sensor = c.description.sensorOrientation;
  final ccw = switch (c.value.deviceOrientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  return c.description.lensDirection == CameraLensDirection.front
      ? (sensor + ccw) % 360
      : (sensor - ccw + 360) % 360;
}

bool _isLandscape(BuildContext context) => MediaQuery.orientationOf(context) == Orientation.landscape;

/// Camera preview scaled to cover its box without stretching. Display only:
/// recognition uses the image stream, not this widget.
class _CameraView extends StatelessWidget {
  final CameraController controller;
  const _CameraView({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final size = value.previewSize;
        if (!value.isInitialized || size == null) return const ColoredBox(color: Colors.black);
        final landscape = value.deviceOrientation == DeviceOrientation.landscapeLeft ||
            value.deviceOrientation == DeviceOrientation.landscapeRight;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.05,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.28)],
              stops: const [0.62, 1.0],
            ),
          ),
          child: ColoredBox(
            color: Colors.black,
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: landscape ? size.longestSide : size.shortestSide,
                  height: landscape ? size.shortestSide : size.longestSide,
                  child: CameraPreview(controller),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Record controls under the camera. Kept identical in
/// phrase_tutorial_practice.dart and civic_tutorial_practice.dart:
/// one status line (countdown / recording bar / checking bar / body hint)
/// and the round record button, in the same look on every screen.
class _RecordControls extends StatelessWidget {
  final int countdown;
  final bool isRecording;
  final bool isEvaluating;

  /// Seconds recorded so far, and how full the recording bar is (0-1).
  final double elapsed;
  final double recordProgress;

  /// Body / hands in view (shown while idle).
  final bool bodyVisible;

  /// null disables the button.
  final VoidCallback? onRecord;
  final bool showButton;
  final double? width;
  final String heroTag;

  const _RecordControls({
    required this.countdown,
    required this.isRecording,
    required this.isEvaluating,
    required this.elapsed,
    required this.recordProgress,
    required this.bodyVisible,
    required this.onRecord,
    required this.heroTag,
    this.showButton = true,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final barWidth = width ?? MediaQuery.sizeOf(context).width * 0.70;

    // One animation only (extra spinners made the camera lag): a static
    // dot + the bar; the record button is hidden while checking.
    Widget bar(String label, double? value) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle, size: 10, color: primary),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SmartBlur(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  width: barWidth,
                  height: 14,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.surface.withValues(alpha: 0.5), width: 1),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 200),
                      widthFactor: value ?? 0.5,
                      child: Container(
                        decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

    final Widget status;
    if (countdown > 0) {
      status = Text(
        'Ibaba ang mga kamay… $countdown',
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFFF08C00)),
      );
    } else if (isRecording) {
      status = bar('Nagre-record... ${elapsed.toStringAsFixed(1)}s', recordProgress.clamp(0.0, 1.0));
    } else if (isEvaluating) {
      status = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Sinusuri ang kumpas...', style: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 10),
          SizedBox(
            width: barWidth,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LinearProgressIndicator(minHeight: 14, color: primary, backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.4)),
            ),
          ),
        ],
      );
    } else {
      status = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(bodyVisible ? Icons.check_circle_rounded : Icons.accessibility_new_rounded,
              size: 18, color: bodyVisible ? const Color(0xFF2E9E4F) : const Color(0xFFF08C00)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              bodyVisible ? 'Nakikita ang katawan. Pindutin ang RECORD' : 'Lumayo nang kaunti para makita ang balikat at mga kamay',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: bodyVisible ? const Color(0xFF2E9E4F) : const Color(0xFFF08C00),
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        status,
        if (showButton && !isEvaluating) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 64,
            width: 64,
            child: FloatingActionButton(
              heroTag: heroTag,
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              disabledElevation: 0,
              elevation: 8,
              onPressed: onRecord,
              child: Icon(countdown > 0 ? Icons.close : (isRecording ? Icons.stop : Icons.fiber_manual_record), size: 32),
            ),
          ),
        ],
      ],
    );
  }
}
