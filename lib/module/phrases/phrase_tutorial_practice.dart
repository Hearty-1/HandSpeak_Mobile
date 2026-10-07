import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;

import '/services/handspeak_api_service.dart';
import '/services/holistic_capture.dart';
import 'phrase_recognizer.dart';
import 'pose_provider.dart';

// =============================================================================
// THEME VISUAL MAPPING (Imported from Numbers UI/UX)
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
// CALENDAR SIGNS (assets/phrases/calendar_v1.json)
// =============================================================================
/// The 12 months of the FSL calendar model. Class order = model output order;
/// index 12 is INVALID_GESTURE.
class CalendarSigns {
  static const List<String> classNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];
  static const List<String> displayLabels = [
    'Enero', 'Pebrero', 'Marso', 'Abril', 'Mayo', 'Hunyo', 'Hulyo', 'Agosto',
    'Setyembre', 'Oktubre', 'Nobyembre', 'Disyembre',
  ];
  static const int invalidIndex = 12;

  static String _compact(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Month index (0..11) for a lesson title / server label in Filipino or
  /// English ("Enero", "january", "SETYEMBRE", "calendar_marso"), else -1.
  static int indexFor(String? name) {
    if (name == null) return -1;
    var key = _compact(name);
    for (final prefix in ['calendar', 'buwan', 'month']) {
      if (key.startsWith(prefix) && key.length > prefix.length) key = key.substring(prefix.length);
    }
    for (int i = 0; i < 12; i++) {
      if (_compact(displayLabels[i]) == key || _compact(classNames[i]) == key) return i;
    }
    // Common alternative spellings.
    const alt = {'septyembre': 8, 'setiyembre': 8, 'nobiyembre': 10, 'disiyembre': 11};
    return alt[key] ?? -1;
  }

  static bool isMonth(String? name) => indexFor(name) != -1;
}

// =============================================================================
// MAIN PRACTICE WIDGET
// =============================================================================
/// Practice for phrases. Greetings use the hand_landmarker + PhraseRecognizer
/// features and POST /v1/predict/greetings. Calendar months (Enero..Disyembre)
/// use the native raw Pose + Hands capture and POST /v1/predict_raw/calendar
/// (server runs the calendar v4 pipeline and its strict gates).
class PhraseTutorialPractice extends StatefulWidget {
  final String targetPhrase;

  const PhraseTutorialPractice({super.key, required this.targetPhrase});

  @override
  State<PhraseTutorialPractice> createState() => _PhraseTutorialPracticeState();
}

