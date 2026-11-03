import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/providers/language_provider.dart';
import '/widgets/button_3d.dart';

/// Soft (not neon) colours of the three difficulties.
class DifficultyColors {
  static const easy = Color(0xFF4FA36B);
  static const medium = Color(0xFFD99A3D);
  static const hard = Color(0xFFC9637A);
  static const locked = Color(0xFF8C9099);
}

/// A difficulty (Easy / Medium / Hard) as a card, in shades of the app
/// theme's colour (see [themed]), in the style of the Home
/// "Daily Challenges" card: a solid soft colour with a gentle gradient, white
/// text, the level icon in a white circle, an arrow, a white star progress
/// bar, a big faint icon as a watermark, the 3D sheen and a push effect.
/// Locked difficulties are grey with a lock and their unlock rule.
class DifficultyCard extends StatelessWidget {
  /// The card colour of difficulty [level] (1-3) in the app theme: shades of
  /// the theme's primary colour, lighter for Easy, deeper for Hard, kept in
  /// a range where white text reads well.
  static Color themed(Color primary, int level) {
    final hsl = HSLColor.fromColor(primary);
    final s = hsl.saturation.clamp(0.25, 0.60);
    final l = switch (level) { 1 => 0.52, 2 => 0.44, _ => 0.35 };
    final hue = (hsl.hue + switch (level) { 1 => -12.0, 2 => 0.0, _ => 12.0 }) % 360;
    return HSLColor.fromAHSL(1, hue, s, l).toColor();
  }

  final String title;
  final String subtitle;
  final Color color;
  final bool isUnlocked;
  final int currentStars;
  final int maxStars;
  final String? lockedMessage;
  final VoidCallback onTap;
  final double height;

  const DifficultyCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isUnlocked,
    required this.currentStars,
    required this.maxStars,
    required this.onTap,
    this.lockedMessage,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    final progress = maxStars > 0 ? (currentStars / maxStars).clamp(0.0, 1.0) : 0.0;
    final level = switch (title.toUpperCase()) { 'EASY' => 1, 'MEDIUM' => 2, _ => 3 };
    final levelIcon = switch (level) {
      1 => Icons.signal_cellular_alt_1_bar_rounded,
      2 => Icons.signal_cellular_alt_2_bar_rounded,
      _ => Icons.signal_cellular_alt_rounded,
    };
    final base = isUnlocked ? themed(Theme.of(context).primaryColor, level) : DifficultyColors.locked;
    final big = height >= 200;
    final done = isUnlocked && maxStars > 0 && currentStars >= maxStars;
    final r = BorderRadius.circular(24);

    return Semantics(
      button: true,
      label: '$title. ${isUnlocked ? subtitle : (lockedMessage ?? L.t('Locked', 'Naka-lock'))}. $currentStars of $maxStars stars.',
      child: Pressable3D(
        radius: r,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            if (isUnlocked) {
              onTap();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(lockedMessage ?? L.t('Locked!', 'Naka-lock!')), backgroundColor: DifficultyColors.hard),
              );
            }
          },
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(base, Colors.white, 0.08)!, Color.lerp(base, Colors.black, 0.12)!],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              boxShadow: [BoxShadow(color: base.withValues(alpha: 0.30), blurRadius: 16, offset: const Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: r,
              child: Stack(
                children: [
                  // Big faint level icon as a watermark.
                  Positioned(
                    right: -14,
                    bottom: -22,
                    child: Icon(levelIcon, size: height * 0.8, color: Colors.white.withValues(alpha: 0.10)),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: big ? 20 : 14),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(big ? 16 : 12),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle),
                          child: Icon(isUnlocked ? levelIcon : Icons.lock_rounded, color: Colors.white, size: big ? 44 : 34),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      title,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: big ? 26 : 21,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ),
                                  // Only a status worth telling: all stars earned, or locked.
                                  if (done || !isUnlocked) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(done ? Icons.check_circle_rounded : Icons.lock_rounded, color: Colors.white, size: 12),
                                          const SizedBox(width: 3),
                                          Text(
                                            done ? L.t('COMPLETED', 'TAPOS NA') : L.t('LOCKED', 'NAKA-LOCK'),
                                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontFamily: 'Inter', fontWeight: FontWeight.w800),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isUnlocked ? subtitle : (lockedMessage ?? L.t('Locked', 'Naka-lock')),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: big ? 14.5 : 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                ),
                              ),
                              SizedBox(height: big ? 14 : 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: big ? 10 : 8,
                                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFFE082)),
                                  const SizedBox(width: 2),
                                  Text(
                                    '$currentStars/$maxStars',
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          isUnlocked ? Icons.arrow_forward_ios_rounded : Icons.lock_outline_rounded,
                          color: Colors.white.withValues(alpha: 0.85),
                          size: 20,
                        ),
                      ],
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
