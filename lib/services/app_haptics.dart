import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One haptic vocabulary for the whole app, following the platform guidelines
/// (Apple HIG / Android haptics): each meaning always feels the same, light
/// for small events, heavy only for errors, a celebration only for rare
/// rewards, and never the long generic buzz.
///
///   selection  taps, tabs, toggles, pickers
///   correct    a correct answer / correct sign
///   wrong      a wrong answer, a heart lost, a sign not accepted
///   tick       countdown numbers, the last seconds of a timer
///   recordStart / recordStop   the camera starts / stops recording
///   celebrate  level complete, badge unlocked, level up (rare)
///   failed     level failed (no hearts left)
///
/// Always paired with something on screen (haptics are never the only cue).
/// Settings > Vibration turns them all off ([enabled], saved on the phone).
class AppHaptics {
  AppHaptics._();

  static const String _key = 'haptics_enabled';

  /// Settings > Vibration (on by default).
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled.value = p.getBool(_key) ?? true;
    } catch (_) {}
  }

  static Future<void> set(bool on) async {
    enabled.value = on;
    if (on) selection();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, on);
    } catch (_) {}
  }

  static bool get _on => enabled.value;

  /// Real vibration through MainActivity.kt ("handspeak/vibrate"), the same
  /// channel the practice feedback uses. Flutter's HapticFeedback goes through
  /// the system "touch feedback" setting, which many Android phones have off
  /// or very weak, so it is only the fallback (and the iOS path).
  static const MethodChannel _vibrator = MethodChannel('handspeak/vibrate');

  /// [pattern]: [off, on, off, on...] in ms; [fallback]: HapticFeedback call.
  /// Pulses are at least 40 ms: shorter ones (12-30 ms) are too weak for
  /// most phone motors to be felt, while the practice card's 90-380 ms are.
  static Future<void> _play(List<int> pattern, void Function() fallback) async {
    if (!_on) {
      debugPrint('AppHaptics: skipped $pattern (Settings > Vibration is off)');
      return;
    }
    try {
      final ok = await _vibrator.invokeMethod<bool>('pattern', {'pattern': pattern});
      debugPrint('AppHaptics: $pattern -> native $ok');
      if (ok == true) return;
    } catch (e) {
      debugPrint('AppHaptics: $pattern -> native error $e');
    }
    try {
      fallback();
    } catch (_) {}
  }

  static void selection() => _play(const [0, 40], HapticFeedback.selectionClick);

  static void correct() => _play(const [0, 100], HapticFeedback.mediumImpact);

  static void wrong() => _play(const [0, 300], HapticFeedback.heavyImpact);

  static void tick() => _play(const [0, 50], HapticFeedback.lightImpact);

  static void recordStart() => _play(const [0, 120], HapticFeedback.mediumImpact);

  static void recordStop() => _play(const [0, 70], HapticFeedback.lightImpact);

  /// Rare rewards only: a short double pulse.
  static Future<void> celebrate() => _play(const [0, 90, 110, 90], HapticFeedback.heavyImpact);

  static void failed() => _play(const [0, 500], HapticFeedback.heavyImpact);
}
