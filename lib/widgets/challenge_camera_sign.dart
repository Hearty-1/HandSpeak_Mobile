import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '/providers/language_provider.dart';
import '/services/dynamic_sign_judge.dart';
import '/services/frame_gate.dart';
import '/services/lighting_monitor.dart';
import '/widgets/sign_recording.dart';

/// Result of one camera answer in a challenge.
class ChallengeSignResult {
  final bool correct;
  final double score; // 0..100
  final bool isDynamic;
  final String model; // gesture_attempts modelVersion
  final String? predicted;
  final double? confidence;
  final int? frames;

  /// No model can check this sign yet: the question is skipped (no score,
  /// no heart lost), not answered wrong.
  final bool skipped;

  const ChallengeSignResult({
    this.skipped = false,
    required this.correct,
    required this.score,
    required this.isDynamic,
    required this.model,
    this.predicted,
    this.confidence,
    this.frames,
  });
}

/// Camera question of the solo / group challenges, the same as the Hard
/// camera activities (easyAct_mc.dart / easyNumAct_mc.dart):
///  - a centred square camera, 60% of the screen width;
///  - still signs (letters A-Y, numbers 0-10): CAPTURE & CHECK judges the
///    best template match of the last 1.5 s, then the server's static model
///    must confirm it;
///  - moving signs (J, Z, numbers 11-100): RECORD SIGN -> 3-2-1 -> 3 s
///    recording -> the J / Z or decade model judges only the recording.
/// Numbers use the numbers templates and models, letters the alphabet ones.
/// [onResult] gets the answer once (correct or not).
class ChallengeCameraSign extends StatefulWidget {
  final String sign;
  final bool enabled;
  final ValueChanged<ChallengeSignResult> onResult;

  /// A new value starts a new try of the same sign with the same camera
  /// (practice TRY AGAIN), without restarting the camera and hand tracker.
  final int attempt;

  /// Seconds of "get ready" before a moving sign is recorded (0 in the timed
  /// challenges: recording starts at once).
  final int countdown;

  const ChallengeCameraSign({super.key, required this.sign, required this.onResult, this.enabled = true, this.attempt = 0, this.countdown = 3});

  /// Numbers 11-100 and J / Z are signed with movement.
  static bool isDynamicSign(String sign) {
    final s = sign.trim().toUpperCase();
    final n = int.tryParse(s);
    if (n != null) return n >= 11;
    return s == 'J' || s == 'Z';
  }

  @override
  State<ChallengeCameraSign> createState() => _ChallengeCameraSignState();
}

class _ChallengeCameraSignState extends State<ChallengeCameraSign> {
  static const double _threshold = 70.0;
  static const int _windowMs = 1500;

  CameraController? _camera;
  HandLandmarkerPlugin? _landmarker;
  StreamSubscription<List<Hand>>? _handSub;
  final FrameGate _gate = FrameGate();
  bool _ready = false;
  bool _processing = false;
  int _w = 0, _h = 0, _rot = 0;

  final DynamicSignJudge _judge = DynamicSignJudge();
  final StaticLetterChecker _shapeChecker = StaticLetterChecker();
  final StaticServerCheck _serverCheck = StaticServerCheck();
  late final SignRecordingController _recorder = SignRecordingController(countdownSeconds: widget.countdown, onChanged: () {
    if (mounted) setState(() {});
  });

  List<dynamic>? _template;
  String _templateSource = '';
  final List<({int t, double score})> _recent = [];
  double _liveScore = 0;
  bool _handsVisible = false;
  bool _judging = false;
  bool _answered = false;

  String get _sign => widget.sign.trim().toUpperCase();
  bool get _isNumber => int.tryParse(_sign) != null;
  bool get _isDynamic => ChallengeCameraSign.isDynamicSign(_sign);

  @override
  void initState() {
    super.initState();
    _init();
    _prepareSign();
  }

