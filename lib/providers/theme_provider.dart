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

/// Galaxy Explorer palette. Every Galaxy-specific screen uses these, so the
/// whole theme stays consistent. Text colors pass WCAG AA on [bg] and [card]
/// (body text 16:1, accents 7-11:1); white on [primary] is 4.8:1.
class GalaxyPalette {
  GalaxyPalette._();

  // Space
  static const Color bg = Color(0xFF080928); // deep space (screens detect the theme by this)
  static const Color bgDeep = Color(0xFF05061C); // gradient end / shadows
  static const Color card = Color(0xFF1B1A4B); // indigo night surface
  static const Color cardHigh = Color(0xFF262466); // raised surface / selected
  static const Color field = Color(0xFF13123A); // inputs, progress tracks

  // Light
  static const Color primary = Color(0xFF7C4DFF); // electric violet: buttons, active
  static const Color primaryGlow = Color(0xFFA98BFF); // glows, focus rings
  static const Color secondary = Color(0xFF4C5FE6); // cosmic blue
  static const Color accent = Color(0xFFB9A6FF); // starlight lavender: icons, captions
  static const Color text = Color(0xFFEDE9FF); // starlight white: body text
  static const Color textMuted = Color(0xFFA9A3D6); // secondary text
  static const Color border = Color(0xFF3A3378); // glass edges

  // Feedback
  static const Color success = Color(0xFF3DDC97); // aurora green: correct
  static const Color successDeep = Color(0xFF0F4A3A);
  static const Color error = Color(0xFFFF6B8B); // nebula rose: wrong
  static const Color errorDeep = Color(0xFF4A1238);
  static const Color star = Color(0xFFFFD166); // star gold: XP, stars, rewards
  static const Color info = Color(0xFF5CE1E6); // comet cyan: hints, live status

