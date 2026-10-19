import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who is using the app.
///
///  * [student]  – signs in with an approved account; full access (as before).
///  * [faculty]  – enters like a guest (no sign-in); learning content only.
///  * [parent]   – enters like a guest (no sign-in); learning content only.
enum UserRole {
  student('Student', Icons.school_rounded),
  faculty('Faculty', Icons.co_present_rounded),
  parent('Parent', Icons.family_restroom_rounded);

  final String label;
  final IconData icon;
  const UserRole(this.label, this.icon);

  /// Roles that browse without an account.
  bool get isGuest => this != UserRole.student;
}

/// Every gated part of the app. Add new features here and list them in
/// [RoleProvider._permissions].
enum AppFeature {
  /// Module tutorials, including the practice inside each tutorial lesson.
  tutorials,

  /// The module "Practice" (Train Sign) stage.
  practice,

  /// Module activities (difficulty selection + every activity screen).
  activities,

  /// Challenges, the Arena, rankings and daily quests.
  challenges,

  /// XP, stars, streaks, levels and module unlock progress.
  progress,

  /// Student profile, friends and avatar.
  profile,

  /// In-app notifications bell and notification settings.
  notifications,

  /// Account settings: personal details, password, session logs.
  account,
}

/// Role-based access control (RBAC) for HandSpeak.
///
/// The permission matrix lives in one place ([_permissions]) so access can be
/// changed without touching any screen. Screens ask `roles.can(feature)`; the
/// navigation guard [RoleGuard] enforces the same rules on the screens
/// themselves, so a hidden button is never the only protection.
class RoleProvider extends ChangeNotifier {
  static const String _guestRoleKey = 'guest_role';

  /// What each role may open. Students can do everything.
  static final Map<UserRole, Set<AppFeature>> _permissions = {
    UserRole.student: {...AppFeature.values},
    // Faculty and Parent: module tutorials and practice only. No activities.
    UserRole.faculty: {AppFeature.tutorials, AppFeature.practice},
    UserRole.parent: {AppFeature.tutorials, AppFeature.practice},
  };

  UserRole? _guestRole;

  /// A real (email / Google) student login. Faculty / Parent use an
  /// ANONYMOUS Firebase session: it only provides the ID token the sign
  /// recognition server and Firebase Storage templates need, and never counts
  /// as a student account (no XP, progress or analytics are written for it).
  static bool get hasStudentAccount {
    final u = FirebaseAuth.instance.currentUser;
    return u != null && !u.isAnonymous;
  }

  /// Loads a remembered Faculty / Parent choice (call before `runApp`).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_guestRoleKey);
    _guestRole = UserRole.values.where((r) => r.isGuest && r.name == saved).firstOrNull;
    _activeGuest = _guestRole;
    if (_guestRole != null) unawaited(_ensureGuestSession());
  }

  /// The Faculty / Parent role in use (static, for services without a
  /// BuildContext such as HandSpeakApiService).
  static UserRole? _activeGuest;

  /// Anonymous Firebase session for a guest, so camera recognition works
  /// (the Cloud Run server requires a Firebase ID token). Needs the
  /// Anonymous provider enabled in Firebase Authentication; if it is not
  /// (firebase_auth/admin-restricted-operation), the guest still browses,
  /// but server-scored signs report that guest checking is not enabled.
  /// Returns true when a Firebase session exists afterwards.
  static Future<bool> ensureGuestSession() async {
    if (FirebaseAuth.instance.currentUser != null) return true;
    if (_activeGuest == null) return false;
    try {
      await FirebaseAuth.instance.signInAnonymously();
      return FirebaseAuth.instance.currentUser != null;
    } catch (e) {
      debugPrint('Guest (anonymous) sign-in failed: $e');
      return false;
    }
  }

  /// A Faculty / Parent guest is using the app (no student login).
  static bool get guestActive => _activeGuest != null && !hasStudentAccount;

  Future<void> _ensureGuestSession() => ensureGuestSession();

  /// The active role. A student login always wins, so a remembered guest
  /// choice can never downgrade (or upgrade) a real account.
  /// `null` means nobody has chosen a role yet: nothing is permitted.
  UserRole? get role {
    if (hasStudentAccount) return UserRole.student;
    return _guestRole;
  }

  bool get isStudent => role == UserRole.student;

  /// Faculty / Parent browsing without an account.
  bool get isGuest => role?.isGuest ?? false;

  /// Display name for the active role ("Faculty", "Parent", "Student").
  String get roleLabel => role?.label ?? 'Guest';

  bool can(AppFeature feature) {
    final r = role;
    return r != null && (_permissions[r]?.contains(feature) ?? false);
  }

  /// Picks Faculty or Parent (guest access) and remembers it for next launch.
  /// Choosing Student does not store anything: the account login decides.
  Future<void> chooseRole(UserRole chosen) async {
    _guestRole = chosen.isGuest ? chosen : null;
    _activeGuest = _guestRole;
    final prefs = await SharedPreferences.getInstance();
    if (_guestRole == null) {
      await prefs.remove(_guestRoleKey);
      // Leaving guest mode ends the anonymous session (a student logs in next).
      if (FirebaseAuth.instance.currentUser?.isAnonymous ?? false) {
        await FirebaseAuth.instance.signOut();
      }
    } else {
      await prefs.setString(_guestRoleKey, chosen.name);
      await _ensureGuestSession();
    }
    notifyListeners();
  }

  /// Leaves guest mode (used by "Change Role" and by sign out).
  Future<void> clear() => chooseRole(UserRole.student);
}

