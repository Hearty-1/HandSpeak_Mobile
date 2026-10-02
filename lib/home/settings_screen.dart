import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/theme_provider.dart';
import '../providers/sound_provider.dart';
import '../services/local_notification_service.dart'; 

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Notification State
  bool _streakNotif = true;
  bool _dailyChallengesNotif = true;
  bool _friendNotif = true;
  bool _notificationSound = true;
  bool _notificationVibration = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data()!.containsKey('preferences')) {
        final prefs = doc.data()!['preferences'] as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _friendNotif = prefs['friendNotifications'] ?? true;
            _notificationSound = prefs['playSound'] ?? true;
            _notificationVibration = prefs['enableVibration'] ?? true;
          });
        }
      }
    }
  }

  Future<void> _updateNotificationPreference(String key, bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'preferences': {
          key: value,
        }
      }, SetOptions(merge: true));
    }
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
          "Settings",
          style: theme.appBarTheme.titleTextStyle,
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24.0),
        children: [
          _buildSectionHeader("Account & Profile", textColor),
          _buildSettingsCard(
            context: context,
            children: [
              ListTile(
                leading: const Icon(CupertinoIcons.person_alt_circle, color: Color(0xFFFFB800)),
                title: Text("Edit Personal Details", style: TextStyle(color: textColor)),
                trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: textColor.withOpacity(0.5)),
                onTap: () {
                  _showEditProfileDialog(context);
                },
              ),
            ],
          ),

          _buildSectionHeader("Game Settings", textColor),
          _buildSettingsCard(
            context: context,
            children: [
              SwitchListTile(
                activeColor: const Color(0xFFFFB800),
                secondary: Icon(
                  soundProvider.isBgmMuted
                      ? CupertinoIcons.speaker_slash_fill
                      : CupertinoIcons.music_note_2,
                  color: const Color(0xFFFFB800),
                ),
                title: Text("Background Music", style: TextStyle(color: textColor)),
                value: !soundProvider.isBgmMuted,
                onChanged: (val) {
                  soundProvider.toggleBgmMute();
                },
              ),
              Divider(height: 1, color: theme.dividerColor),
              SwitchListTile(
                activeColor: const Color(0xFFFFB800),
                secondary: Icon(
                  soundProvider.isSfxMuted
                      ? CupertinoIcons.speaker_slash
                      : CupertinoIcons.speaker_2_fill,
                  color: const Color(0xFFFFB800),
                ),
                title: Text("Sound Effects", style: TextStyle(color: textColor)),
                value: !soundProvider.isSfxMuted,
                onChanged: (val) {
                  soundProvider.toggleSfxMute();
                },
              ),
              Divider(height: 1, color: theme.dividerColor),
              ListTile(
                leading: const Icon(CupertinoIcons.paintbrush_fill, color: Color(0xFFFFB800)),
                title: Text("Theme", style: TextStyle(color: textColor)),
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

          // Clean, Professional Notifications Section
          _buildSectionHeader("Notifications", textColor),
          _buildSettingsCard(
            context: context,
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(CupertinoIcons.bell_solid, color: Colors.redAccent, size: 20),
                ),
                title: Text("Push Notifications", style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                subtitle: Text("Manage alerts, sounds, and behaviors", style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 12)),
                trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: textColor.withOpacity(0.5)),
                onTap: () => _showNotificationPreferences(context),
              ),
            ],
          ),

          _buildSectionHeader("Security & Privacy", textColor),
          _buildSettingsCard(
            context: context,
            children: [
              ListTile(
                leading: Icon(CupertinoIcons.lock_fill, color: textColor.withOpacity(0.6)),
                title: Text("Change Password", style: TextStyle(color: textColor)),
                trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: textColor.withOpacity(0.5)),
                onTap: () {
                  _showChangePasswordDialog(context);
                },
              ),
              Divider(height: 1, color: theme.dividerColor),
              ListTile(
                leading: Icon(CupertinoIcons.device_phone_portrait, color: textColor.withOpacity(0.6)),
                title: Text("Session & Activity Logs", style: TextStyle(color: textColor)),
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

  void _showNotificationPreferences(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onBackground;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 32.0, top: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: textColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text("Notification Preferences", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 16),
                SwitchListTile(
                  activeColor: const Color(0xFFFFB800),
                  secondary: const Icon(CupertinoIcons.flame_fill, color: Colors.deepOrange),
                  title: Text("Streak Reminders", style: TextStyle(color: textColor)),
                  value: _streakNotif,
                  onChanged: (val) async {
                    setSheetState(() => _streakNotif = val);
                    setState(() => _streakNotif = val);
                    if (val) {
                      await LocalNotificationService.scheduleStreakReminder(
                        playSound: _notificationSound,
                        enableVibration: _notificationVibration,
                      );
                    } else {
                      await LocalNotificationService.cancelStreakReminder();
                    }
                  },
                ),
                SwitchListTile(
                  activeColor: const Color(0xFFFFB800),
                  secondary: const Icon(CupertinoIcons.star_fill, color: Color(0xFFFFB800)),
                  title: Text("Daily Challenges", style: TextStyle(color: textColor)),
                  value: _dailyChallengesNotif,
                  onChanged: (val) {
                    setSheetState(() => _dailyChallengesNotif = val);
                    setState(() => _dailyChallengesNotif = val);
                  },
                ),
                SwitchListTile(
                  activeColor: const Color(0xFFFFB800),
                  secondary: const Icon(CupertinoIcons.person_2_fill, color: Colors.blue),
                  title: Text("Friend Requests & Activity", style: TextStyle(color: textColor)),
                  value: _friendNotif,
                  onChanged: (val) async {
                    setSheetState(() => _friendNotif = val);
                    setState(() => _friendNotif = val);
                    await _updateNotificationPreference('friendNotifications', val);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Divider(height: 1, color: theme.dividerColor),
                ),
                SwitchListTile(
                  activeColor: const Color(0xFFFFB800),
                  secondary: const Icon(CupertinoIcons.speaker_2_fill, color: Colors.green),
                  title: Text("Notification Sounds", style: TextStyle(color: textColor)),
                  value: _notificationSound,
                  onChanged: (val) async {
                    setSheetState(() => _notificationSound = val);
                    setState(() => _notificationSound = val);
                    await _updateNotificationPreference('playSound', val);
                  },
                ),
                SwitchListTile(
                  activeColor: const Color(0xFFFFB800),
                  secondary: const Icon(CupertinoIcons.waveform_path, color: Colors.purple),
                  title: Text("Vibration", style: TextStyle(color: textColor)),
                  value: _notificationVibration,
                  onChanged: (val) async {
                    setSheetState(() => _notificationVibration = val);
                    setState(() => _notificationVibration = val);
                    await _updateNotificationPreference('enableVibration', val);
                  },
                ),
              ],
            ),
          );
        }
      ),
    );
  }

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
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
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
                    Text("Personal Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: textColor)),
                  ],
                ),
                contentPadding: const EdgeInsets.all(24),
                content: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildEnhancedTextField(context: context, controller: emailController, label: "Email Address", icon: CupertinoIcons.mail_solid, readOnly: true),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(context: context, controller: studentIdController, label: "Student ID", icon: CupertinoIcons.doc_text_fill, readOnly: true),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(context: context, controller: firstNameController, label: "First Name", icon: CupertinoIcons.person_fill),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(context: context, controller: middleNameController, label: "Middle Name", icon: CupertinoIcons.person_fill),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(context: context, controller: lastNameController, label: "Last Name", icon: CupertinoIcons.person_fill),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildEnhancedTextField(context: context, controller: gradeController, label: "Grade", icon: CupertinoIcons.chart_bar_alt_fill)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildEnhancedTextField(context: context, controller: sectionController, label: "Section", icon: CupertinoIcons.group_solid)),
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
                          child: Text("Cancel", style: TextStyle(color: textColor.withOpacity(0.6), fontWeight: FontWeight.bold)),
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
                              : const Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            title: Text("Change Password", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: textColor)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildEnhancedTextField(context: context, controller: currentPasswordController, label: "Current Password", icon: CupertinoIcons.lock_fill, obscureText: true),
                  const SizedBox(height: 16),
                  _buildEnhancedTextField(context: context, controller: newPasswordController, label: "New Password", icon: CupertinoIcons.lock_rotation, obscureText: true),
                  const SizedBox(height: 16),
                  _buildEnhancedTextField(context: context, controller: confirmPasswordController, label: "Confirm New Password", icon: CupertinoIcons.checkmark_shield_fill, obscureText: true),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
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
                child: const Text("Update"),
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