import 'package:flutter/material.dart';

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
/// numbers, phrases): one consistent, child-friendly look: a soft tinted card,
/// a big friendly icon, a short bold title and one line of advice. No
/// percentages or test details.
class PracticeFeedback extends StatelessWidget {
  final String message;
  final String? title;
  final FeedbackTone tone;
  final double? width;

  const PracticeFeedback({super.key, required this.message, this.title, this.tone = FeedbackTone.info, this.width});

  static ({Color color, IconData icon}) styleOf(FeedbackTone tone, ThemeData theme) => switch (tone) {
        FeedbackTone.success => (color: const Color(0xFF2E9E4F), icon: Icons.check_circle_rounded),
        FeedbackTone.almost => (color: const Color(0xFFF08C00), icon: Icons.thumb_up_alt_rounded),
        FeedbackTone.tryAgain => (color: const Color(0xFFE8590C), icon: Icons.replay_circle_filled_rounded),
        FeedbackTone.problem => (color: const Color(0xFFE03131), icon: Icons.info_rounded),
        FeedbackTone.info => (color: theme.primaryColor, icon: Icons.lightbulb_rounded),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final style = styleOf(tone, theme);
    final hasTitle = title != null && title!.trim().isNotEmpty;
    final hasMessage = message.trim().isNotEmpty;
    if (!hasTitle && !hasMessage) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: width ?? MediaQuery.sizeOf(context).width * 0.82,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: style.color.withValues(alpha: 0.55), width: 1.6),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: style.color.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Icon(style.icon, color: style.color, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasTitle)
                  Text(title!,
                      style: TextStyle(color: style.color, fontSize: 16, fontWeight: FontWeight.w900, fontFamily: 'Inter', height: 1.2)),
                if (hasTitle && hasMessage) const SizedBox(height: 2),
                if (hasMessage)
                  Text(
                    message,
                    style: TextStyle(
                      color: hasTitle ? textColor.withValues(alpha: 0.8) : (tone == FeedbackTone.info ? textColor.withValues(alpha: 0.85) : style.color),
                      fontSize: 14,
                      fontWeight: hasTitle ? FontWeight.w600 : FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
