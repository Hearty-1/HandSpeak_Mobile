import 'package:flutter/material.dart';

import '/providers/theme_provider.dart' show GalaxyPalette;

/// Answer feedback of the activities (alphabet / numbers / greetings / civic):
/// the themed title, subtitle, gradient and badge of the bottom bar after
/// CHECK. Keys: icon, title, subtitle, gradient, badgeColor, accentColor.
Map<String, dynamic> activityFeedbackVisuals(BuildContext context, bool isCorrect) {
  final color = Theme.of(context).scaffoldBackgroundColor;
  final IconData feedbackIcon = isCorrect ? Icons.check_rounded : Icons.close_rounded;

  final hex = color.toARGB32() & 0xFFFFFF;
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();

  if (hex == 0x080928 || (r <= 15 && g <= 15 && b >= 30 && b <= 50)) { 
    return {
      'icon': feedbackIcon,
      'title': isCorrect ? "Cosmic Victory! 🚀" : "Asteroid Bump! ☄️",
      'subtitle': isCorrect 
          ? "Out of this world accuracy!" 
          : "Trajectory off course!",
      // Aurora green = correct, nebula rose = wrong (instantly distinguishable).
      'gradient': isCorrect ? GalaxyPalette.correct : GalaxyPalette.wrong,
      'badgeColor': isCorrect ? GalaxyPalette.success : GalaxyPalette.error,
      'accentColor': isCorrect ? GalaxyPalette.success : GalaxyPalette.error,
    };
  }

  if (hex == 0x1D3D3A || ((r >= 20 && r <= 38) && (g >= 50 && g <= 75) && (b >= 45 && b <= 70))) { 
    return {
      'icon': feedbackIcon,
      'title': isCorrect ? "Magical Spell! 🌿" : "Lost in the Woods! 🍃",
      'subtitle': isCorrect 
          ? "Ancient wisdom guided you!" 
          : "The forest breeze threw you off!",
      'gradient': isCorrect 
          ? const LinearGradient(colors: [Color(0xFF1D3D3A), Color(0xFF4D7C73)])
          : const LinearGradient(colors: [Color(0xFF1D3D3A), Color(0xFF4A2A22)]),
      'badgeColor': isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),
      'accentColor': const Color(0xFFD7B3A1),
    };
  }

  if (hex == 0x001B3A || (r <= 5 && (g >= 20 && g <= 35) && (b >= 50 && b <= 65))) { 
    return {
      'icon': feedbackIcon,
      'title': isCorrect ? "Splashtastic! 🌊" : "Washed Away! 🐙",
      'subtitle': isCorrect 
          ? "Riding the big wave like a pro!" 
          : "Caught in the ocean current!",
      'gradient': isCorrect 
          ? const LinearGradient(colors: [Color(0xFF001B3A), Color(0xFF00305A)])
          : const LinearGradient(colors: [Color(0xFF001B3A), Color(0xFF3A1C28)]),
      'badgeColor': isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),
      'accentColor': const Color(0xFF00E5FF),
    };
  }

  if (hex == 0xE0EAFC || (r >= 210 && g >= 220 && b >= 240)) { 
    return {
      'icon': feedbackIcon,
      'title': isCorrect ? "On Cloud Nine! ☁️" : "A Little Stormy! 🌧️",
      'subtitle': isCorrect 
          ? "Bright sky ahead, great job!" 
          : "A quick raincloud passed through!",
      'gradient': isCorrect 
          ? const LinearGradient(colors: [Color(0xFFA8C0FF), Color(0xFF3F2B96)])
          : const LinearGradient(colors: [Color(0xFF4B6CB7), Color(0xFF182848)]),
      'badgeColor': isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),
      'accentColor': const Color(0xFF5C7CFA),
    };
  }

  return {
    'icon': feedbackIcon,
    'title': isCorrect ? "Awesome Job! 🎉" : "Not Quite! 💡",
    'subtitle': isCorrect 
        ? "You nailed the correct answer!" 
        : "Don't give up, try again!",
    'gradient': isCorrect 
        ? const LinearGradient(colors: [Color(0xFF11998E), Color(0xFF38EF7D)])
        : const LinearGradient(colors: [Color(0xFFCB2D3E), Color(0xFFEF473A)]),
    'badgeColor': isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),
    'accentColor': isCorrect ? const Color(0xFF58CC02) : const Color(0xFFEA2B2B),
  };
}

/// One piece of a sequence question (activities and challenges). A picture or
/// video is a big square tile (two to a row on a phone), filled edge to
/// edge, so it can really be seen; text is a pill. A placed piece shows its
/// position (1, 2, 3...) in a badge; [border] marks right / wrong after CHECK.
class SequencePiece extends StatelessWidget {
  final bool isMedia;
  final Widget child;
  final bool placed;
  final int? order;
  final Color? border;
  final VoidCallback? onTap;

  const SequencePiece({super.key, required this.isMedia, required this.child, this.placed = false, this.order, this.border, this.onTap});

  /// Side of a picture / video piece: half of the content width (two to a
  /// row on a phone), so the sign in it is big enough to see.
  static double mediaSize(BuildContext context) => ((MediaQuery.sizeOf(context).width - 48 - 24 - 14) / 2).clamp(120.0, 220.0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = mediaSize(context);
    final edge = border ?? (placed ? theme.primaryColor : theme.dividerColor);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: isMedia ? size : null,
            height: isMedia ? size : null,
            padding: isMedia ? const EdgeInsets.all(3) : const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: placed ? theme.primaryColor.withValues(alpha: 0.16) : theme.cardColor,
              borderRadius: BorderRadius.circular(isMedia ? 16 : 24),
              border: Border.all(color: edge, width: 2.5),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: isMedia
                ? ClipRRect(borderRadius: BorderRadius.circular(13), child: SizedBox.expand(child: child))
                : DefaultTextStyle.merge(
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: theme.colorScheme.onSurface),
                    child: child,
                  ),
          ),
          if (order != null)
            Positioned(
              top: -7,
              left: -7,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: edge,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text('$order', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Camera question layout of the Alphabet / Numbers camera levels: the hint
/// chip under the camera and the full-width main button.
Widget cameraLevelChip(ThemeData theme, {required String text, required bool active, Color? color, IconData? icon}) {
  final c = color ?? (active ? theme.primaryColor : Colors.grey);
  return AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    decoration: BoxDecoration(
      color: active ? c.withValues(alpha: 0.12) : theme.cardColor,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: active ? c : theme.dividerColor, width: 1.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon ?? (active ? Icons.pan_tool_rounded : Icons.pan_tool_outlined), color: c, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: active ? c : theme.colorScheme.onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ],
    ),
  );
}

Widget cameraLevelButton(ThemeData theme, {required String label, required VoidCallback? onPressed, bool recording = false}) {
  return SizedBox(
    width: double.infinity,
    height: 54,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.primaryColor,
        disabledBackgroundColor: theme.dividerColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: theme.colorScheme.onPrimary)),
    ),
  );
}

/// The question text without its own answer tacked on after the "?"
/// ("What is this sign? 100" -> "What is this sign?"). Plain text compare
/// (no pattern built from the answer: answers can be whole pictures stored as
/// text). Long or picture answers are never part of the text.
String questionWithoutAnswer(String text, String answer) {
  final a = answer.trim();
  if (a.isEmpty || a.length > 60 || a.contains('\n')) return text;
  final t = text.trimRight();
  if (!t.toLowerCase().endsWith(a.toLowerCase())) return text;
  final head = t.substring(0, t.length - a.length).trimRight();
  return head.endsWith('?') ? head : text;
}