class _PhraseTutorialPracticeState extends State<PhraseTutorialPractice>
    with WidgetsBindingObserver {
  // ---- pipeline objects ----------------------------------------------------
  CameraController? _controller;
  HandLandmarkerPlugin? _landmarker;
  StreamSubscription<List<Hand>>? _landmarkSub;
  final PhraseRecognizer _recognizer = PhraseRecognizer(); 
  final PoseProvider _pose = PoseProvider();

  static final Map<String, Uint8List> _gestureImageCache = {};
  Uint8List? _templateImage;

  // ---- state ---------------------------------------------------------------
  bool _disposed = false;
  bool _isInitialized = false;
  bool _initFailed = false;
  bool _isSuccessAchieved = false;
  bool _handsVisible = false;
  bool _poseVisible = false;

  // Recording
  bool _isRecording = false;
  DateTime? _recordStart;
  Timer? _maxRecordTimer;
  Timer? _countdownTimer;
  int _countdown = 0; 
  final List<Float32List> _frames = [];
  final List<bool> _frameHasHands = [];
  final List<bool> _frameHasPose = [];
  final List<int> _frameTimesMs = [];
  bool _sawHands = false;
  int _lastHandMs = 0;
  int _lastUiMs = 0;
  double _xScale = 1.0;

  // Hands must be gone this long before auto-stop: longer than the server's
  // 1 s hand memory, so a brief tracking drop does not end the sign early.
  static const int _autoStopAfterMs = 1500;
  static const int _manualStopTrimMs = 600;

  late final int _targetIndex = PhraseRecognizer.classIndexFor(widget.targetPhrase);
  static const Duration _maxRecording = Duration(seconds: 12);

  double _minConfidence = PhraseRecognizer.defaultMinConfidence;
  final int xpReward = 20;

  // UI text
  String _status = 'Preparing…';
  String _resultTitle = '';
  String _resultDetail = '';
  Color _resultColor = Colors.grey;
  bool _isEvaluating = false;

  // ---- calendar mode (raw Pose + Hands -> /v1/predict_raw/calendar) --------
  late final bool _isCalendar = CalendarSigns.isMonth(widget.targetPhrase);
  late final int _calendarTarget = CalendarSigns.indexFor(widget.targetPhrase);
  final List<RawFrame> _rawFrames = [];
  // Up to 2 frames in flight: native converts the next camera image while
  // the previous one is still in the pose / hand models.
  int _nativeInFlight = 0;
  static const int _maxInFlight = 2;
  int _imageWidth = 0, _imageHeight = 0;
  String _engine = '';
  String _debug = '';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    _loadGestureTemplateImage();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || !_isInitialized) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cancelRecording();
      _landmarkSub?.pause();
      if (c.value.isStreamingImages) {
        unawaited(c.stopImageStream().catchError((_) {}));
      }
    } else if (state == AppLifecycleState.resumed) {
      _landmarkSub?.resume();
      unawaited(_startImageStream());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _maxRecordTimer?.cancel();
    _countdownTimer?.cancel();
    _landmarkSub?.cancel();

    final c = _controller;
    _controller = null;
    if (c != null) {
      unawaited(() async {
        try {
          if (c.value.isStreamingImages) await c.stopImageStream();
        } catch (_) {}
        try {
          await c.dispose();
        } catch (_) {}
      }());
    }

    try {
      _landmarker?.dispose();
    } catch (_) {}
    _landmarker = null;

    unawaited(_pose.dispose());
    _recognizer.dispose();
    super.dispose();
  }

  void _setStatus(String s) {
    if (!mounted || _disposed) return;
    setState(() => _status = s);
  }

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> _bootstrap() async {
    await Future.wait([_fetchConfig(), PhraseRecognizer.loadTemplates()]);
    if (_disposed) return;
    await _initializePipeline();
  }

  Future<void> _fetchConfig() async {
    try {
      _setStatus('Loading training config…');
      final key = PhraseRecognizer.normalizeKey(widget.targetPhrase);
      final col = FirebaseFirestore.instance.collection('gesture_training_data');
      const timeout = Duration(seconds: 4);

      DocumentSnapshot<Map<String, dynamic>>? doc;
      for (final id in ['phrases_$key', key, 'words_$key', 'letters_$key']) {
        final snap = await col.doc(id).get().timeout(timeout);
        if (snap.exists) {
          doc = snap;
          break;
        }
      }
      if (doc == null) {
        final q = await col
            .where('gestureKeyNormalized', isEqualTo: key)
            .limit(1)
            .get()
            .timeout(timeout);
        if (q.docs.isNotEmpty) doc = q.docs.first;
      }

      final raw = doc?.data()?['accuracyThreshold'];
      if (raw is num && raw > 0) {
        _minConfidence = raw <= 1.0 ? raw * 100.0 : raw.toDouble();
      }
    } catch (e) {
      debugPrint('Firestore config skipped ($e). Using defaults.');
    }
  }

  HandLandmarkerPlugin _createLandmarker() {
    try {
      return HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.gpu,
      );
    } catch (e) {
      debugPrint('GPU delegate unavailable ($e). Falling back to CPU.');
      return HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.cpu,
      );
    }
  }

  void _fail(String message) {
    debugPrint('Pipeline init failed: $message');
    if (!mounted || _disposed) return;
    setState(() {
      _initFailed = true;
      _status = '❌ $message';
    });
  }

  Future<void> _initializePipeline() async {
    String stage = 'hand landmarker';
    try {
      // Calendar months are tracked natively (fsl_holistic_channel) instead.
      if (!_isCalendar) {
        _setStatus('1/3 Starting hand tracking…');
        _landmarker = _createLandmarker();
        _landmarkSub = _landmarker!.landmarkStream.listen(
          _onHandsDetected,
          onError: (e) => _setStatus('❌ Hand tracking error: $e'),
        );
      }

      stage = 'camera';
      _setStatus('2/3 Opening camera…');
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail('No camera found on this device.');
        return;
      }
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      
      _recognizer.mirrorX = false;
      _pose.mirrorX = false;
      _recognizer.handRotation = cam.sensorOrientation;

      final controller = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: (Platform.isAndroid || _isCalendar)
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      _controller = controller;

      stage = 'camera stream';
      _setStatus('3/3 Starting stream…');
      _isInitialized = true;
      await _startImageStream();

      if (!mounted || _disposed) return;
      setState(() {
        _status = 'Stand back so your upper body is visible,\nthen tap RECORD.';
      });
    } on CameraException catch (e) {
      _fail('Camera error (${e.code}): ${e.description ?? ''}\nCheck camera permission.');
    } catch (e) {
      _fail('Failed at $stage:\n$e');
    }
  }

  Future<void> _startImageStream() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isStreamingImages) {
      return;
    }
    await c.startImageStream(_onCameraImage);
  }

  void _onCameraImage(CameraImage image) {
    if (_disposed || !_isInitialized || _isSuccessAchieved) return;
    if (_isCalendar) {
      unawaited(_onCalendarImage(image));
      return;
    }
    final c = _controller;
    final landmarker = _landmarker;
    if (c == null || landmarker == null) return;

    final int rotation = c.description.sensorOrientation;
    final bool swap = rotation == 90 || rotation == 270;
    _xScale = PhraseRecognizer.aspectXScale(
      swap ? image.height : image.width,
      swap ? image.width : image.height,
    );
    try {
      landmarker.processFrame(image, rotation);
    } catch (e) {
      debugPrint('Dropped frame: $e');
    }
    unawaited(_pose.process(image, rotation));
  }

  // ---------------------------------------------------------------------------
  // Frame collection
  // ---------------------------------------------------------------------------

  void _onHandsDetected(List<Hand> hands) {
    if (_disposed || !mounted || _isSuccessAchieved) return;

    final features = _recognizer.extractFrameFeatures(
      hands,
      pose: _pose.latest(),
      xScale: _xScale,
    );
    final bool visible = _recognizer.lastFrameHadHands;
    final bool poseVisible = _recognizer.lastFrameHadPose;
    final bool visibilityChanged = visible != _handsVisible || poseVisible != _poseVisible;
    _handsVisible = visible;
    _poseVisible = poseVisible;

    if (!_isRecording) {
      if (visibilityChanged) setState(() {});
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _frames.add(features);
    _frameHasHands.add(visible);
    _frameHasPose.add(poseVisible);
    _frameTimesMs.add(nowMs);

    if (visible) {
      _sawHands = true;
      _lastHandMs = nowMs;
    } else if (_sawHands && nowMs - _lastHandMs > _autoStopAfterMs) {
      unawaited(_stopAndEvaluate());
      return;
    }

    if (visibilityChanged || nowMs - _lastUiMs > 80) {
      _lastUiMs = nowMs;
      setState(() {});
    }
  }

  // Capture-rate diagnostics (logcat "FslDart"), non-release builds only.
  int _perfCount = 0, _perfStartMs = 0, _perfRttSum = 0;
  void _logCalendarPerf(int sentMs) {
    if (kReleaseMode) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_perfCount == 0) _perfStartMs = now;
    _perfCount++;
    _perfRttSum += now - sentMs;
    if (_perfCount == 30) {
      debugPrint('FslDart: ${(29000 / (now - _perfStartMs)).toStringAsFixed(1)} fps, '
          'round trip ${(_perfRttSum / 30).toStringAsFixed(0)} ms');
      _perfCount = 0;
      _perfRttSum = 0;
    }
  }

  /// Calendar mode: one native Pose + Hands pass per camera frame.
  Future<void> _onCalendarImage(CameraImage image) async {
    final c = _controller;
    if (_nativeInFlight >= _maxInFlight || _isEvaluating || c == null) return;
    _nativeInFlight++;
    final sentMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final r = await HolisticCapture.process(image, c.description.sensorOrientation);
      if (r == null || _disposed || !mounted) return;
      _logCalendarPerf(sentMs);
      _imageWidth = r.imageWidth;
      _imageHeight = r.imageHeight;
      _engine = r.engine;
      final f = r.frame;
      final changed = f.hasHands != _handsVisible || r.poseVisible != _poseVisible;
      _handsVisible = f.hasHands;
      _poseVisible = r.poseVisible;

      if (!_isRecording) {
        if (changed) setState(() {});
        return;
      }
      _rawFrames.add(f);
      if (f.hasHands) {
        _sawHands = true;
        _lastHandMs = f.timeMs;
      } else if (_sawHands && f.timeMs - _lastHandMs > _autoStopAfterMs) {
        unawaited(_stopAndEvaluate()); // hands lowered: the sign is done
        return;
      }
      // Redraw at most ~4x per second while recording: every rebuild of this
      // screen (blur filters) competes with MediaPipe for the GPU.
      if (changed || f.timeMs - _lastUiMs > 250) {
        _lastUiMs = f.timeMs;
        setState(() {});
      }
    } catch (e) {
      debugPrint('Calendar capture error: $e');
    } finally {
      _nativeInFlight--;
    }
  }

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

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdown = 3;
      _resultTitle = '';
      _resultDetail = '';
      _resultColor = Colors.grey;
      _status = 'Lower your arms to your sides…';
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _disposed) {
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

  void _clearCapture() {
    _frames.clear();
    _frameHasHands.clear();
    _frameHasPose.clear();
    _frameTimesMs.clear();
    _rawFrames.clear();
    _sawHands = false;
    _lastHandMs = 0;
  }

  void _startRecording() {
    _clearCapture();
    _recognizer.resetTracking();
    _maxRecordTimer?.cancel();
    _maxRecordTimer = Timer(_maxRecording, _stopAndEvaluate);
    setState(() {
      _countdown = 0;
      _isRecording = true;
      _recordStart = DateTime.now();
      _status = 'Sign now! Lower your hands when finished.';
    });
  }

  void _cancelRecording() {
    _maxRecordTimer?.cancel();
    _countdownTimer?.cancel();
    if (_countdown > 0) {
      _countdown = 0;
      if (mounted && !_disposed) {
        setState(() => _status = 'Cancelled. Tap RECORD to try again.');
      }
      return;
    }
    if (!_isRecording) return;
    _clearCapture();
    if (mounted && !_disposed) {
      setState(() {
        _isRecording = false;
        _recordStart = null;
        _status = 'Recording cancelled. Tap RECORD to try again.';
      });
    } else {
      _isRecording = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Evaluation via Cloud Run API
  // ---------------------------------------------------------------------------

  List<double> _probsFromResponse(PredictResponse response) {
    final probs = List<double>.filled(PhraseRecognizer.numClasses, 0.0);
    final entries = [response.prediction, ...response.topK];

    double scale = 1.0;
    if (entries.any((p) => p.confidence > 1.0)) scale = 0.01; 

    for (final p in entries) {
      int idx = -1;
      for (final name in [p.label, p.labelEn, p.code]) {
        if (name == null || name.isEmpty) continue;
        idx = PhraseRecognizer.classIndexFor(name);
        if (idx != -1) break;
      }
      if (idx == -1 && p.index >= 0 && p.index < probs.length) idx = p.index;
      if (idx == -1) continue;
      probs[idx] = p.confidence * scale;
    }
    return probs;
  }

  Future<PredictResponse> _predictCloud(List<double> features) async {
    final api = HandSpeakApiService();
    try {
      return await api.predict(
        modelId: HandSpeakModels.greetings,
        features: features,
        topK: PhraseRecognizer.numClasses,
      );
    } on Exception catch (e) {
      if (!e.toString().contains('[4')) rethrow;
      return api.predict(modelId: HandSpeakModels.greetings, features: features);
    }
  }

  void _showResult({
    required String title,
    required String detail,
    required Color color,
    double score = 0.0,
  }) {
    if (!mounted || _disposed) return;
    setState(() {
      _isRecording = false;
      _isEvaluating = false;
      _recordStart = null;
      _resultTitle = title;
      _resultDetail = detail;
      _resultColor = color;
      _status = 'Tap RECORD to try again.';
    });
  }

  Future<void> _stopAndEvaluate({bool manual = false}) async {
    if (!_isRecording || _disposed) return;
    _isRecording = false;
    _maxRecordTimer?.cancel();

    if (_isCalendar) {
      await _evaluateCalendar(manual);
      return;
    }

    final frames = List<Float32List>.of(_frames);
    final hasHands = List<bool>.of(_frameHasHands);
    final hasPose = List<bool>.of(_frameHasPose);
    final times = List<int>.of(_frameTimesMs);
    _clearCapture();

    if (!mounted) return;

    int usable = frames.length;
    if (manual && times.isNotEmpty) {
      final cutoff = times.last - _manualStopTrimMs;
      while (usable > 0 && times[usable - 1] > cutoff) {
        usable--;
      }
    }

    final window = PhraseRecognizer.trainingWindow(hasHands.sublist(0, usable));
    if (window == null) {
      _showResult(
        title: 'No hands detected',
        detail: 'Start with your arms down, raise your hands to sign, and '
            'keep your upper body and hands inside the camera frame.',
        color: Colors.red,
      );
      return;
    }
    final clip = frames.sublist(window[0], window[1]);
    final clipPose = hasPose.sublist(window[0], window[1]);

    if (!PhraseRecognizer.fillMissingPose(clip, clipPose)) {
      _showResult(
        title: 'Body not detected',
        detail: 'Step back so your shoulders, elbows and hands are visible.',
        color: Colors.red,
      );
      return;
    }
    
    if (clip.length < PhraseRecognizer.minRecordedFrames) {
      _showResult(
        title: 'Too fast',
        detail: 'Only ${clip.length} frames captured. Sign slightly slower.',
        color: Colors.red,
      );
      return;
    }

    setState(() {
      _isEvaluating = true;
      _isRecording = false;
      _recordStart = null;
      _status = 'Analyzing motion...';
    });

    final Float32List seq = _recognizer.prepareStandardSequence(clip, PhraseRecognizer.sequenceLength);
    final List<double> featureVector = seq.toList();

    try {
      final response = await _predictCloud(featureVector);
      if (!mounted || _disposed) return;

      final eval = _recognizer.classifyProbabilities(
        _probsFromResponse(response),
        minConfidence: _minConfidence,
      );
      
      final bool rightSign = _targetIndex != -1
          ? eval.top1Index == _targetIndex
          : PhraseRecognizer.compactKey(eval.top1Label) == PhraseRecognizer.compactKey(widget.targetPhrase);
      final bool isMatch = rightSign && eval.verdict == PhraseVerdict.accepted;
      final double targetPct = _targetIndex != -1
          ? eval.probPercent(_targetIndex)
          : (rightSign ? eval.top1Prob : 0.0);
      final String stats = 'Confidence: ${eval.top1Prob.toStringAsFixed(1)}%\n'
          'Margin: ${eval.margin.toStringAsFixed(1)}%';

      if (isMatch) {
        setState(() {
          _resultColor = Colors.greenAccent;
          _resultTitle = 'Match!';
          _resultDetail = stats;
          _status = 'Great job!';
          _isEvaluating = false;
        });
        _onSuccess();
        return;
      }

      final String title;
      switch (eval.verdict) {
        case PhraseVerdict.rejectedUnknown:
          title = 'Sign not recognized';
          break;
        case PhraseVerdict.uncertain:
          title = rightSign
              ? 'Almost! Needs more clarity'
              : 'Unclear — looks like ${eval.top1Label}';
          break;
        default:
          title = 'Predicted: ${eval.top1Label}';
      }
      _showResult(
        title: title,
        detail: stats,
        color: rightSign ? Colors.orange : Colors.redAccent,
        score: targetPct,
      );
    } catch (e) {
      debugPrint('Cloud Run prediction error: $e');
      _showResult(
        title: 'Evaluation Failed',
        detail: e.toString().replaceAll('Exception: ', ''),
        color: Colors.redAccent,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Calendar evaluation via POST /v1/predict_raw/calendar
  // ---------------------------------------------------------------------------

  String _monthName(Prediction? p) {
    if (p == null) return '';
    final i = CalendarSigns.indexFor(p.label);
    return i >= 0 ? CalendarSigns.displayLabels[i] : p.label;
  }

  int _monthIndexOf(Prediction p) {
    if (p.label.toUpperCase().contains('INVALID') || p.index == CalendarSigns.invalidIndex) return -1;
    final byName = CalendarSigns.indexFor(p.label);
    if (byName != -1) return byName;
    return (p.index >= 0 && p.index < 12) ? p.index : -1;
  }

  /// Gate codes from /v1/predict_raw/calendar -> Tagalog guidance. Takes
  /// precedence over HolisticCapture.rejectAdvice for these codes.
  static const Map<String, String> _calendarAdvice = {
    'FRAGMENT_DURATION': 'Kulang pa ang haba ng kumpas para sa senyas na ito. Isagawa nang buo at huwag magmadali.',
    'NO_HANDS': 'Walang nakitang kamay. Ipakita ang katawan at mga kamay sa camera.',
    'TOO_SHORT': 'Masyadong maikli ang kumpas. Isagawa ang buong galaw.',
    'LOW_CONFIDENCE': 'Hindi pa tiyak ang kumpas. Gawin nang mas malinaw at buo.',
    'SMALL_MARGIN': 'Hindi pa tiyak ang kumpas. Gawin nang mas malinaw at buo.',
  };

  static String? _adviceFor(String code) => _calendarAdvice[code] ?? HolisticCapture.rejectAdvice[code];

  /// Shorter sub-windows of a capture (the whole capture is judged too):
  /// 1.5 / 2.0 / 2.6 s long, every 0.5 s, at most 8.
  List<List<RawFrame>> _calendarWindows(List<RawFrame> frames) {
    if (frames.length < 10) return const [];
    final t0 = frames.first.timeMs, total = frames.last.timeMs - t0;
    final out = <List<RawFrame>>[];
    for (final len in const [1500, 2000, 2600]) {
      if (len > total - 300) continue;
      for (int start = 0; start + len <= total; start += 500) {
        final w = frames
            .where((f) => f.timeMs - t0 >= start && f.timeMs - t0 <= start + len)
            .toList();
        if (w.length >= 8 && w.any((f) => f.hasHands)) out.add(w);
      }
    }
    if (out.length <= 8) return out;
    return [for (int i = 0; i < 8; i++) out[(i * (out.length - 1) / 7).round()]];
  }

  Future<void> _evaluateCalendar(bool manual) async {
    var frames = List<RawFrame>.of(_rawFrames)..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    _clearCapture();
    if (!mounted) return;

    if (manual && frames.isNotEmpty) {
      final cutoff = frames.last.timeMs - _manualStopTrimMs; // the reach to the screen
      frames = frames.where((f) => f.timeMs <= cutoff).toList();
    }
    if (!frames.any((f) => f.hasHands)) {
      _showResult(
        title: 'No hands detected',
        detail: HolisticCapture.rejectAdvice['NO_HANDS']!,
        color: Colors.red,
      );
      return;
    }
    // No client-side idle trimming here: month signs are mostly handshape
    // changes with a nearly still wrist, so a wrist-speed trim cut out the
    // sign itself (only the shortest months, Nov/Dec, still passed the
    // per-month FRAGMENT_DURATION floor). The server applies calendar's own
    // trim_still, exactly as in training. Only drop the resting lead-in /
    // tail where no hand is visible at all.
    final firstHand = frames.indexWhere((f) => f.hasHands);
    final lastHand = frames.lastIndexWhere((f) => f.hasHands);
    frames = frames.sublist(firstHand, lastHand + 1);

    setState(() {
      _isEvaluating = true;
      _recordStart = null;
      _status = 'Analyzing motion...';
    });

    final target = _calendarTarget;
    final targetLabel = CalendarSigns.displayLabels[target];
    final t0 = frames.first.timeMs;
    final secs = (frames.last.timeMs - t0) / 1000.0;
    try {
      // The whole capture plus a few shorter windows, judged in parallel by
      // the server. Training clips are pure signing (~1.2-2 s); a capture
      // also holds the hand coming up, pauses and the hand going down, which
      // can dilute a correct sign. Every window still has to pass all of the
      // server's strict gates (confidence, margin, entropy, duration).
      final api = HandSpeakApiService();
      final windows = _calendarWindows(frames);
      Future<RawPredictResponse?> judge(List<RawFrame> w, {bool rethrowErrors = false}) async {
        try {
          final w0 = w.first.timeMs;
          // Upright landmarks + hands assigned to the pose wrists, exactly
          // like the desktop engine (a no-op when native already did it).
          final fixed = CaptureFixer.fix([for (final f in w) f.toJson(w0)], _imageWidth, _imageHeight);
          return await api.predictRaw(
            modelId: HandSpeakModels.calendar,
            frames: fixed.frames,
            imageWidth: fixed.imageWidth,
            imageHeight: fixed.imageHeight,
          );
        } catch (e) {
          if (rethrowErrors) rethrow;
          debugPrint('Calendar window error: $e');
          return null;
        }
      }

      final results = await Future.wait([
        judge(frames, rethrowErrors: true),
        for (final w in windows) judge(w),
      ]);
      if (!mounted || _disposed) return;
      bool isTargetAccept(RawPredictResponse? r) =>
          r != null && r.accepted && r.prediction != null && _monthIndexOf(r.prediction!) == target;

      final matchAt = results.indexWhere(isTargetAccept);
      final result = matchAt >= 0 ? results[matchAt]! : results.first!;
      String windowLabel(int i) {
        final r = results[i];
        final name = i == 0 ? 'full' : 'w$i';
        if (r == null) return '$name:error';
        if (r.prediction != null) return '$name:${_monthName(r.prediction)}${r.accepted ? '✓' : ''}';
        return '$name:${r.failed.isNotEmpty ? r.failed.first : '-'}';
      }

      final windowReport = [for (int i = 0; i < results.length; i++) windowLabel(i)].join(' ');
      debugPrint('Calendar response: ${result.raw}');
      debugPrint('Calendar windows: $windowReport');
      if (!kReleaseMode) {
        // Debug / profile builds keep each attempt for offline analysis:
        // adb shell run-as <package> ls code_cache/calendar_dumps
        try {
          final dir = Directory('${Directory.systemTemp.path}/calendar_dumps')..createSync(recursive: true);
          File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${CalendarSigns.classNames[target]}.json')
              .writeAsStringSync(jsonEncode({
            'target': target,
            'image_width': _imageWidth,
            'image_height': _imageHeight,
            'frames': [for (final f in frames) f.toJson(t0)],
            'response': results.first?.raw,
            'windows': windowReport,
          }));
        } catch (e) {
          debugPrint('Calendar dump failed: $e');
        }
      }

      final top = result.prediction;
      final topIdx = top == null ? -1 : _monthIndexOf(top);
      double confFor(int idx) {
        for (final p in [if (top != null) top, ...result.topK]) {
          if (_monthIndexOf(p) == idx) return p.confidence > 1.0 ? p.confidence / 100.0 : p.confidence;
        }
        return 0.0;
      }

      final accepted = result.accepted;
      if (kDebugMode) {
        final checks = result.raw['checks'];
        final lines = checks is List
            ? [
                for (final c in checks)
                  if (c is Map) "${c['passed'] == true ? '✓' : '✗'} ${c['label']}: ${c['text']}"
              ].join('\n')
            : '';
        _debug = 'target #$target $targetLabel | top=#$topIdx (${top?.label} '
            '${top?.confidence.toStringAsFixed(2)}) | failed=${result.failed}\n'
            'capture: ${frames.length} frames / ${secs.toStringAsFixed(1)} s = '
            '${(frames.length / (secs > 0 ? secs : 1)).toStringAsFixed(1)} fps | '
            '${_engine.isEmpty ? 'OLD NATIVE BUILD - run "flutter run" again' : _engine}\n'
            'windows: $windowReport\n'
            'top3: ${result.topK.take(3).map((p) => '${_monthName(p)} ${(p.confidence > 1 ? p.confidence : p.confidence * 100).toStringAsFixed(0)}%').join(', ')}\n'
            '$lines';
      }

      if (accepted && topIdx == target) {
        final conf = confFor(target);
        setState(() {
          _resultColor = Colors.greenAccent;
          _resultTitle = 'Match!';
          _resultDetail = conf > 0 ? 'Confidence: ${(conf * 100).toStringAsFixed(1)}%' : '';
          _status = 'Great job!';
          _isEvaluating = false;
        });
        _onSuccess();
        return;
      }
      if (accepted && topIdx != -1) {
        _showResult(
          title: 'Predicted: ${_monthName(top)}',
          detail: 'Subukang muli ang $targetLabel. Sundan ang halimbawa.',
          color: Colors.redAccent,
        );
        return;
      }
      final code = result.failed.firstWhere((c) => _adviceFor(c) != null,
          orElse: () => result.failed.isNotEmpty ? result.failed.first : '');
      final advice = _adviceFor(code) ??
          (result.message?.trim().isNotEmpty == true
              ? 'Hindi tinanggap: ${result.message}'
              : 'Hindi makilala ang kumpas. Ulitin nang mas malinaw.');
      final close = topIdx != -1 && !const {'NO_HANDS', 'TOO_SHORT', 'LOW_MOTION'}.contains(code);
      _showResult(
        title: close && topIdx == target
            ? 'Almost! Needs more clarity'
            : (close ? 'Unclear — looks like ${_monthName(top)}' : 'Sign not recognized'),
        detail: advice,
        color: close && topIdx == target ? Colors.orange : Colors.redAccent,
      );
    } on ArgumentError catch (e) {
      // Rejected by the API client before upload (e.g. no pose in most frames).
      debugPrint('Calendar capture rejected client-side: ${e.message}');
      _showResult(
        title: 'Body not detected',
        detail: '${e.message}'.contains('Pose')
            ? 'Hindi makita ang katawan. Ipakita ang balikat, katawan at mga kamay sa camera.'
            : 'Hindi maipadala ang kumpas. Subukang muli.',
        color: Colors.redAccent,
      );
    } catch (e) {
      debugPrint('Calendar prediction error: $e');
      final text = e.toString();
      _showResult(
        title: 'Evaluation Failed',
        // 404 only if the deployed server has no calendar route (it does since
        // revision handspeak-inference-00012); every other failure is shown as-is.
        detail: text.contains('[404]')
            ? 'Hindi mahanap sa server ang calendar model (/v1/predict_raw/calendar). I-update ang app o subukang muli mamaya.'
            : text.replaceAll('Exception: ', ''),
        color: Colors.redAccent,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Success / XP
  // ---------------------------------------------------------------------------

  Future<void> _awardXp() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'phraseXp': FieldValue.increment(xpReward),
          'xp': FieldValue.increment(xpReward),
          'dailyXp': FieldValue.increment(xpReward),
          'completedLessons': FieldValue.increment(1),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Failed to write XP: $e');
    }
  }

  Future<void> _onSuccess() async {
    if (_isSuccessAchieved) return;
    _isSuccessAchieved = true;

    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.heavyImpact();

    await _awardXp();
    if (!mounted) return;

    final theme = Theme.of(context);
    final visuals = _ThemeVisuals.fromTheme(theme);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: TweenAnimationBuilder(
            tween: Tween<double>(begin: 0.5, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
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
                    "Mastered!",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Outstanding job! You have successfully mastered the phrase \"${widget.targetPhrase}\"!",
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
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: child,
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.green.withOpacity(0.4), width: 2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(visuals.secondaryIcon, color: Colors.green, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              "+$xpReward XP Earned!",
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.green),
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
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context);
                    },
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

  // ---------------------------------------------------------------------------
  // Reference image
  // ---------------------------------------------------------------------------

  Future<void> _loadGestureTemplateImage() async {
    final key = PhraseRecognizer.normalizeKey(widget.targetPhrase);
    final cached = _gestureImageCache[key];
    if (cached != null) {
      _templateImage = cached;
      return;
    }

    try {
      final ref = FirebaseStorage.instance.ref().child('gesture_templates/$key.jpg');
      final data = await ref.getData(5 * 1024 * 1024);
      if (data != null && data.isNotEmpty) {
        _gestureImageCache[key] = data;
        if (mounted && !_disposed) setState(() => _templateImage = data);
      }
    } catch (e) {
      debugPrint("Reference image unavailable for '$key': $e");
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final theme = Theme.of(context);
    final visuals = _ThemeVisuals.fromTheme(theme);
    final isDark = theme.brightness == Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    final double elapsed = (_isRecording && _recordStart != null)
        ? DateTime.now().difference(_recordStart!).inMilliseconds / 1000.0
        : 0.0;
    final double recordProgress = (elapsed / _maxRecording.inSeconds).clamp(0.0, 1.0).toDouble();

    Color borderColor;
    if (_isRecording) {
      borderColor = Colors.redAccent;
    } else if (_isEvaluating) {
      borderColor = theme.colorScheme.primary;
    } else if (_resultColor == Colors.greenAccent) {
      borderColor = Colors.greenAccent;
    } else {
      borderColor = theme.dividerColor.withOpacity(0.6);
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.cardColor.withOpacity(0.4),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text(
          'Tutorial Practice',
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
            top: -20, right: -20,
            child: Opacity(
              opacity: 0.12,
              child: Transform.rotate(
                angle: -0.2,
                child: Icon(visuals.ambientIcon1, size: 220, color: theme.primaryColor),
              ),
            ),
          ),
          Positioned(
            bottom: 40, left: -30,
            child: Opacity(
              opacity: 0.10,
              child: Transform.rotate(
                angle: 0.3,
                child: Icon(visuals.ambientIcon2, size: 240, color: theme.colorScheme.secondary),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      widget.targetPhrase,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Inter',
                      ),
                    ),
                    if (_isCalendar)
                      Text(
                        CalendarSigns.classNames[_calendarTarget],
                        style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 12),

                    if (_templateImage != null)
                      SizedBox(
                        width: screenWidth * 0.60,
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                _templateImage!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                                  child: const Icon(Icons.broken_image, color: Colors.grey, size: 50),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_templateImage != null) const SizedBox(height: 24),

                    SizedBox(
                      width: screenWidth * 0.70, // Slightly wider for phrase capture
                      child: AspectRatio(
                        aspectRatio: 3 / 4, // Taller box ensures upper body and arms are visible
                        child: Stack(
                          alignment: Alignment.center,
                          fit: StackFit.expand,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  width: 4.0,
                                  color: borderColor,
                                ),
                                boxShadow: [
                                  if (_isRecording || _resultColor == Colors.greenAccent)
                                    BoxShadow(
                                      color: borderColor.withOpacity(0.6),
                                      blurRadius: 25,
                                      spreadRadius: 2,
                                    )
                                  else
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    )
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: _isInitialized && _controller != null
                                    ? FittedBox(
                                        fit: BoxFit.cover,
                                        child: SizedBox(
                                          width: _controller!.value.previewSize?.height ?? 1,
                                          height: _controller!.value.previewSize?.width ?? 1,
                                          child: CameraPreview(_controller!),
                                        ),
                                      )
                                    : Center(
                                        child: CircularProgressIndicator(color: theme.primaryColor),
                                      ),
                              ),
                            ),

                            if (_isInitialized && !_isSuccessAchieved)
                              Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: 110,
                                  height: 110,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: borderColor.withOpacity(0.9),
                                      width: _isRecording ? 4.0 : 3.0,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          color: Colors.black45,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (_isRecording) ...[
                                                const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 12),
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                _isRecording 
                                                  ? "Recording" 
                                                  : (_isEvaluating ? "Evaluating..." : "Frame Body"),
                                                style: TextStyle(
                                                  color: _isRecording ? Colors.redAccent : Colors.white,
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
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      _status,
                      style: TextStyle(
                        color: _initFailed 
                            ? Colors.red 
                            : (_isEvaluating ? theme.colorScheme.primary : (_poseVisible ? Colors.green : theme.colorScheme.onSurface)),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),

                    if (_isEvaluating) ...[
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "Analyzing motion...",
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                width: screenWidth * 0.70,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: theme.colorScheme.surface.withOpacity(0.5), width: 1),
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: 0.5, // Indeterminate looking
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    ] else if (_isRecording) ...[
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 20),
                              const SizedBox(width: 6),
                              Text(
                                "Recording... ${elapsed.toStringAsFixed(1)}s",
                                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                width: screenWidth * 0.70,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: theme.colorScheme.surface.withOpacity(0.5), width: 1),
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: recordProgress,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [Colors.redAccent, Colors.red]),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 10)
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    ] else if (_countdown > 0) ...[
                       Text(
                        'Arms down… $_countdown',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.orange),
                      ),
                    ] else ...[
                      if (_isInitialized && !_isSuccessAchieved)
                        SizedBox(
                          height: 64,
                          width: 64,
                          child: FloatingActionButton(
                            heroTag: 'record_button',
                            backgroundColor: theme.primaryColor,
                            foregroundColor: Colors.white,
                            onPressed: _toggleRecording,
                            elevation: 8,
                            child: const Icon(Icons.fiber_manual_record, size: 32),
                          ),
                        ),
                    ],

                    if (_resultTitle.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            decoration: BoxDecoration(
                              color: _resultColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: _resultColor.withOpacity(0.6),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _resultTitle,
                                  style: TextStyle(
                                    color: _resultColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                                if (_resultDetail.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    _resultDetail,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (kDebugMode && _debug.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SelectableText(
                        _debug,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}