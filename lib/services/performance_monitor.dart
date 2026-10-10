import 'dart:async';
import 'dart:ui' show FrameTiming, ImageFilter;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// =============================================================================
// PERFORMANCE MODE
// =============================================================================

/// App-wide "Performance Mode": turns off the expensive blur effects
/// (79 BackdropFilters across the app) so the GPU is free for the camera
/// models. Persisted on the device.
class PerformanceSettings {
  PerformanceSettings._();
  static const String _prefKey = 'performance_mode';
  static final ValueNotifier<bool> reduceEffects = ValueNotifier(false);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      reduceEffects.value = prefs.getBool(_prefKey) ?? false;
    } catch (_) {}
  }

  static Future<void> set(bool on) async {
    reduceEffects.value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, on);
    } catch (_) {}
  }
}

/// Drop-in replacement for [BackdropFilter]: in Performance Mode the blur is
/// skipped (the translucent "glass" colour of the child stays).
class SmartBlur extends StatelessWidget {
  final ImageFilter filter;
  final Widget? child;
  final BlendMode blendMode;
  const SmartBlur({super.key, required this.filter, this.child, this.blendMode = BlendMode.srcOver});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PerformanceSettings.reduceEffects,
      builder: (context, reduce, _) => reduce
          ? (child ?? const SizedBox.shrink())
          : BackdropFilter(filter: filter, blendMode: blendMode, child: child),
    );
  }
}

// =============================================================================
// MONITOR
// =============================================================================

enum PerfIssue { slowCamera, slowNetwork, jank }

class PerfStatus {
  final PerfIssue issue;
  final String title;
  final String detail;
  final List<String> tips;
  const PerfStatus(this.issue, this.title, this.detail, this.tips);
}

/// Measures, while the app runs:
///  * camera recognition: results per second and frame-to-result latency
///    (reported by FrameGate / HolisticCapture),
///  * server evaluation time (reported by HandSpeakApiService),
///  * UI smoothness: share of frames slower than 2 vsyncs (FrameTiming).
/// When a problem persists it publishes a [PerfStatus] with tips.
class PerformanceMonitor {
  PerformanceMonitor._();
  static final PerformanceMonitor instance = PerformanceMonitor._();

  /// Current problem to show (null = all good / dismissed).
  final ValueNotifier<PerfStatus?> status = ValueNotifier(null);

  final List<_Sample> _camera = []; // (time, latency ms)
  final List<int> _network = []; // last request durations, ms
  final List<_Frame> _frames = [];
  Timer? _timer;
  bool _started = false;
  final Map<PerfIssue, DateTime> _snoozedUntil = {};
  final Map<PerfIssue, DateTime> _since = {}; // when each problem started

  // Thresholds.
  static const double minCameraFps = 7; // results / s while the camera is used
  static const int maxCameraLatencyMs = 260;
  static const int maxNetworkMs = 4500;
  static const double maxJankRatio = 0.30;
  static const Duration persistFor = Duration(seconds: 4); // ignore short spikes
  static const Duration snooze = Duration(minutes: 3);

  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _evaluate());
  }

  // ------------------------------------------------------------- inputs ---
  /// One camera recognition result arrived [latencyMs] after its frame was sent.
  void reportCameraResult(int latencyMs) {
    _camera.add(_Sample(DateTime.now(), latencyMs));
    if (_camera.length > 120) _camera.removeRange(0, _camera.length - 120);
  }

  /// One server request took [ms].
  void reportNetwork(int ms) {
    _network.add(ms);
    if (_network.length > 5) _network.removeAt(0);
    _evaluate();
  }

  void _onTimings(List<FrameTiming> timings) {
    final now = DateTime.now();
    for (final t in timings) {
      _frames.add(_Frame(now, t.totalSpan.inMilliseconds));
    }
    _frames.removeWhere((f) => now.difference(f.time) > const Duration(seconds: 4));
  }

  /// Hide [issue] for a while (user dismissed it).
  void dismiss(PerfIssue issue) {
    _snoozedUntil[issue] = DateTime.now().add(snooze);
    status.value = null;
  }

  // --------------------------------------------------------- evaluation ---
  void _evaluate() {
    final now = DateTime.now();
    final problems = <PerfIssue, PerfStatus>{};

    // Camera: only judged while results are flowing (a camera screen is open).
    final recent = _camera.where((s) => now.difference(s.time) <= const Duration(seconds: 3)).toList();
    if (recent.length >= 3) {
      final span = now.difference(recent.first.time).inMilliseconds / 1000.0;
      final fps = span <= 0 ? 0.0 : recent.length / span;
      final latency = recent.map((s) => s.latencyMs).reduce((a, b) => a + b) / recent.length;
      if (fps < minCameraFps || latency > maxCameraLatencyMs) {
        problems[PerfIssue.slowCamera] = PerfStatus(
          PerfIssue.slowCamera,
          'Camera is running slowly',
          '${fps.toStringAsFixed(0)} checks per second · ${latency.round()} ms delay',
          [
            if (!PerformanceSettings.reduceEffects.value) 'Turn on Performance Mode to free up your phone for the camera.',
            'Close other apps running in the background.',
            'Turn off Battery Saver, or plug in your phone.',
            'Use bright, even lighting so your hands are easy to see.',
            'Keep your phone cool: performance drops when it gets hot.',
          ],
        );
      }
    }

    // Network: the last two evaluations were slow.
    if (_network.length >= 2 && _network.sublist(_network.length - 2).every((ms) => ms > maxNetworkMs)) {
      final last = _network.last / 1000.0;
      problems[PerfIssue.slowNetwork] = PerfStatus(
        PerfIssue.slowNetwork,
        'Slow internet connection',
        'Checking your sign took ${last.toStringAsFixed(1)} s',
        const [
          'Move closer to your Wi-Fi router, or switch to a stronger network.',
          'Pause downloads, videos or other apps using the internet.',
          'Results still count: please wait for the answer before signing again.',
        ],
      );
    }

    // UI smoothness. Not judged in debug builds: they always render slowly
    // (no AOT), which would raise a false "app is lagging" alarm.
    if (!kDebugMode && _frames.length >= 30) {
      final slow = _frames.where((f) => f.ms > 33).length / _frames.length;
      if (slow > maxJankRatio) {
        problems[PerfIssue.jank] = PerfStatus(
          PerfIssue.jank,
          'The app is lagging',
          '${(slow * 100).round()}% of screen updates are slow',
          [
            if (!PerformanceSettings.reduceEffects.value) 'Turn on Performance Mode to reduce visual effects.',
            'Close other apps running in the background.',
            'Restart HandSpeak if it has been open for a long time.',
            'Free up some storage space on your phone.',
          ],
        );
      }
    }

    // Persistence + snooze, priority camera > network > jank.
    for (final issue in PerfIssue.values) {
      if (problems.containsKey(issue)) {
        _since.putIfAbsent(issue, () => now);
      } else {
        _since.remove(issue);
      }
    }
    PerfStatus? show;
    for (final issue in PerfIssue.values) {
      final p = problems[issue];
      if (p == null) continue;
      final snoozed = _snoozedUntil[issue];
      if (snoozed != null && now.isBefore(snoozed)) continue;
      final persistent = issue == PerfIssue.slowNetwork || now.difference(_since[issue]!) >= persistFor;
      if (persistent) {
        show = p;
        break;
      }
    }
    // Keep a visible banner until its problem clears; don't flicker.
    final current = status.value;
    if (current != null && problems.containsKey(current.issue)) {
      status.value = problems[current.issue];
    } else {
      status.value = show;
    }
  }

  void dispose() {
    _timer?.cancel();
    if (_started) SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _started = false;
  }
}

