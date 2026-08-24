import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { defaultWarm, light, dark, system }

class ThemeProvider extends ChangeNotifier {
  static const String _themePrefKey = "user_app_theme";
  
  AppThemeMode _themeMode = AppThemeMode.defaultWarm;

  AppThemeMode get themeMode => _themeMode;

  String get themeString {
    switch (_themeMode) {
      case AppThemeMode.light:
        return "Light Theme";
      case AppThemeMode.dark:
        return "Dark Theme";
      case AppThemeMode.system:
        return "System Default";
      case AppThemeMode.defaultWarm:
      default:
        return "Default Theme";
    }
  }

  ThemeProvider() {
    _loadThemeFromPrefs();
  }

  void setThemeFromString(String themeName) {
    switch (themeName) {
      case "Light Theme":
        setTheme(AppThemeMode.light);
        break;
      case "Dark Theme":
        setTheme(AppThemeMode.dark);
        break;
      case "System Default":
        setTheme(AppThemeMode.system);
        break;
      case "Default Theme":
      default:
        setTheme(AppThemeMode.defaultWarm);
        break;
    }
  }

  void setTheme(AppThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePrefKey, mode.toString());
  }

  void _loadThemeFromPrefs() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedTheme = prefs.getString(_themePrefKey);
    if (savedTheme != null) {
      _themeMode = AppThemeMode.values.firstWhere(
        (e) => e.toString() == savedTheme,
        orElse: () => AppThemeMode.defaultWarm,
      );
      notifyListeners();
    }
  }

  // --- THEME DATA DEFINITIONS ---

  // 1. Default Theme (Original Warm Aesthetic)
  static final ThemeData defaultWarmTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFFFF9E5),
    primaryColor: const Color(0xFFFFB800),
    cardColor: Colors.white,
    dividerColor: Colors.black12,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFFFFB800),
      surface: Colors.white,
      onSurface: Colors.black87,
      onBackground: Colors.black87,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.black87),
      titleTextStyle: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 20),
    ),
  );

  // 2. Light Theme (Standard Clean White)
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF8F9FA),
    primaryColor: const Color(0xFFFFB800),
    cardColor: Colors.white,
    dividerColor: Colors.black12,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFFFFB800),
      surface: Colors.white,
      onSurface: Colors.black87,
      onBackground: Colors.black87,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.black87),
      titleTextStyle: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 20),
    ),
  );

  // 3. Dark Theme (Modern Dark Mode)
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF121212),
    primaryColor: const Color(0xFFFFB800),
    cardColor: const Color(0xFF1E1E1E),
    dividerColor: Colors.white12,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFFFB800),
      surface: Color(0xFF1E1E1E),
      onSurface: Colors.white,
      onBackground: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
    ),
  );

  // Get current active theme
  ThemeData get activeTheme {
    switch (_themeMode) {
      case AppThemeMode.light:
        return lightTheme;
      case AppThemeMode.dark:
        return darkTheme;
      case AppThemeMode.defaultWarm:
      default:
        return defaultWarmTheme;
    }
  }

  // Get current active theme mode for Flutter MaterialApp
  ThemeMode get activeThemeMode {
    if (_themeMode == AppThemeMode.system) {
      return ThemeMode.system;
    }
    return ThemeMode.light; // Controlled via dynamic ThemeData insertion
  }
}