/// Shorthand: `context.roles.can(AppFeature.activities)` (rebuilds on change).
extension RoleContext on BuildContext {
  RoleProvider get roles => watch<RoleProvider>();
  RoleProvider get rolesRead => read<RoleProvider>();
}

/// Wraps a screen and shows an "access restricted" page instead of it when
/// the current role may not open [feature].
class RoleGuard extends StatelessWidget {
  final AppFeature feature;
  final Widget child;

  const RoleGuard({super.key, required this.feature, required this.child});

  @override
  Widget build(BuildContext context) {
    if (context.roles.can(feature)) return child;
    return const AccessRestrictedScreen();
  }
}

/// Under Tutorial + Practice in a module, for Faculty / Parent (who have no
/// Activity / Challenges section there): how to learn with the module.
class GuestModuleGuide extends StatelessWidget {
  final double scale;
  const GuestModuleGuide({super.key, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    const steps = [
      (Icons.play_circle_rounded, 'Watch the tutorial', 'See each sign slowly, as often as you like.'),
      (Icons.videocam_rounded, 'Practise on camera', 'Copy the sign; HandSpeak checks your handshape.'),
      (Icons.event_repeat_rounded, 'Come back daily', 'A few signs a day stick better than many at once.'),
    ];
    return Container(
      padding: EdgeInsets.all(18 * scale),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22 * scale),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.25), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How to learn here',
              style: TextStyle(color: textColor, fontSize: 18 * scale, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
          SizedBox(height: 14 * scale),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) SizedBox(height: 12 * scale),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(8 * scale),
                  decoration: BoxDecoration(color: theme.primaryColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(steps[i].$1, color: theme.primaryColor, size: 20 * scale),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i + 1}. ${steps[i].$2}',
                          style: TextStyle(color: textColor, fontSize: 15 * scale, fontWeight: FontWeight.w800)),
                      SizedBox(height: 2 * scale),
                      Text(steps[i].$3,
                          style: TextStyle(color: textColor.withValues(alpha: 0.65), fontSize: 13 * scale, height: 1.35)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 16 * scale),
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 15 * scale, color: textColor.withValues(alpha: 0.5)),
              SizedBox(width: 6 * scale),
              Expanded(
                child: Text('Activities and challenges are for students with an account.',
                    style: TextStyle(color: textColor.withValues(alpha: 0.55), fontSize: 12 * scale, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AccessRestrictedScreen extends StatelessWidget {
  const AccessRestrictedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final role = context.rolesRead.roleLabel;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.primaryColor.withValues(alpha: 0.15),
                ),
                child: Icon(Icons.lock_rounded, size: 48, color: theme.primaryColor),
              ),
              const SizedBox(height: 22),
              Text(
                'Students only',
                style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.6),
              ),
              const SizedBox(height: 10),
              Text(
                'This part of HandSpeak is only available to students. '
                '$role accounts can use the module tutorials and practice.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textColor.withValues(alpha: 0.65), fontSize: 15, height: 1.45),
              ),
              const SizedBox(height: 26),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () => Navigator.maybePop(context),
                child: const Text('Go back', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
