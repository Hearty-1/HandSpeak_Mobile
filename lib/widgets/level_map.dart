import 'dart:math' as math;

import 'package:flutter/material.dart';

import '/services/performance_monitor.dart';

/// Activity level map: the levels sit along a winding 3D pathway of raised
/// stepping stones (each with a darker side, a top-lit face and a shine, in
/// the theme's node colours) over a soft glowing trail, with props of the
/// map's theme beside the path (planets and stars for Galaxy, mushrooms and
/// leaves for the Forest, shells and bubbles for the Ocean, ...). Same
/// arguments as ListView.builder, so a level list switches to it by name;
/// [itemBuilder] builds one level (its stars + node), centred on its point.
class LevelMap extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final Color color;

  /// Distance between two levels along the map.
  final double spacing;

  /// Level the map opens at (the student's current one): scrolled to the
  /// middle of the screen the first time the map is shown.
  final int initialIndex;

  const LevelMap({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.color,
    this.padding,
    this.physics,
    this.spacing = 190,
    this.initialIndex = 0,
  });

  static List<Offset> _points(int n, double width, double spacing) {
    final amp = math.min(width * 0.26, 120.0);
    return [
      for (var i = 0; i < n; i++) Offset(width / 2 + amp * math.sin(i * 1.05), 110 + i * spacing),
    ];
  }

  /// Props of the app theme (same background colours as the theme screens).
  static List<String> _props(Color bg) {
    final hex = bg.toARGB32() & 0xFFFFFF;
    final r = (bg.r * 255).round(), g = (bg.g * 255).round(), b = (bg.b * 255).round();
    if (hex == 0x080928 || (r <= 15 && g <= 15 && b >= 30 && b <= 50)) return ['🪐', '⭐', '🌙', '☄️', '🚀', '✨'];
    if (hex == 0x1D3D3A || (r >= 20 && r <= 38 && g >= 50 && g <= 75 && b >= 45 && b <= 70)) return ['🍄', '🌿', '🌲', '🦋', '🍀', '🌼'];
    if (hex == 0x001B3A || (r <= 5 && g >= 20 && g <= 35 && b >= 50 && b <= 65)) return ['🐚', '🫧', '🐠', '⭐', '🪸', '🐙'];
    if (hex == 0xE0EAFC || (r >= 210 && g >= 220 && b >= 240)) return ['☁️', '🌈', '🎈', '🪁', '☀️', '🕊️'];
    return ['🌸', '🌻', '🍓', '🦋', '🌷', '🍯'];
  }

  @override
  State<LevelMap> createState() => _LevelMapState();
}

class _LevelMapState extends State<LevelMap> {
  final ScrollController _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Once, after the first layout: bring the current level to the middle.
  void _scrollToCurrent(List<Offset> pts, double top) {
    if (_scrolled || pts.isEmpty) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final i = widget.initialIndex.clamp(0, pts.length - 1);
      final pos = _scroll.position;
      final target = (top + pts[i].dy - pos.viewportDimension / 2).clamp(0.0, pos.maxScrollExtent);
      if (target > 0) _scroll.animateTo(target, duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemCount = widget.itemCount, itemBuilder = widget.itemBuilder, padding = widget.padding;
    final physics = widget.physics, color = widget.color, spacing = widget.spacing;
    return LayoutBuilder(builder: (context, c) {
      final pad = (padding ?? EdgeInsets.zero).resolve(Directionality.of(context));
      final width = c.maxWidth - pad.horizontal;
      final pts = LevelMap._points(itemCount, width, spacing);
      final height = (pts.isEmpty ? 0.0 : pts.last.dy) + 140;
      final props = LevelMap._props(theme.scaffoldBackgroundColor);
      _scrollToCurrent(pts, pad.top);
      // Stones in a lighter shade than the nodes, so the nodes and the stars
      // earned above them stand out.
      final stone = Color.lerp(color, Colors.white, 0.55)!;
      final light = Color.lerp(color, Colors.white, 0.85)!;
      return SingleChildScrollView(
        controller: _scroll,
        physics: physics,
        padding: pad,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _PathwayPainter(pts, stone, light, theme.brightness == Brightness.dark)),
              ),
              // Theme props beside the path, between two levels, on the side
              // the path curves away from.
              for (var i = 0; i + 1 < pts.length; i++)
                () {
                  final mid = Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
                  final left = mid.dx > width / 2;
                  return Positioned(
                    left: left ? math.max(8, mid.dx - width * 0.42) : null,
                    right: left ? null : math.max(8, width - mid.dx - width * 0.42),
                    top: mid.dy - 26,
                    child: _Prop(emoji: props[i % props.length], phase: i * 0.37),
                  );
                }(),
              for (var i = 0; i < itemCount; i++)
                Positioned(
                  left: pts[i].dx,
                  top: pts[i].dy,
                  // Centre the level (stars above, node below) on its point.
                  child: FractionalTranslation(translation: const Offset(-0.5, -0.62), child: itemBuilder(context, i)),
                ),
            ],
          ),
        ),
      );
    });
  }
}

