import 'dart:convert';

import 'package:flutter/material.dart';

/// The student's avatar on the activity map, on top of the level they are
/// up to (the furthest unlocked level), so the map shows where they are as
/// they progress. It hops on the node (a jump, a squash on landing and a
/// shadow), so it looks alive for the kids. [avatar]: users.avatar /
/// photoURL (base64 data URI, URL or asset); a person icon without one.
class LevelAvatar extends StatefulWidget {
  final String? avatar;
  final Color color;
  final double size;

  const LevelAvatar({super.key, required this.avatar, required this.color, this.size = 60});

  /// users/{uid} avatar field.
  static String? of(Map<String, dynamic>? userData) {
    final v = userData?['avatar'] ?? userData?['photoURL'] ?? userData?['photoUrl'];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  @override
  State<LevelAvatar> createState() => _LevelAvatarState();
}

class _LevelAvatarState extends State<LevelAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  Widget _image() {
    final a = widget.avatar;
    final fallback = Icon(Icons.person_rounded, color: widget.color, size: widget.size * 0.6);
    if (a == null) return fallback;
    if (a.startsWith('data:image')) {
      try {
        return Image.memory(base64Decode(a.split(',').last), fit: BoxFit.cover, gaplessPlayback: true);
      } catch (_) {
        return fallback;
      }
    }
    if (a.startsWith('http')) return Image.network(a, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
    if (a.startsWith('assets/')) return Image.asset(a, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _hop,
      builder: (context, child) {
        // 0-0.7 in the air (an arc), 0.7-1 landed: squashed, then back.
        final t = _hop.value;
        final air = t < 0.7 ? t / 0.7 : 1.0;
        final height = t < 0.7 ? 16 * (4 * air * (1 - air)) : 0.0;
        final squash = t < 0.7 ? 0.0 : 1 - ((t - 0.7) / 0.3 * 2 - 1).abs();
        return SizedBox(
          width: s + 10,
          height: s + 22,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              // Shadow on the node, smaller while in the air.
              Positioned(
                bottom: 0,
                child: Container(
                  width: s * (0.75 - height / 60),
                  height: 7,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25 - height / 120),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Positioned(
                bottom: 4 + height,
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.diagonal3Values(1 + 0.12 * squash, 1 - 0.14 * squash, 1),
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(color: widget.color.withValues(alpha: 0.55), blurRadius: 10, spreadRadius: 1),
            BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 3)),
          ],
        ),
        child: ClipOval(child: _image()),
      ),
    );
  }
}

/// A level node on the activity map as a 3D button in the theme's colours:
/// a darker base under it (the button's thickness), a top-lit face with a
/// glossy highlight, and a soft glow; locked levels are grey. The face sinks
/// onto its base while pressed.
class LevelNode3D extends StatefulWidget {
  final bool unlocked;
  final Color color;
  final Color light;
  final double size;

  const LevelNode3D({super.key, required this.unlocked, required this.color, required this.light, this.size = 86});

  @override
  State<LevelNode3D> createState() => _LevelNode3DState();
}

class _LevelNode3DState extends State<LevelNode3D> {
  bool _down = false;

  void _set(bool v) {
    if (v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    const depth = 9.0;
    const ring = 9.0;
    final face = widget.unlocked ? widget.color : Colors.grey.shade500;
    final light = widget.unlocked ? widget.light : Colors.grey.shade300;
    final base = Color.lerp(face, Colors.black, 0.35)!;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: SizedBox(
        width: s + 2 * ring,
        height: s + 2 * ring + depth,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // Glow ring
            Container(
              width: s + 2 * ring,
              height: s + 2 * ring,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.unlocked ? widget.color.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            // Base (the button's thickness)
            Positioned(
              top: ring + depth,
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: base,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.30), blurRadius: 10, offset: const Offset(0, 6))],
                ),
              ),
            ),
            // Face
            AnimatedPositioned(
              duration: const Duration(milliseconds: 80),
              top: ring + (_down ? depth * 0.8 : 0),
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(center: const Alignment(-0.3, -0.45), radius: 0.95, colors: [light, face]),
                  border: Border.all(color: Colors.white.withValues(alpha: widget.unlocked ? 0.9 : 0.6), width: 4),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Glossy highlight
                    Positioned(
                      top: s * 0.08,
                      child: Container(
                        width: s * 0.55,
                        height: s * 0.22,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(s),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.0)],
                          ),
                        ),
                      ),
                    ),
                    Icon(
                      widget.unlocked ? Icons.play_arrow_rounded : Icons.lock_rounded,
                      color: Colors.white,
                      size: s * 0.53,
                      shadows: [Shadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stars earned on a level, shown above its node like a crown: three glossy
/// stars in an arc (the side ones tilted and lower, the middle one bigger),
/// each with a thick white outline and a drop shadow. Earned stars are gold
/// with a shine; missing ones are dimmed slots, so the count reads at a
/// glance on any theme.
class LevelStars extends StatelessWidget {
  final int earned;
  const LevelStars({super.key, required this.earned});

  Widget _star(bool on, double size) {
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Drop shadow
          Transform.translate(
            offset: const Offset(0, 2.5),
            child: Icon(Icons.star_rounded, size: size + 7, color: Colors.black.withValues(alpha: 0.28)),
          ),
          // White outline
          Icon(Icons.star_rounded, size: size + 7, color: Colors.white),
          // Face: gold with a top shine, or a dim slot
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: on ? const [Color(0xFFFFF176), Color(0xFFFFC107), Color(0xFFFF8F00)] : [Colors.grey.shade300, Colors.grey.shade500],
            ).createShader(r),
            child: Icon(Icons.star_rounded, size: size),
          ),
          if (on)
            Positioned(
              top: size * 0.30,
              left: size * 0.34,
              child: Container(
                width: size * 0.22,
                height: size * 0.12,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(size)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A soft halo behind the arc keeps the stars clear of the path.
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.0)], radius: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Transform.rotate(angle: -0.28, child: _star(earned >= 1, 17)),
          ),
          Transform.translate(offset: const Offset(0, -2), child: _star(earned >= 2, 23)),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Transform.rotate(angle: 0.28, child: _star(earned >= 3, 17)),
          ),
        ],
      ),
    );
  }
}
