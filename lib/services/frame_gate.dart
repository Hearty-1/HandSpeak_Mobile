import 'performance_monitor.dart';

/// Limits how many camera frames are in the hand_landmarker plugin at once.
///
/// The plugin copies the three YUV planes (~700 KB) on the UI isolate for
/// every frame and hands them to MediaPipe in LIVE_STREAM mode, which drops
/// whatever it cannot keep up with. Feeding all 30 camera fps wasted most of
/// those copies on the thread that draws the UI.
///
/// LIVE_STREAM pipelines frames internally (palm detection of one frame runs
/// while another is in the landmark stage), so allowing ONLY one frame in
/// flight lowered the result rate and broke motion-based checks (dynamic
/// numbers: the movement was never detected). [maxInFlight] = 3 keeps the
/// pipeline full (same result rate as before) while still skipping the
/// frames MediaPipe would have dropped anyway.
class FrameGate {
  final int maxInFlight;

  /// A frame whose result never arrives (dropped / paused stream) stops
  /// counting as in flight after this long.
  final Duration timeout;

  FrameGate({this.maxInFlight = 3, this.timeout = const Duration(milliseconds: 500)});

  final List<DateTime> _inFlight = []; // send times, oldest first (results come back in order)

  /// True (and marks a frame in flight) when a new frame may be sent.
  bool tryEnter() {
    final now = DateTime.now();
    _inFlight.removeWhere((t) => now.difference(t) > timeout);
    if (_inFlight.length >= maxInFlight) return false;
    _inFlight.add(now);
    return true;
  }

  /// Call when a result (even an empty one) arrives from the landmarker.
  void done() {
    if (_inFlight.isEmpty) return;
    final sent = _inFlight.removeAt(0);
    PerformanceMonitor.instance.reportCameraResult(DateTime.now().difference(sent).inMilliseconds);
  }
}
