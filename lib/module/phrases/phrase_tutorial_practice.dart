import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;

import '/services/lighting_monitor.dart';
import '/services/handspeak_api_service.dart';
import '/services/holistic_capture.dart';
import 'phrase_recognizer.dart';
import 'pose_provider.dart';
import '/services/frame_gate.dart';

import '/widgets/practice_feedback.dart';
import '/services/performance_monitor.dart';
import '/services/progress_service.dart';
import '/services/xp_rewards.dart';

import '/module/civic/civic_tutorial_detail.dart' show CustomVideoPlayer;
import '/services/role_service.dart';
import '/providers/language_provider.dart';

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

    if ((primary.b * 255).round() > 160 && (primary.r * 255).round() < 120) {
      return const _ThemeVisuals(
        mainBadgeIcon: Icons.water_drop_rounded,
        secondaryIcon: Icons.waves_rounded,
        ambientIcon1: Icons.bubble_chart_rounded,
        ambientIcon2: Icons.sailing_rounded,
      );
    } else if ((primary.g * 255).round() > 160 && (primary.r * 255).round() < 120) {
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
  /// English, with or without numbering / prefixes: "Enero", "january",
  /// "SETYEMBRE", "calendar_marso", "01_January", "enero_01", "Jan"; else -1.
  static int indexFor(String? name) {
    if (name == null) return -1;
    var key = _compact(name).replaceAll(RegExp(r'[0-9]'), ''); // training folders are often numbered
    for (final prefix in ['calendar', 'buwan', 'month']) {
      if (key.startsWith(prefix) && key.length > prefix.length) key = key.substring(prefix.length);
    }
    if (key.isEmpty) return -1;
    for (int i = 0; i < 12; i++) {
      if (_compact(displayLabels[i]) == key || _compact(classNames[i]) == key) return i;
    }
    // Common alternative spellings and 3-letter abbreviations.
    const alt = {
      'septyembre': 8, 'setiyembre': 8, 'septiyembre': 8, 'nobiyembre': 10, 'disiyembre': 11, 'pebrero': 1, 'febrero': 1,
      'jan': 0, 'feb': 1, 'mar': 2, 'apr': 3, 'jun': 5, 'jul': 6, 'aug': 7, 'sep': 8, 'sept': 8, 'oct': 9, 'nov': 10, 'dec': 11,
    };
    return alt[key] ?? -1;
  }

  /// True for the model's "no sign" class (INVALID_GESTURE / Hindi kilalang senyas).
  static bool isInvalidName(String? name) {
    final k = _compact(name ?? '');
    return k.contains('invalid') || k.contains('hindikilala') || k.contains('unknown') || k.contains('nosign');
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

  /// Lesson demo video / image (optional; a placeholder is shown otherwise).
  final String mediaUrl;

  /// Continuous practice (phrase_practice.dart): no "Mastered!" dialog; an
  /// inline success card is shown, then [onMastered] moves to the next phrase.
  final bool continuous;
  final VoidCallback? onMastered;

  /// Continuous practice header, e.g. "Phrase 3 of 21", with a Skip button.
  final String? progressLabel;
  final VoidCallback? onSkip;

  /// XP for the first mastery of this phrase; null = the XP plan
  /// (xp_rewards.dart): tutorial vs continuous practice.
  final int? xpReward;

  const PhraseTutorialPractice({
    super.key,
    required this.targetPhrase,
    this.mediaUrl = '',
    this.continuous = false,
    this.onMastered,
    this.progressLabel,
    this.onSkip,
    this.xpReward,
  });

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

  /// Month signs take ~1-1.5 s: a shorter cap keeps a capture from filling
  /// up with lowered hands (the server rejects > 50 % cut-off frames).
  static const Duration _maxCalendarRecording = Duration(seconds: 6);
  Duration get _recordingLimit => _isCalendar ? _maxCalendarRecording : _maxRecording;

  /// A hand that is fully inside the image (all 21 points within a small
  /// margin of the edges). Lowered hands resting at the bottom edge are
  /// still detected but cut off: they are not signing, and the calendar
  /// server rejects captures with too many cut-off frames (OUT_OF_FRAME).
  static bool _handInFrame(List<List<double>>? hand) {
    if (hand == null || hand.isEmpty) return false;
    const m = 0.02;
    for (final p in hand) {
      if (p.length < 2 || p[0] < m || p[0] > 1 - m || p[1] < m || p[1] > 1 - m) return false;
    }
    return true;
  }

  static bool _signingHands(RawFrame f) => _handInFrame(f.leftHand) || _handInFrame(f.rightHand);

  double _minConfidence = PhraseRecognizer.defaultMinConfidence;
  int get xpReward => widget.xpReward ?? (widget.continuous ? XpRewards.phrasePractice : XpRewards.phraseTutorial);
  int _xpGained = 0; // XP actually awarded (0 when the phrase was mastered before)

  // UI text
  String _status = L.t('Preparing…', 'Inihahanda…');
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
  /// Debug details of the last check (debug builds), printed to the log.
  set _debug(String v) => debugPrint(v);

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
      _setStatus(L.t('Preparing the checker…', 'Inihahanda ang pagsusuri…'));
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
        _fail(L.t('No camera found on this device.', 'Walang camera sa device na ito.'));
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
        _status = L.t('Step back a little so your shoulders and hands are visible,\nthen tap RECORD.', 'Lumayo nang kaunti para makita ang balikat at mga kamay,\nsaka pindutin ang RECORD.');
      });
    } on CameraException catch (e) {
      _fail(L.t("Camera error (${e.code}): ${e.description ?? ''}\nCheck the camera permission.", "Camera error (${e.code}): ${e.description ?? ''}\nTingnan ang pahintulot sa camera."));
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

  final FrameGate _frameGate = FrameGate();

  void _onCameraImage(CameraImage image) {
    LightingMonitor.instance.onImage(image); // low-light warning
    if (_disposed || !_isInitialized || _isSuccessAchieved) return;
    if (_isCalendar) {
      unawaited(_onCalendarImage(image));
      return;
    }
    final c = _controller;
    final landmarker = _landmarker;
    if (c == null || landmarker == null) return;

    final int rotation = _cameraImageRotation(c); // live device rotation
    _recognizer.handRotation = rotation;
    final bool swap = rotation == 90 || rotation == 270;
    _xScale = PhraseRecognizer.aspectXScale(
      swap ? image.height : image.width,
      swap ? image.width : image.height,
    );
    try {
      if (!_frameGate.tryEnter()) return; // one frame in flight (services/frame_gate.dart)
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
    _frameGate.done();
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
      final r = await HolisticCapture.process(image, _cameraImageRotation(c));
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
      // Lowered hands at the bottom edge are still detected but cut off;
      // only hands fully in frame count as signing, so auto-stop works when
      // the hands are lowered (not only when they leave the camera).
      if (_signingHands(f)) {
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
      _status = L.t('Lower your hands and get ready...', 'Ibaba ang mga kamay at pumwesto...');
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
    _maxRecordTimer = Timer(_recordingLimit, _stopAndEvaluate);
    setState(() {
      _countdown = 0;
      _isRecording = true;
      _recordStart = DateTime.now();
      _status = L.t('Do the sign, then lower your hands.', 'Isagawa ang kumpas, saka ibaba ang mga kamay.');
    });
  }

  void _cancelRecording() {
    _maxRecordTimer?.cancel();
    _countdownTimer?.cancel();
    if (_countdown > 0) {
      _countdown = 0;
      if (mounted && !_disposed) {
        setState(() => _status = L.t('Cancelled. Tap RECORD to try again.', 'Kinansela. Pindutin ang RECORD para ulitin.'));
      }
      return;
    }
    if (!_isRecording) return;
    _clearCapture();
    if (mounted && !_disposed) {
      setState(() {
        _isRecording = false;
        _recordStart = null;
        _status = L.t('Cancelled. Tap RECORD to try again.', 'Kinansela. Pindutin ang RECORD para ulitin.');
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

  static final int _haponIndex = PhraseRecognizer.classIndexFor('Magandang Hapon');
  static final int _mabutiIndex = PhraseRecognizer.classIndexFor('Mabuti');
  static final Set<int> _haponMabuti = {_haponIndex, _mabutiIndex};

  /// Highest point of the signing wrist, in shoulder widths below the
  /// shoulder line (smaller = higher). Training clips (GREETINGS zip,
  /// fsl105_palm_norm): Magandang Hapon reaches the face, median 0.01
  /// (p10..p90 -0.24..0.31); Mabuti stays at the chest, median 0.57
  /// (0.47..0.84). The ranges do not overlap; 0.40 sits between them.
  static const double _haponWristTop = 0.40;

  /// [_haponWristTop] measure for a clip of 96-feature frames (pose points
  /// 4 / 5 = left / right wrist at [8, 9] / [10, 11]); the wrist that moves
  /// most is the signing hand. Null without pose data.
  static double? _signingWristTop(List<Float32List> clip) {
    double? best;
    double bestPath = -1;
    for (final xi in const [8, 10]) {
      double path = 0, top = double.infinity;
      double? px, py;
      for (final f in clip) {
        if (f.length < 12 || (f[0] == 0 && f[1] == 0)) continue; // no pose
        final x = f[xi], y = f[xi + 1];
        if (px != null) path += math.sqrt((x - px) * (x - px) + (y - py!) * (y - py));
        px = x;
        py = y;
        if (y < top) top = y;
      }
      if (top.isFinite && path > bestPath) {
        bestPath = path;
        best = top;
      }
    }
    return best;
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
      _status = L.t('Tap RECORD to try again.', 'Pindutin ang RECORD para ulitin.');
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
        title: L.t('No hands detected', 'Walang nakitang kamay'),
        detail: L.t('Start with your hands down, then raise them and sign in front of the camera.', 'Magsimula nang nakababa ang mga kamay, saka itaas at isagawa ang kumpas sa harap ng camera.'),
        color: Colors.red,
      );
      return;
    }
    final clip = frames.sublist(window[0], window[1]);
    final clipPose = hasPose.sublist(window[0], window[1]);

    if (!PhraseRecognizer.fillMissingPose(clip, clipPose)) {
      _showResult(
        title: L.t('Step back a little', 'Lumayo nang kaunti'),
        detail: L.t('Show your shoulders, elbows and hands to the camera.', 'Ipakita ang balikat, siko at mga kamay sa camera.'),
        color: Colors.red,
      );
      return;
    }
    
    if (clip.length < PhraseRecognizer.minRecordedFrames) {
      _showResult(
        title: L.t('A little too fast!', 'Medyo mabilis!'),
        detail: L.t('Sign a little slower so the camera can see the whole sign.', 'Bagalan nang kaunti para makita ng camera ang buong kumpas.'),
        color: Colors.red,
      );
      return;
    }

    setState(() {
      _isEvaluating = true;
      _isRecording = false;
      _recordStart = null;
      _status = L.t('Checking your sign...', 'Sinusuri ang kumpas...');
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
      
      // Magandang Hapon vs Mabuti: the greetings model mixes them up (a real
      // Hapon came back MABUTI 94-100%, 2026-10-23 logs), so between these two
      // the signing hand's height decides (see _haponWristTop).
      var top1Index = eval.top1Index;
      var top1Label = eval.top1Label;
      var verdict = eval.verdict;
      final wristTop = _signingWristTop(clip);
      if (wristTop != null &&
          _haponMabuti.contains(_targetIndex) &&
          _haponMabuti.contains(eval.top1Index) &&
          verdict != PhraseVerdict.rejectedUnknown) {
        top1Index = wristTop <= _haponWristTop ? _haponIndex : _mabutiIndex;
        top1Label = _recognizer.labelFor(top1Index);
        verdict = PhraseVerdict.accepted;
      }
      debugPrint('Greeting pair check: wristTop=${wristTop?.toStringAsFixed(2)} '
          'server=${eval.top1Label} -> $top1Label');

      final bool rightSign = _targetIndex != -1
          ? top1Index == _targetIndex
          : PhraseRecognizer.compactKey(top1Label) == PhraseRecognizer.compactKey(widget.targetPhrase);
      final bool isMatch = rightSign && verdict == PhraseVerdict.accepted;
      final double targetPct = _targetIndex != -1
          ? eval.probPercent(_targetIndex)
          : (rightSign ? eval.top1Prob : 0.0);
      debugPrint('Greeting: top $top1Label ${eval.top1Prob.toStringAsFixed(1)}%, margin ${eval.margin.toStringAsFixed(1)}%');
      debugPrint('Greeting target=${widget.targetPhrase} frames=${clip.length} top3=[${([response.prediction, ...response.topK]..sort((x, y) => y.confidence.compareTo(x.confidence))).take(4).map((p) => '${p.label} ${(p.confidence > 1 ? p.confidence : p.confidence * 100).toStringAsFixed(1)}%').toSet().join(', ')}]');

      if (isMatch) {
        setState(() {
          _resultColor = Colors.greenAccent;
          _resultTitle = L.t('Great job!', 'Mahusay!');
          _resultDetail = L.t('You signed "${widget.targetPhrase}" correctly!', 'Tumpak ang kumpas para sa "${widget.targetPhrase}"!');
          _status = L.t('Great job! Correct sign!', 'Mahusay! Tumpak ang kumpas!');
          _isEvaluating = false;
        });
        _onSuccess();
        return;
      }

      final String title;
      switch (verdict) {
        case PhraseVerdict.rejectedUnknown:
          title = L.t("Let's try again!", 'Subukang muli!');
          break;
        case PhraseVerdict.uncertain:
          title = rightSign ? L.t('Almost there!', 'Malapit na!') : L.t('That looked like "$top1Label"', 'Mukhang "$top1Label" ang naisagawa');
          break;
        default:
          title = L.t('That looked like "$top1Label"', 'Mukhang "$top1Label" ang naisagawa');
      }
      _showResult(
        title: title,
        detail: rightSign
            ? L.t('Sign it once more, a little slower and clearer.', 'Ulitin nang mas mabagal at mas malinaw.')
            : L.t('Watch the example again, then try "${widget.targetPhrase}".', 'Panoorin muli ang halimbawa, saka subukan ang "${widget.targetPhrase}".'),
        color: rightSign ? Colors.orange : Colors.redAccent,
        score: targetPct,
      );
    } catch (e) {
      debugPrint('Cloud Run prediction error: $e');
      _showResult(
        title: L.t('Could not check that one', 'Hindi masuri ang kumpas'),
        detail: L.t('Check your internet connection, then try again.', 'Tingnan ang koneksyon sa internet, saka subukang muli.'),
        color: Colors.redAccent,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Calendar evaluation via POST /v1/predict_raw/calendar
  // ---------------------------------------------------------------------------

  String _monthName(Prediction? p) {
    if (p == null) return '';
    final i = _monthIndexOf(p);
    return i >= 0 ? CalendarSigns.displayLabels[i] : p.label;
  }

  /// Server prediction -> month 0..11, or -1 (invalid / unknown).
  /// Names first (label = Filipino display label, label_en = class name):
  /// a retrained model may order its classes differently (e.g. alphabetical
  /// folders), so the class index is only trusted when no name is given.
  int _monthIndexOf(Prediction p) {
    final names = [p.label, p.labelEn, p.code].whereType<String>().where((n) => n.trim().isNotEmpty).toList();
    if (names.any(CalendarSigns.isInvalidName)) return -1;
    for (final n in names) {
      final i = CalendarSigns.indexFor(n);
      if (i != -1) return i;
    }
    if (names.isNotEmpty) return -1; // a name we do not know: never guess by index
    if (p.index == CalendarSigns.invalidIndex) return -1;
    return (p.index >= 0 && p.index < 12) ? p.index : -1;
  }

  /// Gate codes from /v1/predict_raw/calendar -> Tagalog guidance. Takes
  /// precedence over HolisticCapture.rejectAdvice for these codes.
  static Map<String, String> get _calendarAdvice => {
    'FRAGMENT_DURATION': L.t('The sign was too short for this phrase. Do all of it, without rushing.', 'Kulang pa ang haba ng kumpas para sa senyas na ito. Isagawa nang buo at huwag magmadali.'),
    'NO_HANDS': L.t('No hands detected. Show your body and hands to the camera.', 'Walang nakitang kamay. Ipakita ang katawan at mga kamay sa camera.'),
    'TOO_SHORT': L.t('The sign was too short. Do the whole movement.', 'Masyadong maikli ang kumpas. Isagawa ang buong galaw.'),
    'LOW_CONFIDENCE': L.t('Not sure yet. Sign it more clearly and completely.', 'Hindi pa tiyak ang kumpas. Gawin nang mas malinaw at buo.'),
    'SMALL_MARGIN': L.t('Not sure yet. Sign it more clearly and completely.', 'Hindi pa tiyak ang kumpas. Gawin nang mas malinaw at buo.'),
  };

  static String? _adviceFor(String code) => _calendarAdvice[code] ?? HolisticCapture.rejectAdvice[code];

  /// Released calendar models (source_checkpoint; responses report
  /// `<feature_version>/<checkpoint>`). v1 = palm_calendar_best.pt is the model
  /// the training team recommends for production (calendar kit REPORT.md,
  /// 2026-10-13: 64 % of live attempts accepted vs 30 % for v2).
  /// Practice check (see _evaluateCalendar): failed server checks that only
  /// mean "not sure" (INVALID included: for signers v2 never saw, it puts
  /// "not a sign" first and the right month second), and how clearly the
  /// target must lead the other MONTHS. Measured by replaying the server code
  /// + v2 on 145 labelled captures (3 phone, 142 calendar-kit live takes):
  /// 0 / 1,595 wrong-month passes; the phone's January and November pass.
  static const Set<String> _unsureChecks = {
    'LOW_CONFIDENCE', 'SMALL_MARGIN', 'HIGH_ENTROPY', 'UNSTABLE', 'INVALID_CLASS',
  };
  static const double _practiceMinConf = 0.30;
  static const double _practiceMinLead = 0.25; // over the next month

  /// Server checks that fail on long still holds around the sign.
  static const Set<String> _retrimChecks = {'PHASE_IMBALANCE', 'LOW_MOTION', 'FRAGMENT_DURATION'};

  /// Frames from 3 before the first to 3 after the last frame in which a hand
  /// moved (mean |dx|, |dy| of its 21 points > 0.008 of the image), so
  /// handshape changes with a still wrist count as motion too.
  static List<RawFrame> _trimToHandMotion(List<RawFrame> frames) {
    const thr = 0.008, pad = 3;
    double motion(RawFrame a, RawFrame b) {
      var best = 0.0;
      for (final pair in [(a.leftHand, b.leftHand), (a.rightHand, b.rightHand)]) {
        final x = pair.$1, y = pair.$2;
        if (x == null || y == null || x.length != y.length) continue;
        var sum = 0.0;
        for (var i = 0; i < x.length; i++) {
          sum += (x[i][0] - y[i][0]).abs() + (x[i][1] - y[i][1]).abs();
        }
        best = math.max(best, sum / (2 * x.length));
      }
      return best;
    }

    var first = -1, last = -1;
    for (var i = 1; i < frames.length; i++) {
      if (motion(frames[i - 1], frames[i]) > thr) {
        if (first == -1) first = i;
        last = i;
      }
    }
    if (first == -1 || first == last) return frames;
    return frames.sublist(math.max(first - pad, 0), math.min(last + pad, frames.length - 1) + 1);
  }

  static const Map<String, String> _calendarModels = {
    'palm_calendar_best.pt': 'v1',
    'palm_calendar_v2_ens3': 'v2',
  };

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
        title: L.t('No hands detected', 'Walang nakitang kamay'),
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
    // Calendar v2 client spec (calendar kit README, section 1): trim ONLY the
    // frames with no hand at all at the start / end; the server does its own
    // trim_still. (Auto-stop above already ends the capture shortly after the
    // hands leave full view, so lowered hands do not fill the capture.)
    final firstHand = frames.indexWhere((f) => f.hasHands);
    final lastHand = frames.lastIndexWhere((f) => f.hasHands);
    frames = frames.sublist(firstHand, lastHand + 1);

    setState(() {
      _isEvaluating = true;
      _recordStart = null;
      _status = L.t('Checking your sign...', 'Sinusuri ang kumpas...');
    });

    final target = _calendarTarget;
    final targetLabel = CalendarSigns.displayLabels[target];
    final t0 = frames.first.timeMs;
    final secs = (frames.last.timeMs - t0) / 1000.0;
    try {
      // One request per attempt, like Lupang Hinirang: the v2 gate already
      // checks stability on slightly shifted views, and shorter sub-windows
      // were always rejected (they lose the start / end of the sign).
      // Upright landmarks + hands assigned to the pose wrists (CaptureFixer).
      Future<RawPredictResponse> send(List<RawFrame> fs) {
        final s0 = fs.first.timeMs;
        final fixed = CaptureFixer.fix([for (final f in fs) f.toJson(s0)], _imageWidth, _imageHeight,
            reassignHands: !HolisticResult.isHolisticEngine(_engine));
        return HandSpeakApiService().predictRaw(
          modelId: HandSpeakModels.calendar,
          frames: fixed.frames,
          imageWidth: fixed.imageWidth,
          imageHeight: fixed.imageHeight,
          topK: 5, // the practice check compares the target with the next month
        );
      }

      var result = await send(frames);
      // A capture rejected for its timing (long still holds before / after
      // the sign: PHASE_IMBALANCE, ...) is sent once more, cut to the part
      // where the hands move. Replayed on 24 phone attempts + 142 kit takes
      // with the server code (2026-10-14): one more phone attempt passes
      // (January, 4.6 s capture -> 60 % January), no kit take is lost and no
      // wrong month passes. Trimming every capture instead lost 2 kit takes.
      if (result.failed.any(_retrimChecks.contains)) {
        final moving = _trimToHandMotion(frames);
        if (moving.length != frames.length && moving.length >= 8) {
          debugPrint('Calendar retry: ${result.failed} -> ${frames.length} -> ${moving.length} frames');
          result = await send(moving);
        }
      }
      if (!mounted || _disposed) return;
      final modelName = _calendarModels[result.modelVersion.split('/').last] ?? 'UNKNOWN MODEL';
      debugPrint('Calendar response: ${result.raw}');
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
            'response': result.raw,
          }));
        } catch (e) {
          debugPrint('Calendar dump failed: $e');
        }
      }

      final top = result.prediction;
      final topIdx = top == null ? -1 : _monthIndexOf(top);
      final accepted = result.accepted;

      // Practice check. The server gate is built for open recognition (any of
      // 12 months, unknown signers) and abstains on most correct signs from
      // signers it never saw (calendar v2 report: ~9 % accepted). In a lesson
      // the target month is known, so the question is only "is this that
      // month?": pass when the ONLY failed checks are the "not sure" ones and
      // the model's own top guess is the target with a clear lead. A
      // different top month, INVALID, too short, too little motion, no hands
      // or hands out of frame still fail exactly as before.
      double pct(Prediction p) => p.confidence > 1.0 ? p.confidence / 100.0 : p.confidence;
      // The model's best MONTH (INVALID left out) and the next month.
      final monthGuesses = [for (final p in result.topK) if (_monthIndexOf(p) != -1) p];
      final best = monthGuesses.isNotEmpty ? monthGuesses.first : top;
      final bestIdx = best == null ? -1 : _monthIndexOf(best);
      final bestConf = best == null ? 0.0 : pct(best);
      final nextMonth = monthGuesses.length > 1 ? pct(monthGuesses[1]) : 0.0;
      final practicePass = !accepted &&
          bestIdx == target &&
          result.failed.isNotEmpty &&
          result.failed.every(_unsureChecks.contains) &&
          bestConf >= _practiceMinConf &&
          bestConf - nextMonth >= _practiceMinLead;

      if (kDebugMode) {
        final checks = result.raw['checks'];
        final lines = checks is List
            ? [
                for (final c in checks)
                  if (c is Map) "${c['passed'] == true ? '✓' : '✗'} ${c['label']}: ${c['text']}"
              ].join('\n')
            : '';
        _debug = 'calendar $modelName (${result.modelVersion.isEmpty ? '?' : result.modelVersion})\n'
            'target #$target $targetLabel | top=#$topIdx (${top?.label}${top?.labelEn != null ? '/${top!.labelEn}' : ''} idx ${top?.index} '
            '${top?.confidence.toStringAsFixed(2)}) | failed=${result.failed}\n'
            'capture: ${frames.length} frames / ${secs.toStringAsFixed(1)} s = '
            '${(frames.length / (secs > 0 ? secs : 1)).toStringAsFixed(1)} fps | '
            '${_engine.isEmpty ? 'OLD NATIVE BUILD - run "flutter run" again' : _engine}\n'
            'top3: ${result.topK.take(3).map((p) => '${_monthName(p)} ${(p.confidence > 1 ? p.confidence : p.confidence * 100).toStringAsFixed(0)}%').join(', ')}\n'
            '$lines';
      }

      if ((accepted && topIdx == target) || practicePass) {
        setState(() {
          _resultColor = Colors.greenAccent;
          _resultTitle = L.t('Great job!', 'Mahusay!');
          _resultDetail = L.t('Correct sign!', 'Tumpak ang kumpas!');
          _status = L.t('Great job! Correct sign!', 'Mahusay! Tumpak ang kumpas!');
          _isEvaluating = false;
        });
        _onSuccess();
        return;
      }
      if (accepted && topIdx != -1) {
        _showResult(
          title: L.t('That looked like ${_monthName(top)}', 'Mukhang ${_monthName(top)} ang naisagawa'),
          detail: L.t('Try $targetLabel again. Follow the example.', 'Subukang muli ang $targetLabel. Sundan ang halimbawa.'),
          color: Colors.redAccent,
        );
        return;
      }
      final code = result.failed.firstWhere((c) => _adviceFor(c) != null,
          orElse: () => result.failed.isNotEmpty ? result.failed.first : '');
      final advice = _adviceFor(code) ??
          (result.message?.trim().isNotEmpty == true
              ? L.t('Not accepted: ${result.message}', 'Hindi tinanggap: ${result.message}')
              : L.t('The sign was not recognized. Try again more clearly.', 'Hindi makilala ang kumpas. Ulitin nang mas malinaw.'));
      // A rejected answer has no prediction: use the model's top guess.
      final close = bestIdx != -1 && !const {'NO_HANDS', 'TOO_SHORT', 'LOW_MOTION'}.contains(code);
      _showResult(
        title: close && bestIdx == target
            ? L.t('Almost! Make it clearer', 'Malapit na! Gawin nang mas malinaw')
            : (close ? L.t('Unclear — looks like ${_monthName(best)}', 'Hindi malinaw — mukhang ${_monthName(best)}') : L.t('Sign not recognized', 'Hindi makilala ang kumpas')),
        detail: advice,
        color: close && topIdx == target ? Colors.orange : Colors.redAccent,
      );
    } on ArgumentError catch (e) {
      // Rejected by the API client before upload (e.g. no pose in most frames).
      debugPrint('Calendar capture rejected client-side: ${e.message}');
      _showResult(
        title: L.t('Body not detected', 'Hindi makita ang katawan'),
        detail: '${e.message}'.contains('Pose')
            ? L.t('Your body is not visible. Show your shoulders, body and hands to the camera.', 'Hindi makita ang katawan. Ipakita ang balikat, katawan at mga kamay sa camera.')
            : L.t('Could not send your sign. Try again.', 'Hindi maipadala ang kumpas. Subukang muli.'),
        color: Colors.redAccent,
      );
    } catch (e) {
      debugPrint('Calendar prediction error: $e');
      final text = e.toString();
      _showResult(
        title: L.t('Could not check that one', 'Hindi masuri ang kumpas'),
        // 404 only if the deployed server has no calendar route (it does since
        // revision handspeak-inference-00012); every other failure is shown as-is.
        detail: text.contains('[404]')
            ? L.t('The calendar model was not found on the server (/v1/predict_raw/calendar). Update the app or try again later.', 'Hindi mahanap sa server ang calendar model (/v1/predict_raw/calendar). I-update ang app o subukang muli mamaya.')
            : text.replaceAll('Exception: ', ''),
        color: Colors.redAccent,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Success / XP
  // ---------------------------------------------------------------------------

  Future<void> _awardXp() async {
    // Once per phrase (tutorial and continuous practice counted separately).
    // Faculty / Parent (guest): 0 XP; the mastery is kept on the device.
    _xpGained = await ProgressService().awardFirstMastery(
      moduleKey: widget.continuous ? XpRewards.practiceKey('phrases') : 'phrases',
      itemKey: ProgressService.masteryKey(widget.targetPhrase),
      xp: xpReward,
      xpField: 'phraseXp',
      countsAsLesson: !widget.continuous,
    );
  }

  Future<void> _onSuccess() async {
    if (_isSuccessAchieved) return;
    _isSuccessAchieved = true;

    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.heavyImpact();

    await _awardXp();
    if (!mounted) return;

    if (widget.continuous) {
      // Inline success card (see build), then the next phrase.
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) widget.onMastered?.call();
      return;
    }

    final theme = Theme.of(context);
    final visuals = _ThemeVisuals.fromTheme(theme);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SmartBlur(
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
                border: Border.all(color: theme.primaryColor.withValues(alpha: 0.6), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.35),
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
                          color: theme.primaryColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(visuals.mainBadgeIcon, color: theme.primaryColor, size: 64),
                      ),
                      Positioned(
                        right: 0, top: 0,
                        child: Icon(visuals.secondaryIcon, color: theme.primaryColor.withValues(alpha: 0.7), size: 22),
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
                        ? "You signed \"${widget.targetPhrase}\" correctly. Keep practising!"
                        : "Outstanding job! You have successfully mastered the phrase \"${widget.targetPhrase}\"!",
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
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
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.4), width: 2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(!context.rolesRead.isStudent ? Icons.check_circle_rounded : visuals.secondaryIcon, color: Colors.green, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              _xpGained > 0 ? "+$_xpGained XP Earned!" : (context.rolesRead.isStudent ? "Daily XP limit reached" : "Correct sign!"),
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
                      shadowColor: theme.primaryColor.withValues(alpha: 0.5),
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

  /// Lesson demo video, else its image, else the gesture template, else a
  /// video-style placeholder.
  Widget _buildReference(ThemeData theme) {
    final url = widget.mediaUrl.trim();
    final path = url.split('?').first.toLowerCase();
    if (url.isNotEmpty && const ['.mp4', '.mov', '.webm', '.m4v', '.3gp', '.mkv'].any(path.endsWith)) {
      return ColoredBox(color: Colors.black, child: Center(child: CustomVideoPlayer(videoUrl: url)));
    }
    final fallback = _templateImage != null
        ? Image.memory(_templateImage!, fit: BoxFit.cover)
        : _buildPlaceholder(theme);
    if (url.startsWith('assets/')) {
      return Image.asset(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
    }
    if (url.isEmpty) return fallback;
    return FutureBuilder<String>(
      future: _mediaUrlFuture ??= url.startsWith('http')
          ? Future.value(url)
          : FirebaseStorage.instance.ref(url).getDownloadURL().catchError((_) => ''),
      builder: (context, snap) {
        final u = snap.data;
        if (u == null) return Center(child: CircularProgressIndicator(color: theme.primaryColor));
        if (u.isEmpty) return fallback;
        return Image.network(u, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
      },
    );
  }

  Future<String>? _mediaUrlFuture;

  Widget _buildPlaceholder(ThemeData theme) {
    final label = _isCalendar ? CalendarSigns.displayLabels[_calendarTarget] : widget.targetPhrase;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(theme.primaryColor, Colors.black, 0.55)!, const Color(0xFF15151F)],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(
            'Demo video coming soon',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600, fontSize: 11),
          ),
        ],
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // Continuous practice (phrase_practice.dart)
  // ---------------------------------------------------------------------------

  Widget _buildProgressHeader(ThemeData theme) {
    final onSurface = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.progressLabel!,
              style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          if (widget.onSkip != null) ...[
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: (_isRecording || _isEvaluating || _isSuccessAchieved || _countdown > 0) ? null : widget.onSkip,
              icon: const Icon(Icons.skip_next_rounded, size: 18),
              label: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(foregroundColor: onSurface.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }

  /// Same success card as the alphabet / numbers continuous practice.
  Widget _buildContinuousSuccess(ThemeData theme, _ThemeVisuals visuals) {
    return ClipRRect(
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
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(visuals.mainBadgeIcon, color: Colors.green, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      !context.rolesRead.isStudent ? L.t('Great job! Correct sign', 'Mahusay! Tumpak ang kumpas') : (_xpGained > 0 ? L.t('Great job! +$_xpGained XP', 'Mahusay! +$_xpGained XP') : L.t('Great job! (daily XP limit reached)', 'Mahusay! (naabot na ang XP ngayong araw)')),
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 20, fontFamily: 'Inter'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  L.t('Next phrase...', 'Susunod na parirala...'),
                  style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool landscape = _isLandscape(context);
    // Landscape: the tutorial pane is ~45% of the screen, camera on the right.
    final double screenWidth = MediaQuery.of(context).size.width * (landscape ? 0.45 : 1.0);
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
    final double recordProgress = (elapsed / _recordingLimit.inSeconds).clamp(0.0, 1.0).toDouble();

    Color borderColor;
    // Same frame colours as the numbers practice: green = correct, soft grey
    // otherwise; while recording / checking the theme colour (no alarming red).
    if (_isRecording) {
      borderColor = theme.colorScheme.primary;
    } else if (_isEvaluating) {
      borderColor = theme.colorScheme.primary;
    } else if (_resultColor == Colors.greenAccent) {
      borderColor = Colors.greenAccent;
    } else {
      borderColor = theme.dividerColor.withValues(alpha: 0.6);
    }

    // Camera box (with its overlays): inline in portrait, right pane in landscape.
    final Widget cameraPane = Stack(
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
                                      color: borderColor.withValues(alpha: 0.6),
                                      blurRadius: 25,
                                      spreadRadius: 2,
                                    )
                                  else
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    )
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: _isInitialized && _controller != null
                                    ? _CameraView(controller: _controller!)
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
                                      color: borderColor.withValues(alpha: 0.9),
                                      width: _isRecording ? 4.0 : 3.0,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SmartBlur(
                                        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          color: Colors.black45,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (_isRecording) ...[
                                                Icon(Icons.fiber_manual_record, color: theme.colorScheme.primary, size: 12),
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                _isRecording 
                                                  ? "Recording" 
                                                  : (_isEvaluating ? "Evaluating..." : "Frame Body"),
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
                                ),
                              ),
                          ],
                        );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.cardColor.withValues(alpha: 0.4),
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
          widget.continuous ? 'Continuous Practice' : 'Tutorial Practice',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (widget.progressLabel != null) _buildProgressHeader(theme),
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
                        style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: screenWidth * 0.60,
                      child: AspectRatio(
                        aspectRatio: 1 / 1,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: _buildReference(theme),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (!landscape)
                      SizedBox(
                        width: screenWidth * 0.60,
                        child: AspectRatio(aspectRatio: 1 / 1, child: cameraPane),
                      ),
                    const SizedBox(height: 16),


                    if (!(widget.continuous && _isSuccessAchieved))
                      _RecordControls(
                        heroTag: 'record_button',
                        countdown: _countdown,
                        isRecording: _isRecording,
                        isEvaluating: _isEvaluating,
                        elapsed: elapsed,
                        recordProgress: recordProgress,
                        bodyVisible: _poseVisible,
                        showButton: _isInitialized && !_isSuccessAchieved,
                        onRecord: _toggleRecording,
                        width: screenWidth * 0.70,
                      ),

                    if (widget.continuous && _isSuccessAchieved) ...[
                      const SizedBox(height: 24),
                      _buildContinuousSuccess(theme, visuals),
                    ] else ...[
                      // One feedback card under the controls, as in the civic
                      // practice: the verdict after an attempt, else the
                      // instruction / status.
                      const SizedBox(height: 16),
                      if (_resultTitle.isNotEmpty && !_initFailed && !_isRecording && !_isEvaluating)
                        PracticeFeedback(
                          title: _resultTitle,
                          message: _resultDetail,
                          tone: PracticeFeedback.toneForColor(_resultColor),
                        )
                      else
                        PracticeFeedback(
                          message: _status,
                          tone: _initFailed ? FeedbackTone.problem : FeedbackTone.info,
                        ),
                    ],
                  ],
                ),
              ),
            ),
                ),
                if (landscape)
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 16, 16),
                      child: cameraPane,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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
        L.t('Lower your hands… $countdown', 'Ibaba ang mga kamay… $countdown'),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFFF08C00)),
      );
    } else if (isRecording) {
      status = bar(L.t('Recording... ${elapsed.toStringAsFixed(1)}s', 'Nagre-record... ${elapsed.toStringAsFixed(1)}s'), recordProgress.clamp(0.0, 1.0));
    } else if (isEvaluating) {
      status = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(L.t('Checking your sign...', 'Sinusuri ang kumpas...'), style: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 14)),
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
              bodyVisible ? L.t('Body in view. Tap RECORD', 'Nakikita ang katawan. Pindutin ang RECORD') : L.t('Step back a little so your shoulders and hands are visible', 'Lumayo nang kaunti para makita ang balikat at mga kamay'),
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
