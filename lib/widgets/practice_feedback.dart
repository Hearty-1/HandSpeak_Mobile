import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '/providers/language_provider.dart';

/// How a practice feedback message should feel.
enum FeedbackTone {
  /// Instructions / waiting ("Show your hand…").
  info,

  /// The sign was correct.
  success,

  /// Right sign, not clear enough yet.
  almost,

  /// Wrong / not recognised: try again.
  tryAgain,

  /// Something to fix outside the sign (camera, body not visible, internet).
  problem,
}

/// The feedback card under the camera in every tutorial practice (alphabet,
/// numbers, phrases, civic).
///
/// Deaf-friendly: nothing depends on sound. A new result is announced
/// visually (the card pops and its border flashes) and by touch (a phone
/// vibration pattern per result), never only by a sound effect.
///
/// Universal Design for Learning (UDL), multiple means of representation:
/// every result is shown at once as a colour, a distinct icon shape, a word
/// label ("Correct!" / "Tama!", "Almost" / "Malapit na") and a short plain sentence, so it is clear
/// without colour vision, without reading much, or without sound. Messages
/// say what to do next (action), never only what went wrong, and there are
/// no percentages or test details. Screen readers announce the card.
class PracticeFeedback extends StatefulWidget {
  final String message;
  final String? title;
  final FeedbackTone tone;
  final double? width;

  const PracticeFeedback({super.key, required this.message, this.title, this.tone = FeedbackTone.info, this.width});

  static ({Color color, IconData icon, String label}) styleOf(FeedbackTone tone, ThemeData theme) => switch (tone) {
        FeedbackTone.success => (color: const Color(0xFF2E9E4F), icon: Icons.check_circle_rounded, label: L.t('Correct!', 'Tama!')),
        FeedbackTone.almost => (color: const Color(0xFFF08C00), icon: Icons.thumb_up_alt_rounded, label: L.t('Almost', 'Malapit na')),
        FeedbackTone.tryAgain => (color: const Color(0xFFE8590C), icon: Icons.replay_circle_filled_rounded, label: L.t('Try again', 'Subukang muli')),
        FeedbackTone.problem => (color: const Color(0xFFE03131), icon: Icons.warning_rounded, label: L.t('Fix this first', 'Ayusin muna')),
        FeedbackTone.info => (color: theme.primaryColor, icon: Icons.sign_language_rounded, label: L.t('Guide', 'Gabay')),
      };

  /// Maps the old result colours (green / orange / red) to a tone.
  static FeedbackTone toneForColor(Color c) {
    if (c == Colors.greenAccent || c == Colors.green) return FeedbackTone.success;
    if (c == Colors.orange || c == Colors.orangeAccent) return FeedbackTone.almost;
    if (c == Colors.red) return FeedbackTone.problem;
    if (c == Colors.redAccent) return FeedbackTone.tryAgain;
    return FeedbackTone.info;
  }

  @override
  State<PracticeFeedback> createState() => _PracticeFeedbackState();
}

class _PracticeFeedbackState extends State<PracticeFeedback> with SingleTickerProviderStateMixin {
  // Pop + border flash when a new result arrives: the visual "sound".
  late final AnimationController _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void didUpdateWidget(PracticeFeedback old) {
    super.didUpdateWidget(old);
    final changed = old.tone != widget.tone || old.title != widget.title || old.message != widget.message;
    // Only results get attention; plain instructions update quietly.
    if (changed && widget.tone != FeedbackTone.info) {
      _pop.forward(from: 0);
      _vibrate(widget.tone);
    }
  }

  static const MethodChannel _vibrator = MethodChannel('handspeak/vibrate');

  /// A different vibration pattern per result, so it can be felt without
  /// looking ([off, on, off, on…] in ms, played by MainActivity.kt).
  static const Map<FeedbackTone, List<int>> _patterns = {
    FeedbackTone.success: [0, 90, 110, 90], // two short buzzes
    FeedbackTone.almost: [0, 140], // one short buzz
    FeedbackTone.tryAgain: [0, 380], // one long buzz
    FeedbackTone.problem: [0, 380],
  };

  static Future<void> _vibrate(FeedbackTone tone) async {
    final pattern = _patterns[tone];
    if (pattern == null) return;
    try {
      final ok = await _vibrator.invokeMethod<bool>('pattern', {'pattern': pattern});
      if (ok == true) return;
    } catch (_) {
      // No native channel (e.g. iOS): fall back below.
    }
    try {
      await HapticFeedback.vibrate();
    } catch (_) {}
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final style = PracticeFeedback.styleOf(widget.tone, theme);
    final title = widget.title?.trim() ?? '';
    final message = widget.message.trim();
    if (title.isEmpty && message.isEmpty) return const SizedBox.shrink();
    final isResult = widget.tone != FeedbackTone.info;

    return Semantics(
      liveRegion: true,
      container: true,
      label: '${style.label}. ${[title, message].where((t) => t.isNotEmpty).join('. ')}',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _pop,
        builder: (context, child) {
          // 1 -> 1.05 -> 1 scale and a thicker border at the start.
          final t = _pop.isAnimating ? Curves.easeOut.transform(_pop.value) : 1.0;
          final bump = (1 - (2 * t - 1).abs());
          return Transform.scale(
            scale: 1 + 0.05 * bump,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: widget.width ?? MediaQuery.sizeOf(context).width * 0.84,
              padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.12 + 0.10 * bump),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: style.color.withValues(alpha: 0.6 + 0.4 * bump), width: 1.8 + 2.2 * bump),
              ),
              child: child,
            ),
          );
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: style.color.withValues(alpha: 0.18), shape: BoxShape.circle),
              child: Icon(style.icon, color: style.color, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Word label: the result does not rely on colour alone.
                  if (isResult)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: style.color, borderRadius: BorderRadius.circular(8)),
                      child: Text(style.label,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                    ),
                  if (title.isNotEmpty)
                    Text(title,
                        style: TextStyle(
                            color: style.color, fontSize: 17, fontWeight: FontWeight.w900, fontFamily: 'Inter', height: 1.25)),
                  if (title.isNotEmpty && message.isNotEmpty) const SizedBox(height: 3),
                  if (message.isNotEmpty)
                    Text(
                      message,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.9),
                        fontSize: 15,
                        fontWeight: title.isNotEmpty ? FontWeight.w600 : FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
