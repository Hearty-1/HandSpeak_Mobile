import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 3D button shape used by every Elevated / Filled / Outlined button in the
/// app: a soft raised pill, lit from the top (a sheen and a thin rim of
/// light) with a faint shade at the bottom, over a soft drop shadow (see
/// [with3DButtons]). Works with any background colour. While pressed the
/// sheen fades, so the button looks pushed in.
class Button3DBorder extends RoundedRectangleBorder {
  /// Height of the dark bottom lip.
  final double depth;

  const Button3DBorder({super.side, super.borderRadius = const BorderRadius.all(Radius.circular(28)), this.depth = 4});

  /// Pressed look: a thinner lip.
  Button3DBorder get pressed => Button3DBorder(side: side, borderRadius: borderRadius, depth: depth * 0.35);

  @override
  Button3DBorder copyWith({BorderSide? side, BorderRadiusGeometry? borderRadius, double? depth}) =>
      Button3DBorder(side: side ?? this.side, borderRadius: borderRadius ?? this.borderRadius, depth: depth ?? this.depth);

  @override
  ShapeBorder scale(double t) => Button3DBorder(side: side.scale(t), borderRadius: borderRadius * t, depth: depth * t);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is Button3DBorder) {
      return Button3DBorder(
        side: BorderSide.lerp(a.side, side, t),
        borderRadius: BorderRadiusGeometry.lerp(a.borderRadius, borderRadius, t)!,
        depth: a.depth + (depth - a.depth) * t,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is Button3DBorder) return b.lerpFrom(this, t);
    return super.lerpTo(b, t);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final outer = borderRadius.resolve(textDirection).toRRect(rect);
    canvas.save();
    canvas.clipRRect(outer);
    if (depth > 0) {
      final k = depth / 4; // 1 normally, smaller while pressed
      // Soft sheen: light from the top, a faint shade at the bottom, like
      // a raised pill (no hard edge).
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.28 * k),
              Colors.white.withValues(alpha: 0.0),
              Colors.black.withValues(alpha: 0.10 * k),
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(rect),
      );
      // Thin inner rim of light along the top.
      canvas.drawRRect(
        outer.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: 0.55 * k), Colors.white.withValues(alpha: 0.0)],
            stops: const [0.0, 0.5],
          ).createShader(rect),
      );
    }
    canvas.restore();
    super.paint(canvas, rect, textDirection: textDirection);
  }

  @override
  bool operator ==(Object other) => other is Button3DBorder && super == other && other.depth == depth;

  @override
  int get hashCode => Object.hash(super.hashCode, depth);
}

/// The 3D shape for every button state (thinner lip while pressed).
WidgetStateProperty<OutlinedBorder> button3DShape([BorderRadiusGeometry radius = const BorderRadius.all(Radius.circular(28))]) {
  final normal = Button3DBorder(borderRadius: radius);
  return WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed) ? normal.pressed : normal);
}

/// [theme] with 3D Elevated / Filled / Outlined buttons (shape, plus a short
/// drop shadow for elevated ones). Buttons that set their own shape keep it.
ThemeData with3DButtons(ThemeData theme) {
  ButtonStyle add(ButtonStyle? s) => (s ?? const ButtonStyle()).copyWith(shape: button3DShape());
  return theme.copyWith(
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: add(theme.elevatedButtonTheme.style).copyWith(
        elevation: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? 0 : (s.contains(WidgetState.pressed) ? 1 : 6)),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.35)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: add(theme.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: add(theme.outlinedButtonTheme.style)),
  );
}

/// Makes any tappable card / tile 3D with a push effect: it sinks a little
/// (moves down and shrinks) while a finger is on it, with a light haptic tick.
/// With [radius], a soft sheen is drawn on top (lit from the top, shaded at
/// the bottom) like the 3D buttons. Uses a Listener, so the child's own
/// onTap (GestureDetector, InkWell, ListTile) keeps working.
class Pressable3D extends StatefulWidget {
  final Widget child;
  final BorderRadius? radius;
  final bool enabled;

  const Pressable3D({super.key, required this.child, this.radius, this.enabled = true});

  @override
  State<Pressable3D> createState() => _Pressable3DState();
}

class _Pressable3DState extends State<Pressable3D> {
  bool _down = false;

