import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../home/home.dart';
import '../services/role_service.dart';
import 'login_screen.dart';

/// "Who is using HandSpeak?" Shown after the welcome slides.
///
///  * Student  -> the normal student login / sign up (unchanged).
///  * Faculty / Parent -> straight into the app like a guest, limited to the
///    module tutorials and tutorial practice (see [RoleProvider]).
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  UserRole? _selected;
  bool _busy = false;

  static const Map<UserRole, ({String blurb, Color accent})> _info = {
    UserRole.student: (
      blurb: 'Log in to learn, earn XP, play activities and join challenges.',
      accent: Color(0xFFFFB800),
    ),
    UserRole.faculty: (
      blurb: 'Browse the module tutorials and practice. No account needed.',
      accent: Color(0xFF3D7BFF),
    ),
    UserRole.parent: (
      blurb: 'Learn the signs alongside your child. No account needed.',
      accent: Color(0xFF7DC579),
    ),
  };

  Future<void> _continue() async {
    final role = _selected;
    if (role == null || _busy) return;
    HapticFeedback.selectionClick();

    if (role == UserRole.student) {
      // Students keep the existing login flow exactly as it was.
      await context.read<RoleProvider>().chooseRole(UserRole.student);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SnedStudentLogin()));
      return;
    }

    // Faculty / Parent: no login, go straight in with restricted access.
    setState(() => _busy = true);
    await context.read<RoleProvider>().chooseRole(role);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SnedInterafce1(userName: role.label)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final accent = _selected == null ? theme.primaryColor : _info[_selected]!.accent;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -100,
            child: _Blob(size: 320, color: accent.withValues(alpha: 0.20)),
          ),
          Positioned(
            bottom: -150,
            left: -120,
            child: _Blob(size: 360, color: accent.withValues(alpha: 0.12)),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Navigator.canPop(context)
                        ? IconButton(
                            icon: Icon(Icons.arrow_back_ios_new_rounded, color: onSurface, size: 20),
                            onPressed: () => Navigator.pop(context),
                          )
                        : const SizedBox(height: 48),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: Image.asset('assets/pictures/logo.png', width: 70)),
                        const SizedBox(height: 22),
                        Text(
                          'WELCOME',
                          style: TextStyle(
                            color: accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Who is using\nHandSpeak?',
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 34,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Choose your role so we can show you the right features.',
                          style: TextStyle(color: onSurface.withValues(alpha: 0.65), fontSize: 15.5, height: 1.4),
                        ),
                        const SizedBox(height: 26),
                        for (final role in UserRole.values) ...[
                          _RoleCard(
                            role: role,
                            blurb: _info[role]!.blurb,
                            accent: _info[role]!.accent,
                            selected: _selected == role,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selected = role);
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _selected == null || _busy ? null : _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        disabledBackgroundColor: onSurface.withValues(alpha: 0.12),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _selected == null
                                      ? 'Select a role'
                                      : _selected == UserRole.student
                                          ? 'Continue to login'
                                          : 'Continue as ${_selected!.label}',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                                ),
                                if (_selected != null) ...[
                                  const SizedBox(width: 10),
                                  const Icon(Icons.arrow_forward_rounded, size: 24),
                                ],
                              ],
                            ),
                    ),
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

class _RoleCard extends StatelessWidget {
  final UserRole role;
  final String blurb;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.role,
    required this.blurb,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      label: '${role.label}. $blurb',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.12) : theme.cardColor.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? accent : onSurface.withValues(alpha: 0.10),
              width: selected ? 2 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: (selected ? accent : Colors.black).withValues(alpha: selected ? 0.22 : 0.05),
                blurRadius: selected ? 18 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.18),
                ),
                child: Icon(role.icon, color: accent, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role.label,
                      style: TextStyle(color: onSurface, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      blurb,
                      style: TextStyle(color: onSurface.withValues(alpha: 0.62), fontSize: 13.5, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(selected),
                  color: selected ? accent : onSurface.withValues(alpha: 0.3),
                  size: 26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}
