import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Watches camera brightness for every camera screen (they call [onImage]
/// from their image stream). [isDark] turns true after the picture has been
/// too dark for a moment (hand tracking gets unreliable), and false again
/// once it is bright enough; the app-wide warning (widgets/app_status_overlay)
/// shows it. A screen that stops sending frames clears the warning.
class LightingMonitor {
  LightingMonitor._();
  static final LightingMonitor instance = LightingMonitor._();

  final ValueNotifier<bool> isDark = ValueNotifier<bool>(false);

  // Mean luma (0-255) below which the picture counts as dark, and the level
  // it must reach again to clear the warning (hysteresis: no flicker).
  static const double _darkBelow = 55;
  static const double _okAbove = 70;
  static const int _darkForMs = 1500;
  static const int _sampleEveryMs = 400;

  int _lastSampleMs = 0;
  int _darkSinceMs = 0;
  int _lastFrameMs = 0;
  double lastBrightness = 128;

  /// Cheap: samples ~1 in 40 pixels of the Y (brightness) plane a few times a
  /// second. Works for YUV (Android) and BGRA (iOS) frames.
  void onImage(CameraImage image) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastFrameMs = now;
    if (now - _lastSampleMs < _sampleEveryMs) return;
    _lastSampleMs = now;
    try {
      final plane = image.planes.first;
      final bytes = plane.bytes;
      if (bytes.isEmpty) return;
      final bgra = image.format.group == ImageFormatGroup.bgra8888;
      final step = bgra ? 4 * 37 : 37;
      int sum = 0, n = 0;
      for (int i = 0; i < bytes.length; i += step) {
        if (bgra) {
          if (i + 2 >= bytes.length) break;
          sum += (bytes[i] * 29 + bytes[i + 1] * 150 + bytes[i + 2] * 77) >> 8; // B, G, R
        } else {
          sum += bytes[i];
        }
        n++;
      }
      if (n == 0) return;
      lastBrightness = sum / n;
      if (lastBrightness < _darkBelow) {
        if (_darkSinceMs == 0) _darkSinceMs = now;
        if (!isDark.value && now - _darkSinceMs >= _darkForMs) isDark.value = true;
      } else {
        _darkSinceMs = 0;
        if (isDark.value && lastBrightness > _okAbove) isDark.value = false;
      }
    } catch (_) {}
  }

  /// No frames for a while (camera closed): drop the warning.
  void tick() {
    if (isDark.value && DateTime.now().millisecondsSinceEpoch - _lastFrameMs > 2000) {
      isDark.value = false;
      _darkSinceMs = 0;
    }
  }
}
