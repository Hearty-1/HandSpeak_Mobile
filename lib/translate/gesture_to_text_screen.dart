import 'dart:async';
import '/widgets/guide_tour.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '/module/custom_category_screen.dart'
    show TranslateCameraPreview, TranslateHint, readPublishedClip;
import '/providers/language_provider.dart';
import '/services/app_haptics.dart';
import '/services/dynamic_sign_judge.dart'
    show DynamicSignJudge, StaticLetterChecker, TemplateStore;
import '/services/handspeak_api_service.dart';
import '/services/holistic_capture.dart';
import '/services/latency_probe.dart';
import '/services/practice_letter_score.dart';
import '/services/lighting_monitor.dart';
import '/services/performance_monitor.dart' show SmartBlur;
import '/services/published_gesture_models.dart';
import 'greetings_reader.dart';
import 'text_to_gesture_view.dart';

/// Translate: Sign -> Text (every model, detected automatically) and
/// Text -> Sign (the lesson videos in the cloud).
///
/// Sign -> Text has three modes, so each sign is read only by the models that
/// can know it (reading everything at once mixed up look-alikes):
///  * Letters: a held handshape -> static letters model (A-Y); a drawn
///    letter -> J / Z;
///  * Numbers: a held handshape -> static numbers model (1-10);
///  * Words: every phrase together -> Greetings and every published
///    (web-trained) category (foods, drinks, family ...).
/// One full-body camera stream is cut into signs by the hands. Letters and
/// digits join the current word, words get a space. Space, delete and
/// corrections use the phone keyboard in the text box.
/// What Sign -> Text listens for.
enum SignMode { letters, numbers, words }

extension SignModeLook on SignMode {
  String get emoji => switch (this) {
    SignMode.letters => '🔤',
    SignMode.numbers => '🔢',
    SignMode.words => '💬',
  };
  String get label => switch (this) {
    SignMode.letters => L.t('Letters', 'Titik'),
    SignMode.numbers => L.t('Numbers', 'Numero'),
    SignMode.words => L.t('Words', 'Salita'),
  };
  String get sample => switch (this) {
    SignMode.letters => 'A B C',
    SignMode.numbers => '1 2 3',
    SignMode.words => L.t('Hello!', 'Kumusta!'),
  };
  Color get color => switch (this) {
    SignMode.letters => const Color(0xFFFF8A3D),
    SignMode.numbers => const Color(0xFF3D8BFF),
    SignMode.words => const Color(0xFF22B573),
  };
}

// Translate guide (the ? in the app bar).
final GlobalKey _tgDirection = GlobalKey();
final GlobalKey _tgModes = GlobalKey();
final GlobalKey _tgCamera = GlobalKey();
final GlobalKey _tgText = GlobalKey();
final GlobalKey _tgShare = GlobalKey();

class GestureToTextScreen extends StatefulWidget {
  const GestureToTextScreen({super.key});

  @override
  State<GestureToTextScreen> createState() => _GestureToTextScreenState();
}