/// A theme prop with depth (a soft shadow under it) that bobs gently.
class _Prop extends StatefulWidget {
  final String emoji;
  final double phase;
  const _Prop({required this.emoji, required this.phase});

  @override
  State<_Prop> createState() => _PropState();
}

class _PropState extends State<_Prop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..value = widget.phase % 1;

  // Light mode (slow phone, PerformanceSettings): the props stay still (no endless animation).
  void _apply() {
    if (PerformanceSettings.on) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _apply();
    PerformanceSettings.reduceEffects.addListener(_apply);
  }

  @override
  void dispose() {
    PerformanceSettings.reduceEffects.removeListener(_apply);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return SizedBox(
          width: 56,
          height: 62,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: 30 - 6 * t,
                height: 6,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18 - 0.06 * t), borderRadius: BorderRadius.circular(8)),
              ),
              Positioned(bottom: 6 + 6 * t, child: child!),
            ],
          ),
        );
      },
      child: Text(
        widget.emoji,
        style: TextStyle(fontSize: 36, shadows: [Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 3))]),
      ),
    );
  }
}

class _PathwayPainter extends CustomPainter {
  final List<Offset> pts;
  final Color color;
  final Color light;
  final bool dark;

  _PathwayPainter(this.pts, this.color, this.light, this.dark);

  /// A smooth curve through the points (Catmull-Rom as cubic Béziers), from
  /// above the first level to below the last.
  Path _path() {
    final p = [Offset(pts.first.dx, pts.first.dy - 120), ...pts, Offset(pts.last.dx, pts.last.dy + 120)];
    final path = Path()..moveTo(p[0].dx, p[0].dy);
    for (var i = 0; i < p.length - 1; i++) {
      final p0 = i > 0 ? p[i - 1] : p[i];
      final p1 = p[i], p2 = p[i + 1];
      final p3 = i + 2 < p.length ? p[i + 2] : p2;
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty) return;
    final path = _path();

    // Soft glowing trail under the stones.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 54
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: dark ? 0.08 : 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    final side = Color.lerp(color, Colors.black, dark ? 0.30 : 0.18)!;
    const w = 38.0, h = 22.0, thick = 7.0;
    for (final m in path.computeMetrics()) {
      var n = 0;
      for (double d = 0; d < m.length; d += 34, n++) {
        final pos = m.getTangentForOffset(d)!.position;
        // No stones under a level node or right under its stars.
        if (pts.any((p) => (p - pos).distance < 62 || (p.translate(0, -84) - pos).distance < 34)) continue;
        // Alternate sizes a little, like real stepping stones.
        final k = n.isEven ? 1.0 : 0.86;
        final top = Rect.fromCenter(center: pos, width: w * k, height: h * k);
        // Shadow on the ground
        canvas.drawOval(top.shift(const Offset(0, thick + 4)).inflate(2),
            Paint()..color = Colors.black.withValues(alpha: 0.18)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
        // Side (thickness)
        canvas.drawOval(top.shift(const Offset(0, thick)), Paint()..color = side);
        canvas.drawRect(Rect.fromLTRB(top.left, top.center.dy, top.right, top.center.dy + thick), Paint()..color = side);
        // Top face, lit from the top-left
        canvas.drawOval(
          top,
          Paint()
            ..shader = RadialGradient(center: const Alignment(-0.35, -0.5), radius: 0.9, colors: [light, color]).createShader(top),
        );
        // Shine
        canvas.drawOval(
          Rect.fromCenter(center: top.center.translate(-w * k * 0.14, -h * k * 0.18), width: w * k * 0.42, height: h * k * 0.32),
          Paint()..color = Colors.white.withValues(alpha: 0.55),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PathwayPainter old) => old.pts != pts || old.color != color || old.dark != dark;
}
