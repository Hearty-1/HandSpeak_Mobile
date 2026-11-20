import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/providers/language_provider.dart';
import '/services/app_haptics.dart';

/// One stop of a [GuideTour]: the widget to point at ([target], a GlobalKey
/// on it) and what to say about it.
///
/// Deaf-friendly: keep [title] to 1-3 words and [body] to one short, plain
/// sentence; [icon] shows the same idea as a picture.
class GuideStep {
  final GlobalKey target;
  final String title;
  final String body;
  final IconData? icon;
  const GuideStep({required this.target, required this.title, required this.body, this.icon});
}

/// "Which button does what", made for Deaf and Hard-of-Hearing learners:
/// everything is visual (nothing relies on sound):
///  * the screen dims and a pulsing, glowing ring circles one button;
///  * a bouncing pointing hand 👆 shows exactly where to tap;
///  * a speech-bubble card points at the button, with a big picture icon,
///    1-3 word title and one short sentence;
///  * progress is shown as dots, not only numbers;
///  * each step gives a short vibration (felt, not heard).
/// Steps whose widget is not on screen are skipped.
///
///   GuideTour.start(context, [GuideStep(target: _menuKey, title: ..., body: ...), ...]);
class GuideTour {
  static OverlayEntry? _entry;

  static void start(BuildContext context, List<GuideStep> steps) {
    final shown = steps.where((s) => s.target.currentContext != null).toList();
    if (shown.isEmpty) return;
    _entry?.remove();
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
      builder: (_) => _GuideOverlay(
        steps: shown,
        onClose: () {
          _entry?.remove();
          _entry = null;
        },
      ),
    );
    overlay.insert(_entry!);
    AppHaptics.selection();
  }
}

class _GuideOverlay extends StatefulWidget {
  final List<GuideStep> steps;
  final VoidCallback onClose;
  const _GuideOverlay({required this.steps, required this.onClose});