class _GestureToTextScreenState extends State<GestureToTextScreen> {
  bool _toGesture = false; // Text -> Sign
  SignMode _mode = SignMode.letters;
  final TextEditingController _text = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
  }

  @override
  void dispose() {
    _tts.stop();
    _text.dispose();
    super.dispose();
  }

  void _put(String value) => _text.value = TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
  );

  /// A letter or digit joins the current word.
  void _addSymbol(String s) => _put(_text.text + s);

  /// A word or phrase gets a space before it.
  void _addWord(String w) {
    final t = _text.text;
    _put('$t${t.isEmpty || t.endsWith(' ') ? '' : ' '}$w');
  }

  Future<void> _copy() async {
    if (_text.text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _text.text.trim()));
    AppHaptics.selection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L.t('Copied', 'Nakopya')),
        behavior: SnackBarBehavior.fixed,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _speak() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    if (_speaking) {
      await _tts.stop();
      setState(() => _speaking = false);
      return;
    }
    AppHaptics.selection();
    try {
      await _tts.setLanguage(L.isFilipino ? 'fil-PH' : 'en-US');
    } catch (_) {}
    await _tts.setSpeechRate(0.45);
    setState(() => _speaking = true);
    final r = await _tts.speak(t);
    if (r != 1 && mounted) setState(() => _speaking = false);
  }

  /// The step-by-step guide (Sign -> Text; on Text -> Sign the camera
  /// steps are skipped automatically), then the full explanation.
  void _startGuide() {
    GuideTour.start(context, [
      GuideStep(
        target: _tgDirection,
        icon: Icons.swap_horiz_rounded,
        title: L.t('Sign or text', 'Kumpas o teksto'),
        body: L.t('Sign → Text, or Text → Sign.', 'Kumpas → Teksto, o Teksto → Kumpas.'),
      ),
      GuideStep(
        target: _tgModes,
        icon: Icons.category_rounded,
        title: L.t('What will you sign?', 'Ano ang ikukumpas mo?'),
        body: L.t('Pick Letters, Numbers or Words first.', 'Pumili muna: Titik, Numero o Salita.'),
      ),
      GuideStep(
        target: _tgCamera,
        icon: Icons.back_hand_rounded,
        title: L.t('Sign here', 'Mag-kumpas dito'),
        body: L.t('Hold still until the bar is full. For J, Z and words: sign, then put your hand down.',
            'Huwag gumalaw hanggang mapuno ang bar. Sa J, Z at salita: mag-kumpas, saka ibaba ang kamay.'),
      ),
      GuideStep(
        target: _tgText,
        icon: Icons.edit_note_rounded,
        title: L.t('Your words', 'Iyong mga salita'),
        body: L.t('Your signs show here. Tap to fix them.', 'Dito lalabas ang kumpas. Pindutin para ayusin.'),
      ),
      GuideStep(
        target: _tgShare,
        icon: Icons.copy_rounded,
        title: L.t('Copy or speak', 'Kopyahin o basahin'),
        body: L.t('Copy the words, or let the phone say them.', 'Kopyahin, o ipabasa sa phone.'),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final top = MediaQuery.paddingOf(context).top + 65;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButtonLocation: PetAssistant.location,
      floatingActionButton: PetAssistant(onGuide: _startGuide),
      appBar: AppBar(
        toolbarHeight: 65,
        backgroundColor: theme.cardColor.withValues(alpha: 0.4),
        elevation: 0,
        centerTitle: true,
        iconTheme: theme.iconTheme.copyWith(color: textColor),
        flexibleSpace: ClipRRect(
          clipBehavior: Clip.antiAlias,
          child: SmartBlur(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text(
          L.t('Translate', 'Isalin'),
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            fontSize: 22,
          ),
        ),
        actions: [
          // The app logo, as on the other main screens.
          Padding(
            padding: const EdgeInsets.only(right: 16.0, left: 8.0),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.0),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/pictures/image 66.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Icon(Icons.account_circle, size: 40, color: theme.disabledColor),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // The app's background: soft theme-coloured circles.
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.primaryColor.withValues(alpha: 0.20),
              ),
            ),
          ),
          Positioned(
            top: 400,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary.withValues(alpha: 0.15),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: top + 8),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _directionSwitch(theme),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _toGesture
                      ? TextToGestureView(
                          key: const ValueKey('text-to-sign'),
                          initialText: _text.text.trim(),
                        )
                      : _signToText(theme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _directionSwitch(ThemeData theme) {
    Widget side(bool toGesture, String label) {
      final on = _toGesture == toGesture;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (on) return;
            AppHaptics.selection();
            if (_speaking) _tts.stop();
            FocusScope.of(context).unfocus();
            setState(() => _toGesture = toGesture);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? theme.primaryColor : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: on
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GlassCard(
      key: _tgDirection,
      radius: 20,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          side(false, L.t('Sign → Text', 'Kumpas → Teksto')),
          const SizedBox(width: 4),
          side(true, L.t('Text → Sign', 'Teksto → Kumpas')),
        ],
      ),
    );
  }

  Widget _signToText(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight;
        final camera = ClipRRect(
          key: _tgCamera,
          borderRadius: BorderRadius.circular(24),
          child: _AutoSignCamera(
            mode: _mode,
            onSymbol: _addSymbol,
            onWord: _addWord,
          ),
        );
        final controls = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (wide) ...[_modePicker(theme), const SizedBox(height: 12)],
            _textCard(theme),
            const SizedBox(height: 12),
            _shareRow(theme),
          ],
        );
        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: camera),
                const SizedBox(width: 16),
                Expanded(child: SingleChildScrollView(child: controls)),
              ],
            ),
          );
        }
        // The camera keeps a usable size; the page scrolls when the keyboard is open.
        final camH = (c.maxHeight * 0.5).clamp(220.0, c.maxWidth * 1.1);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 110), // room for the pet
          child: Column(
            children: [
              _modePicker(theme),
              const SizedBox(height: 12),
              SizedBox(height: camH, width: double.infinity, child: camera),
              const SizedBox(height: 14),
              controls,
            ],
          ),
        );
      },
    );
  }

  /// Three big, colourful choices: what the child is about to sign.
  Widget _modePicker(ThemeData theme) {
    Widget tile(SignMode m) {
      final on = _mode == m;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: m.label,
          child: GestureDetector(
            onTap: () {
              if (on) return;
              AppHaptics.selection();
              setState(() => _mode = m);
            },
            child: AnimatedScale(
              scale: on ? 1.0 : 0.94,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 6,
                ),
                decoration: BoxDecoration(
                  gradient: on
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(m.color, Colors.white, 0.25)!,
                            m.color,
                          ],
                        )
                      : null,
                  color: on ? null : theme.cardColor.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: on
                        ? Colors.white.withValues(alpha: 0.8)
                        : m.color.withValues(alpha: 0.45),
                    width: on ? 2.5 : 1.5,
                  ),
                  boxShadow: on
                      ? [
                          BoxShadow(
                            color: m.color.withValues(alpha: 0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(m.emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        m.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: on ? Colors.white : m.color,
                        ),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        m.sample,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: on
                              ? Colors.white.withValues(alpha: 0.9)
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.55,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      key: _tgModes,
      children: [
        tile(SignMode.letters),
        const SizedBox(width: 10),
        tile(SignMode.numbers),
        const SizedBox(width: 10),
        tile(SignMode.words),
      ],
    );
  }

  Widget _textCard(ThemeData theme) {
    final onSurface = theme.colorScheme.onSurface;
    return GlassCard(
      key: _tgText,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L.t('✏️ My words', '✏️ Aking mga salita'),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: onSurface,
            ),
          ),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: onSurface,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: L.t(
                'Your signs will show up here!',
                'Dito lalabas ang iyong mga kumpas!',
              ),
              hintStyle: TextStyle(
                color: onSurface.withValues(alpha: 0.4),
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            L.t(
              'Tap the text to edit it with the keyboard.',
              'Pindutin ang teksto para i-edit gamit ang keyboard.',
            ),
            style: TextStyle(
              fontSize: 12,
              color: onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shareRow(ThemeData theme) {
    final has = _text.text.trim().isNotEmpty;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );
    return Row(
      key: _tgShare,
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: has ? _copy : null,
              icon: const Icon(Icons.copy_rounded),
              label: Text(
                L.t('Copy', 'Kopyahin'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              style: OutlinedButton.styleFrom(
                shape: shape,
                backgroundColor: theme.cardColor.withValues(alpha: 0.5),
                side: BorderSide(
                  color: theme.primaryColor.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: has ? _speak : null,
              icon: Icon(
                _speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
              ),
              label: Text(
                _speaking ? L.t('Stop', 'Ihinto') : L.t('Speak', 'Basahin'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: theme.primaryColor,
                shape: shape,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The app's frosted-glass card.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SmartBlur(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: double.infinity,
            padding: padding,
            decoration: BoxDecoration(
              color: theme.cardColor.withValues(alpha: isDark ? 0.55 : 0.6),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.55),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Automatic sign detection
// =============================================================================

class _AutoSignCamera extends StatefulWidget {
  final SignMode mode;
  final ValueChanged<String> onSymbol;
  final ValueChanged<String> onWord;
  const _AutoSignCamera({
    required this.mode,
    required this.onSymbol,
    required this.onWord,
  });

  @override
  State<_AutoSignCamera> createState() => _AutoSignCameraState();
}

class _AutoSignCameraState extends State<_AutoSignCamera>
    with WidgetsBindingObserver {
  /// Held still this long: a letter / number is read.
  static const int _holdMs = 700;

  /// Mean wrist / fingertip movement per frame (palm sizes) below which the hand is still.
  static const double _stillMotion = 0.06;

  /// Movement that starts the next handshape after one was read.
  static const double _releaseMotion = 0.22;

  /// Hands out of view this long: the sign is over.
  static const int _endAfterMs = 600;

  /// A moving sign needs this much hand travel (palm sizes) and frames.
  static const double _minTravel = 2.5;
  static const int _minFrames = 10;
  static const int _maxSegmentMs = 8000;

  /// Accuracy: a reading must beat the model's next guess by this much, and
  /// a moving word must reach this confidence (close calls are not guessed).
  static const double _minMargin = 0.15;
  static const double _minWordConfidence = 0.6;
  static const double _minWordMargin = 0.1;

  /// Cost saving: a greeting this confident is taken without also asking
  /// every published model.
  static const double _sureConfidence = 0.85;

  CameraController? _camera;
  bool _disposed = false;

  // Letters / Numbers: the practice's hand-only tracker (faster and a sharper
  // hand than the full-body one, which gave ~7 fps and read G / P as H and
  // K as U). Words keep the full-body tracker (greetings need the body).
  HandLandmarkerPlugin? _handPlugin;
  StreamSubscription<List<Hand>>? _handSub;
  bool _handInFlight = false;
  int _handRotation = 0;
  bool get _handMode => widget.mode != SignMode.words;

  /// Raw hand_landmarker hands of the current segment, by frame time.
  final Map<int, Hand> _rawHands = {};

  // J / Z strokes, cut out exactly like the letter practice does
  // (TutorialPractice._trackDynamicStroke): a stroke starts when the drawing
  // fingertip (pinky for J, index for Z) moves fast for 2 frames (with the 4
  // frames before it), and ends after 0.45 s of slow tip, 3.5 s, or the
  // hand lost for 0.35 s. Only the stroke goes to the J / Z check, not the
  // arm coming up or a letter held before it.
  static const double _strokeStartSpeed = 1.5; // palm lengths per second
  static const double _strokeIdleSpeed = 0.7;
  static const int _strokeIdleMs = 450;
  static const int _maxStrokeMs = 3500;
  static const int _strokeLossMs = 350;
  static const int _preRollFrames = 4;
  Hand? _prevStrokeHand;
  int _prevStrokeMs = 0;
  double _tipSpeed = 0;
  int _fastFrames = 0;
  bool _stroking = false;
  int _strokeStartMs = 0;
  int _strokeIdleSince = 0;
  int _lastStrokeHandMs = 0;
  int _strokeCooldownUntil = 0;

  /// When the hand came into view: raising the arm is not a stroke, so one
  /// starts only after the hand has been up for [_settleMs].
  int _handUpSince = 0;
  static const int _settleMs = 600;
  final List<List<Hand>> _preRoll = [];

  // The hand's rotation, voted like TutorialPractice._voteOrientation: on the
  // frames before a stroke (the hand held up), which way makes the wrist ->
  // middle knuckle point up; locked after 12 clear frames and used for J / Z.
  final Map<int, double> _uprightVotes = {0: 0, 90: 0, 180: 0, 270: 0};
  int _orientationFrames = 0;
  int? _lockedRotation;

  void _voteOrientation(Hand hand) {
    if (_lockedRotation != null) return;
    final dx = hand.landmarks[9].x - hand.landmarks[0].x;
    final dy = hand.landmarks[9].y - hand.landmarks[0].y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return;
    _uprightVotes[0] = _uprightVotes[0]! + dy / len;
    _uprightVotes[90] = _uprightVotes[90]! + dx / len;
    _uprightVotes[180] = _uprightVotes[180]! - dy / len;
    _uprightVotes[270] = _uprightVotes[270]! - dx / len;
    if (++_orientationFrames < 12) return;
    final best = _uprightVotes.entries.reduce((a, b) => a.value <= b.value ? a : b);
    if (best.value / _orientationFrames < -0.5) {
      _lockedRotation = best.key;
      _jz.forcedRotation = best.key;
      debugPrint('[Translate] hand rotation locked at ${best.key} (camera $_handRotation)');
    } else if (_orientationFrames > 60) {
      // Not clear yet (hand sideways a lot): start the vote again.
      _uprightVotes.updateAll((_, _) => 0);
      _orientationFrames = 0;
    }
  }
  int _inFlight = 0;
  int _imageWidth = 0, _imageHeight = 0;
  String _engine = '';

  // Models.
  final GreetingsReader _greetings = GreetingsReader();
  final DynamicSignJudge _jz = DynamicSignJudge();
  List<PublishedGestureModel> _published = [];

  // The sign being collected.
  final List<RawFrame> _segment = [];
  RawFrame? _prev;
  int _lastHandMs = 0;
  int? _stillSince;
  double _travel = 0; // since the segment start or the last still read
  bool _readStill =
      false; // a handshape of this segment was read; waiting for movement
  bool _busy = false;
  bool _handsVisible = false;
  double _hold = 0;
  String _title = '';
  String _note = '';

  @override
  void didUpdateWidget(_AutoSignCamera old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) {
      _jz.clear();
      _rawHands.clear();
      _resetSegment();
      _title = '';
      _note = '';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    _loadModels();
    DynamicSignJudge.prepare(letters: true);
    _loadTemplates();
  }

  // ---- on-phone handshape templates (the same ones the practice uses) ------

  static const List<String> _letterKeys = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'K', 'L', 'M', //
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y',
  ];
  static const List<String> _numberKeys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'];
  final Map<String, List<dynamic>> _letterTemplates = {};
  final Map<String, List<dynamic>> _numberTemplates = {};


  /// Letters this close to the best are look-alikes (A/S 78/77, X/T 84/82):
  /// the server, then the finger rules, then the score decide.
  static const double _templateTie = 5;


  Future<void> _loadTemplates() async {
    Future<void> load(String folder, List<String> keys, Map<String, List<dynamic>> into) async {
      await Future.wait([
        for (final k in keys)
          TemplateStore.load(folder, k).then((t) {
            if (t != null) into[k] = t;
          }),
      ]);
    }

    await Future.wait([
      load('alphabet', _letterKeys, _letterTemplates),
      load('numbers', _numberKeys, _numberTemplates),
    ]);
    debugPrint('[Translate] templates: ${_letterTemplates.length} letters, ${_numberTemplates.length} numbers');
  }

  /// Each key's score for the held hand with the practice's own scorer
  /// (PracticeLetterScore: G/H/K/P/Q sideways-locked, 70 passes), averaged
  /// over the last frames, best first.
  static List<(String, double)> _rankTemplates(List<List<Landmark>> hands, Map<String, List<dynamic>> templates) {
    final use = hands.length <= 5 ? hands : hands.sublist(hands.length - 5);
    final out = <(String, double)>[
      for (final e in templates.entries)
        (e.key, use.map((h) => PracticeLetterScore.score(h, e.value, e.key)).reduce((a, b) => a + b) / use.length),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  Future<void> _loadModels() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('published_gesture_models')
          .where('active', isEqualTo: true)
          .get();
      final cats = {
        for (final d in snap.docs)
          (d.data()['category'] ?? '').toString().trim(),
      }..remove('');
      final models = <PublishedGestureModel>[];
      for (final c in cats) {
        final m = await PublishedGestureModels.forCategory(c);
        if (m != null && !models.any((x) => x.modelId == m.modelId)) {
          models.add(m);
        }
      }
      if (mounted) _published = models;
      debugPrint(
        '[Translate] published models: ${models.map((m) => m.name).join(', ')}',
      );
    } catch (e) {
      debugPrint('[Translate] published models not read: $e');
    }
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty || _disposed) return;
      final cam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final c = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await c.initialize();
      if (_disposed) {
        await c.dispose();
        return;
      }
      _handPlugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.gpu,
      );
      _handSub = _handPlugin!.landmarkStream.listen(_onHands);
      setState(() => _camera = c);
      await c.startImageStream(_onImage);
    } catch (e) {
      debugPrint('[Translate] camera unavailable: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _camera;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (c.value.isStreamingImages) c.stopImageStream();
    } else if (state == AppLifecycleState.resumed &&
        !c.value.isStreamingImages) {
      c.startImageStream(_onImage);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final c = _camera;
    _camera = null;
    unawaited(() async {
      try {
        if (c != null && c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      await c?.dispose();
    }());
    _handSub?.cancel();
    _handPlugin?.dispose();
    _greetings.dispose();
    super.dispose();
  }

  int _rotation(CameraController c) {
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

  static bool _inFrame(List<List<double>>? hand) {
    if (hand == null || hand.isEmpty) return false;
    const m = 0.02;
    for (final p in hand) {
      if (p.length < 2 ||
          p[0] < m ||
          p[0] > 1 - m ||
          p[1] < m ||
          p[1] > 1 - m) {
        return false;
      }
    }
    return true;
  }

  /// Mean movement of the wrist and fingertips between two frames, in palm sizes.
  static double _motion(RawFrame a, RawFrame b) {
    double one(List<List<double>>? p, List<List<double>>? q) {
      if (p == null || q == null || p.length < 21 || q.length < 21) return -1;
      final palm =
          math.sqrt(
            math.pow(p[9][0] - p[0][0], 2) + math.pow(p[9][1] - p[0][1], 2),
          ) +
          1e-6;
      var sum = 0.0;
      for (final i in const [0, 4, 8, 12, 16, 20]) {
        sum += math.sqrt(
          math.pow(p[i][0] - q[i][0], 2) + math.pow(p[i][1] - q[i][1], 2),
        );
      }
      return sum / 6 / palm;
    }

    final l = one(a.leftHand, b.leftHand), r = one(a.rightHand, b.rightHand);
    final m = math.max(l, r);
    return m < 0 ? 1.0 : m; // a hand appeared / disappeared: count as movement
  }

  Future<void> _onImage(CameraImage image) async {
    LightingMonitor.instance.onImage(image);
    final c = _camera;
    if (_disposed || c == null) return;
    if (_handMode) {
      final plugin = _handPlugin;
      if (plugin == null || _handInFlight) return;
      _handInFlight = true;
      _handRotation = _rotation(c);
      _imageWidth = image.width;
      _imageHeight = image.height;
      try {
        plugin.processFrame(image, _handRotation);
      } catch (e) {
        _handInFlight = false;
        debugPrint('[Translate] hand tracker error: $e');
      }
      return;
    }
    if (_inFlight >= 2) return;
    _inFlight++;
    try {
      final r = await HolisticCapture.process(image, _rotation(c));
      if (r == null || _disposed || !mounted) return;
      _imageWidth = r.imageWidth;
      _imageHeight = r.imageHeight;
      _engine = r.engine;
      _onFrame(r.frame);
    } catch (e) {
      debugPrint('[Translate] capture error: $e');
    } finally {
      _inFlight--;
    }
  }

  static double _palm(List<Landmark> p) =>
      math.sqrt(math.pow(p[9].x - p[0].x, 2) + math.pow(p[9].y - p[0].y, 2)) + 1e-6;

  /// Letters: cuts J / Z strokes out of the live frames (see [_strokeStartSpeed]).
  void _trackStroke(List<Hand> usable, int now) {
    if (usable.isEmpty) {
      if (now - _lastStrokeHandMs > _strokeLossMs) _handUpSince = 0;
      if (_stroking && now - _lastStrokeHandMs > _strokeLossMs) _finishStroke(now);
      if (!_stroking) {
        _prevStrokeHand = null;
        _fastFrames = 0;
        _preRoll.clear();
      }
      return;
    }
    _lastStrokeHandMs = now;
    if (_handUpSince == 0) _handUpSince = now;
    final hand = usable.first;
    final p = hand.landmarks;
    final prev = _prevStrokeHand;
    if (prev != null && now > _prevStrokeMs) {
      final q = prev.landmarks;
      final palm = _palm(p);
      final dt = (now - _prevStrokeMs) / 1000.0;
      // The faster of the two drawing tips (pinky: J, index: Z).
      double speed(int i) => math.sqrt(math.pow(p[i].x - q[i].x, 2) + math.pow(p[i].y - q[i].y, 2)) / palm / dt;
      final raw = math.max(speed(20), speed(8));
      _tipSpeed = 0.5 * _tipSpeed + 0.5 * raw;
    }
    _prevStrokeHand = hand;
    _prevStrokeMs = now;

    if (!_stroking) {
      _voteOrientation(hand);
      _preRoll.add(usable);
      if (_preRoll.length > _preRollFrames) _preRoll.removeAt(0);
      if (now < _strokeCooldownUntil || _busy || now - _handUpSince < _settleMs) return;
      _fastFrames = _tipSpeed > _strokeStartSpeed ? _fastFrames + 1 : 0;
      if (_fastFrames >= 2) {
        _stroking = true;
        _strokeStartMs = now;
        _strokeIdleSince = 0;
        _jz.clear();
        for (final f in _preRoll) {
          _jz.addFrame(f, imageWidth: _imageWidth, imageHeight: _imageHeight, rotation: _handRotation);
        }
        _preRoll.clear();
      }
      return;
    }
    _jz.addFrame(usable, imageWidth: _imageWidth, imageHeight: _imageHeight, rotation: _handRotation);
    if (_tipSpeed < _strokeIdleSpeed) {
      if (_strokeIdleSince == 0) _strokeIdleSince = now;
    } else {
      _strokeIdleSince = 0;
    }
    if ((_strokeIdleSince != 0 && now - _strokeIdleSince >= _strokeIdleMs) || now - _strokeStartMs >= _maxStrokeMs) {
      _finishStroke(now);
    }
  }

  void _finishStroke(int now) {
    _stroking = false;
    _fastFrames = 0;
    _strokeCooldownUntil = now + 700;
    unawaited(_judgeStroke());
  }

  /// One finished stroke: J or Z? (On-phone model, then the server, as in
  /// practice.) A stroke that is neither (moving to the next letter) is
  /// ignored quietly.
  Future<void> _judgeStroke() async {
    if (_busy || _jz.frameCount < 8 || !mounted) {
      _jz.clear();
      return;
    }
    _busy = true;
    try {
      final found = <(String, double)>[];
      for (final l in const ['J', 'Z']) {
        try {
          final v = await _jz.judgeLetter(l);
          debugPrint('[Translate] stroke $l: ${v.isCorrect ? 'yes' : 'no'} ${v.score.toStringAsFixed(0)} '
              '(${v.frames} frames) ${v.isCorrect ? '' : v.feedback}');
          if (v.isCorrect) found.add((l, v.score));
        } catch (e) {
          debugPrint('[Translate] stroke $l check failed: $e');
        }
      }
      if (!mounted || found.isEmpty) return;
      found.sort((a, b) => b.$2.compareTo(a.$2));
      final letter = found.first.$1;
      AppHaptics.correct();
      widget.onSymbol(letter);
      // The hand held at the end of the J / Z is not read as another letter.
      _readStill = true;
      _stillSince = null;
      _travel = 0;
      _show(letter, L.t('Great job! Move your hand for the next one.', 'Magaling! Igalaw ang kamay para sa susunod.'));
    } finally {
      _busy = false;
      _jz.clear();
    }
  }

  /// Letters / Numbers: one hand_landmarker result (raw image points).
  void _onHands(List<Hand> hands) {
    _handInFlight = false;
    if (_disposed || !mounted || !_handMode) return;
    final usable = hands.where((h) => h.landmarks.length == 21).toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (widget.mode == SignMode.letters) _trackStroke(usable, now);
    final hand = usable.isEmpty ? null : usable.first;
    if (hand != null) {
      _rawHands[now] = hand;
      _rawHands.removeWhere((t, _) => now - t > _maxSegmentMs);
    }
    _onFrame(RawFrame(
      rightHand: hand == null ? null : [for (final p in hand.landmarks) [p.x, p.y, p.z]],
      timeMs: now,
    ));
  }

  void _onFrame(RawFrame f) {
    final signing = _inFrame(f.leftHand) || _inFrame(f.rightHand);
    if (signing != _handsVisible) setState(() => _handsVisible = signing);
    if (_busy) return;
    final now = f.timeMs;

    if (signing) _lastHandMs = now;
    if (_segment.isEmpty) {
      if (!signing) return;
      _segment.add(f);
      _prev = f;
      _travel = 0;
      _readStill = false;
      _stillSince = null;
      return;
    }

    // Hands lowered: the sign is over.
    if (!signing && now - _lastHandMs > _endAfterMs) {
      final frames = List<RawFrame>.of(_segment);
      final moved = _travel;
      final readStill = _readStill;
      _resetSegment();
      // Numbers 1-10 are all held handshapes: a moving sign is not read.
      if (widget.mode == SignMode.words &&
          !readStill &&
          moved >= _minTravel &&
          frames.where((x) => x.hasHands).length >= _minFrames) {
        unawaited(_readMoving(frames));
      }
      return;
    }

    _segment.add(f);
    if (_segment.length > 1 && now - _segment.first.timeMs > _maxSegmentMs) {
      _segment.removeAt(0);
    }
    if (!f.hasHands) return;
    final prev = _prev;
    _prev = f;
    final m = prev == null ? 1.0 : _motion(f, prev);

    if (_readStill) {
      // After a letter / number: a clear movement starts the next handshape.
      if (m > _releaseMotion) {
        _readStill = false;
        _travel = 0;
        _stillSince = null;
      }
      return;
    }
    if (m > _stillMotion) {
      _travel += m;
      _stillSince = null;
      if (_hold != 0) setState(() => _hold = 0);
      return;
    }
    // Words are moving signs: a pause is not read as a handshape.
    if (widget.mode == SignMode.words) return;
    _stillSince ??= now;
    final held = now - _stillSince!;
    setState(() => _hold = (held / _holdMs).clamp(0.0, 1.0));
    // Still after little travel: a handshape (letter / number), not a moving sign.
    if (held < _holdMs || _stroking) return;
    unawaited(_readStillSign());
  }

  void _resetSegment() {
    _segment.clear();
    _rawHands.clear();
    _prev = null;
    _stillSince = null;
    _travel = 0;
    _readStill = false;
    if (_hold != 0 && mounted) setState(() => _hold = 0);
  }

  void _show(String title, String note) {
    if (!mounted) return;
    setState(() {
      _title = title;
      _note = note;
    });
  }

  // ---- still: letters A-Y (not J, Z) and numbers 1-10 ------------------------

  Future<void> _readStillSign() async {
    if (_busy) return;
    _busy = true;
    _readStill = true;
    _show(L.t('Reading...', 'Binabasa...'), '');
    try {
      // Only the frames of the held handshape (not the movement into it):
      // the raw hand_landmarker hands, as the practice uses them.
      final since = _stillSince;
      var held = [
        for (final e in _rawHands.entries)
          if (since == null || e.key >= since) e.value,
      ];
      if (held.length < 4) held = _rawHands.values.toList();
      if (held.length > 10) held = held.sublist(held.length - 10);
      if (held.isEmpty) return;
      final rot = ((_handRotation % 360) + 360) % 360;
      final swap = rot == 90 || rot == 270;
      final upW = swap ? _imageHeight : _imageWidth, upH = swap ? _imageWidth : _imageHeight;
      // Upright points for the server (as StaticServerCheck sends them).
      final upright = [
        for (final h in held)
          [
            for (final lm in h.landmarks)
              () {
                final (ux, uy) = switch (rot) {
                  90 => (1.0 - lm.y, lm.x),
                  180 => (1.0 - lm.x, 1.0 - lm.y),
                  270 => (lm.y, 1.0 - lm.x),
                  _ => (lm.x, lm.y),
                };
                return [ux, uy, lm.z];
              }(),
          ],
      ];
      LatencyProbe.markInput();
      final numbers = widget.mode == SignMode.numbers;
      final resFuture = HandSpeakApiService()
          .predictRawStatic(numbers: numbers, frames: upright, imageWidth: upW, imageHeight: upH)
          .timeout(const Duration(seconds: 10))
          .then<StaticPredictResponse?>((r) => r)
          .catchError((Object e) {
            debugPrint('[Translate] static ${numbers ? 'numbers' : 'letters'} failed: $e');
            return null;
          });
      // A clear server reading: passes its threshold and beats its own
      // second guess by [_minMargin].
      bool clear(StaticPredictResponse? r) {
        if (r == null || r.label.trim().isEmpty || r.confidence < r.threshold) {
          return false;
        }
        var second = 0.0;
        for (final p in r.topK) {
          if (p.label.trim().toUpperCase() != r.label.trim().toUpperCase() && p.confidence > second) {
            second = p.confidence;
          }
        }
        return r.confidence - second >= _minMargin;
      }

      // The phone's templates and finger / direction rules (as in practice)
      // with the server's reading. The server alone often gives no answer or
      // mixes up look-alikes (K/U, X/T, S/A ...).
      final lms = [for (final h in held) h.landmarks];
      final ranked = _rankTemplates(lms, numbers ? _numberTemplates : _letterTemplates);
      final res = await resFuture;
      String? serverSays;
      if (clear(res)) {
        final symbol = numbers ? res!.label.replaceAll(RegExp(r'[^0-9]'), '') : res!.label.trim().toUpperCase();
        if (symbol.isNotEmpty) serverSays = symbol;
      }
      double scoreOf(String k) => ranked.firstWhere((e) => e.$1 == k, orElse: () => (k, 0.0)).$2;
      // The practice's finger / direction rules (G/H/P/Q sideways or down,
      // K vs U, M/N/S/T ...) for a candidate letter, on the raw hands.
      bool shapeOk(String k) {
        if (numbers || !StaticLetterChecker.appliesTo(k)) return true;
        final checker = StaticLetterChecker();
        String? problem;
        for (final h in held.length <= 5 ? held : held.sublist(held.length - 5)) {
          problem = checker.check(h, k, imageWidth: _imageWidth, imageHeight: _imageHeight, rotation: _handRotation);
        }
        return problem == null;
      }

      // As in practice: a letter is right when its score reaches the pass
      // mark (70) AND its finger / direction rules pass. Every letter is
      // checked that way; the best passing one wins. The server only breaks
      // a close tie between passing letters (U/V/R ...).
      String? best;
      String how = '-';
      final passing = [
        for (final e in ranked.take(8))
          if (e.$2 >= PracticeLetterScore.pass && shapeOk(e.$1)) e,
      ];
      if (passing.isNotEmpty) {
        final top = passing.first;
        final tied = passing.where((e) => top.$2 - e.$2 < _templateTie).toList();
        if (tied.length > 1 && serverSays != null && tied.any((e) => e.$1 == serverSays)) {
          best = serverSays;
          how = 'practice+server';
        } else {
          best = top.$1;
          how = passing.length == 1 ? 'practice' : 'practice (best of ${passing.map((e) => e.$1).join('/')})';
        }
      } else if (serverSays != null &&
          scoreOf(serverSays) >= PracticeLetterScore.pass - 10 &&
          shapeOk(serverSays)) {
        // Almost passing, and the server and the finger rules agree.
        best = serverSays;
        how = 'server+rules';
      }
      debugPrint(
        '[Translate] still (${widget.mode.name}): server ${res?.label} ${res?.confidence.toStringAsFixed(2)}, '
        'templates ${ranked.take(3).map((e) => '${e.$1} ${e.$2.toStringAsFixed(0)}').join(' ')} -> ${best ?? '-'} ($how)',
      );
      if (!mounted) return;
      if (best != null) {
        AppHaptics.correct();
        widget.onSymbol(best);
        _travel = 0;
        _show(
          best,
          L.t(
            'Great job! Move your hand for the next one.',
            'Magaling! Igalaw ang kamay para sa susunod.',
          ),
        );
      } else {
        _readStill =
            false; // not a letter / number: it may still be a moving sign
        _stillSince = null;
        _show(
          '',
          L.t(
            'Almost! Try the handshape again, nice and clear. 💪',
            'Halos na! Subukan ulit ang porma, malinaw. 💪',
          ),
        );
      }
    } finally {
      _busy = false;
      if (mounted) setState(() => _hold = 0);
    }
  }

  // ---- moving: greetings, published models, J / Z ----------------------------

  Future<void> _readMoving(
    List<RawFrame> frames, {
    bool thenHandshape = false,
  }) async {
    var readHandshape = false;
    if (_busy) return;
    _busy = true;
    _show(L.t('Reading...', 'Binabasa...'), '');
    LatencyProbe.markInput();
    try {
      final words = widget.mode == SignMode.words;
      final firstHand = frames.indexWhere((f) => f.hasHands);
      final lastHand = frames.lastIndexWhere((f) => f.hasHands);
      final clip = firstHand < 0 ? <RawFrame>[] : frames.sublist(firstHand, lastHand + 1);
      final fixed = words && clip.isNotEmpty
          ? CaptureFixer.fix(
              [for (final f in clip) f.toJson(clip.first.timeMs)],
              _imageWidth,
              _imageHeight,
              reassignHands: !HolisticResult.isHolisticEngine(_engine),
            )
          : null;

      final candidates =
          <(String, double, bool)>[]; // (text, confidence, isSymbol)
      // Cost saving: greetings first (one call); the published models (one
      // call each) only when greetings did not clearly recognise the sign.
      if (words && fixed != null) {
        try {
          final g = await _greetings.read(
            fixed.frames,
            fixed.imageWidth,
            fixed.imageHeight,
          );
          if (g != null) candidates.add((g.$1, g.$2, false));
        } catch (e) {
          debugPrint('[Translate] greetings failed: $e');
        }
      }
      final greetingSure =
          candidates.isNotEmpty && candidates.first.$2 >= _sureConfidence;
      final tasks = <Future<void>>[
        if (words && !greetingSure)
          for (final m in _published)
            readPublishedClip(m, clip, _imageWidth, _imageHeight, _engine)
                .then((w) {
                  if (w != null) candidates.add((w.word, w.confidence, false));
                })
                .catchError(
                  (Object e) => debugPrint('[Translate] ${m.name} failed: $e'),
                ),
      ];
      await Future.wait(tasks);

      // Letters mode: J / Z from the live hand_landmarker frames (real
      // timing, as in practice; DynamicSignJudge keeps the last 4 s).
      if (!words) {
        for (final l in ['J', 'Z']) {
          try {
            final v = await _jz.judgeLetter(l);
            debugPrint('[Translate] $l: ${v.isCorrect ? 'yes' : 'no'} ${v.score.toStringAsFixed(0)} '
                '(${v.frames} frames, ${v.model}) ${v.isCorrect ? '' : v.feedback}');
            if (v.isCorrect) candidates.add((l, v.score / 100, true));
          } catch (e) {
            debugPrint('[Translate] $l check failed: $e');
          }
        }
        if (candidates.isNotEmpty) _jz.clear();
      }

      candidates.sort((a, b) => b.$2.compareTo(a.$2));
      // Not confident enough, or another model claims a different word
      // almost as strongly: ask again instead of guessing.
      if (candidates.isNotEmpty) {
        final top = candidates.first;
        final rival = candidates
            .where((c) => c.$1.toLowerCase() != top.$1.toLowerCase())
            .firstOrNull;
        if (top.$2 < _minWordConfidence ||
            (rival != null && top.$2 - rival.$2 < _minWordMargin)) {
          debugPrint(
            '[Translate] moving: unsure (${top.$1} ${top.$2.toStringAsFixed(2)}'
            '${rival == null ? '' : ' vs ${rival.$1} ${rival.$2.toStringAsFixed(2)}'})',
          );
          candidates.clear();
        }
      }
      debugPrint(
        '[Translate] moving: ${candidates.map((c) => '${c.$1} ${c.$2.toStringAsFixed(2)}').join(', ')}',
      );
      if (!mounted) return;
      if (candidates.isNotEmpty) {
        final best = candidates.first;
        AppHaptics.correct();
        best.$3 ? widget.onSymbol(best.$1) : widget.onWord(best.$1);
        _travel = 0;
        _show(best.$1, L.t('Great job! 🎉', 'Magaling! 🎉'));
      } else if (thenHandshape) {
        readHandshape = true; // not J / Z: the held handshape is a letter
      } else {
        AppHaptics.wrong();
        _show(
          '',
          words
              ? L.t(
                  "Hmm, let's try that again! Sign it slowly, then put your hands down. 🙂",
                  'Hmm, ulitin natin! Dahan-dahang ikumpas, saka ibaba ang mga kamay. 🙂',
                )
              : L.t(
                  "Hmm, let's try again! For J and Z, draw the letter slowly. 🙂",
                  'Hmm, ulitin natin! Sa J at Z, iguhit nang dahan-dahan ang titik. 🙂',
                ),
        );
      }
    } catch (e) {
      debugPrint('[Translate] moving read failed: $e');
      _show(
        '',
        L.t(
          'Could not reach the server. Check your internet connection.',
          'Hindi maabot ang server. Tingnan ang koneksyon sa internet.',
        ),
      );
    } finally {
      _busy = false;
    }
    if (readHandshape && mounted) await _readStillSign();
  }

  @override
  Widget build(BuildContext context) {
    final c = _camera;
    final String title;
    final mode = widget.mode;
    if (_busy) {
      title = L.t('🤔 Thinking...', '🤔 Nag-iisip...');
    } else if (_title.isNotEmpty && !_handsVisible) {
      title = _title;
    } else if (!_handsVisible) {
      title = L.t('👋 Show me your hands!', '👋 Ipakita ang iyong mga kamay!');
    } else if (mode == SignMode.words) {
      title = L.t('💬 Sign your word...', '💬 Ikumpas ang salita...');
    } else {
      title = _hold > 0
          ? L.t('✋ Hold it... hold it...', '✋ Hawakan... hawakan...')
          : L.t('✋ Make your handshape', '✋ Gawin ang porma');
    }
    final subtitle = _note.isNotEmpty
        ? _note
        : switch (mode) {
            SignMode.letters => L.t(
              'Hold a letter still · draw J or Z, then lower your hand',
              'Hawakan ang titik · iguhit ang J o Z, saka ibaba ang kamay',
            ),
            SignMode.numbers => L.t(
              'Hold a number (1-10) still until the bar is full',
              'Hawakan ang numero (1-10) hanggang mapuno ang bar',
            ),
            SignMode.words => L.t(
              'Do the whole sign, then put your hands down',
              'Gawin ang buong kumpas, saka ibaba ang mga kamay',
            ),
          };
    return Stack(
      fit: StackFit.expand,
      children: [
        if (c != null && c.value.isInitialized)
          TranslateCameraPreview(controller: c)
        else
          const ColoredBox(color: Colors.black),
        if (_hold > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: _hold,
              minHeight: 10,
              color: mode.color,
              backgroundColor: Colors.white24,
            ),
          ),
        Positioned(
          top: 12,
          right: 12,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (_handsVisible ? const Color(0xFF22A06B) : Colors.black)
                  .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _handsVisible
                      ? Icons.back_hand_rounded
                      : Icons.do_not_touch_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  _handsVisible
                      ? L.t('Hands in view', 'Kita ang kamay')
                      : L.t('No hands', 'Walang kamay'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Mode badge (top left).
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: mode.color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${mode.emoji} ${mode.label}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        TranslateHint(title: title, subtitle: subtitle, raised: false),
      ],
    );
  }
}
