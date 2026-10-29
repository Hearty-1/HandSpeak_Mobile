import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '/services/performance_monitor.dart';
import '../services/auth_service.dart';
import '../providers/theme_provider.dart';
import '../providers/sound_provider.dart';
import '/providers/language_provider.dart';

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
    final textColor = theme.colorScheme.onBackground;

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
              style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 13, height: 1.4),
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
                hintStyle: TextStyle(color: textColor.withOpacity(0.3), letterSpacing: 8),
                filled: true,
                fillColor: theme.disabledColor.withOpacity(0.08),
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
            child: Text(context.tr(context.tr('Cancel', 'Kanselahin'), 'Kanselahin'), style: TextStyle(color: textColor.withOpacity(0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    final textColor = theme.colorScheme.onBackground;

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
          _buildSectionHeader(context.tr(context.tr('Account & Profile', 'Account at Profile'), 'Account at Profile'), textColor),
          _buildSettingsCard(
            context: context,
            children: [
              ListTile(
                leading: const Icon(CupertinoIcons.person_alt_circle, color: Color(0xFFFFB800)),
                title: Text(context.tr(context.tr('Edit Personal Details', 'I-edit ang Personal na Detalye'), 'I-edit ang Personal na Detalye'), style: TextStyle(color: textColor)),
                trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: textColor.withOpacity(0.5)),
                onTap: () {
                  _showEditProfileDialog(context);
                },
              ),
            ],
          ),

          _buildSectionHeader(context.tr(context.tr('Game Settings', 'Mga Setting ng Laro'), 'Mga Setting ng Laro'), textColor),
          _buildSettingsCard(
            context: context,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: PerformanceSettings.reduceEffects,
                builder: (context, on, _) => SwitchListTile(
                  activeColor: const Color(0xFFFFB800),
                  inactiveThumbColor: Colors.grey.shade400,
                  inactiveTrackColor: Colors.grey.withOpacity(0.3),
                  secondary: const Icon(CupertinoIcons.bolt_fill, color: Color(0xFFFFB800)),
                  title: Text(context.tr(context.tr('Performance Mode', 'Performance Mode'), context.tr('Performance Mode', 'Performance Mode')), style: TextStyle(color: textColor)),
                  subtitle: Text(
                    context.tr(context.tr('Turns off blur effects so the camera and app run faster on slower phones.', 'Pinapatay ang blur effects para bumilis ang camera at app sa mabagal na phone.'), 'Pinapatay ang blur effects para bumilis ang camera at app sa mabagal na phone.'),
                    style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 12),
                  ),
                  value: on,
                  onChanged: (val) => PerformanceSettings.set(val),
                ),
              ),
              Divider(height: 1, color: theme.dividerColor),
              SwitchListTile(
                activeColor: const Color(0xFFFFB800),
                inactiveThumbColor: Colors.grey.shade400,
                inactiveTrackColor: Colors.grey.withOpacity(0.3),
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
              ),
              Divider(height: 1, color: theme.dividerColor),
              SwitchListTile(
                activeColor: const Color(0xFFFFB800),
                inactiveThumbColor: Colors.grey.shade400,
                inactiveTrackColor: Colors.grey.withOpacity(0.3),
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
              ),
              Divider(height: 1, color: theme.dividerColor),
              ListTile(
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
              ),
              Divider(height: 1, color: theme.dividerColor),
              ListTile(
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
              ),
            ],
          ),

          _buildSectionHeader(context.tr(context.tr('Security & Privacy', 'Seguridad at Privacy'), 'Seguridad at Privacy'), textColor),
          _buildSettingsCard(
            context: context,
            children: [
              SwitchListTile(
                activeColor: const Color(0xFFFFB800),
                inactiveThumbColor: Colors.grey.shade400,
                inactiveTrackColor: Colors.grey.withOpacity(0.3),
                secondary: Icon(CupertinoIcons.shield_fill, color: textColor.withOpacity(0.6)),
                title: Text(context.tr(context.tr('Two-Factor Authentication', 'Two-Factor Authentication'), context.tr('Two-Factor Authentication', 'Two-Factor Authentication')), style: TextStyle(color: textColor)),
                subtitle: Text(
                  context.tr(context.tr('Add extra security to your account with Email 2FA', 'Dagdag na seguridad sa account gamit ang Email 2FA'), 'Dagdag na seguridad sa account gamit ang Email 2FA'),
                  style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 12),
                ),
                value: _twoFactorEnabled,
                onChanged: (val) {
                  setState(() => _twoFactorEnabled = val);
                  _handle2FAToggle(val);
                },
              ),
              Divider(height: 1, color: theme.dividerColor),
              ListTile(
                leading: Icon(CupertinoIcons.lock_fill, color: textColor.withOpacity(0.6)),
                title: Text(context.tr(context.tr('Change Password', 'Palitan ang Password'), 'Palitan ang Password'), style: TextStyle(color: textColor)),
                trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: textColor.withOpacity(0.5)),
                onTap: () {
                  _showChangePasswordDialog(context);
                },
              ),
              Divider(height: 1, color: theme.dividerColor),
              ListTile(
                leading: Icon(CupertinoIcons.device_phone_portrait, color: textColor.withOpacity(0.6)),
                title: Text(context.tr(context.tr('Session & Activity Logs', 'Session at Activity Logs'), 'Session at Activity Logs'), style: TextStyle(color: textColor)),
                trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: textColor.withOpacity(0.5)),
                onTap: () {
                  _showSessionHistory(context);
                },
              ),
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
          color: textColor.withOpacity(0.6),
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
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
    final textColor = theme.colorScheme.onBackground;

    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      obscureText: obscureText,
      style: TextStyle(
        color: readOnly ? textColor.withOpacity(0.5) : textColor,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: textColor.withOpacity(0.6), fontSize: 14),
        prefixIcon: Icon(icon, color: readOnly ? textColor.withOpacity(0.3) : const Color(0xFFFFB800), size: 20),
        filled: true,
        fillColor: readOnly ? theme.disabledColor.withOpacity(0.05) : theme.cardColor,
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

  void _showEditProfileDialog(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        builder: (context, snapshot) {
          final theme = Theme.of(context);
          final textColor = theme.colorScheme.onBackground;

          if (snapshot.connectionState == ConnectionState.waiting) {
            return AlertDialog(
              backgroundColor: theme.cardColor,
              content: const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(color: Color(0xFFFFB800))),
              ),
            );
          }

          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
            return AlertDialog(
              backgroundColor: theme.cardColor,
              title: Text("Error", style: TextStyle(color: textColor)),
              content: Text("Could not load user details.", style: TextStyle(color: textColor)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr(context.tr('Close', 'Isara'), 'Isara'))),
              ],
            );
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final emailController = TextEditingController(text: user.email ?? userData['email'] ?? '');
          final studentIdController = TextEditingController(text: userData['studentId'] ?? '');
          final firstNameController = TextEditingController(text: userData['firstName'] ?? '');
          final middleNameController = TextEditingController(text: userData['middleName'] ?? '');
          final lastNameController = TextEditingController(text: userData['lastName'] ?? '');
          final gradeController = TextEditingController(text: userData['grade'] ?? '');
          final sectionController = TextEditingController(text: userData['section'] ?? '');
          
          bool isUpdating = false;

          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                backgroundColor: theme.cardColor,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                titlePadding: const EdgeInsets.only(top: 24, left: 24, right: 24),
                title: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF9E5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(CupertinoIcons.person_crop_circle_fill, color: Color(0xFFFFB800), size: 48),
                    ),
                    const SizedBox(height: 16),
                    Text(context.tr(context.tr('Personal Details', 'Personal na Detalye'), 'Personal na Detalye'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: textColor)),
                  ],
                ),
                contentPadding: const EdgeInsets.all(24),
                content: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildEnhancedTextField(context: context, controller: emailController, label: context.tr(context.tr('Email Address', 'Email Address'), context.tr('Email Address', 'Email Address')), icon: CupertinoIcons.mail_solid, readOnly: true),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(context: context, controller: studentIdController, label: "Student ID", icon: CupertinoIcons.doc_text_fill, readOnly: true),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(context: context, controller: firstNameController, label: context.tr(context.tr('First Name', 'Pangalan'), 'Pangalan'), icon: CupertinoIcons.person_fill),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(context: context, controller: middleNameController, label: context.tr(context.tr('Middle Name', 'Gitnang Pangalan'), 'Gitnang Pangalan'), icon: CupertinoIcons.person_fill),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(context: context, controller: lastNameController, label: context.tr(context.tr('Last Name', 'Apelyido'), 'Apelyido'), icon: CupertinoIcons.person_fill),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildEnhancedTextField(context: context, controller: gradeController, label: context.tr(context.tr('Grade', 'Baitang'), 'Baitang'), icon: CupertinoIcons.chart_bar_alt_fill)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildEnhancedTextField(context: context, controller: sectionController, label: context.tr(context.tr('Section', 'Seksyon'), 'Seksyon'), icon: CupertinoIcons.group_solid)),
                        ],
                      ),
                    ],
                  ),
                ),
                actionsPadding: const EdgeInsets.only(bottom: 24, right: 24, left: 24),
                actions: [
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: isUpdating ? null : () => Navigator.pop(context), 
                          child: Text(context.tr(context.tr('Cancel', 'Kanselahin'), 'Kanselahin'), style: TextStyle(color: textColor.withOpacity(0.6), fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB800)),
                          onPressed: isUpdating ? null : () async {
                            setState(() => isUpdating = true);
                            try {
                              String fullName = '${firstNameController.text.trim()} ${middleNameController.text.trim()} ${lastNameController.text.trim()}'.replaceAll('  ', ' ').trim();

                              await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                                'firstName': firstNameController.text.trim(),
                                'middleName': middleNameController.text.trim(),
                                'lastName': lastNameController.text.trim(),
                                'grade': gradeController.text.trim(),
                                'section': sectionController.text.trim(),
                                'name': fullName, 
                              });

                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              setState(() => isUpdating = false);
                            }
                          }, 
                          child: isUpdating 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                              : Text(context.tr(context.tr('Save', 'I-save'), 'I-save'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }
          );
        },
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
          final textColor = theme.colorScheme.onBackground;

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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('login_activity').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          controller: scrollController,
          children: snapshot.data!.docs.map((doc) => ListTile(title: Text(doc['action'] ?? 'Action'))).toList(),
        );
      },
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
