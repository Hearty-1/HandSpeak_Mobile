import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '/services/handspeak_api_service.dart';
import 'phrase_recognizer.dart';
import 'pose_provider.dart';

/// Practice screen: camera -> MediaPipe hands (+ ML Kit pose) -> frame extraction
/// -> Cloud Run inference API. The user taps RECORD, signs the whole phrase,
/// taps STOP; the clip is resampled and sent to the cloud model for evaluation.
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
  final PhraseRecognizer _recognizer = PhraseRecognizer(); // Used for feature extraction only
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
  int _countdown = 0; // > 0 while counting down before capture starts
  final List<Float32List> _frames = [];
  final List<bool> _frameHasHands = [];
  final List<bool> _frameHasPose = [];
  final List<int> _frameTimesMs = [];
  bool _sawHands = false;
  int _lastHandMs = 0;
  int _lastUiMs = 0;
  double _xScale = 1.0;

  /// Stop automatically once the hands have been lowered for this long.
  static const int _autoStopAfterMs = 900;

  /// On a manual STOP, drop the last part of the clip (the reach to the
  /// screen), which never appears in the training recordings.
  static const int _manualStopTrimMs = 600;

  /// Model class of the phrase being practised (-1 if not a model class).
  late final int _targetIndex =
      PhraseRecognizer.classIndexFor(widget.targetPhrase);
  static const Duration _maxRecording = Duration(seconds: 12);

  // Config (Firestore may override the confidence gate)
  double _minConfidence = PhraseRecognizer.defaultMinConfidence;
  final int xpReward = 25;

  // UI text
  String _status = 'Preparing…';
  String _resultTitle = '';
  String _resultDetail = '';
  Color _resultColor = Colors.grey;
  double _currentScore = 0.0;

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

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
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
      // 1) Hand landmarker ----------------------------------------------------
      _setStatus('1/3 Starting hand tracking…');
      _landmarker = _createLandmarker();
      _landmarkSub = _landmarker!.landmarkStream.listen(
        _onHandsDetected,
        onError: (e) => _setStatus('❌ Hand tracking error: $e'),
      );

      // 2) Camera -------------------------------------------------------------
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
      // The model was trained on the raw (un-flipped) webcam frame. The image
      // stream is un-flipped too (only the preview is mirrored), so never
      // mirror the landmarks -- even for the front camera.
      _recognizer.mirrorX = false;
      _pose.mirrorX = false;
      // hand_landmarker reports landmarks in the raw sensor frame; ML Kit
      // pose is upright. Rotate the hands into the upright frame.
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

      // 3) Stream -------------------------------------------------------------
      stage = 'camera stream';
      _setStatus('3/3 Starting stream…');
      _isInitialized = true;
      await _startImageStream();

      if (!mounted || _disposed) return;
      setState(() {
        _status = 'Ready. Stand back so your upper body is visible, then tap RECORD.';
      });
    } on CameraException catch (e) {
      _fail('Camera error (${e.code}): ${e.description ?? ''}\n'
          'Check the camera permission.');
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
    final c = _controller;
    final landmarker = _landmarker;
    if (c == null || landmarker == null) return;

    final int rotation = c.description.sensorOrientation;
    // Features are built in the upright frame; correct x so they use the
    // same aspect ratio as the 640x480 training frames.
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

    // Always extract (also outside recording) so the rotation check and the
    // hand/pose indicators stay live.
    final features = _recognizer.extractFrameFeatures(
      hands,
      pose: _pose.latest(),
      xScale: _xScale,
    );
    final bool visible = _recognizer.lastFrameHadHands;
    final bool poseVisible = _recognizer.lastFrameHadPose;
    final bool visibilityChanged =
        visible != _handsVisible || poseVisible != _poseVisible;
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
      // Hands lowered after signing -> finish, like the end of a training clip.
      unawaited(_stopAndEvaluate());
      return;
    }

    if (visibilityChanged || nowMs - _lastUiMs > 80) {
      _lastUiMs = nowMs;
      setState(() {});
    }
  }

  void _toggleRecording() {
    if (!_isInitialized || _isSuccessAchieved) return;
    if (_countdown > 0) {
      _cancelRecording();
    } else if (_isRecording) {
      _stopAndEvaluate(manual: true);
    } else {
      _startCountdown();
    }
  }

  /// Gives the user time to put their arms down at their sides: every
  /// training clip starts from that rest position, not from tapping a phone.
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

  /// Turns the server response into an 11-class probability vector (classes
  /// the server didn't return are 0). Labels are resolved by name first,
  /// because a missing `index` field is parsed as 0.
  List<double> _probsFromResponse(PredictResponse response) {
    final probs = List<double>.filled(PhraseRecognizer.numClasses, 0.0);
    final entries = [response.prediction, ...response.topK];

    double scale = 1.0;
    if (entries.any((p) => p.confidence > 1.0)) scale = 0.01; // percent

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
      // Ask for the full distribution so the class-8 mask and the margin
      // check can be applied exactly like live_stable_engine.py.
      return await api.predict(
        modelId: HandSpeakModels.greetings,
        features: features,
        topK: PhraseRecognizer.numClasses,
      );
    } on Exception catch (e) {
      // Server may cap top_k; retry with its default before giving up.
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
      _recordStart = null;
      _currentScore = score;
      _resultTitle = title;
      _resultDetail = detail;
      _resultColor = color;
      _status = 'Tap RECORD to try again.';
    });
  }

  Future<void> _stopAndEvaluate({bool manual = false}) async {
    if (!_isRecording || _disposed) return;
    _isRecording = false; // stop collecting immediately (no re-entry)
    _maxRecordTimer?.cancel();

    final frames = List<Float32List>.of(_frames);
    final hasHands = List<bool>.of(_frameHasHands);
    final hasPose = List<bool>.of(_frameHasPose);
    final times = List<int>.of(_frameTimesMs);
    _clearCapture();

    if (!mounted) return;

    // A manual STOP means the last moment is the reach to the screen.
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

    // Training clips always have a pose; fill frames ML Kit missed.
    if (!PhraseRecognizer.fillMissingPose(clip, clipPose)) {
      _showResult(
        title: 'Body not detected',
        detail: 'Step back so your shoulders, elbows and hands are visible.',
        color: Colors.red,
      );
      return;
    }
    final posePct = 100 * clipPose.where((v) => v).length / clip.length;
    debugPrint('Phrase clip: ${frames.length} recorded, window $window, '
        'pose in ${posePct.toStringAsFixed(0)}% of frames, '
        'hand rotation ${_recognizer.effectiveHandRotation}');
    if (clip.length < PhraseRecognizer.minRecordedFrames) {
      _showResult(
        title: 'Too fast',
        detail: 'Only ${clip.length} frames captured '
            '(need ${PhraseRecognizer.minRecordedFrames}+). Sign slightly slower.',
        color: Colors.red,
      );
      return;
    }

    setState(() {
      _isRecording = false;
      _recordStart = null;
      _status = 'Evaluating gesture via Cloud Run…';
    });

    // Same preprocessing as training: linear resample to 32 x 96, flatten.
    final Float32List seq = _recognizer.prepareStandardSequence(
        clip, PhraseRecognizer.sequenceLength);
    final List<double> featureVector = seq.toList();
    // Distance to the mean training sequences (lower = closer to training).
    debugPrint('Phrase templates: '
        '${PhraseRecognizer.templateReport(seq, _targetIndex)}');

    try {
      final response = await _predictCloud(featureVector);
      if (!mounted || _disposed) return;

      final eval = _recognizer.classifyProbabilities(
        _probsFromResponse(response),
        minConfidence: _minConfidence,
      );
      debugPrint('Phrase eval: target=$_targetIndex top1=${eval.top1Index} '
          '(${eval.top1Prob.toStringAsFixed(1)}%) top2=${eval.top2Index} '
          'margin=${eval.margin.toStringAsFixed(1)} frames=${clip.length}');

      final bool rightSign = _targetIndex != -1
          ? eval.top1Index == _targetIndex
          : PhraseRecognizer.compactKey(eval.top1Label) ==
              PhraseRecognizer.compactKey(widget.targetPhrase);
      final bool isMatch =
          rightSign && eval.verdict == PhraseVerdict.accepted;
      final double targetPct = _targetIndex != -1
          ? eval.probPercent(_targetIndex)
          : (rightSign ? eval.top1Prob : 0.0);
      final String stats = 'Confidence: ${eval.top1Prob.toStringAsFixed(1)}% '
          '(min ${_minConfidence.toStringAsFixed(0)}%) • '
          'Margin: ${eval.margin.toStringAsFixed(1)}% '
          '(min ${PhraseRecognizer.minMargin.toStringAsFixed(0)}%)';

      if (isMatch) {
        setState(() {
          _currentScore = targetPct;
          _resultColor = Colors.green;
          _resultTitle = 'Match!';
          _resultDetail = stats;
          _status = 'Great job!';
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
              ? 'Almost! Not confident enough'
              : 'Unclear — looks like ${eval.top1Label}';
          break;
        default:
          title = 'Predicted: ${eval.top1Label}';
      }
      _showResult(
        title: title,
        detail: stats,
        color: rightSign ? Colors.orange : Colors.red,
        score: targetPct,
      );
    } catch (e) {
      debugPrint('Cloud Run prediction error: $e');
      _showResult(
        title: 'Evaluation Failed',
        detail: e.toString().replaceAll('Exception: ', ''),
        color: Colors.red,
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
    await _awardXp();
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Success!', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Text(
          'Outstanding job! You matched the standard for "${widget.targetPhrase}"!',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
            },
            child: const Text('Return to Curriculum'),
          ),
        ],
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
      final ref =
          FirebaseStorage.instance.ref().child('gesture_templates/$key.jpg');
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
    final c = _controller;
    final bool cameraReady =
        _isInitialized && c != null && c.value.isInitialized && c.value.previewSize != null;

    final double elapsed = (_isRecording && _recordStart != null)
        ? DateTime.now().difference(_recordStart!).inMilliseconds / 1000.0
        : 0.0;
    final double progress =
        (elapsed / _maxRecording.inSeconds).clamp(0.0, 1.0).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Practice Mode')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Target: ${widget.targetPhrase}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (_templateImage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_templateImage!, height: 140, fit: BoxFit.contain),
                  ),
                ),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(color: _initFailed ? Colors.red : Colors.blueGrey),
              ),
              const SizedBox(height: 12),
              if (cameraReady)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _isRecording
                            ? Colors.redAccent
                            : (_handsVisible ? Colors.green : Colors.blueAccent),
                        width: 4,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    height: 340,
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: c.value.previewSize!.height,
                        height: c.value.previewSize!.width,
                        child: CameraPreview(c),
                      ),
                    ),
                  ),
                )
              else if (!_initFailed)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                ),
              const SizedBox(height: 12),
              if (_countdown > 0)
                Text(
                  'Arms down… $_countdown',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                )
              else if (_isRecording) ...[
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 6),
                Text('${_frames.length} frames • ${elapsed.toStringAsFixed(1)}s'),
              ] else
                Text(
                  !_poseVisible
                      ? 'Step back so your upper body is visible'
                      : 'Body detected ✓  Tap RECORD, then sign after the countdown',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _poseVisible ? Colors.green : Colors.orange),
                ),
              const SizedBox(height: 16),
              if (cameraReady)
                SizedBox(
                  height: 64,
                  width: 64,
                  child: FloatingActionButton(
                    heroTag: 'record_button',
                    backgroundColor:
                        (_isRecording || _countdown > 0) ? Colors.red : Colors.white,
                    foregroundColor:
                        (_isRecording || _countdown > 0) ? Colors.white : Colors.black,
                    onPressed: _isSuccessAchieved ? null : _toggleRecording,
                    child: Icon(
                      _countdown > 0
                          ? Icons.close
                          : (_isRecording ? Icons.stop : Icons.fiber_manual_record),
                      size: 32,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (_resultTitle.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _resultColor.withOpacity(0.08),
                    border: Border.all(color: _resultColor.withOpacity(0.6)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _resultTitle,
                        style: TextStyle(
                          color: _resultColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_resultDetail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(_resultDetail, style: const TextStyle(fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Target score: ${_currentScore.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}