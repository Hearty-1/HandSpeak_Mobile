import 'package:flutter/material.dart';

/// Sizing shared by every screen, so the app looks right on small phones,
/// large phones, foldables and tablets.
///
/// Screens are designed at 393 dp wide (a typical phone). [scale] grows or
/// shrinks sizes with the width, but only within [minScale]-[maxScale]: very
/// small phones do not get unreadable text, tablets do not get giant UI.
class Responsive {
  static const double designWidth = 393;
  static const double minScale = 0.75; // 320-wide phones: ~0.81
  static const double maxScale = 1.25;

  /// Widest the app content gets on tablets / landscape (a centered column).
  static const double maxContentWidth = 600;

  /// Size factor for a [width] (e.g. constraints.maxWidth).
  static double scale(double width) => (width / designWidth).clamp(minScale, maxScale).toDouble();

  /// Size factor of the current screen.
  static double of(BuildContext context) => scale(MediaQuery.sizeOf(context).width);

  static bool isTablet(BuildContext context) => MediaQuery.sizeOf(context).shortestSide >= 600;
}

/// Wraps the whole app (MaterialApp.builder):
/// - system font size limited to 0.85x-1.3x, so very large accessibility
///   fonts do not break cards and buttons (still bigger, just bounded);
/// - on tablets in portrait, the app is a centered column of
///   [Responsive.maxContentWidth] instead of being stretched edge to edge.
class ResponsiveApp extends StatelessWidget {
  final Widget child;
  const ResponsiveApp({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Small / narrow phones get a lower cap: a large system font there made
    // dialogs and cards too big for the screen.
    final small = mq.size.shortestSide < 360;
    final text = mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: small ? 1.1 : 1.3);
    Widget app = MediaQuery(data: mq.copyWith(textScaler: text), child: child);

    final size = mq.size;
    final tabletPortrait = size.shortestSide >= 600 && size.height > size.width;
    if (tabletPortrait && size.width > Responsive.maxContentWidth) {
      final w = Responsive.maxContentWidth;
      app = ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: SizedBox(
            width: w,
            // The column reports its own width to the screens inside.
            child: MediaQuery(
              data: mq.copyWith(textScaler: text, size: Size(w, size.height)),
              child: ClipRect(child: child),
            ),
          ),
        ),
      );
    }
    return app;
  }
}
