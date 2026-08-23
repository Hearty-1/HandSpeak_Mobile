import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Game Settings State
  bool _soundEnabled = true;
  String _selectedTheme = "Light Theme";

  // Notification State
  bool _streakNotif = true;
  bool _dailyChallengesNotif = true;
  bool _friendNotif = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        centerTitle: true,
        title: const Text(
          "Settings",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24.0),
        children: [
          _buildSectionHeader("Account & Profile"),
          _buildSettingsCard(
            children: [
              ListTile(
                leading: const Icon(CupertinoIcons.person_alt_circle, color: Color(0xFFFFB800)),
                title: const Text("Edit Personal Details"),
                trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                onTap: () => _showEditProfileDialog(context),
              ),
            ],
          ),

          _buildSectionHeader("Game Settings"),
          _buildSettingsCard(
            children: [
              SwitchListTile(
                activeColor: const Color(0xFFFFB800),
                secondary: const Icon(CupertinoIcons.speaker_2_fill, color: Color(0xFFFFB800)),
                title: const Text("Sound Effects"),
                value: _soundEnabled,
                onChanged: (val) => setState(() => _soundEnabled = val),
              ),
              const Divider(height: 1, color: Colors.black12),
              ListTile(
                leading: const Icon(CupertinoIcons.paintbrush_fill, color: Color(0xFFFFB800)),
                title: const Text("Theme"),
                trailing: DropdownButton<String>(
                  value: _selectedTheme,
                  underline: const SizedBox(),
                  icon: const Icon(CupertinoIcons.chevron_down, size: 16),
                  items: ["Light Theme", "Dark Theme", "System Default"]
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedTheme = val);
                  },
                ),
              ),
            ],
          ),

          _buildSectionHeader("Notifications"),
          _buildSettingsCard(
            children: [
              SwitchListTile(
                activeColor: const Color(0xFFFFB800),
                secondary: const Icon(CupertinoIcons.flame_fill, color: Colors.deepOrange),
                title: const Text("Streak Reminders"),
                value: _streakNotif,
                onChanged: (val) => setState(() => _streakNotif = val),
              ),
              const Divider(height: 1, color: Colors.black12),
              SwitchListTile(
                activeColor: const Color(0xFFFFB800),
                secondary: const Icon(CupertinoIcons.star_fill, color: Color(0xFFFFB800)),
                title: const Text("Daily Challenges"),
                value: _dailyChallengesNotif,
                onChanged: (val) => setState(() => _dailyChallengesNotif = val),
              ),
              const Divider(height: 1, color: Colors.black12),
              SwitchListTile(
                activeColor: const Color(0xFFFFB800),
                secondary: const Icon(CupertinoIcons.person_2_fill, color: Colors.blue),
                title: const Text("Friend Requests & Activity"),
                value: _friendNotif,
                onChanged: (val) => setState(() => _friendNotif = val),
              ),
            ],
          ),

          _buildSectionHeader("Security & Privacy"),
          _buildSettingsCard(
            children: [
              ListTile(
                leading: const Icon(CupertinoIcons.lock_fill, color: Colors.black54),
                title: const Text("Change Password"),
                trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                onTap: () => _showChangePasswordDialog(context),
              ),
              const Divider(height: 1, color: Colors.black12),
              ListTile(
                leading: const Icon(CupertinoIcons.device_phone_portrait, color: Colors.black54),
                title: const Text("Session & Activity Logs"),
                trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
                onTap: () => _showSessionHistory(context),
              ),
            ],
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.black54,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildEnhancedTextField({
    required TextEditingController controller, 
    required String label, 
    required IconData icon, 
    bool readOnly = false,
    bool obscureText = false, 
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      obscureText: obscureText, 
      style: TextStyle(
        color: readOnly ? Colors.black45 : Colors.black87,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black54, fontSize: 14),
        prefixIcon: Icon(icon, color: readOnly ? Colors.black26 : const Color(0xFFFFB800), size: 20),
        filled: true,
        fillColor: readOnly ? Colors.grey.shade100 : Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFFB800), width: 1.5),
        ),
      ),
    );
  }

  // --- ACTIVITY LOG HELPER ---
  
  Future<void> _logAccountActivity({
    required String uid,
    required String action,
    required String description,
  }) async {
    try {
      String formattedTime = DateFormat("MMMM d, yyyy 'at' h:mm:ss a").format(DateTime.now());

      // Target path: users -> [uid] -> login_activity
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('login_activity')
          .add({
        'action': action,
        'description': description,
        'status': 'active',
        'timestamp': formattedTime,
        'uid': uid,
      });
    } catch (e) {
      debugPrint("Failed to log activity: $e");
    }
  }

  // --- DIALOGS FOR SETTINGS ACTIONS ---

  void _showEditProfileDialog(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must be logged in to edit details.")),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
              backgroundColor: Colors.white,
              content: SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(color: Color(0xFFFFB800))),
              ),
            );
          }

          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text("Error"),
              content: const Text("Could not load user details. Please try again later."),
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
                backgroundColor: Colors.white,
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
                    const Text("Personal Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                    const SizedBox(height: 8),
                    const Text(
                      "Review or update your account information below.",
                      style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.normal),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                contentPadding: const EdgeInsets.all(24),
                content: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildEnhancedTextField(
                        controller: emailController, 
                        label: "Email Address", 
                        icon: CupertinoIcons.mail_solid, 
                        readOnly: true, 
                      ),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(
                        controller: studentIdController, 
                        label: "Student ID", 
                        icon: CupertinoIcons.doc_text_fill,
                        readOnly: true, 
                      ),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(
                        controller: firstNameController, 
                        label: "First Name", 
                        icon: CupertinoIcons.person_fill,
                      ),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(
                        controller: middleNameController, 
                        label: "Middle Name", 
                        icon: CupertinoIcons.person_fill,
                      ),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(
                        controller: lastNameController, 
                        label: "Last Name", 
                        icon: CupertinoIcons.person_fill,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildEnhancedTextField(
                              controller: gradeController, 
                              label: "Grade", 
                              icon: CupertinoIcons.chart_bar_alt_fill,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEnhancedTextField(
                              controller: sectionController, 
                              label: "Section", 
                              icon: CupertinoIcons.group_solid,
                            ),
                          ),
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
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: isUpdating ? null : () => Navigator.pop(context), 
                          child: const Text("Cancel", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFB800),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: isUpdating ? null : () async {
                            setState(() => isUpdating = true);
                            
                            try {
                              String fullName = '${firstNameController.text.trim()} ${middleNameController.text.trim()} ${lastNameController.text.trim()}';
                              fullName = fullName.replaceAll('  ', ' ').trim();

                              await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                                'firstName': firstNameController.text.trim(),
                                'middleName': middleNameController.text.trim(),
                                'lastName': lastNameController.text.trim(),
                                'grade': gradeController.text.trim(),
                                'section': sectionController.text.trim(),
                                'name': fullName, 
                              });

                              // Log the activity under users -> [uid] -> login_activity
                              await _logAccountActivity(
                                uid: user.uid, 
                                action: "Profile details updated", 
                                description: "Updated personal information (Name, Grade, Section)."
                              );

                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Row(
                                      children: [
                                        Icon(CupertinoIcons.checkmark_alt_circle_fill, color: Colors.white),
                                        SizedBox(width: 12),
                                        Text("Profile updated successfully!"),
                                      ],
                                    ),
                                    backgroundColor: Colors.green.shade600,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                );
                              }
                            } catch (e) {
                              setState(() => isUpdating = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Failed to update: $e"), backgroundColor: Colors.red),
                              );
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
    bool isLoading = false;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: Colors.white,
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
                  child: const Icon(CupertinoIcons.lock_shield_fill, color: Color(0xFFFFB800), size: 48),
                ),
                const SizedBox(height: 16),
                const Text("Change Password", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                const SizedBox(height: 8),
                const Text(
                  "Create a new, strong password to keep your account secure.",
                  style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.normal),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            contentPadding: const EdgeInsets.all(24),
            content: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.red.shade400, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(errorMessage!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildEnhancedTextField(
                    controller: currentPasswordController,
                    label: "Current Password",
                    icon: CupertinoIcons.lock_fill,
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  _buildEnhancedTextField(
                    controller: newPasswordController,
                    label: "New Password",
                    icon: CupertinoIcons.lock_rotation,
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  _buildEnhancedTextField(
                    controller: confirmPasswordController,
                    label: "Confirm New Password",
                    icon: CupertinoIcons.checkmark_shield_fill,
                    obscureText: true,
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
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: isLoading ? null : () => Navigator.pop(context), 
                      child: const Text("Cancel", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB800),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: isLoading ? null : () async {
                        setState(() => errorMessage = null);

                        if (newPasswordController.text.isEmpty || currentPasswordController.text.isEmpty) {
                          setState(() => errorMessage = "Please fill in all password fields.");
                          return;
                        }
                        if (newPasswordController.text != confirmPasswordController.text) {
                          setState(() => errorMessage = "Your new passwords do not match.");
                          return;
                        }

                        setState(() => isLoading = true);
                        
                        try {
                          User? user = FirebaseAuth.instance.currentUser;
                          if (user != null && user.email != null) {
                            AuthCredential credential = EmailAuthProvider.credential(
                              email: user.email!,
                              password: currentPasswordController.text.trim(),
                            );
                            await user.reauthenticateWithCredential(credential);
                            await user.updatePassword(newPasswordController.text.trim());
                            
                            // Log the activity under users -> [uid] -> login_activity
                            await _logAccountActivity(
                              uid: user.uid, 
                              action: "Password changed", 
                              description: "Successfully updated account password."
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Row(
                                    children: [
                                      Icon(CupertinoIcons.checkmark_alt_circle_fill, color: Colors.white),
                                      SizedBox(width: 12),
                                      Text("Password updated successfully!"),
                                    ],
                                  ),
                                  backgroundColor: Colors.green.shade600,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              );
                            }
                          }
                        } on FirebaseAuthException catch (e) {
                          setState(() {
                            if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
                              errorMessage = "The current password you entered is incorrect.";
                            } else if (e.code == 'weak-password') {
                              errorMessage = "The new password is too weak. Please use at least 8 characters.";
                            } else {
                              errorMessage = e.message ?? "An error occurred. Please try again.";
                            }
                          });
                        } catch (e) {
                          setState(() => errorMessage = "An unexpected error occurred.");
                        } finally {
                          setState(() => isLoading = false);
                        }
                      }, 
                      child: isLoading 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : const Text("Update", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return DefaultTabController(
            length: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 24.0, left: 24.0, right: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Security & Activity", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TabBar(
                    indicatorColor: const Color(0xFFFFB800),
                    labelColor: const Color(0xFFFFB800),
                    unselectedLabelColor: Colors.black54,
                    dividerColor: Colors.grey.shade200,
                    tabs: const [
                      Tab(text: "Device History"),
                      Tab(text: "Activity Logs"),
                    ],
                  ),
                  const SizedBox(height: 16),
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

  // --- TAB 1: DEVICE HISTORY ---
  Widget _buildDeviceHistoryTab(String uid, ScrollController scrollController) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('device_sessions')
          .orderBy('lastLogin', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB800)));
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              "No registered device history found.",
              style: TextStyle(color: Colors.black54),
            ),
          );
        }

        return ListView.separated(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.black12),
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            var data = doc.data() as Map<String, dynamic>;
            
            String deviceName = data['deviceName'] ?? 'Unknown Device';
            String os = data['os'] ?? 'Unknown OS';
            Timestamp? lastLogin = data['lastLogin'];
            
            String dateStr = lastLogin != null 
                ? DateFormat.yMMMd().add_jm().format(lastLogin.toDate()) 
                : 'Recent Session';

            bool isCurrentDevice = index == 0;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4.0),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isCurrentDevice ? const Color(0xFFFFF9E5) : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  os.toLowerCase().contains('android') || os.toLowerCase().contains('ios') 
                      ? CupertinoIcons.device_phone_portrait 
                      : CupertinoIcons.desktopcomputer,
                  color: isCurrentDevice ? const Color(0xFFFFB800) : Colors.black54, 
                ),
              ),
              title: Text(
                deviceName + (isCurrentDevice ? " (Active Device)" : ""),
                style: TextStyle(
                  fontWeight: isCurrentDevice ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: Text("$os\nLast active: $dateStr", style: const TextStyle(fontSize: 12)),
              isThreeLine: true,
              trailing: IconButton(
                icon: const Icon(CupertinoIcons.trash, color: Colors.redAccent, size: 20),
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('device_sessions')
                      .doc(doc.id)
                      .delete();
                },
              ),
            );
          },
        );
      },
    );
  }

  // --- TAB 2: ACTIVITY LOGS ---
  Widget _buildActivityLogsTab(String uid, ScrollController scrollController) {
    return StreamBuilder<QuerySnapshot>(
      // Target path: users -> [uid] -> login_activity
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('login_activity')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB800)));
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No activity logs found."));
        }

        return ListView.separated(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.black12),
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            var data = doc.data() as Map<String, dynamic>;
            
            String action = data['action'] ?? 'Unknown Action';
            String description = data['description'] ?? 'No description provided';
            String status = data['status'] ?? 'unknown';
            
            String timeStr = 'Unknown time';
            if (data['timestamp'] != null) {
              if (data['timestamp'] is Timestamp) {
                timeStr = DateFormat.yMMMd().add_jm().format((data['timestamp'] as Timestamp).toDate());
              } else {
                timeStr = data['timestamp'].toString(); 
              }
            }

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.list_bullet, color: Colors.blue, size: 20),
              ),
              title: Text(action, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(description, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text(timeStr, style: const TextStyle(fontSize: 12, color: Colors.black45)),
                  ],
                ),
              ),
              trailing: status == 'active' 
                  ? const Icon(CupertinoIcons.check_mark_circled_solid, color: Colors.green, size: 18)
                  : null,
            );
          },
        );
      },
    );
  }
}