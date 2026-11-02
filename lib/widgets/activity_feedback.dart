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
