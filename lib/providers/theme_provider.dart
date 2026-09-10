import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum AppThemeMode { 
  defaultWarm, galaxy, enchantedForest, ocean, cloudy 
}

class ThemeOption {
  final String name;
  final AppThemeMode mode;
  final Color bgColor;
  final Color primaryColor;

  const ThemeOption({
    required this.name,
    required this.mode,
    required this.bgColor,
    required this.primaryColor,
  });
}

/// Custom extension for fine-tuned Glassmorphism styling across themes
class GlassThemeExtension extends ThemeExtension<GlassThemeExtension> {
  final Color glassBorder;
  final Color glassCard;
  final Color glassHighlight;

  const GlassThemeExtension({
    required this.glassBorder,
    required this.glassCard,
    required this.glassHighlight,
  });

  @override
  GlassThemeExtension copyWith({
    Color? glassBorder,
    Color? glassCard,
    Color? glassHighlight,
  }) {
    return GlassThemeExtension(
      glassBorder: glassBorder ?? this.glassBorder,
      glassCard: glassCard ?? this.glassCard,
      glassHighlight: glassHighlight ?? this.glassHighlight,
    );
  }

  @override
  GlassThemeExtension lerp(ThemeExtension<GlassThemeExtension>? other, double t) {
    if (other is! GlassThemeExtension) return this;
    return GlassThemeExtension(
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassCard: Color.lerp(glassCard, other.glassCard, t)!,
      glassHighlight: Color.lerp(glassHighlight, other.glassHighlight, t)!,
    );
  }
}

class ThemeProvider extends ChangeNotifier {
  static const String themePrefKey = "user_app_theme";
  
  AppThemeMode _themeMode = AppThemeMode.defaultWarm;

  AppThemeMode get themeMode => _themeMode;

  static final List<ThemeOption> themeOptions = [
    ThemeOption(
      name: "Default Theme",
      mode: AppThemeMode.defaultWarm,
      bgColor: const Color(0xFFFFF9E5),
      primaryColor: const Color(0xFF7DC579),
    ),
    ThemeOption(
      name: "Galaxy Explorer",
      mode: AppThemeMode.galaxy,
      bgColor: const Color(0xFF080928), // Updated #080928
      primaryColor: const Color(0xFF8750A1), // Updated #8750A1
    ),
    ThemeOption(
      name: "Enchanted Forest",
      mode: AppThemeMode.enchantedForest,
      bgColor: const Color(0xFF1D3D3A),
      primaryColor: const Color(0xFFD7B3A1),
    ),
    ThemeOption(
      name: "Deep Ocean",
      mode: AppThemeMode.ocean,
      bgColor: const Color(0xFF001B3A),
      primaryColor: const Color(0xFF00E5FF),
    ),
    ThemeOption(
      name: "Cloudy Sky",
      mode: AppThemeMode.cloudy,
      bgColor: const Color(0xFFE0EAFC),
      primaryColor: const Color(0xFF5C7CFA),
    ),
  ];

  String get themeString {
    switch (_themeMode) {
      case AppThemeMode.galaxy: return "Galaxy Explorer";
      case AppThemeMode.enchantedForest: return "Enchanted Forest";
      case AppThemeMode.ocean: return "Deep Ocean";
      case AppThemeMode.cloudy: return "Cloudy Sky";
      case AppThemeMode.defaultWarm:
      return "Default Theme";
    }
  }

  ThemeProvider() {
    loadThemeFromPrefs();
  }

