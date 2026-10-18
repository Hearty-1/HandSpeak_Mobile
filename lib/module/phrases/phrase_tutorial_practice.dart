import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '/services/handspeak_api_service.dart';
import 'phrase_recognizer.dart';
import 'pose_provider.dart';
import '/services/frame_gate.dart';

import '/services/performance_monitor.dart';
import '/services/progress_service.dart';
import '/services/xp_rewards.dart';

import '/module/civic/civic_tutorial_detail.dart' show CustomVideoPlayer;

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
// MAIN PRACTICE WIDGET
// =============================================================================
/// Practice for phrases (greetings): hand_landmarker + PhraseRecognizer
/// features and POST /v1/predict/greetings. The months (calendar model) were
/// removed: the model does not recognise new signers yet (2026-10-14 phone
/// replay: 5 of 27 correct attempts accepted).
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

  double _minConfidence = PhraseRecognizer.defaultMinConfidence;
  int get xpReward => widget.xpReward ?? (widget.continuous ? XpRewards.phrasePractice : XpRewards.phraseTutorial);
  int _xpGained = 0; // XP actually awarded (0 when the phrase was mastered before)

  // UI text
  String _status = 'Preparing…';
  String _resultTitle = '';
  String _resultDetail = '';
  Color _resultColor = Colors.grey;
  bool _isEvaluating = false;

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
      _setStatus('1/3 Starting hand tracking…');
      _landmarker = _createLandmarker();
      _landmarkSub = _landmarker!.landmarkStream.listen(
        _onHandsDetected,
        onError: (e) => _setStatus('❌ Hand tracking error: $e'),
      );

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
        imageFormatGroup: Platform.isAndroid
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

  final FrameGate _frameGate = FrameGate();

  void _onCameraImage(CameraImage image) {
    if (_disposed || !_isInitialized || _isSuccessAchieved) return;
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
  // Success / XP
  // ---------------------------------------------------------------------------

  Future<void> _awardXp() async {
    // Once per phrase (tutorial and continuous practice counted separately).
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
                              _xpGained > 0 ? "+$_xpGained XP Earned!" : "Daily XP limit reached",
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
      return Image.asset(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
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
        return Image.network(u, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
      },
    );
  }

  Future<String>? _mediaUrlFuture;

  Widget _buildPlaceholder(ThemeData theme) {
    final label = widget.targetPhrase;
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
              color: Colors.white.withOpacity(0.14),
              border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
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
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w600, fontSize: 11),
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
              color: theme.primaryColor.withOpacity(0.12),
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
              style: TextButton.styleFrom(foregroundColor: onSurface.withOpacity(0.7)),
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
                      _xpGained > 0 ? "Success! +$_xpGained XP" : "Success! (daily XP limit reached)",
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 20, fontFamily: 'Inter'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "Loading next phrase...",
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontWeight: FontWeight.w600, fontSize: 14),
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
                                      color: borderColor.withOpacity(0.9),
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
                        );

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
                                color: Colors.black.withOpacity(0.06),
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

                    Text(
                      _status,
                      style: TextStyle(
                        color: _initFailed
                            ? Colors.red
                            : (_resultColor == Colors.greenAccent ? Colors.green : theme.colorScheme.primary),
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
                            child: SmartBlur(
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
                            child: SmartBlur(
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

                    if (widget.continuous && _isSuccessAchieved) ...[
                      const SizedBox(height: 24),
                      _buildContinuousSuccess(theme, visuals),
                    ] else if (_resultTitle.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: SmartBlur(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: screenWidth * 0.80,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: _resultColor == Colors.greenAccent
                                  ? Colors.green.withOpacity(0.2)
                                  : theme.cardColor.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: _resultColor.withOpacity(0.6), width: 1.5),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _resultTitle,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _resultColor == Colors.greenAccent
                                        ? (isDark ? Colors.greenAccent : Colors.green.shade700)
                                        : _resultColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                                if (_resultDetail.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _resultDetail,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface.withOpacity(0.7),
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
