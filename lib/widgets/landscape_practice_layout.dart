import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Landscape layout shared by every practice screen (tutorial practice and
/// practice sessions, all categories):
///
///   [ demo video ]   [ sign, button, feedback ]   [ camera ]
///
/// The demo and the camera are squares of the SAME size, as large as the
/// height allows while the middle column keeps at least [minMiddle] width.
class LandscapePracticeLayout extends StatelessWidget {
  final Widget demo;
  final Widget middle;
  final Widget camera;
  final double minMiddle;

  const LandscapePracticeLayout({super.key, required this.demo, required this.middle, required this.camera, this.minMiddle = 200});

  static bool isLandscape(BuildContext context) => MediaQuery.orientationOf(context) == Orientation.landscape;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: LayoutBuilder(builder: (context, box) {
        const gap = 14.0;
        final side = math.max(120.0, math.min(box.maxHeight, (box.maxWidth - minMiddle - 2 * gap) / 2));
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: side,
              height: side,
              child: ClipRRect(borderRadius: BorderRadius.circular(16), child: demo),
            ),
            const SizedBox(width: gap),
            // The middle widget scrolls itself (it may be a scroll view).
            Expanded(child: middle),
            const SizedBox(width: gap),
            SizedBox(width: side, height: side, child: camera),
          ],
        );
      }),
    );
  }
}