  void _set(bool v) {
    if (!widget.enabled || v == _down) return;
    if (v) HapticFeedback.selectionClick();
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radius;
    Widget child = widget.child;
    if (r != null) {
      child = Container(
        foregroundDecoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: _down ? 0.06 : 0.22),
              Colors.white.withValues(alpha: 0.0),
              Colors.black.withValues(alpha: _down ? 0.02 : 0.08),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: child,
      );
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedSlide(
        offset: Offset(0, _down ? 0.02 : 0),
        duration: const Duration(milliseconds: 90),
        child: AnimatedScale(
          scale: _down ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: child,
        ),
      ),
    );
  }
}

/// A picture / card as a raised 3D button: rounded, with a soft drop shadow
/// and a darker bottom edge under it. Pair with [Pressable3D] for the push.
class Raised3D extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;

  const Raised3D({super.key, required this.child, required this.radius});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          // Bottom edge (the "thickness" of the button), then a soft shadow.
          BoxShadow(color: Colors.black.withValues(alpha: 0.10), offset: const Offset(0, 5)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}

/// A picture as a 3D button with no background: a darker copy of the
/// picture itself sits under it as the button's thickness (so the edge
/// follows the drawing's outline), and while pressed the picture sinks onto
/// it. Taps reach the parent (GestureDetector) as before.
class PictureButton3D extends StatefulWidget {
  final Widget picture;
  final double depth;

  const PictureButton3D({super.key, required this.picture, this.depth = 6});

  @override
  State<PictureButton3D> createState() => _PictureButton3DState();
}

class _PictureButton3DState extends State<PictureButton3D> {
  bool _down = false;

  void _set(bool v) {
    if (v == _down) return;
    if (v) HapticFeedback.selectionClick();
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.depth;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Padding(
        padding: EdgeInsets.only(bottom: d),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Thickness: the same picture, darkened, just below.
            Transform.translate(
              offset: Offset(0, d),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.28), BlendMode.srcATop),
                child: widget.picture,
              ),
            ),
            AnimatedSlide(
              offset: Offset.zero,
              duration: const Duration(milliseconds: 80),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(0, _down ? d * 0.8 : 0, 0),
                child: widget.picture,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Menu item like the web app's sidebar: a plain row (outlined icon +
/// label) that lights up as a pale capsule with a glowing accent edge on the
/// left while it is pressed (the web shows it on hover / for the open page;
/// [selected] keeps it lit). [solid] makes it the filled pill of the web's
/// Logout button. [child] is usually a ListTile (its onTap keeps working).
class MenuCapsule extends StatefulWidget {
  final Widget child;
  final bool selected;
  final bool solid;

  const MenuCapsule({super.key, required this.child, this.selected = false, this.solid = false});

  @override
  State<MenuCapsule> createState() => _MenuCapsuleState();
}

class _MenuCapsuleState extends State<MenuCapsule> {
  bool _down = false;

  void _set(bool v) {
    if (v == _down) return;
    if (v) HapticFeedback.selectionClick();
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.primaryColor;
    const r = BorderRadius.all(Radius.circular(30));
    final lit = widget.selected || _down;

    final BoxDecoration deco;
    if (widget.solid) {
      final base = Color.lerp(accent, Colors.black, 0.55)!;
      deco = BoxDecoration(
        borderRadius: r,
        color: _down ? Color.lerp(base, Colors.black, 0.15) : base,
        boxShadow: [BoxShadow(color: base.withValues(alpha: _down ? 0.2 : 0.35), blurRadius: _down ? 4 : 10, offset: Offset(0, _down ? 1 : 4))],
      );
    } else {
      deco = BoxDecoration(
        borderRadius: r,
        gradient: lit
            ? LinearGradient(colors: [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0.10)])
            : null,
        border: Border.all(color: lit ? accent.withValues(alpha: 0.35) : Colors.transparent, width: 1.2),
        boxShadow: lit ? [BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 3))] : const [],
      );
    }

    Widget tile = Material(
      type: MaterialType.transparency,
      child: ListTileTheme(
        data: ListTileThemeData(
          shape: const StadiumBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          iconColor: widget.solid ? Colors.white : null,
          textColor: widget.solid ? Colors.white : null,
        ),
        child: widget.child,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: deco,
            child: ClipRRect(
              borderRadius: r,
              child: Stack(
                children: [
                  tile,
                  // Glowing accent edge on the left (web sidebar highlight).
                  if (lit && !widget.solid)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: accent,
                          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 8)],
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
}
