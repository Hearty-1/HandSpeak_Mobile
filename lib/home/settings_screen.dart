import '/widgets/button_3d.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/theme_provider.dart';
import '../providers/sound_provider.dart';
import '/providers/language_provider.dart';
import '/services/performance_monitor.dart';
import '/services/activity_log.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const int _otpValidMinutes = 10;

  bool _twoFactorEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        bool isMfaEnabled = false;

        if (data.containsKey('twoFactorEnabled')) {
          isMfaEnabled = data['twoFactorEnabled'] == true;
        } else if (data.containsKey('preferences') && data['preferences'] is Map) {
          isMfaEnabled = data['preferences']['twoFactorEnabled'] == true;
        }

        if (mounted) {
          setState(() {
            _twoFactorEnabled = isMfaEnabled;
          });
        }
      }
    }
  }

  Future<void> _updatePreference(String key, bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'preferences': {
          key: value,
        },
        'twoFactorEnabled': value,
      }, SetOptions(merge: true));
    }
  }

  Future<void> _handle2FAToggle(bool enable) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null || user.email!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No valid email address found on account.")),
      );
      setState(() => _twoFactorEnabled = false);
      return;
    }

    final email = user.email!;

    if (enable) {
      // 1. Generate a 6-digit verification code
      // Random.secure: a predictable code is no protection.
      final String generatedOtp = (100000 + Random.secure().nextInt(900000)).toString();
      final DateTime expiresAt = DateTime.now().add(const Duration(minutes: _otpValidMinutes));

      try {
        // Save OTP payload to Firestore for trigger/cloud email dispatch
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'twoFactorOTP': {
            'code': generatedOtp,
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt': Timestamp.fromDate(expiresAt),
            'email': email,
          }
        }, SetOptions(merge: true));

        // Send confirmation email & notification
        await _sendEmailVerificationCode(user, email, generatedOtp);

        if (!mounted) return;

        // Prompt user to enter the 6-digit email code
        String? enteredCode = await _showEmailCodePrompt(context, email);

        final bool expired = DateTime.now().isAfter(expiresAt);
        if (enteredCode != null && !expired && enteredCode.trim() == generatedOtp) {
          setState(() => _twoFactorEnabled = true);
          await _updatePreference('twoFactorEnabled', true);

          // Clear temporary OTP data after successful verification
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'twoFactorOTP': FieldValue.delete(),
            'twoFactorEnabled': true,
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("2FA via Email successfully enabled.")),
            );
          }
        } else {
          if (mounted && enteredCode != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(expired
                  ? "That code has expired. Turn 2FA on again to get a new code."
                  : "Invalid verification code. 2FA not enabled.")),
            );
          }
          setState(() => _twoFactorEnabled = false);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to enable Email 2FA: $e")),
          );
        }
        setState(() => _twoFactorEnabled = false);
      }
    } else {
      try {
        setState(() => _twoFactorEnabled = false);
        await _updatePreference('twoFactorEnabled', false);
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'twoFactorEnabled': false,
        }, SetOptions(merge: true));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("2FA successfully disabled.")),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to disable 2FA.")),
          );
        }
        setState(() => _twoFactorEnabled = true);
      }
    }
  }

  Future<void> _sendEmailVerificationCode(User user, String email, String code) async {
  try {
    await FirebaseFirestore.instance.collection('mail').add({
      'to': [email], // TOP-LEVEL ARRAY of emails
      'message': {
        // Code first in the subject, so it shows in the notification preview.
        'subject': '$code is your HandSpeak verification code',
        'text': _otpEmailText(code, email),
        'html': _otpEmailHtml(code, email),
      },
    });
  } catch (e) {
    debugPrint("FIREBASE MAIL ERROR: $e");
  }

  // Dispatch in-app notification record
  await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
    'notifications': FieldValue.arrayUnion([
      {
        'title': '2FA Security Code 🔒',
        'body': 'We sent a 6-digit verification code to $email. It expires in $_otpValidMinutes minutes.',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isRead': false,
      }
    ])
  }, SetOptions(merge: true));
}

  Future<String?> _showEmailCodePrompt(BuildContext context, String email) async {
    final controller = TextEditingController();
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(CupertinoIcons.mail_solid, color: Color(0xFFFFB800)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Enter Email Code",
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "A 6-digit verification code has been dispatched to:\n$email",
              style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                hintText: "123456",
                counterText: "",
                hintStyle: TextStyle(color: textColor.withValues(alpha: 0.3), letterSpacing: 8),
                filled: true,
                fillColor: theme.disabledColor.withValues(alpha: 0.08),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFFFB800), width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr(context.tr('Cancel', 'Kanselahin'), 'Kanselahin'), style: TextStyle(color: textColor.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB800),
              shape: Button3DBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: Text(context.tr(context.tr('Verify', 'I-verify'), 'I-verify'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final soundProvider = Provider.of<SoundProvider>(context);
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: theme.appBarTheme.iconTheme,
        centerTitle: true,
        title: Text(
          context.tr(context.tr('Settings', 'Mga Setting'), 'Mga Setting'),
          style: theme.appBarTheme.titleTextStyle,
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24.0),
        children: [
          _buildSectionHeader(context.tr(context.tr('Game Settings', 'Mga Setting ng Laro'), 'Mga Setting ng Laro'), textColor),
          _buildSettingsCard(
            context: context,
            children: [
              // Same light mode as the lag warning's button (saved on the phone).
              ValueListenableBuilder<bool>(
                valueListenable: PerformanceSettings.reduceEffects,
                builder: (context, on, _) => Pressable3D(child: SwitchListTile(
                  activeThumbColor: const Color(0xFFFFB800),
                  inactiveThumbColor: Colors.grey.shade400,
                  inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                  secondary: const Icon(CupertinoIcons.bolt_fill, color: Color(0xFFFFB800)),
                  title: Text(context.tr('Performance Mode', 'Performance Mode'), style: TextStyle(color: textColor)),
                  value: on,
                  onChanged: (val) => PerformanceSettings.set(val),
                )),
              ),
              Divider(height: 1, color: theme.dividerColor),
              Pressable3D(child: SwitchListTile(
                activeThumbColor: const Color(0xFFFFB800),
                inactiveThumbColor: Colors.grey.shade400,
                inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                secondary: Icon(
                  soundProvider.isBgmMuted
                      ? CupertinoIcons.speaker_slash_fill
                      : CupertinoIcons.music_note_2,
                  color: const Color(0xFFFFB800),
                ),
                title: Text(context.tr(context.tr('Background Music', 'Background na Musika'), 'Background na Musika'), style: TextStyle(color: textColor)),
                value: !soundProvider.isBgmMuted,
                onChanged: (val) {
                  soundProvider.toggleBgmMute();
                },
              )),
              Divider(height: 1, color: theme.dividerColor),
              Pressable3D(child: SwitchListTile(
                activeThumbColor: const Color(0xFFFFB800),
                inactiveThumbColor: Colors.grey.shade400,
                inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                secondary: Icon(
                  soundProvider.isSfxMuted
                      ? CupertinoIcons.speaker_slash
                      : CupertinoIcons.speaker_2_fill,
                  color: const Color(0xFFFFB800),
                ),
                title: Text(context.tr(context.tr('Sound Effects', 'Sound Effects'), context.tr('Sound Effects', 'Sound Effects')), style: TextStyle(color: textColor)),
                value: !soundProvider.isSfxMuted,
                onChanged: (val) {
                  soundProvider.toggleSfxMute();
                },
              )),
              Divider(height: 1, color: theme.dividerColor),
              Pressable3D(child: ListTile(
                leading: const Icon(Icons.translate_rounded, color: Color(0xFFFFB800)),
                title: Text(context.tr(context.tr('Language', 'Wika'), 'Wika'), style: TextStyle(color: textColor)),
                trailing: DropdownButton<String>(
                  value: context.watch<LanguageProvider>().code,
                  dropdownColor: theme.cardColor,
                  underline: const SizedBox(),
                  icon: Icon(CupertinoIcons.chevron_down, size: 16, color: textColor),
                  items: [
                    DropdownMenuItem(value: LanguageProvider.english, child: Text('English', style: TextStyle(color: textColor))),
                    DropdownMenuItem(value: LanguageProvider.filipino, child: Text('Filipino', style: TextStyle(color: textColor))),
                  ],
                  onChanged: (val) {
                    if (val != null) context.read<LanguageProvider>().setLanguage(val);
                  },
                ),
              )),
              Divider(height: 1, color: theme.dividerColor),
              Pressable3D(child: ListTile(
                leading: const Icon(CupertinoIcons.paintbrush_fill, color: Color(0xFFFFB800)),
                title: Text(context.tr(context.tr('Theme', 'Tema'), 'Tema'), style: TextStyle(color: textColor)),
                trailing: DropdownButton<String>(
                  value: themeProvider.themeString,
                  dropdownColor: theme.cardColor,
                  underline: const SizedBox(),
                  icon: Icon(CupertinoIcons.chevron_down, size: 16, color: textColor),
                  items: [
                    "Default Theme", 
                    "Galaxy Explorer",
                    "Enchanted Forest",
                    "Deep Ocean",
                    "Cloudy Sky",
                  ].map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t, style: TextStyle(color: textColor)),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      themeProvider.setThemeFromString(val);
                    }
                  },
                ),
              )),
            ],
          ),

          _buildSectionHeader(context.tr(context.tr('Security & Privacy', 'Seguridad at Privacy'), 'Seguridad at Privacy'), textColor),
          _buildSettingsCard(
            context: context,
            children: [
              Pressable3D(child: SwitchListTile(
                activeThumbColor: const Color(0xFFFFB800),
                inactiveThumbColor: Colors.grey.shade400,
                inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                secondary: Icon(CupertinoIcons.shield_fill, color: textColor.withValues(alpha: 0.6)),
                title: Text(context.tr(context.tr('Two-Factor Authentication', 'Two-Factor Authentication'), context.tr('Two-Factor Authentication', 'Two-Factor Authentication')), style: TextStyle(color: textColor)),
                subtitle: Text(
                  context.tr(context.tr('Add extra security to your account with Email 2FA', 'Dagdag na seguridad sa account gamit ang Email 2FA'), 'Dagdag na seguridad sa account gamit ang Email 2FA'),
                  style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 12),
                ),
                value: _twoFactorEnabled,
                onChanged: (val) {
                  setState(() => _twoFactorEnabled = val);
                  _handle2FAToggle(val);
                },
              )),
              Divider(height: 1, color: theme.dividerColor),
              Pressable3D(child: ListTile(
                leading: Icon(CupertinoIcons.lock_fill, color: textColor.withValues(alpha: 0.6)),
                title: Text(context.tr(context.tr('Change Password', 'Palitan ang Password'), 'Palitan ang Password'), style: TextStyle(color: textColor)),
                trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: textColor.withValues(alpha: 0.5)),
                onTap: () {
                  _showChangePasswordDialog(context);
                },
              )),
              Divider(height: 1, color: theme.dividerColor),
              Pressable3D(child: ListTile(
                leading: Icon(CupertinoIcons.device_phone_portrait, color: textColor.withValues(alpha: 0.6)),
                title: Text(context.tr(context.tr('Session & Activity Logs', 'Session at Activity Logs'), 'Session at Activity Logs'), style: TextStyle(color: textColor)),
                trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: textColor.withValues(alpha: 0.5)),
                onTap: () {
                  _showSessionHistory(context);
                },
              )),
            ],
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // --- HELPER WIDGETS & DIALOGS ---

  Widget _buildSectionHeader(String title, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: textColor.withValues(alpha: 0.6),
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required BuildContext context, required List<Widget> children}) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // Raised 3D card: lit from the top, a faint shade at the bottom.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.05)],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildEnhancedTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool readOnly = false,
    bool obscureText = false,
  }) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      obscureText: obscureText,
      style: TextStyle(
        color: readOnly ? textColor.withValues(alpha: 0.5) : textColor,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 14),
        prefixIcon: Icon(icon, color: readOnly ? textColor.withValues(alpha: 0.3) : const Color(0xFFFFB800), size: 20),
        filled: true,
        fillColor: readOnly ? theme.disabledColor.withValues(alpha: 0.05) : theme.cardColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: theme.dividerColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFFB800), width: 1.5),
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController(); 

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          final textColor = theme.colorScheme.onSurface;

          return AlertDialog(
            backgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Text(context.tr(context.tr('Change Password', 'Palitan ang Password'), 'Palitan ang Password'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: textColor)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildEnhancedTextField(context: context, controller: currentPasswordController, label: context.tr(context.tr('Current Password', 'Kasalukuyang Password'), 'Kasalukuyang Password'), icon: CupertinoIcons.lock_fill, obscureText: true),
                  const SizedBox(height: 16),
                  _buildEnhancedTextField(context: context, controller: newPasswordController, label: context.tr(context.tr('New Password', 'Bagong Password'), 'Bagong Password'), icon: CupertinoIcons.lock_rotation, obscureText: true),
                  const SizedBox(height: 16),
                  _buildEnhancedTextField(context: context, controller: confirmPasswordController, label: context.tr(context.tr('Confirm New Password', 'Kumpirmahin ang Bagong Password'), 'Kumpirmahin ang Bagong Password'), icon: CupertinoIcons.checkmark_shield_fill, obscureText: true),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr(context.tr('Cancel', 'Kanselahin'), 'Kanselahin'))),
              ElevatedButton(
                onPressed: () async {
                  if (newPasswordController.text != confirmPasswordController.text) return;
                  User? user = FirebaseAuth.instance.currentUser;
                  if (user != null && user.email != null) {
                    AuthCredential credential = EmailAuthProvider.credential(email: user.email!, password: currentPasswordController.text.trim());
                    await user.reauthenticateWithCredential(credential);
                    await user.updatePassword(newPasswordController.text.trim());
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                child: Text(context.tr(context.tr('Update', 'I-update'), 'I-update')),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showSessionHistory(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    AuthService().registerDeviceSession(user.uid);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return DefaultTabController(
            length: 2,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const TabBar(tabs: [Tab(text: "Device History"), Tab(text: "Activity Logs")]),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildDeviceHistoryTab(user.uid, scrollController),
                        _buildActivityLogsTab(user.uid, scrollController),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeviceHistoryTab(String uid, ScrollController scrollController) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('device_sessions').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          controller: scrollController,
          children: snapshot.data!.docs.map((doc) => ListTile(title: Text(doc['deviceName'] ?? 'Device'))).toList(),
        );
      },
    );
  }

  Widget _buildActivityLogsTab(String uid, ScrollController scrollController) {
    return _ActivityLogView(uid: uid, scrollController: scrollController);
  }
}

