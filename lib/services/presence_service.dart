import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Online status of players (the green dot on avatars).
///
/// While the app is open and in the foreground, the signed-in user's
/// document gets `online: true` and a `lastSeenAt` heartbeat every minute;
/// going to the background or signing out writes `online: false`. A player
/// counts as online only while `online` is true AND the heartbeat is fresh,
/// so a phone that crashed or lost its connection turns grey by itself
/// after [staleAfter].
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  static const Duration heartbeat = Duration(seconds: 60);
  static const Duration staleAfter = Duration(minutes: 3);

  Timer? _timer;
  StreamSubscription<User?>? _auth;
  String? _uid;
  bool _foreground = true;

  void start() {
    if (_auth != null) return;
    WidgetsBinding.instance.addObserver(this);
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      final old = _uid;
      if (old != null && old != user?.uid) _write(old, false); // signed out / switched
      _uid = (user == null || user.isAnonymous) ? null : user.uid;
      _restart();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    final uid = _uid;
    if (uid == null) return;
    if (!_foreground) {
      _write(uid, false);
      return;
    }
    _write(uid, true);
    _timer = Timer.periodic(heartbeat, (_) {
      final u = _uid;
      if (u != null && _foreground) _write(u, true);
    });
  }

  /// Call before signing out (afterwards the write is no longer allowed).
  Future<void> goOffline() async {
    _timer?.cancel();
    final uid = _uid;
    _uid = null;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'online': false, 'lastSeenAt': FieldValue.serverTimestamp()}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  static void _write(String uid, bool online) {
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'online': online, 'lastSeenAt': FieldValue.serverTimestamp()}, SetOptions(merge: true))
        .catchError((Object e) => debugPrint('Presence not saved: $e'));
  }

  /// Whether the player of user document [d] is online now.
  static bool isOnline(Map<String, dynamic>? d) {
    if (d == null || d['online'] != true) return false;
    final t = d['lastSeenAt'];
    // A write still pending on this phone has no server time yet: fresh.
    if (t == null) return true;
    if (t is! Timestamp) return false;
    return DateTime.now().difference(t.toDate()) < staleAfter;
  }
}

/// [child] (an avatar) with a green dot at its lower right while [online].
class OnlineBadge extends StatelessWidget {
  final Widget child;
  final bool online;

  /// Diameter of the avatar, to size and place the dot.
  final double size;
  const OnlineBadge({super.key, required this.child, required this.online, required this.size});

  @override
  Widget build(BuildContext context) {
    if (!online) return child;
    final dot = (size * 0.26).clamp(10.0, 22.0);
    final ring = Theme.of(context).cardColor;
    // On the circle's edge at 45° (lower right).
    final inset = size * 0.146 - dot / 2;
    return Stack(clipBehavior: Clip.none, children: [
      child,
      Positioned(
        right: inset,
        bottom: inset,
        child: Semantics(
          label: 'Online',
          child: Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: const Color(0xFF22A06B),
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: (dot * 0.18).clamp(2.0, 4.0)),
            ),
          ),
        ),
      ),
    ]);
  }
}