class _Sample {
  final DateTime time;
  final int latencyMs;
  _Sample(this.time, this.latencyMs);
}

class _Frame {
  final DateTime time;
  final int ms;
  _Frame(this.time, this.ms);
}

// =============================================================================
// FEEDBACK BANNER
// =============================================================================

/// Wrap the app (MaterialApp.builder) with this: shows a compact banner at
/// the top when the monitor detects lag; tap to see tips, one tap to turn on
/// Performance Mode, or dismiss for a few minutes.
class PerformanceHintOverlay extends StatefulWidget {
  final Widget child;
  const PerformanceHintOverlay({super.key, required this.child});

  @override
  State<PerformanceHintOverlay> createState() => _PerformanceHintOverlayState();
}

class _PerformanceHintOverlayState extends State<PerformanceHintOverlay> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    PerformanceMonitor.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<PerfStatus?>(
          valueListenable: PerformanceMonitor.instance.status,
          builder: (context, status, _) {
            if (status == null) _expanded = false;
            return Positioned(
              left: 12,
              right: 12,
              top: MediaQuery.of(context).padding.top + 8,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, a) => SlideTransition(
                  position: Tween(begin: const Offset(0, -1.2), end: Offset.zero)
                      .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
                  child: FadeTransition(opacity: a, child: child),
                ),
                child: status == null ? const SizedBox.shrink() : _banner(context, status),
              ),
            );
          },
        ),
      ],
    );
  }

  IconData _icon(PerfIssue i) => switch (i) {
        PerfIssue.slowCamera => Icons.videocam_off_rounded,
        PerfIssue.slowNetwork => Icons.wifi_tethering_error_rounded,
        PerfIssue.jank => Icons.speed_rounded,
      };

  Widget _banner(BuildContext context, PerfStatus s) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const amber = Color(0xFFFFB020);
    final bg = isDark ? const Color(0xF21E1B3A) : const Color(0xF7FFFFFF);
    final text = isDark ? Colors.white : const Color(0xFF2A2340);
    final perfOn = PerformanceSettings.reduceEffects.value;

    return Material(
      key: ValueKey(s.issue),
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: amber.withValues(alpha: 0.6), width: 1.2),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: amber.withValues(alpha: 0.18), shape: BoxShape.circle),
                    child: Icon(_icon(s.issue), color: amber, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.title, style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 14)),
                      Text(_expanded ? s.detail : '${s.detail} · tap for tips',
                          style: TextStyle(color: text.withValues(alpha: 0.65), fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  // No tooltip: this banner sits above the Navigator's Overlay.
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 18, color: text.withValues(alpha: 0.6)),
                    onPressed: () => PerformanceMonitor.instance.dismiss(s.issue),
                  ),
                ]),
                if (_expanded) ...[
                  const SizedBox(height: 8),
                  for (final tip in s.tips)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6, right: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 5, right: 8),
                          child: Icon(Icons.circle, size: 6, color: amber),
                        ),
                        Expanded(child: Text(tip, style: TextStyle(color: text.withValues(alpha: 0.85), fontSize: 12.5, height: 1.35))),
                      ]),
                    ),
                  if (!perfOn && s.issue != PerfIssue.slowNetwork)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, right: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: amber,
                            foregroundColor: const Color(0xFF2A2340),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            PerformanceSettings.set(true);
                            PerformanceMonitor.instance.dismiss(s.issue);
                          },
                          icon: const Icon(Icons.bolt_rounded, size: 18),
                          label: const Text('Turn on Performance Mode', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
