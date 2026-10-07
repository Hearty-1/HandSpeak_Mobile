import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/services/performance_monitor.dart';

/// One tab of [AppNavBar].
class AppNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const AppNavItem({required this.icon, required this.activeIcon, required this.label});
}

/// Floating, frosted-glass tab bar in the style of iOS (blurred capsule,
/// tinted icon + small label, selection haptic, springy highlight).
///
/// Responsive by construction instead of fixed sizes:
///  * every tab is an [Expanded] slot, so the bar fits any width (small
///    phones, large display-size / font settings, tablets: capped at 520 dp
///    and centred);
///  * the system text scale is clamped inside the bar so labels never wrap
///    or overflow;
///  * the bottom gap follows the device's real inset (gesture pill or the
///    3-button navigation bar, e.g. Tecno HiOS) via [MediaQuery.viewPadding],
///    so the bar never sits under or on top of the system buttons.
///
/// Use as `Scaffold(extendBody: true, bottomNavigationBar: AppNavBar(...))`.
class AppNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<AppNavItem> items;

  const AppNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.items = defaultItems,
  });

  static const List<AppNavItem> defaultItems = [
    AppNavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
    AppNavItem(icon: Icons.auto_stories_outlined, activeIcon: Icons.auto_stories_rounded, label: 'Learn'),
    AppNavItem(icon: Icons.sports_esports_outlined, activeIcon: Icons.sports_esports_rounded, label: 'Arena'),
    AppNavItem(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = mq.size.width;

    // Proportional sizing, clamped to sensible limits.
    final sideMargin = (width * 0.045).clamp(10.0, 24.0);
    final barHeight = (width * 0.17).clamp(58.0, 68.0);
    final bottomInset = mq.viewPadding.bottom;
    // Gesture pill / 3-button bar: sit just above it; no inset: small gap.
    final bottomGap = bottomInset > 0 ? bottomInset + 4.0 : 12.0;

    final tint = theme.colorScheme.primary;
    final idle = theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.55 : 0.5);

    return MediaQuery(
      // Labels follow the user's font size, but never so large that they break the bar.
      data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(sideMargin, 0, sideMargin, bottomGap),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              height: barHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(barHeight / 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(barHeight / 2),
                child: SmartBlur(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: (isDark ? const Color(0xFF1C1C1E) : Colors.white)
                          .withValues(alpha: isDark ? 0.72 : 0.78),
                      borderRadius: BorderRadius.circular(barHeight / 2),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.6),
                        width: 0.8,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Row(
                        children: [
                          for (int i = 0; i < items.length; i++)
                            Expanded(
                              child: _NavTab(
                                item: items[i],
                                selected: i == currentIndex,
                                tint: tint,
                                idle: idle,
                                isDark: isDark,
                                onTap: () {
                                  if (i == currentIndex) return;
                                  HapticFeedback.selectionClick();
                                  onTap(i);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final AppNavItem item;
  final bool selected;
  final Color tint;
  final Color idle;
  final bool isDark;
  final VoidCallback onTap;

  const _NavTab({
    required this.item,
    required this.selected,
    required this.tint,
    required this.idle,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? tint : idle;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // the whole slot is tappable
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          decoration: BoxDecoration(
            color: selected ? tint.withValues(alpha: isDark ? 0.22 : 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              // Icon and label scale with the slot, then FittedBox guarantees
              // nothing overflows on very small or zoomed screens.
              final iconSize = (c.maxHeight * 0.44).clamp(20.0, 26.0);
              return Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedScale(
                          scale: selected ? 1.08 : 1.0,
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutBack,
                          child: Icon(selected ? item.activeIcon : item.icon, size: iconSize, color: color),
                        ),
                        const SizedBox(height: 2),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.1,
                            letterSpacing: 0.1,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: color,
                          ),
                          child: Text(item.label, maxLines: 1),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