  @override
  void didUpdateWidget(covariant ChallengeCameraSign old) {
    super.didUpdateWidget(old);
    if (old.sign != widget.sign || old.attempt != widget.attempt) {
      _recorder.cancel();
      _judge.clear();
      _serverCheck.clear();
      _recent.clear();
      _liveScore = 0;
      _answered = false;
      _judging = false;
      _template = null;
      _prepareSign();
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _handSub?.cancel();
    if (_camera?.value.isStreamingImages ?? false) _camera?.stopImageStream();
    _camera?.dispose();
    _landmarker?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _landmarker = HandLandmarkerPlugin.create(numHands: 2, minHandDetectionConfidence: 0.5, delegate: HandLandmarkerDelegate.gpu);
      _handSub = _landmarker!.landmarkStream.listen(_onHands);
      final cameras = await availableCameras();
      if (!mounted || cameras.isEmpty) return;
      final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      final c = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      _camera = c;
      await c.initialize();
      if (!mounted) return;
      await c.startImageStream(_onImage);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('Challenge camera setup failed: $e');
    }
  }

  /// Template of a still sign, models of a moving one.
  Future<void> _prepareSign() async {
    final sign = _sign;
    if (_isDynamic) {
      final n = int.tryParse(sign);
      DynamicSignJudge.prepare(letters: n == null, number: n).catchError((e) => debugPrint('Moving-sign models failed to load: $e'));
      return;
    }
    final folder = _isNumber ? 'numbers' : 'alphabet';
    final t = await TemplateStore.load(folder, sign);
    if (!mounted || sign != _sign) return;
    setState(() {
      _template = t;
      _templateSource = TemplateStore.sourceOf(folder, sign) ?? 'models/$folder/$sign.json';
    });
  }

  void _onImage(CameraImage image) {
    LightingMonitor.instance.onImage(image);
    if (!_ready || _landmarker == null || _answered || _processing) return;
    _processing = true;
    try {
      _w = image.width;
      _h = image.height;
      _rot = _rotation(_camera);
      if (!_gate.tryEnter()) return;
      _landmarker!.processFrame(image, _rot);
    } catch (e) {
      debugPrint('Challenge camera frame error: $e');
    } finally {
      _processing = false;
    }
  }