/// Settings > Activity Logs: the user's activity (ActivityLog), live, newest
/// first, grouped by day, with a filter per kind of activity.
class _ActivityLogView extends StatefulWidget {
  final String uid;
  final ScrollController scrollController;
  const _ActivityLogView({required this.uid, required this.scrollController});

  @override
  State<_ActivityLogView> createState() => _ActivityLogViewState();
}

class _ActivityLogViewState extends State<_ActivityLogView> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = ActivityLog.stream(widget.uid, limit: 200);
  ActivityCategory? _filter;

  static const Map<ActivityCategory, (String, IconData, Color)> _kinds = {
    ActivityCategory.auth: ('Sign-in', Icons.login_rounded, Color(0xFF5C6BC0)),
    ActivityCategory.learning: ('Learning', Icons.school_rounded, Color(0xFF42A5F5)),
    ActivityCategory.practice: ('Practice', Icons.camera_alt_rounded, Color(0xFF26A69A)),
    ActivityCategory.activity: ('Activities', Icons.extension_rounded, Color(0xFFFFA726)),
    ActivityCategory.challenge: ('Challenges', Icons.sports_esports_rounded, Color(0xFFEF5350)),
    ActivityCategory.achievement: ('Badges', Icons.emoji_events_rounded, Color(0xFFFFC107)),
    ActivityCategory.account: ('Account', Icons.manage_accounts_rounded, Color(0xFF8D6E63)),
  };

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${_two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  static String _day(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// One line of facts from an entry's details.
  static String _facts(Map<String, dynamic> d) {
    final parts = <String>[];
    if (d['correct'] != null && (d['total'] ?? d['attempts']) != null) parts.add('${d['correct']}/${d['total'] ?? d['attempts']} correct');
    if (d['heartsLeft'] != null) parts.add('${d['heartsLeft']} ♥ left');
    if (d['accuracy'] is num) parts.add('${(d['accuracy'] as num).round()}% accuracy');
    if (parts.isEmpty && d['description'] is String) parts.add(d['description'] as String);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final k in [null, ...ActivityCategory.values])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(k == null ? 'All' : _kinds[k]!.$1),
                    selected: _filter == k,
                    onSelected: (_) => setState(() => _filter = k),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Activity could not be loaded.', style: TextStyle(color: textColor.withValues(alpha: 0.6))));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final entries = [
                for (final doc in snap.data!.docs)
                  if (_filter == null || doc.data()['category'] == _filter!.name) doc.data(),
              ];
              if (entries.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No activity yet. Your sign-ins, lessons, practice, activities, challenges and badges will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textColor.withValues(alpha: 0.6)),
                    ),
                  ),
                );
              }
              final rows = <Widget>[];
              String? lastDay;
              for (final e in entries) {
                final ts = (e['clientTime'] ?? e['timestamp']);
                final when = ts is Timestamp ? ts.toDate() : DateTime.now();
                final day = _day(when);
                if (day != lastDay) {
                  lastDay = day;
                  rows.add(Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                    child: Text(day, style: TextStyle(fontWeight: FontWeight.w900, color: textColor.withValues(alpha: 0.6), fontSize: 13)),
                  ));
                }
                final cat = ActivityCategory.values.where((c) => c.name == e['category']).firstOrNull ?? ActivityCategory.account;
                final (_, icon, color) = _kinds[cat]!;
                final facts = _facts(Map<String, dynamic>.from(e['details'] as Map? ?? const {}));
                rows.add(Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${e['title'] ?? e['eventType'] ?? 'Activity'}',
                                style: TextStyle(fontWeight: FontWeight.w800, color: textColor, fontSize: 14)),
                            if (facts.isNotEmpty)
                              Text(facts, style: TextStyle(color: textColor.withValues(alpha: 0.65), fontSize: 12.5)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_time(when), style: TextStyle(color: textColor.withValues(alpha: 0.55), fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ));
              }
              return ListView(controller: widget.scrollController, children: rows);
            },
          ),
        ),
      ],
    );
  }
}


