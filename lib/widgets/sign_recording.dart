import 'dart:async';

import 'package:flutter/material.dart';

import '/providers/language_provider.dart';

/// Record-then-check for moving signs in the camera activities (alphabet
/// J / Z, numbers 11-100): RECORD SIGN -> 3-2-1 countdown -> the sign is
/// recorded for [recordSeconds] -> it is checked. Only the frames of the
/// recording are judged, so the movement is checked from start to end and
/// nothing before the tap counts. Static signs keep CAPTURE & CHECK.
class SignRecordingController {
  SignRecordingController({required this.onChanged, this.countdownSeconds = 3, this.recordSeconds = 3.0});

  /// Called on every step (rebuild the screen).
  final VoidCallback onChanged;
  final int countdownSeconds;
  final double recordSeconds;

  int countdown = 0;
  bool recording = false;

  /// Share of the recording done (0-1).
  double progress = 0;

  Timer? _timer;
  DateTime? _start;

  bool get busy => countdown > 0 || recording;

  /// Starts the countdown; [onRecordingStarted] when the recording starts
  /// (clear old frames there), [onDone] when it ends (check the sign).
  void start({required VoidCallback onRecordingStarted, required VoidCallback onDone}) {
    if (busy) return;
    countdown = countdownSeconds;
    progress = 0;
    onChanged();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      countdown--;
      if (countdown > 0) {
        onChanged();
        return;
      }
      t.cancel();
      recording = true;
      _start = DateTime.now();
      onRecordingStarted();
      onChanged();
      _timer = Timer.periodic(const Duration(milliseconds: 50), (t) {
        final s = DateTime.now().difference(_start!).inMilliseconds / 1000.0;
        progress = (s / recordSeconds).clamp(0.0, 1.0);
        if (s >= recordSeconds) {
          t.cancel();
          recording = false;
          progress = 0;
          onChanged();
          onDone();
        } else {
          onChanged();
        }
      });
    });
  }

  /// Stops without checking (question changed, screen closed).
  void cancel() {
    _timer?.cancel();
    _timer = null;
    countdown = 0;
    recording = false;
    progress = 0;
  }

  void dispose() => cancel();
}

/// Status line under the camera for a moving sign: the countdown, the
/// recording bar, or what to do.
class SignRecordingStatus extends StatelessWidget {
  final SignRecordingController controller;
  final String sign;
  final bool checking;
  final bool handsVisible;

  const SignRecordingStatus({
    super.key,
    required this.controller,
    required this.sign,
    required this.checking,
    required this.handsVisible,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (controller.countdown > 0) {
      return Column(
        children: [
          Text(L.t('Get ready...', 'Humanda...'),
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w700, fontSize: 15)),
          Text('${controller.countdown}',
              style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.w900, fontSize: 44, height: 1.1)),
        ],
      );
    }
    if (controller.recording) {
      return Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fiber_manual_record_rounded, color: Colors.redAccent, size: 18),
              const SizedBox(width: 6),
              Text(L.t('Recording - sign "$sign" now', 'Nagre-record - ikumpas ang "$sign"'),
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 220,
              height: 14,
              child: LinearProgressIndicator(
                value: controller.progress,
                backgroundColor: theme.dividerColor,
                color: Colors.redAccent,
              ),
            ),
          ),
        ],
      );
    }
    final text = checking
        ? L.t('Checking your "$sign"...', 'Sinusuri ang "$sign"...')
        : (handsVisible
            ? L.t('Tap RECORD SIGN, then do the whole "$sign" sign.', 'Pindutin ang RECORD SIGN, saka gawin ang buong "$sign".')
            : L.t('Position your hand in the frame, then tap RECORD SIGN.', 'Ilagay ang kamay sa frame, saka pindutin ang RECORD SIGN.'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: handsVisible ? theme.primaryColor.withValues(alpha: 0.12) : theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: handsVisible ? theme.primaryColor : theme.dividerColor, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          checking
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.primaryColor))
              : Icon(Icons.videocam_rounded, color: handsVisible ? theme.primaryColor : Colors.grey, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text,
                style: TextStyle(
                    color: handsVisible ? theme.primaryColor : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

/// Label of the main button for a moving sign.
String signRecordingButtonLabel(SignRecordingController c, {required bool checking}) {
  if (checking) return L.t('CHECKING...', 'SINUSURI...');
  if (c.countdown > 0) return L.t('GET READY... ${c.countdown}', 'HUMANDA... ${c.countdown}');
  if (c.recording) return L.t('RECORDING...', 'NAGRE-RECORD...');
  return L.t('RECORD SIGN', 'I-RECORD ANG KUMPAS');
}