  void setTheme(AppThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(themePrefKey, mode.name);

    User? currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .update({
          'themePreference': mode.name, 
        });
        debugPrint("Theme successfully saved to user account in Firestore.");
      } catch (e) {
        debugPrint("Failed to save theme to account: $e");
      }
    }
  }

  void setThemeFromString(String name) {
    switch (name) {
      case "Galaxy Explorer":
        setTheme(AppThemeMode.galaxy);
        break;
      case "Enchanted Forest":
        setTheme(AppThemeMode.enchantedForest);
        break;
      case "Deep Ocean":
        setTheme(AppThemeMode.ocean);
        break;
      case "Cloudy Sky":
        setTheme(AppThemeMode.cloudy);
        break;
      case "Default Theme":
      default:
        setTheme(AppThemeMode.defaultWarm);
        break;
    }
  }

  Future<void> loadThemeFromPrefs() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedThemeName = prefs.getString(themePrefKey);
    if (savedThemeName != null) {
      _themeMode = AppThemeMode.values.firstWhere(
        (e) => e.name == savedThemeName,
        orElse: () => AppThemeMode.defaultWarm,
      );
      notifyListeners();
    }
  }

  // --- THEME DATA BUILDERS ---
  
  static final ThemeData defaultWarmTheme = _buildTheme(
    Brightness.light, 
    const Color(0xFFFFF9E5),
    const Color(0xFFFFB800),
    const Color(0xFF7DC579),
    Colors.white,
    const Color(0xFF322144),
    glassBorder: Colors.white.withOpacity(0.6),
    glassHighlight: Colors.white.withOpacity(0.8),
  );
  
  // UPDATED GALAXY EXPLORER PALETTE
  static final ThemeData galaxyTheme = _buildTheme(
    Brightness.dark, 
    const Color(0xFF080928), // Background
    const Color(0xFF8750A1), // Primary Accent
    const Color(0xFF293088), // Secondary Accent
    const Color(0xFF282059), // Card Surface
    const Color(0xFF9F88D8), // Text / Soft Lavender Highlight
    glassBorder: const Color(0xFF483048).withOpacity(0.4),
    glassHighlight: const Color(0xFF9F88D8).withOpacity(0.35),
  );
  
  // UPDATED ENCHANTED FOREST PALETTE
  static final ThemeData enchantedForestTheme = _buildTheme(
    Brightness.dark, 
    const Color(0xFF1D3D3A), 
    const Color(0xFFD7B3A1), 
    const Color(0xFFB8D4CF), 
    const Color(0xFF4D7C73), 
    const Color(0xFFF2F5F4), 
    glassBorder: Colors.white.withOpacity(0.15),
    glassHighlight: Colors.white.withOpacity(0.30),
  );
  
  static final ThemeData oceanTheme = _buildTheme(
    Brightness.dark, 
    const Color(0xFF001B3A), 
    const Color(0xFF00E5FF), 
    const Color(0xFF00B4D8), 
    const Color(0xFF00305A), 
    Colors.white,
    glassBorder: Colors.white.withOpacity(0.18),
    glassHighlight: Colors.white.withOpacity(0.35),
  );
  
  static final ThemeData cloudyTheme = _buildTheme(
    Brightness.light, 
    const Color(0xFFE0EAFC), 
    const Color(0xFF5C7CFA), 
    const Color(0xFF38BDF8), 
    Colors.white, 
    const Color(0xFF2C3E50),
    glassBorder: Colors.white.withOpacity(0.65),
    glassHighlight: Colors.white.withOpacity(0.90),
  );

  static ThemeData _buildTheme(
    Brightness brightness, 
    Color bg, 
    Color primary, 
    Color secondary, 
    Color card, 
    Color text, {
    required Color glassBorder,
    required Color glassHighlight,
  }) {
    final bool isDark = brightness == Brightness.dark;

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      primaryColor: primary,
      cardColor: card,
      dividerColor: glassBorder,
      extensions: [
        GlassThemeExtension(
          glassBorder: glassBorder,
          glassCard: card.withOpacity(isDark ? 0.45 : 0.65),
          glassHighlight: glassHighlight,
        ),
      ],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: Colors.white,
        secondary: secondary,
        onSecondary: Colors.white,
        error: Colors.red,
        onError: Colors.white,
        surface: card,
        onSurface: text,
        outline: glassBorder,
        outlineVariant: glassHighlight,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: text),
        titleTextStyle: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 20),
      ),
    );
  }

  ThemeData get activeTheme {
    switch (_themeMode) {
      case AppThemeMode.galaxy: return galaxyTheme;
      case AppThemeMode.enchantedForest: return enchantedForestTheme;
      case AppThemeMode.ocean: return oceanTheme;
      case AppThemeMode.cloudy: return cloudyTheme;
      case AppThemeMode.defaultWarm:
      return defaultWarmTheme;
    }
  }

  ThemeMode get activeThemeMode {
    return activeTheme.brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  }
}