  @override
  State<_GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<_GuideOverlay> with SingleTickerProviderStateMixin {
  int _i = 0;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Scrolls the current step's widget into view (e.g. a button lower on a
  /// long page), then redraws the spotlight at its new place.
  Future<void> _reveal() async {
    final ctx = widget.steps[_i].target.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.35,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    if (mounted) setState(() {});
  }

  Rect? _rectOf(GuideStep s) {
    final box = s.target.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return (box.localToGlobal(Offset.zero) & box.size).inflate(8);
  }

  void _go(int step) {
    if (step < 0) return;
    if (step >= widget.steps.length) {
      AppHaptics.correct();
      widget.onClose();
      return;
    }
    AppHaptics.selection();
    setState(() => _i = step);
    _reveal();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final step = widget.steps[_i];
    final hole = _rectOf(step) ?? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
    final last = _i == widget.steps.length - 1;
    // The card goes below the button when it is in the top half, else above.
    final below = hole.center.dy < size.height / 2;
    const margin = 16.0;
    const gap = 46.0; // room for the pointing hand between button and card
    final accent = theme.primaryColor;
    // Where the bubble's tail points (the button's centre, kept on the card).
    final tailX = hole.center.dx.clamp(margin + 28, size.width - margin - 28);
    // The pointing hand sits beside the button, on the card's side.
    final handTop = below ? hole.bottom - 4 : hole.top - 40;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dimmed screen with the pulsing spotlight; a tap anywhere goes on.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _go(_i + 1),
              child: TweenAnimationBuilder<Rect?>(
                tween: RectTween(end: hole),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                builder: (context, r, _) => AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => CustomPaint(
                    painter: _SpotlightPainter(r ?? hole, accent, _pulse.value),
                  ),
                ),
              ),
            ),
          ),
          // Bouncing pointing hand: "tap here".
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Positioned(
              left: hole.center.dx - 18,
              top: handTop + (below ? 1 : -1) * 8 * _pulse.value,
              child: child!,
            ),
            child: IgnorePointer(
              child: Text(
                below ? '👆' : '👇',
                style: const TextStyle(fontSize: 34, shadows: [Shadow(blurRadius: 8, color: Colors.black54)]),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            left: margin,
            right: margin,
            top: below ? hole.bottom + gap : null,
            bottom: below ? null : size.height - hole.top + gap,
            child: _bubble(theme, step, last, below, tailX - margin),
          ),
        ],
      ),
    );
  }

  /// The card with a tail pointing at the button.
  Widget _bubble(ThemeData theme, GuideStep step, bool last, bool below, double tailX) {
    final tail = Padding(
      padding: EdgeInsets.only(left: (tailX - 12).clamp(12.0, double.infinity)),
      child: CustomPaint(size: const Size(24, 12), painter: _TailPainter(theme.cardColor, up: below)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (below) tail,
        _card(theme, step, last),
        if (!below) tail,
      ],
    );
  }

  Widget _card(ThemeData theme, GuideStep step, bool last) {
    final onSurface = theme.colorScheme.onSurface;
    final accent = theme.primaryColor;
    final n = widget.steps.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Big picture of the idea (read before the words).
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(18)),
                child: Icon(step.icon ?? Icons.touch_app_rounded, color: accent, size: 32),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.title,
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: onSurface, height: 1.1)),
                    const SizedBox(height: 4),
                    Text(step.body,
                        style: TextStyle(fontSize: 16, height: 1.3, fontWeight: FontWeight.w600, color: onSurface.withValues(alpha: 0.85))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Progress as dots (seen at a glance).
              Expanded(
                child: Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    for (var k = 0; k < n; k++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: k == _i ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: k <= _i ? accent : onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
              if (_i > 0)
                IconButton(
                  tooltip: L.t('Back', 'Bumalik'),
                  onPressed: () => _go(_i - 1),
                  icon: Icon(Icons.arrow_back_rounded, color: onSurface.withValues(alpha: 0.7)),
                ),
              TextButton.icon(
                onPressed: widget.onClose,
                icon: Icon(Icons.close_rounded, size: 18, color: onSurface.withValues(alpha: 0.6)),
                label: Text(L.t('Skip', 'Laktawan'), style: TextStyle(color: onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: () => _go(_i + 1),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded),
                label: Text(last ? L.t('Done', 'Tapos') : L.t('Next', 'Susunod'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect hole;
  final Color glow;
  final double pulse; // 0..1
  _SpotlightPainter(this.hole, this.glow, this.pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(hole.shortestSide / 2 > 26 ? 26 : hole.shortestSide / 2);
    final cut = RRect.fromRectAndRadius(hole, radius);
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(cut);
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.72));
    // Pulsing outer glow, then a bright ring: easy to spot without sound.
    canvas.drawRRect(
      cut.inflate(4 + 8 * pulse),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = glow.withValues(alpha: 0.6 * (1 - pulse)),
    );
    canvas.drawRRect(
      cut,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole || old.glow != glow || old.pulse != pulse;
}

class _TailPainter extends CustomPainter {
  final Color color;
  final bool up;
  _TailPainter(this.color, {required this.up});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path();
    if (up) {
      p
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width, size.height);
    } else {
      p
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0);
    }
    canvas.drawPath(p..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.color != color || old.up != up;
}

/// Where the student dragged the pet, kept on the phone.
class PetPrefs {
  /// The pet: Hoot the owl.
  static const String name = 'Hoot';
  static const String face = '🦉';

  /// Where the student put the pet, as a share of the screen (x 0 = left
  /// .. 1 = right, y 0 = top .. 1 = bottom); null = the bottom-right corner.
  /// A share (not pixels) so it lands in the same place on every screen.
  static final ValueNotifier<Offset?> moved = ValueNotifier(null);
  static const String _dxKey = 'guide_pet_fx';
  static const String _dyKey = 'guide_pet_fy';
  static Future<void>? _loading;

  /// Reads the saved place once per app run.
  static Future<void> load() => _loading ??= () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final fx = prefs.getDouble(_dxKey), fy = prefs.getDouble(_dyKey);
          if (fx != null && fy != null) moved.value = Offset(fx, fy);
        } catch (_) {}
      }();

  static Future<void> saveMoved(Offset o) async {
    moved.value = o;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_dxKey, o.dx);
      await prefs.setDouble(_dyKey, o.dy);
    } catch (_) {}
  }
}

/// The guide's pet: a friendly animal in the app bar that bobs, blinks and
/// sometimes waves, with a small "?" badge. Tapping it starts the page's
/// [GuideTour] ([onTap]). Visual only (no sound), so it suits Deaf learners.
class GuidePet extends StatefulWidget {
  final VoidCallback onTap;
  final String tooltip;
  const GuidePet({super.key, required this.onTap, this.tooltip = ''});

  /// The pet's animal.
  static const String face = PetPrefs.face;

  @override
  State<GuidePet> createState() => _GuidePetState();
}

class _GuidePetState extends State<GuidePet> with SingleTickerProviderStateMixin {

  // One 4 s loop: bob all the time, blink at 1.6 s, wave (tilt) at 3 s.
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))
    ..repeat();
  bool _pressed = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pet = Tooltip(
      message: widget.tooltip.isEmpty
          ? L.t('Need help? Tap ${PetPrefs.name}!', 'Kailangan ng tulong? Pindutin si ${PetPrefs.name}!')
          : widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          AppHaptics.selection();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value * 4; // seconds in the loop
              final bob = -3 * (0.5 - (0.5 - (t % 1)).abs()) * 2; // up and down each second
              final blinking = t > 1.6 && t < 1.75;
              final wave = t > 3.0 && t < 3.6 ? 0.18 * ((t - 3.0) * 10.5).remainder(2) - 0.18 : 0.0;
              return SizedBox(
                width: 46,
                height: 46,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Transform.translate(
                        offset: Offset(0, bob),
                        child: Transform.rotate(
                          angle: wave,
                          child: Transform.scale(
                            scaleY: blinking ? 0.82 : 1.0,
                            child: Text(
                              GuidePet.face,
                              style: const TextStyle(
                                fontSize: 30,
                                shadows: [Shadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Small "?" badge: Hoot is the help.
                    Positioned(
                      right: 3,
                      top: 3,
                      child: Container(
                        width: 11,
                        height: 11,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: const Text('?',
                            style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900, height: 1)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    // Its own layer: Hoot's constant animation must not repaint the page
    // (blurred app bars / glass cards behind it flickered and cost frames).
    return RepaintBoundary(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: pet));
  }
}


// =============================================================================
// PetAssistant: the pet as a chatbot in the bottom-right corner
// =============================================================================

/// One quick question the pet can answer: a picture, a few words, and the
/// answer as picture steps ((emoji, short words), shown numbered).
class PetTopic {
  final String emoji;
  final String question;
  final List<(String, String)> steps;
  const PetTopic(this.emoji, this.question, this.steps);
}

/// The guide pet floating in the bottom-right corner, like a chatbot. A tap
/// opens a chat: the pet says hello, offers quick-reply buttons and answers
/// in short, picture-led messages (written answers, no AI, works offline).
/// "Show me this page" starts the page's [GuideTour] ([onGuide]).
///
///   Scaffold(floatingActionButton: PetAssistant(onGuide: () => _startGuide(context)), ...)
class PetAssistant extends StatefulWidget {
  /// The page's step-by-step guide; null on pages without one (the chat
  /// then shows only the picture questions).
  final VoidCallback? onGuide;

  /// Extra questions for this page (shown first).
  final List<PetTopic> topics;
  const PetAssistant({super.key, this.onGuide, this.topics = const []});

  /// Use with it: the floating slot then covers the whole screen (see-through;
  /// only the pet takes touches), so the pet can be dragged anywhere.
  ///   floatingActionButtonLocation: PetAssistant.location,
  static const FloatingActionButtonLocation location = _FullScreenSlot();

  /// Questions every page can answer.
  static List<PetTopic> get common => [
        PetTopic('📚', L.t('Learn signs', 'Matuto ng kumpas'), [
          ('📚', L.t('Tap Learn at the bottom.', 'Pindutin ang Matuto sa ibaba.')),
          ('🔤', L.t('Pick a module.', 'Pumili ng module.')),
          ('🎬', L.t('Watch the video.', 'Panoorin ang video.')),
          ('📷', L.t('Copy the sign to the camera.', 'Gayahin ang kumpas sa camera.')),
        ]),
        PetTopic('📷', L.t('Camera does not see me', 'Hindi ako makita ng camera'), [
          ('💡', L.t('Find a bright place.', 'Pumunta sa maliwanag na lugar.')),
          ('🙆', L.t('Show your hands and shoulders.', 'Ipakita ang kamay at balikat.')),
          ('✋', L.t('Hold the sign still.', 'Huwag galawin ang kumpas.')),
        ]),
        PetTopic('⭐', L.t('Get XP and stars', 'Makakuha ng XP at stars'), [
          ('✅', L.t('Finish lessons and activities.', 'Tapusin ang aralin at aktibidad.')),
          ('🎯', L.t('Do the daily quests.', 'Gawin ang daily quests.')),
          ('⭐', L.t('More right answers = more stars.', 'Mas maraming tama = mas maraming stars.')),
        ]),
        PetTopic('🤟', L.t('Translate signs', 'Magsalin ng kumpas'), [
          ('🤟', L.t('Tap Translate at the bottom.', 'Pindutin ang Isalin sa ibaba.')),
          ('🔤', L.t('Pick Letters, Numbers or Words.', 'Pumili: Titik, Numero o Salita.')),
          ('📷', L.t('Sign to the camera.', 'Mag-kumpas sa camera.')),
          ('📝', L.t('Your words show up.', 'Lalabas ang iyong mga salita.')),
        ]),
        PetTopic('👫', L.t('Add friends', 'Magdagdag ng kaibigan'), [
          ('👤', L.t('Go to Arena or Profile.', 'Pumunta sa Arena o Profile.')),
          ('➕', L.t('Tap the person + at the top.', 'Pindutin ang tao + sa itaas.')),
          ('🔍', L.t('Find your classmate.', 'Hanapin ang kaklase.')),
        ]),
        PetTopic('🎮', L.t('Play with classmates', 'Makipaglaro sa kaklase'), [
          ('🏆', L.t('Tap Arena at the bottom.', 'Pindutin ang Arena sa ibaba.')),
          ('🎮', L.t('Open Challenges.', 'Buksan ang Challenges.')),
          ('🚪', L.t('Join a room, or make one.', 'Sumali sa room, o gumawa.')),
        ]),
      ];

  @override
  State<PetAssistant> createState() => _PetAssistantState();
}

/// Puts the floating slot at the top-left corner, so a full-screen child
/// covers the screen exactly.
class _FullScreenSlot extends FloatingActionButtonLocation {
  const _FullScreenSlot();
  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) => Offset.zero;
}

class _PetAssistantState extends State<PetAssistant> {
  // A "Need help?" bubble shows for a few seconds when the page opens.
  bool _hint = true;
  bool _dragging = false;

  /// The pet's top-left corner on screen while it is being dragged / placed.
  Offset? _pos;

  static const double _size = 76; // Hoot's touch area
  static const double _edge = 10;

  @override
  void initState() {
    super.initState();
    PetPrefs.load().then((_) {
      if (mounted) setState(() {});
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  /// Where the pet may be: inside the screen, below the app bar, above the
  /// bottom nav bar.
  Rect _area(Size screen, EdgeInsets pad) => Rect.fromLTRB(
        _edge,
        pad.top + 72,
        screen.width - _size - _edge,
        screen.height - pad.bottom - 96 - _size,
      );

  // A tiny or not-yet-measured screen (first frame, keyboard open, split
  // screen) can give an area whose right / bottom is before its left / top;
  // clamp(min, max) throws then (ArgumentError), so max is never below min.
  Offset _clamp(Offset o, Rect a) => Offset(
        o.dx.clamp(a.left, math.max(a.left, a.right)),
        o.dy.clamp(a.top, math.max(a.top, a.bottom)),
      );

  /// The saved place (or the bottom-right corner) on this screen.
  Offset _placed(Rect a) {
    final f = PetPrefs.moved.value;
    if (f == null) return Offset(a.right, a.bottom);
    return Offset(a.left + f.dx * (a.right - a.left), a.top + f.dy * (a.bottom - a.top));
  }

  void _endDrag(Rect a) {
    final now = _pos ?? _placed(a);
    // Like a chat head: it slides to the nearest side.
    final x = (now.dx - a.left) < (a.right - now.dx) ? a.left : a.right;
    final snapped = _clamp(Offset(x, now.dy), a);
    setState(() {
      _dragging = false;
      _pos = snapped;
    });
    AppHaptics.selection();
    final w = a.right - a.left, h = a.bottom - a.top;
    PetPrefs.saveMoved(Offset(
      w <= 0 ? 1 : (snapped.dx - a.left) / w,
      h <= 0 ? 1 : (snapped.dy - a.top) / h,
    ));
  }

  void _openChat() {
    setState(() => _hint = false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => _PetChat(
        topics: [...widget.topics, ...PetAssistant.common],
        onGuide: widget.onGuide == null
            ? null
            : () {
          Navigator.pop(sheet);
          // Let the sheet close before the guide measures the page.
          Future.delayed(const Duration(milliseconds: 300), widget.onGuide!);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    return SizedBox(
      width: mq.size.width,
      height: mq.size.height,
      // A Stack takes touches only on its children: the rest of the screen
      // stays usable.
      child: LayoutBuilder(builder: (context, c) {
        final screen = Size(c.maxWidth, c.maxHeight);
        final a = _area(screen, mq.padding);
        final pos = _clamp(_dragging && _pos != null ? _pos! : (_pos ?? _placed(a)), a);
        final onLeft = pos.dx < (a.left + a.right) / 2;
        final showHint = _hint && !_dragging;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (showHint)
              Positioned(
                top: pos.dy + 12,
                left: onLeft ? pos.dx + _size + 8 : null,
                right: onLeft ? null : screen.width - pos.dx + 8,
                child: GestureDetector(
                  onTap: _openChat,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(onLeft ? 4 : 16),
                        bottomRight: Radius.circular(onLeft ? 16 : 4),
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Text(L.t('Hi! Need help? 👋', 'Hi! Kailangan ng tulong? 👋'),
                        style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
                  ),
                ),
              ),
            AnimatedPositioned(
              // Follows the finger at once; slides when it snaps to a side.
              duration: _dragging ? Duration.zero : const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              left: pos.dx,
              top: pos.dy,
              width: _size,
              height: _size,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openChat,
                onPanStart: (_) => setState(() {
                  _dragging = true;
                  _hint = false;
                  _pos = pos;
                }),
                onPanUpdate: (d) => setState(() => _pos = _clamp((_pos ?? pos) + d.delta, a)),
                onPanEnd: (_) => _endDrag(a),
                child: AnimatedScale(
                  scale: _dragging ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    alignment: Alignment.center,
                    // The pet's own tap is off here: the drag detector above
                    // handles tap and drag together.
                    child: IgnorePointer(child: Transform.scale(scale: 1.75, child: GuidePet(onTap: _openChat))),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _ChatLine {
  final bool fromPet;
  final String text;

  /// A pet answer as picture steps (emoji, short words); null = plain text.
  final List<(String, String)>? steps;
  const _ChatLine(this.fromPet, this.text, {this.steps});
}

class _PetChat extends StatefulWidget {
  final List<PetTopic> topics;
  final VoidCallback? onGuide;
  const _PetChat({required this.topics, this.onGuide});

  @override
  State<_PetChat> createState() => _PetChatState();
}

/// The chat, made for Deaf and Hard-of-Hearing learners: nothing needs sound
/// or long reading.
///  * answers are numbered picture steps (big emoji + a few words each);
///  * questions are big picture tiles (tap, no typing);
///  * "Hoot is answering" is shown with bouncing dots and a short vibration
///    when the answer arrives;
///  * large, high-contrast text; the newest message scrolls into view.
class _PetChatState extends State<_PetChat> with SingleTickerProviderStateMixin {
  final List<_ChatLine> _lines = [];
  final ScrollController _scroll = ScrollController();
  late final AnimationController _dots = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    const n = PetPrefs.name, f = PetPrefs.face;
    _lines.add(_ChatLine(true, L.t('Hi! I am $n $f. Tap a picture below 👇', 'Hi! Ako si $n $f. Pindutin ang larawan sa ibaba 👇')));
  }

  @override
  void dispose() {
    _dots.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });

  Future<void> _ask(PetTopic t) async {
    if (_typing) return;
    AppHaptics.selection();
    setState(() {
      _lines.add(_ChatLine(false, '${t.emoji} ${t.question}'));
      _typing = true;
    });
    _toEnd();
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _typing = false;
      _lines.add(_ChatLine(true, t.question, steps: t.steps));
    });
    AppHaptics.correct(); // felt: "the answer is here"
    _toEnd();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final accent = theme.primaryColor;
    final size = MediaQuery.sizeOf(context);

    // Hoot's face beside its messages.
    const petFace = Padding(
      padding: EdgeInsets.only(right: 6, bottom: 2),
      child: Text(GuidePet.face, style: TextStyle(fontSize: 30)),
    );

    BoxDecoration petBox() => BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: accent.withValues(alpha: 0.5), width: 2),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(4),
          ),
        );

    // An answer: numbered picture steps.
    Widget stepsCard(List<(String, String)> steps) => Container(
          constraints: BoxConstraints(maxWidth: size.width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: petBox(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var k = 0; k < steps.length; k++)
                Padding(
                  padding: EdgeInsets.only(bottom: k == steps.length - 1 ? 0 : 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(steps[k].$1, style: const TextStyle(fontSize: 28)),
                          ),
                          if (steps.length > 1)
                            Positioned(
                              left: -6,
                              top: -6,
                              child: Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                                child: Text('${k + 1}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          steps[k].$2,
                          style: TextStyle(fontSize: 17, height: 1.25, fontWeight: FontWeight.w700, color: onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

    Widget line(_ChatLine l) {
      if (!l.fromPet) {
        // The child's question, on the right.
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(maxWidth: size.width * 0.72),
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(l.text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        );
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            petFace,
            Flexible(
              child: l.steps != null
                  ? stepsCard(l.steps!)
                  : Container(
                      constraints: BoxConstraints(maxWidth: size.width * 0.72),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: petBox(),
                      child: Text(l.text,
                          style: TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w700, color: onSurface)),
                    ),
            ),
          ],
        ),
      );
    }

    // "Hoot is answering": three bouncing dots.
    Widget typing() => Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              petFace,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: petBox(),
                child: AnimatedBuilder(
                  animation: _dots,
                  builder: (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var k = 0; k < 3; k++)
                        Transform.translate(
                          offset: Offset(0, -6 * math.max(0.0, math.sin(((_dots.value - k * 0.2) % 1.0) * 2 * math.pi))),
                          child: Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

    // A question tile: big picture, few words.
    Widget tile(PetTopic t) => Material(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _typing ? null : () => _ask(t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: onSurface.withValues(alpha: 0.12), width: 1.5),
              ),
              child: Row(
                children: [
                  Text(t.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(t.question,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, height: 1.15, fontWeight: FontWeight.w800, color: onSurface)),
                  ),
                ],
              ),
            ),
          ),
        );

    final topics = widget.topics;
    return Container(
      height: size.height * 0.8,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Header: the pet and its name.
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Row(
              children: [
                const Text(GuidePet.face, style: TextStyle(fontSize: 38)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(PetPrefs.name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: onSurface)),
                      Row(children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(color: Color(0xFF22B573), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(L.t('Your HandSpeak buddy', 'Iyong HandSpeak buddy'),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: onSurface.withValues(alpha: 0.7))),
                      ]),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: L.t('Close', 'Isara'),
                  iconSize: 30,
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: onSurface),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              children: [
                for (final l in _lines) line(l),
                if (_typing) typing(),
              ],
            ),
          ),
          // Picture choices (tap, no typing).
          Container(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(context).bottom),
            decoration: BoxDecoration(
              color: onSurface.withValues(alpha: 0.03),
              border: Border(top: BorderSide(color: onSurface.withValues(alpha: 0.1), width: 1.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onGuide != null) ...[
                // The page guide: the most useful choice, biggest.
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: widget.onGuide,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    icon: const Text('👆', style: TextStyle(fontSize: 24)),
                    label: Text(L.t('Show me this page', 'Ipakita ang pahinang ito'),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 10),
                ],

                LayoutBuilder(
                  builder: (context, c) {
                    final w = (c.maxWidth - 10) / 2;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [for (final t in topics) SizedBox(width: w, height: 62, child: tile(t))],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// The guide of a module page (Alphabet, Numbers, Greetings, Civic and the
/// web categories): Tutorial -> Practice -> Activity -> Challenges. Each page
/// keeps one instance and puts its keys on those four parts.
class ModulePageGuide {
  final GlobalKey tutorial = GlobalKey();
  final GlobalKey practice = GlobalKey();
  final GlobalKey activities = GlobalKey();
  final GlobalKey challenges = GlobalKey();

  void start(BuildContext context) {
    GuideTour.start(context, [
      GuideStep(
        target: tutorial,
        icon: Icons.play_circle_rounded,
        title: L.t('1. Learn', '1. Matuto'),
        body: L.t('Watch each sign, then copy it on camera. The bar shows your progress.',
            'Panoorin ang bawat kumpas, saka gayahin sa camera. Ipinapakita ng bar ang iyong progreso.'),
      ),
      GuideStep(
        target: practice,
        icon: Icons.camera_alt_rounded,
        title: L.t('2. Practise', '2. Magsanay'),
        body: L.t('Practise all the signs with the camera.', 'Sanayin ang lahat ng kumpas gamit ang camera.'),
      ),
      GuideStep(
        target: activities,
        icon: Icons.stars_rounded,
        title: L.t('3. Play levels', '3. Maglaro ng level'),
        body: L.t('Easy, Medium and Hard levels. Win stars and XP.', 'Easy, Medium at Hard na level. Manalo ng stars at XP.'),
      ),
      GuideStep(
        target: challenges,
        icon: Icons.sports_esports_rounded,
        title: L.t('4. Challenges', '4. Mga hamon'),
        body: L.t('Play games with your classmates.', 'Makipaglaro sa iyong mga kaklase.'),
      ),
    ]);
  }
}
