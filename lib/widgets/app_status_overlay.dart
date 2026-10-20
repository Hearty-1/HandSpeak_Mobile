import 'dart:async';

import 'package:flutter/material.dart';

import '/services/lighting_monitor.dart';
import '/services/offline_sync.dart';

/// App-wide notices on top of every screen (MaterialApp.builder):
///  * offline: progress is kept on the phone and synced later;
///  * "All caught up" once the offline progress reached the server;
///  * low light while a camera screen sees a dark picture.
class AppStatusOverlay extends StatefulWidget {
  final Widget child;
  const AppStatusOverlay({super.key, required this.child});

  @override
  State<AppStatusOverlay> createState() => _AppStatusOverlayState();
}

class _AppStatusOverlayState extends State<AppStatusOverlay> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => LightingMonitor.instance.tick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = ConnectivityService.instance;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 12,
          right: 12,
          top: MediaQuery.paddingOf(context).top + 6,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: Listenable.merge([conn.online, conn.justSynced, LightingMonitor.instance.isDark]),
              builder: (context, _) {
                final notices = <Widget>[
                  if (!conn.online.value)
                    const _Notice(
                      key: ValueKey('offline'),
                      icon: Icons.cloud_off_rounded,
                      color: Color(0xFF5C6BC0),
                      title: "You're offline",
                      text: 'Keep learning! Your progress is saved on this phone and will sync when you are back online.',
                    ),
                  if (conn.online.value && conn.justSynced.value)
                    const _Notice(
                      key: ValueKey('synced'),
                      icon: Icons.cloud_done_rounded,
                      color: Color(0xFF2E9E4F),
                      title: 'All caught up!',
                      text: 'Your progress from offline has been saved.',
                    ),
                  if (LightingMonitor.instance.isDark.value)
                    const _Notice(
                      key: ValueKey('dark'),
                      icon: Icons.light_mode_rounded,
                      color: Color(0xFFF08C00),
                      title: "It's a bit dark",
                      text: 'Turn on a light or face a window so the camera can see your hands.',
                    ),
                ];
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: notices.isEmpty
                      ? const SizedBox.shrink(key: ValueKey('none'))
                      : Column(
                          key: ValueKey(notices.map((n) => n.key).join()),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final n in notices) Padding(padding: const EdgeInsets.only(bottom: 6), child: n),
                          ],
                        ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String text;
  const _Notice({super.key, required this.icon, required this.color, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                  Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