// ---------------------------------------------------------------------------
// 2FA email (verification code)
// ---------------------------------------------------------------------------
// Industry-standard one-time-code email: table layout with inline CSS (works
// in Gmail, Outlook, Apple Mail, dark mode), hidden preheader, the code large
// and copyable, how long it is valid, what to do if it was not you, and no
// links or buttons to click (codes are typed, which avoids phishing look-alikes).

String _otpEmailText(String code, String email) => '''
HandSpeak verification code

Your verification code is: $code

Enter this code in the HandSpeak app to turn on 2-step verification.
It expires in 10 minutes and can only be used once.

Never share this code. HandSpeak will never ask you for it by phone, chat or email.

Didn't request this? Ignore this email: your account stays unchanged. If you
keep getting codes you didn't ask for, change your HandSpeak password.

This email was sent to $email because a 2-step verification code was requested for your HandSpeak account.
© ${DateTime.now().year} HandSpeak
''';

String _otpEmailHtml(String code, String email) {
  final spaced = code.split('').join('&#8202;'); // hair space: easy to read, still copies as one code
  final year = DateTime.now().year;
  return '''
<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>Your HandSpeak verification code</title>
<style>
  @media (prefers-color-scheme: dark) {
    .bg { background:#14161a !important; }
    .card { background:#1f2228 !important; border-color:#2c3038 !important; }
    .text { color:#e8eaed !important; }
    .muted { color:#a6abb3 !important; }
    .codebox { background:#2a2440 !important; border-color:#4b3f80 !important; }
    .code { color:#c9b8ff !important; }
  }
  @media only screen and (max-width:520px) {
    .card { padding:28px 20px !important; }
    .code { font-size:32px !important; letter-spacing:6px !important; }
  }
</style>
</head>
<body class="bg" style="margin:0;padding:0;background:#f3f4f7;">
  <!-- Preheader: shown next to the subject in the inbox, hidden in the body -->
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;">
    Your code is $code. It expires in 10 minutes. Never share it with anyone.
  </div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="bg" style="background:#f3f4f7;">
    <tr>
      <td align="center" style="padding:32px 16px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:480px;">
          <tr>
            <td align="center" style="padding:0 0 20px 0;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
              <span style="display:inline-block;width:40px;height:40px;line-height:40px;border-radius:12px;background:#6c4ee3;color:#ffffff;font-size:20px;font-weight:800;text-align:center;vertical-align:middle;">H</span>
              <span class="text" style="font-size:20px;font-weight:800;color:#1d1f24;vertical-align:middle;padding-left:8px;">HandSpeak</span>
            </td>
          </tr>
          <tr>
            <td class="card" style="background:#ffffff;border:1px solid #e3e5ea;border-radius:16px;padding:36px 32px;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
              <h1 class="text" style="margin:0 0 12px 0;font-size:22px;line-height:1.3;color:#1d1f24;font-weight:800;">Your verification code</h1>
              <p class="muted" style="margin:0 0 24px 0;font-size:15px;line-height:1.55;color:#555b66;">
                Enter this code in the HandSpeak app to turn on 2-step verification for your account.
              </p>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" class="codebox" style="background:#f1edff;border:1px solid #d9d0ff;border-radius:12px;padding:20px 12px;">
                    <span class="code" style="font-family:'SFMono-Regular',Consolas,'Courier New',monospace;font-size:36px;font-weight:700;letter-spacing:8px;color:#4a2fc2;">$spaced</span>
                  </td>
                </tr>
              </table>
              <p class="muted" style="margin:20px 0 0 0;font-size:14px;line-height:1.55;color:#555b66;text-align:center;">
                This code expires in <strong class="text" style="color:#1d1f24;">10 minutes</strong> and can only be used once.
              </p>
              <hr style="border:none;border-top:1px solid #e3e5ea;margin:28px 0;">
              <p class="text" style="margin:0 0 8px 0;font-size:14px;line-height:1.55;color:#1d1f24;font-weight:700;">Didn't request this?</p>
              <p class="muted" style="margin:0 0 16px 0;font-size:14px;line-height:1.55;color:#555b66;">
                You can safely ignore this email. Your account stays unchanged. If you keep getting codes you didn't ask for, change your HandSpeak password.
              </p>
              <p class="muted" style="margin:0;font-size:13px;line-height:1.55;color:#555b66;">
                &#128274; Never share this code. HandSpeak will never ask for it by phone, chat or email.
              </p>
            </td>
          </tr>
          <tr>
            <td align="center" class="muted" style="padding:20px 8px 0 8px;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.5;color:#8a909b;">
              This email was sent to $email because a 2-step verification code was requested for your HandSpeak account.<br>
              &copy; $year HandSpeak &middot; Filipino Sign Language learning
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
''';
}
