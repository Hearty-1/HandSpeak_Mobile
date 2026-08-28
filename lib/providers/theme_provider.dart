import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      bgColor: const Color(0xFF0F0C29),
      primaryColor: const Color(0xFFFF2A85),
    ),
    ThemeOption(
      name: "Enchanted Forest",
      mode: AppThemeMode.enchantedForest,
      bgColor: const Color(0xFF132A13),
      primaryColor: const Color(0xFFFFD700),
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
      default: return "Default Theme";
    }
  }

  ThemeProvider() {
    _loadThemeFromPrefs();
  }

  void setTheme(AppThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(themePrefKey, mode.name);
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

  void _loadThemeFromPrefs() async {
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
    const Color(0xFFFFF9E5), // Background
    const Color(0xFFFFB800), // Primary
    const Color(0xFF7DC579), // Secondary
    Colors.white,            // Card
    const Color(0xFF322144), // Text
    glassBorder: Colors.white.withOpacity(0.6),
    glassHighlight: Colors.white.withOpacity(0.8),
  );
  
  static final ThemeData galaxyTheme = _buildTheme(
    Brightness.dark, 
    const Color(0xFF0F0C29), 
    const Color(0xFFFF2A85), 
    const Color(0xFF9D4EDD), 
    const Color(0xFF1F184A), 
    Colors.white,
    glassBorder: Colors.white.withOpacity(0.18),
    glassHighlight: Colors.white.withOpacity(0.35),
  );
  
  static final ThemeData enchantedForestTheme = _buildTheme(
    Brightness.dark, 
    const Color(0xFF132A13), 
    const Color(0xFFFFD700), 
    const Color(0xFF52B788), 
    const Color(0xFF1F4124), 
    const Color(0xFFE5F9E0),
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
      // Translucent divider/border default so borders don't look solid
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
      default: return defaultWarmTheme;
    }
  }

  ThemeMode get activeThemeMode {
    return activeTheme.brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  }
}