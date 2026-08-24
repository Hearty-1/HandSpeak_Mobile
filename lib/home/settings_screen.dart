import 'package:flutter/material.dart'; //[cite: 9]
import 'package:flutter/cupertino.dart'; //[cite: 9]
import 'package:firebase_auth/firebase_auth.dart'; //[cite: 9]
import 'package:cloud_firestore/cloud_firestore.dart'; //[cite: 9]
import 'package:intl/intl.dart'; //[cite: 9]
import 'package:provider/provider.dart'; //[cite: 9]
import '../services/auth_service.dart'; //[cite: 9]
import '../providers/theme_provider.dart'; //[cite: 9]
import '../providers/sound_provider.dart'; //[cite: 9]

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key}); //[cite: 9]

  @override
  State<SettingsScreen> createState() => _SettingsScreenState(); //[cite: 9]
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Notification State
  bool _streakNotif = true; //[cite: 9]
  bool _dailyChallengesNotif = true; //[cite: 9]
  bool _friendNotif = true; //[cite: 9]

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context); //[cite: 9]
    final soundProvider = Provider.of<SoundProvider>(context); //[cite: 9]
    final theme = Theme.of(context); //[cite: 9]
    final textColor = theme.colorScheme.onBackground; //[cite: 9]

    return Scaffold( //[cite: 9]
      backgroundColor: theme.scaffoldBackgroundColor, //[cite: 9]
      appBar: AppBar( //[cite: 9]
        backgroundColor: Colors.transparent, //[cite: 9]
        elevation: 0, //[cite: 9]
        iconTheme: theme.appBarTheme.iconTheme, //[cite: 9]
        centerTitle: true, //[cite: 9]
        title: Text( //[cite: 9]
          "Settings", //[cite: 9]
          style: theme.appBarTheme.titleTextStyle, //[cite: 9]
        ),
      ),
      body: ListView( //[cite: 9]
        physics: const BouncingScrollPhysics(), //[cite: 9]
        padding: const EdgeInsets.all(24.0), //[cite: 9]
        children: [ //[cite: 9]
          _buildSectionHeader("Account & Profile", textColor), //[cite: 9]
          _buildSettingsCard( //[cite: 9]
            context: context, //[cite: 9]
            children: [ //[cite: 9]
              ListTile( //[cite: 9]
                leading: const Icon(CupertinoIcons.person_alt_circle, color: Color(0xFFFFB800)), //[cite: 9]
                title: Text("Edit Personal Details", style: TextStyle(color: textColor)), //[cite: 9]
                trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: textColor.withOpacity(0.5)), //[cite: 9]
                onTap: () { //[cite: 9]
                  _showEditProfileDialog(context); //[cite: 9]
                },
              ),
            ],
          ),

          _buildSectionHeader("Game Settings", textColor), //[cite: 9]
          _buildSettingsCard( //[cite: 9]
            context: context, //[cite: 9]
            children: [ //[cite: 9]
              SwitchListTile( //[cite: 9]
                activeColor: const Color(0xFFFFB800), //[cite: 9]
                secondary: const Icon(CupertinoIcons.speaker_2_fill, color: Color(0xFFFFB800)), //[cite: 9]
                title: Text("Sound Effects", style: TextStyle(color: textColor)), //[cite: 9]
                value: soundProvider.isSoundEnabled, //[cite: 9]
                onChanged: (val) { //[cite: 9]
                  // Only toggle if the switch value is different from the current state
                  if (soundProvider.isSoundEnabled != val) {
                    soundProvider.toggleSound();
                  }
                },
              ),
              Divider(height: 1, color: theme.dividerColor), //[cite: 9]
              ListTile( //[cite: 9]
                leading: const Icon(CupertinoIcons.paintbrush_fill, color: Color(0xFFFFB800)), //[cite: 9]
                title: Text("Theme", style: TextStyle(color: textColor)), //[cite: 9]
                trailing: DropdownButton<String>( //[cite: 9]
                  value: themeProvider.themeString, //[cite: 9]
                  dropdownColor: theme.cardColor, //[cite: 9]
                  underline: const SizedBox(), //[cite: 9]
                  icon: Icon(CupertinoIcons.chevron_down, size: 16, color: textColor), //[cite: 9]
                  items: ["Default Theme", "Light Theme", "Dark Theme", "System Default"] //[cite: 9]
                      .map((t) => DropdownMenuItem( //[cite: 9]
                            value: t, //[cite: 9]
                            child: Text(t, style: TextStyle(color: textColor)), //[cite: 9]
                          ))
                      .toList(), //[cite: 9]
                  onChanged: (val) { //[cite: 9]
                    if (val != null) { //[cite: 9]
                      themeProvider.setThemeFromString(val); //[cite: 9]
                    }
                  },
                ),
              ),
            ],
          ),

          _buildSectionHeader("Notifications", textColor), //[cite: 9]
          _buildSettingsCard( //[cite: 9]
            context: context, //[cite: 9]
            children: [ //[cite: 9]
              SwitchListTile( //[cite: 9]
                activeColor: const Color(0xFFFFB800), //[cite: 9]
                secondary: const Icon(CupertinoIcons.flame_fill, color: Colors.deepOrange), //[cite: 9]
                title: Text("Streak Reminders", style: TextStyle(color: textColor)), //[cite: 9]
                value: _streakNotif, //[cite: 9]
                onChanged: (val) { //[cite: 9]
                  setState(() => _streakNotif = val); //[cite: 9]
                },
              ),
              Divider(height: 1, color: theme.dividerColor), //[cite: 9]
              SwitchListTile( //[cite: 9]
                activeColor: const Color(0xFFFFB800), //[cite: 9]
                secondary: const Icon(CupertinoIcons.star_fill, color: Color(0xFFFFB800)), //[cite: 9]
                title: Text("Daily Challenges", style: TextStyle(color: textColor)), //[cite: 9]
                value: _dailyChallengesNotif, //[cite: 9]
                onChanged: (val) { //[cite: 9]
                  setState(() => _dailyChallengesNotif = val); //[cite: 9]
                },
              ),
              Divider(height: 1, color: theme.dividerColor), //[cite: 9]
              SwitchListTile( //[cite: 9]
                activeColor: const Color(0xFFFFB800), //[cite: 9]
                secondary: const Icon(CupertinoIcons.person_2_fill, color: Colors.blue), //[cite: 9]
                title: Text("Friend Requests & Activity", style: TextStyle(color: textColor)), //[cite: 9]
                value: _friendNotif, //[cite: 9]
                onChanged: (val) { //[cite: 9]
                  setState(() => _friendNotif = val); //[cite: 9]
                },
              ),
            ],
          ),

          _buildSectionHeader("Security & Privacy", textColor), //[cite: 9]
          _buildSettingsCard( //[cite: 9]
            context: context, //[cite: 9]
            children: [ //[cite: 9]
              ListTile( //[cite: 9]
                leading: Icon(CupertinoIcons.lock_fill, color: textColor.withOpacity(0.6)), //[cite: 9]
                title: Text("Change Password", style: TextStyle(color: textColor)), //[cite: 9]
                trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: textColor.withOpacity(0.5)), //[cite: 9]
                onTap: () { //[cite: 9]
                  _showChangePasswordDialog(context); //[cite: 9]
                },
              ),
              Divider(height: 1, color: theme.dividerColor), //[cite: 9]
              ListTile( //[cite: 9]
                leading: Icon(CupertinoIcons.device_phone_portrait, color: textColor.withOpacity(0.6)), //[cite: 9]
                title: Text("Session & Activity Logs", style: TextStyle(color: textColor)), //[cite: 9]
                trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: textColor.withOpacity(0.5)), //[cite: 9]
                onTap: () { //[cite: 9]
                  _showSessionHistory(context); //[cite: 9]
                },
              ),
            ],
          ),
          
          const SizedBox(height: 40), //[cite: 9]
        ],
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildSectionHeader(String title, Color textColor) {
    return Padding( //[cite: 9]
      padding: const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0), //[cite: 9]
      child: Text( //[cite: 9]
        title.toUpperCase(), //[cite: 9]
        style: TextStyle( //[cite: 9]
          color: textColor.withOpacity(0.6), //[cite: 9]
          fontWeight: FontWeight.bold, //[cite: 9]
          fontSize: 13, //[cite: 9]
          letterSpacing: 1.2, //[cite: 9]
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required BuildContext context, required List<Widget> children}) {
    final theme = Theme.of(context); //[cite: 9]
    return Container( //[cite: 9]
      decoration: BoxDecoration( //[cite: 9]
        color: theme.cardColor, //[cite: 9]
        borderRadius: BorderRadius.circular(20), //[cite: 9]
        boxShadow: [ //[cite: 9]
          BoxShadow( //[cite: 9]
            color: Colors.black.withOpacity(0.04), //[cite: 9]
            blurRadius: 10, //[cite: 9]
            offset: const Offset(0, 4), //[cite: 9]
          ),
        ],
      ),
      child: Column(children: children), //[cite: 9]
    );
  }

  Widget _buildEnhancedTextField({
    required BuildContext context, //[cite: 9]
    required TextEditingController controller,  //[cite: 9]
    required String label,  //[cite: 9]
    required IconData icon,  //[cite: 9]
    bool readOnly = false, //[cite: 9]
    bool obscureText = false,  //[cite: 9]
  }) {
    final theme = Theme.of(context); //[cite: 9]
    final textColor = theme.colorScheme.onBackground; //[cite: 9]

    return TextFormField( //[cite: 9]
      controller: controller, //[cite: 9]
      readOnly: readOnly, //[cite: 9]
      obscureText: obscureText,  //[cite: 9]
      style: TextStyle( //[cite: 9]
        color: readOnly ? textColor.withOpacity(0.5) : textColor, //[cite: 9]
        fontWeight: FontWeight.w500, //[cite: 9]
      ),
      decoration: InputDecoration( //[cite: 9]
        labelText: label, //[cite: 9]
        labelStyle: TextStyle(color: textColor.withOpacity(0.6), fontSize: 14), //[cite: 9]
        prefixIcon: Icon(icon, color: readOnly ? textColor.withOpacity(0.3) : const Color(0xFFFFB800), size: 20), //[cite: 9]
        filled: true, //[cite: 9]
        fillColor: readOnly ? theme.disabledColor.withOpacity(0.05) : theme.cardColor, //[cite: 9]
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), //[cite: 9]
        border: OutlineInputBorder( //[cite: 9]
          borderRadius: BorderRadius.circular(16), //[cite: 9]
          borderSide: BorderSide.none, //[cite: 9]
        ),
        enabledBorder: OutlineInputBorder( //[cite: 9]
          borderRadius: BorderRadius.circular(16), //[cite: 9]
          borderSide: BorderSide(color: theme.dividerColor, width: 1), //[cite: 9]
        ),
        focusedBorder: OutlineInputBorder( //[cite: 9]
          borderRadius: BorderRadius.circular(16), //[cite: 9]
          borderSide: const BorderSide(color: Color(0xFFFFB800), width: 1.5), //[cite: 9]
        ),
      ),
    );
  }

  // --- ACTIVITY LOG HELPER ---
  
  Future<void> _logAccountActivity({
    required String uid, //[cite: 9]
    required String action, //[cite: 9]
    required String description, //[cite: 9]
  }) async {
    try {
      String formattedTime = DateFormat("MMMM d, yyyy 'at' h:mm:ss a").format(DateTime.now()); //[cite: 9]

      await FirebaseFirestore.instance //[cite: 9]
          .collection('users') //[cite: 9]
          .doc(uid) //[cite: 9]
          .collection('login_activity') //[cite: 9]
          .add({ //[cite: 9]
        'action': action, //[cite: 9]
        'description': description, //[cite: 9]
        'status': 'active', //[cite: 9]
        'timestamp': formattedTime, //[cite: 9]
        'uid': uid, //[cite: 9]
      });
    } catch (e) {
      debugPrint("Failed to log activity: $e"); //[cite: 9]
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
              content: Text("Could not load user details. Please try again later.", style: TextStyle(color: textColor)),
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
                    const SizedBox(height: 8),
                    Text(
                      "Review or update your account information below.",
                      style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.6), fontWeight: FontWeight.normal),
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
                        context: context,
                        controller: emailController, 
                        label: "Email Address", 
                        icon: CupertinoIcons.mail_solid, 
                        readOnly: true, 
                      ),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(
                        context: context,
                        controller: studentIdController, 
                        label: "Student ID", 
                        icon: CupertinoIcons.doc_text_fill,
                        readOnly: true, 
                      ),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(
                        context: context,
                        controller: firstNameController, 
                        label: "First Name", 
                        icon: CupertinoIcons.person_fill,
                      ),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(
                        context: context,
                        controller: middleNameController, 
                        label: "Middle Name", 
                        icon: CupertinoIcons.person_fill,
                      ),
                      const SizedBox(height: 16),
                      _buildEnhancedTextField(
                        context: context,
                        controller: lastNameController, 
                        label: "Last Name", 
                        icon: CupertinoIcons.person_fill,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildEnhancedTextField(
                              context: context,
                              controller: gradeController, 
                              label: "Grade", 
                              icon: CupertinoIcons.chart_bar_alt_fill,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEnhancedTextField(
                              context: context,
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
                          child: Text("Cancel", style: TextStyle(color: textColor.withOpacity(0.6), fontWeight: FontWeight.bold)),
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
          final theme = Theme.of(context);
          final textColor = theme.colorScheme.onBackground;

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
                  child: const Icon(CupertinoIcons.lock_shield_fill, color: Color(0xFFFFB800), size: 48),
                ),
                const SizedBox(height: 16),
                Text("Change Password", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: textColor)),
                const SizedBox(height: 8),
                Text(
                  "Create a new, strong password to keep your account secure.",
                  style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.6), fontWeight: FontWeight.normal),
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
                    context: context,
                    controller: currentPasswordController,
                    label: "Current Password",
                    icon: CupertinoIcons.lock_fill,
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  _buildEnhancedTextField(
                    context: context,
                    controller: newPasswordController,
                    label: "New Password",
                    icon: CupertinoIcons.lock_rotation,
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  _buildEnhancedTextField(
                    context: context,
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
                      child: Text("Cancel", style: TextStyle(color: textColor.withOpacity(0.6), fontWeight: FontWeight.bold)),
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
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          final theme = Theme.of(context);
          final textColor = theme.colorScheme.onBackground;

          return DefaultTabController(
            length: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 24.0, left: 24.0, right: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Security & Activity", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 16),
                  TabBar(
                    indicatorColor: const Color(0xFFFFB800),
                    labelColor: const Color(0xFFFFB800),
                    unselectedLabelColor: textColor.withOpacity(0.5),
                    dividerColor: theme.dividerColor,
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
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onBackground;

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
          return Center(
            child: Text(
              "No registered device history found.",
              style: TextStyle(color: textColor.withOpacity(0.6)),
            ),
          );
        }

        return ListView.separated(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          separatorBuilder: (context, index) => Divider(height: 1, color: theme.dividerColor),
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
                  color: isCurrentDevice ? const Color(0xFFFFB800).withOpacity(0.15) : theme.disabledColor.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  os.toLowerCase().contains('android') || os.toLowerCase().contains('ios') 
                      ? CupertinoIcons.device_phone_portrait 
                      : CupertinoIcons.desktopcomputer,
                  color: isCurrentDevice ? const Color(0xFFFFB800) : textColor.withOpacity(0.6), 
                ),
              ),
              title: Text(
                deviceName + (isCurrentDevice ? " (Active Device)" : ""),
                style: TextStyle(
                  color: textColor,
                  fontWeight: isCurrentDevice ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: Text("$os\nLast active: $dateStr", style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.6))),
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
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onBackground;

    return StreamBuilder<QuerySnapshot>(
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
          return Center(child: Text("No activity logs found.", style: TextStyle(color: textColor.withOpacity(0.6))));
        }

        return ListView.separated(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          separatorBuilder: (context, index) => Divider(height: 1, color: theme.dividerColor),
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
              title: Text(action, style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(description, style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.8))),
                    const SizedBox(height: 4),
                    Text(timeStr, style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5))),
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