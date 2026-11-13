import '/widgets/button_3d.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/providers/language_provider.dart';
import '/services/performance_monitor.dart';
import '/services/role_service.dart';

/// Success feedback after a correct sign in tutorial / continuous practice,
/// the same as the Greetings (phrase_tutorial_practice.dart) screens: the
/// "Mastered!" dialog with the XP earned, and the inline "Great job! +XP"
/// card of continuous practice.

/// Badge icons that follow the app theme.
class PracticeVisuals {
  final IconData mainBadgeIcon;
  final IconData secondaryIcon;

  const PracticeVisuals(this.mainBadgeIcon, this.secondaryIcon);

  factory PracticeVisuals.fromTheme(ThemeData theme) {
    final primary = theme.primaryColor;
    final r = (primary.r * 255).round(), g = (primary.g * 255).round(), b = (primary.b * 255).round();
    if (b > 160 && r < 120) return const PracticeVisuals(Icons.water_drop_rounded, Icons.waves_rounded);
    if (g > 160 && r < 120) return const PracticeVisuals(Icons.eco_rounded, Icons.forest_rounded);
    if (theme.brightness == Brightness.dark) return const PracticeVisuals(Icons.auto_awesome_rounded, Icons.nights_stay_rounded);
    return const PracticeVisuals(Icons.stars_rounded, Icons.workspace_premium_rounded);
  }
}

/// The double haptic pulse of a correct sign.
Future<void> practiceSuccessHaptics() async {
  HapticFeedback.heavyImpact();
  await Future.delayed(const Duration(milliseconds: 100));
  HapticFeedback.heavyImpact();
}

/// The "Mastered!" dialog. [xpGained]: XP actually awarded (0 when the sign
/// was mastered before or the daily repeat limit was reached). Completes when
/// the learner taps Continue.
Future<void> showPracticeMasteredDialog(BuildContext context, {required String signName, required int xpGained}) {
  final theme = Theme.of(context);
  final visuals = PracticeVisuals.fromTheme(theme);
  final student = context.rolesRead.isStudent;
  // Smaller on small / short phones (the dialog was cut off there).
  final size = MediaQuery.sizeOf(context);
  final k = ((size.width / 393).clamp(0.7, 1.0) * (size.height / 800).clamp(0.75, 1.0)).clamp(0.6, 1.0);
  return showDialog(
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
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Container(
            constraints: BoxConstraints(maxHeight: size.height * 0.85),
            padding: EdgeInsets.all(24 * k),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: theme.primaryColor.withValues(alpha: 0.6), width: 2),
              boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 8)],
            ),
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.all(20 * k),
                      decoration: BoxDecoration(color: theme.primaryColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: Icon(visuals.mainBadgeIcon, color: theme.primaryColor, size: 64 * k),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Icon(visuals.secondaryIcon, color: theme.primaryColor.withValues(alpha: 0.7), size: 22),
                    ),
                  ],
                ),
                SizedBox(height: 20 * k),
                Text(
                  student ? L.t('Mastered!', 'Natutunan!') : L.t('Great signing!', 'Mahusay!'),
                  style: TextStyle(fontSize: 28 * k, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface),
                ),
                SizedBox(height: 12 * k),
                Text(
                  student
                      ? L.t('Outstanding job! You have successfully mastered the sign "$signName"!',
                          'Napakahusay! Natutunan mo na ang kumpas na "$signName"!')
                      : L.t('You signed "$signName" correctly. Keep practising!',
                          'Tama ang pagkumpas mo ng "$signName". Ipagpatuloy ang pagsasanay!'),
                  style: TextStyle(fontSize: 16 * k, color: theme.colorScheme.onSurface.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24 * k),
                TweenAnimationBuilder(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) => Transform.scale(scale: value, child: child),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 24 * k, vertical: 12 * k),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.4), width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(student ? visuals.secondaryIcon : Icons.check_circle_rounded, color: Colors.green, size: 22),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            xpGained > 0
                                ? L.t('+$xpGained XP Earned!', '+$xpGained XP ang nakuha!')
                                : (student ? L.t('Daily XP limit reached', 'Naabot na ang XP ngayong araw') : L.t('Correct sign!', 'Tumpak ang kumpas!')),
                            style: TextStyle(fontSize: 20 * k, fontWeight: FontWeight.w900, color: Colors.green),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 32 * k),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: theme.colorScheme.onPrimary,
                    elevation: 4,
                    shadowColor: theme.primaryColor.withValues(alpha: 0.5),
                    shape: Button3DBorder(borderRadius: BorderRadius.circular(28)),
                    minimumSize: Size(double.infinity, 54 * k),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(L.t('Continue', 'Magpatuloy'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18 * k)),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Inline success card of continuous practice, shown before the next sign.
class ContinuousPracticeSuccess extends StatelessWidget {
  final int xpGained;
  final String nextLabel;

  const ContinuousPracticeSuccess({super.key, required this.xpGained, required this.nextLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visuals = PracticeVisuals.fromTheme(theme);
    final student = context.rolesRead.isStudent;
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
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(visuals.mainBadgeIcon, color: Colors.green, size: 24),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        !student
                            ? L.t('Great job! Correct sign', 'Mahusay! Tumpak ang kumpas')
                            : (xpGained > 0
                                ? L.t('Great job! +$xpGained XP', 'Mahusay! +$xpGained XP')
                                : L.t('Great job! (daily XP limit reached)', 'Mahusay! (naabot na ang XP ngayong araw)')),
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 20, fontFamily: 'Inter'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  nextLabel,
                  style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