  void _onHands(List<Hand> hands) {
    _gate.done();
    if (!mounted || _answered) return;
    _handsVisible = hands.isNotEmpty;
    if (_isDynamic) {
      // Only the recording counts (record first, then check).
      if (_recorder.recording) _judge.addFrame(hands, imageWidth: _w, imageHeight: _h, rotation: _rot);
      setState(() {});
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final t = _template;
    if (t != null && hands.isNotEmpty) {
      double best = 0;
      Hand? bestHand;
      for (final h in hands) {
        final s = _score(h.landmarks, t);
        if (s > best) {
          best = s;
          bestHand = h;
        }
      }
      if (bestHand != null) {
        _serverCheck.add(bestHand, imageWidth: _w, imageHeight: _h, rotation: _rot);
        if (!_isNumber && _shapeChecker.check(bestHand, _sign, imageWidth: _w, imageHeight: _h, rotation: _rot) != null) {
          best = math.min(best, _threshold - 5);
        }
      }
      _recent.add((t: now, score: best));
    }
    _recent.removeWhere((e) => now - e.t > _windowMs);
    _liveScore = _recent.isEmpty ? 0 : _recent.map((e) => e.score).reduce(math.max);
    setState(() {});
  }

  // ---- answers -----------------------------------------------------------------

  void _finish(ChallengeSignResult r) {
    if (_answered) return;
    _answered = true;
    setState(() => _judging = false);
    widget.onResult(r);
  }

  Future<void> _captureAndCheck() async {
    if (_answered || _judging || !widget.enabled) return;
    HapticFeedback.selectionClick();
    final score = _liveScore;
    if (score < _threshold) {
      _finish(ChallengeSignResult(correct: false, score: score, isDynamic: false, model: _templateSource));
      return;
    }
    setState(() => _judging = true);
    final v = await _serverCheck.verify(_sign, number: _isNumber);
    if (!mounted) return;
    final ok = v != null && v.ok;
    _finish(ChallengeSignResult(
      correct: ok,
      score: ok ? score : math.min(score, _threshold - 1),
      isDynamic: false,
      model: v?.model ?? 'server static_${_isNumber ? 'numbers' : 'letters'} (unreachable)',
      predicted: v?.predicted,
      confidence: v?.confidence,
    ));
  }

  void _record() {
    if (_answered || _judging || _recorder.busy || !widget.enabled) return;
    _recorder.start(
      onRecordingStarted: _judge.clear,
      onDone: () async {
        if (!mounted || _answered) return;
        if (!_judge.hasFrames) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(L.t('No hand was seen while recording. Keep your hand in the frame and try again.',
                'Walang nakitang kamay habang nagre-record. Panatilihin ang kamay sa frame at subukang muli.')),
          ));
          return;
        }
        setState(() => _judging = true);
        final n = int.tryParse(_sign);
        final v = n != null ? await _judge.judgeNumber(n) : await _judge.judgeLetter(_sign);
        if (!mounted) return;
        _judge.clear();
        _finish(ChallengeSignResult(
          correct: v.isCorrect,
          score: v.isCorrect ? math.max(v.score, _threshold) : math.min(v.score, _threshold - 1),
          isDynamic: true,
          model: v.model,
          predicted: v.predicted,
          confidence: v.confidence,
          frames: v.frames,
        ));
      },
    );
  }

  // ---- template scoring (as easyAct_mc.dart) ----------------------------------

  static const List<String> _trickyLetters = ['G', 'H', 'K', 'P', 'Q'];
  static const _matrices = [
    [1.0, 0.0, 0.0, 1.0, 1.0],
    [0.0, -1.0, 1.0, 0.0, 1.0],
    [-1.0, 0.0, 0.0, -1.0, 1.0],
    [0.0, 1.0, -1.0, 0.0, 1.0],
    [1.0, 0.0, 0.0, 1.0, -1.0],
    [0.0, -1.0, 1.0, 0.0, -1.0],
    [-1.0, 0.0, 0.0, -1.0, -1.0],
    [0.0, 1.0, -1.0, 0.0, -1.0],
  ];

  double _score(List<Landmark> lms, List<dynamic> t) {
    if (lms.length < 21 || t.length < 21) return 0;
    final wrist = lms[0], mBase = lms[9];
    final tricky = !_isNumber && _trickyLetters.contains(_sign);
    double dist;
    if (tricky) {
      final tip = lms[8];
      dist = math.max(math.sqrt(math.pow(wrist.x - mBase.x, 2) + math.pow(wrist.y - mBase.y, 2)),
          math.sqrt(math.pow(wrist.x - tip.x, 2) + math.pow(wrist.y - tip.y, 2)) * 0.55);
      if (dist < 0.05) dist = 0.05;
    } else {
      dist = math.sqrt(math.pow(wrist.x - mBase.x, 2) + math.pow(wrist.y - mBase.y, 2) + math.pow(wrist.z - mBase.z, 2));
      if (dist == 0) dist = 1;
    }
    double best = 0;
    for (var m = 0; m < _matrices.length; m++) {
      if (tricky && _sign != 'K' && m.isEven) continue;
      final mx = _matrices[m];
      double diff = 0, weight = 0;
      for (var i = 0; i < 21; i++) {
        final dx = ((lms[i].x - wrist.x) / dist) * mx[4];
        final dy = (lms[i].y - wrist.y) / dist;
        final rx = dx * mx[0] + dy * mx[1];
        final ry = dx * mx[2] + dy * mx[3];
        final tx = (t[i]['x'] as num).toDouble(), ty = (t[i]['y'] as num).toDouble();
        if (tricky) {
          final w = const [4, 8, 12].contains(i) ? 1.5 : 1.0;
          diff += math.sqrt(math.pow(rx - tx, 2) + math.pow(ry - ty, 2)) * w;
          weight += w;
        } else {
          final dz = (lms[i].z - wrist.z) / dist;
          final tz = ((t[i]['z'] ?? 0.0) as num).toDouble();
          diff += math.sqrt(math.pow(rx - tx, 2) + math.pow(ry - ty, 2) + math.pow(dz - tz, 2));
          weight += 1;
        }
      }
      final s = (100.0 - (diff / weight) * (tricky ? 45.0 : 80.0)).clamp(0.0, 100.0);
      if (s > best) best = s;
    }
    return best;
  }

  static int _rotation(CameraController? c) {
    if (c == null) return 0;
    final sensor = c.description.sensorOrientation;
    final ccw = switch (c.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    return c.description.lensDirection == CameraLensDirection.front ? (sensor + ccw) % 360 : (sensor - ccw + 360) % 360;
  }

  // ---- UI ------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final passing = !_isDynamic && _liveScore >= _threshold;
    final c = _camera;
    final camera = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(width: 4, color: _handsVisible ? theme.primaryColor : theme.dividerColor.withValues(alpha: 0.6)),
        boxShadow: [if (_handsVisible) BoxShadow(color: theme.primaryColor.withValues(alpha: 0.3), blurRadius: 15, spreadRadius: 1)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _ready && c != null ? _Preview(controller: c) : Center(child: CircularProgressIndicator(color: theme.primaryColor)),
      ),
    );

    final Widget status = _isDynamic
        ? SignRecordingStatus(controller: _recorder, sign: _sign, checking: _judging, handsVisible: _handsVisible)
        : AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: passing ? Colors.green.withValues(alpha: 0.15) : theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: passing ? Colors.green : theme.dividerColor, width: 1.5),
            ),
            child: Text(
              !_handsVisible && _recent.isEmpty
                  ? L.t('Position your hand in the frame', 'Ilagay ang kamay sa frame')
                  : (_template == null
                      ? L.t('Loading the reference sign...', 'Kinukuha ang halimbawang senyas...')
                      : (_judging
                          ? L.t('Checking your $_sign...', 'Sinusuri ang $_sign...')
                          : (passing
                              ? L.t("Match ${_liveScore.toStringAsFixed(0)}% - tap 'CAPTURE & CHECK'.", "Tugma ${_liveScore.toStringAsFixed(0)}% - pindutin ang 'CAPTURE & CHECK'.")
                              : L.t('Match ${_liveScore.toStringAsFixed(0)}%: adjust your hand.', 'Tugma ${_liveScore.toStringAsFixed(0)}%: ayusin ang kamay.')))),
              textAlign: TextAlign.center,
              style: TextStyle(color: passing ? Colors.green : theme.colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          );

    final canAct = widget.enabled && !_answered && _ready && !_judging;
    final button = SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: !canAct
            ? null
            : (_isDynamic ? (_recorder.busy ? null : _record) : ((_handsVisible || _recent.isNotEmpty) ? _captureAndCheck : null)),
        style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor, disabledBackgroundColor: theme.dividerColor),
        child: Text(
          _isDynamic
              ? signRecordingButtonLabel(_recorder, checking: _judging)
              : (_judging ? L.t('CHECKING...', 'SINUSURI...') : 'CAPTURE & CHECK'),
          style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 15),
        ),
      ),
    );

    return LayoutBuilder(builder: (context, box) {
      final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
      if (landscape) {
        return Row(
          children: [
            Expanded(flex: 5, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [status, const SizedBox(height: 14), button])),
            const SizedBox(width: 16),
            Expanded(flex: 6, child: Center(child: AspectRatio(aspectRatio: 1, child: camera))),
          ],
        );
      }
      final side = math.min(MediaQuery.sizeOf(context).width * 0.60, box.maxHeight.isFinite ? box.maxHeight - 140 : double.infinity);
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            Center(child: SizedBox(width: math.max(side, 120), height: math.max(side, 120), child: camera)),
            const SizedBox(height: 14),
            status,
            const SizedBox(height: 14),
            button,
          ],
        ),
      );
    });
  }
}

class _Preview extends StatelessWidget {
  final CameraController controller;
  const _Preview({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final size = value.previewSize;
        if (!value.isInitialized || size == null) return const ColoredBox(color: Colors.black);
        final landscape = value.deviceOrientation == DeviceOrientation.landscapeLeft || value.deviceOrientation == DeviceOrientation.landscapeRight;
        return ColoredBox(
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
        );
      },
    );
  }
}