  static const LinearGradient nebula = LinearGradient(
    colors: [Color(0xFF2A1F7A), primary, Color(0xFFB04BD9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient space = LinearGradient(
    colors: [bg, card, bg],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const LinearGradient correct = LinearGradient(
    colors: [successDeep, Color(0xFF1E8C6A), success],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient wrong = LinearGradient(
    colors: [errorDeep, Color(0xFF9C2A5E), error],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
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
      bgColor: GalaxyPalette.bg,
      primaryColor: GalaxyPalette.primary,
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
  
  // GALAXY EXPLORER: see GalaxyPalette.
  static final ThemeData galaxyTheme = _galaxyComponents(_buildTheme(
    Brightness.dark,
    GalaxyPalette.bg,
    GalaxyPalette.primary,
    GalaxyPalette.secondary,
    GalaxyPalette.card,
    GalaxyPalette.text,
    glassBorder: GalaxyPalette.border.withValues(alpha: 0.7),
    glassHighlight: GalaxyPalette.accent.withValues(alpha: 0.35),
  ));

  /// Galaxy-specific component styling and visual feedback: violet ripples,
  /// glowing focus states, star-gold rewards, aurora / rose status colors.
  static ThemeData _galaxyComponents(ThemeData base) {
    const p = GalaxyPalette.primary;
    final rounded16 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final glowOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) return GalaxyPalette.primaryGlow.withValues(alpha: 0.22);
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
        return GalaxyPalette.primaryGlow.withValues(alpha: 0.12);
      }
      return null;
    });
    final solidButton = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? GalaxyPalette.cardHigh : p),
      foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? GalaxyPalette.textMuted : Colors.white),
      overlayColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.pressed) ? Colors.white.withValues(alpha: 0.14) : null),
      shape: WidgetStatePropertyAll(rounded16),
    );
    OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primaryContainer: GalaxyPalette.cardHigh,
        onPrimaryContainer: GalaxyPalette.text,
        tertiary: GalaxyPalette.star,
        onTertiary: GalaxyPalette.bg,
        error: GalaxyPalette.error,
        onError: GalaxyPalette.bg,
        onSurfaceVariant: GalaxyPalette.textMuted,
        surfaceContainerHighest: GalaxyPalette.cardHigh,
        outline: GalaxyPalette.border,
        outlineVariant: GalaxyPalette.accent.withValues(alpha: 0.35),
      ),
      // Touch feedback: a violet glow instead of the default grey splash.
      splashColor: GalaxyPalette.primaryGlow.withValues(alpha: 0.18),
      highlightColor: GalaxyPalette.primaryGlow.withValues(alpha: 0.08),
      hoverColor: GalaxyPalette.primaryGlow.withValues(alpha: 0.06),
      focusColor: GalaxyPalette.primaryGlow.withValues(alpha: 0.16),
      dividerColor: GalaxyPalette.border.withValues(alpha: 0.6),
      iconTheme: const IconThemeData(color: GalaxyPalette.accent),
      textTheme: base.textTheme.apply(bodyColor: GalaxyPalette.text, displayColor: GalaxyPalette.text),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: GalaxyPalette.primaryGlow,
        selectionColor: p.withValues(alpha: 0.35),
        selectionHandleColor: GalaxyPalette.primaryGlow,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: solidButton.copyWith(
          shadowColor: WidgetStatePropertyAll(p.withValues(alpha: 0.6)),
          elevation: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed) ? 2 : 6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: solidButton),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(GalaxyPalette.accent),
          side: WidgetStateProperty.resolveWith((s) => BorderSide(
              color: s.contains(WidgetState.pressed) ? GalaxyPalette.primaryGlow : GalaxyPalette.border,
              width: 1.4)),
          overlayColor: glowOverlay,
          shape: WidgetStatePropertyAll(rounded16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(GalaxyPalette.primaryGlow),
          overlayColor: glowOverlay,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p,
        foregroundColor: Colors.white,
        splashColor: GalaxyPalette.primaryGlow.withValues(alpha: 0.4),
        elevation: 8,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: GalaxyPalette.primaryGlow,
        linearTrackColor: GalaxyPalette.field,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: p,
        inactiveTrackColor: GalaxyPalette.field,
        thumbColor: GalaxyPalette.primaryGlow,
        overlayColor: p.withValues(alpha: 0.2),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : GalaxyPalette.textMuted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p : GalaxyPalette.field),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p : GalaxyPalette.border),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: GalaxyPalette.accent, width: 1.6),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? GalaxyPalette.primaryGlow : GalaxyPalette.accent),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: GalaxyPalette.field,
        selectedColor: p.withValues(alpha: 0.35),
        labelStyle: const TextStyle(color: GalaxyPalette.text, fontWeight: FontWeight.w600),
        side: const BorderSide(color: GalaxyPalette.border),
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: GalaxyPalette.field,
        hintStyle: const TextStyle(color: GalaxyPalette.textMuted),
        labelStyle: const TextStyle(color: GalaxyPalette.accent),
        prefixIconColor: GalaxyPalette.accent,
        suffixIconColor: GalaxyPalette.accent,
        enabledBorder: field(GalaxyPalette.border),
        focusedBorder: field(GalaxyPalette.primaryGlow, 1.8),
        errorBorder: field(GalaxyPalette.error),
        focusedErrorBorder: field(GalaxyPalette.error, 1.8),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: GalaxyPalette.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: GalaxyPalette.primaryGlow.withValues(alpha: 0.35)),
        ),
        titleTextStyle: const TextStyle(color: GalaxyPalette.text, fontSize: 20, fontWeight: FontWeight.w800),
        contentTextStyle: const TextStyle(color: GalaxyPalette.textMuted, fontSize: 15, height: 1.4),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: GalaxyPalette.card,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: GalaxyPalette.accent,
        modalBarrierColor: Color(0xB305061C),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: GalaxyPalette.cardHigh,
        contentTextStyle: const TextStyle(color: GalaxyPalette.text, fontWeight: FontWeight.w600),
        actionTextColor: GalaxyPalette.star,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: GalaxyPalette.primaryGlow.withValues(alpha: 0.4)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: GalaxyPalette.cardHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: GalaxyPalette.border),
        ),
        textStyle: const TextStyle(color: GalaxyPalette.text),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: GalaxyPalette.accent,
        textColor: GalaxyPalette.text,
        selectedColor: GalaxyPalette.primaryGlow,
        selectedTileColor: GalaxyPalette.cardHigh,
      ),
      cardTheme: CardThemeData(
        color: GalaxyPalette.card,
        surfaceTintColor: Colors.transparent,
        shadowColor: GalaxyPalette.primary.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: GalaxyPalette.border.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
  
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