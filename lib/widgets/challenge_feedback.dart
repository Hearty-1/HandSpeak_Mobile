import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/providers/theme_provider.dart';
import '/widgets/button_3d.dart';

// ==========================================
// Answer feedback of the solo and group challenges, at the bottom
// ==========================================
class ChallengeFeedbackBanner extends StatelessWidget {
  final bool isCorrect;
  final String correctAnswer;
  final int streak;
  final int points;
  /// Solo: the CONTINUE button. Group: null (the next round starts by itself).
  final VoidCallback? onContinue;

  const ChallengeFeedbackBanner({
    super.key,
    required this.isCorrect,
    required this.correctAnswer,
    this.streak = 0,
    this.points = 0,
    this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final glass = theme.extension<GlassThemeExtension>();
    final color = isCorrect ? theme.colorScheme.primary : theme.colorScheme.error;

    AppThemeMode mode = AppThemeMode.defaultWarm;
    try {
      mode = Provider.of<ThemeProvider>(context, listen: false).themeMode;
    } catch (_) {}
    // Same theme words and icons as the group challenge.
    final (IconData icon, String title) = !isCorrect
        ? (Icons.cancel_rounded, 'INCORRECT')
        : switch (mode) {
            AppThemeMode.galaxy => (Icons.auto_awesome_rounded, 'COSMIC SUCCESS!'),
            AppThemeMode.enchantedForest => (Icons.eco_rounded, 'NATURAL BLOOM!'),
            AppThemeMode.ocean => (Icons.water_drop_rounded, 'DEEP IMPACT!'),
            AppThemeMode.cloudy => (Icons.filter_drama_rounded, 'SKY HIGH!'),
            AppThemeMode.defaultWarm => (Icons.star_rounded, 'SUNNY STRIKE!'),
          };
    final sub = isCorrect
        ? ['+$points pts', if (streak > 1) '🔥 $streak streak'].join('  ·  ')
        : (correctAnswer.isNotEmpty ? 'Answer: $correctAnswer' : 'Keep going, you got this!');

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      tween: Tween<double>(begin: 0.0, end: 1.0),
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, (1 - value) * 120),
        child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color.alphaBlend(color.withAlpha(70), theme.cardColor), glass?.glassCard ?? Color.alphaBlend(color.withAlpha(30), theme.cardColor)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: color, width: 2.5)),
          boxShadow: [BoxShadow(color: color.withAlpha(110), blurRadius: 20, spreadRadius: 1)],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: color.withAlpha(45), shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: textColor)),
                        const SizedBox(height: 2),
                        Text(sub,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor.withAlpha(190))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (onContinue == null)
                Text('Next round coming up...',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor.withAlpha(150)))
              else
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    elevation: 0,
                    shape: Button3DBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: Text('CONTINUE',
                      style: TextStyle(color: isCorrect ? theme.colorScheme.onPrimary : theme.colorScheme.onError, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

