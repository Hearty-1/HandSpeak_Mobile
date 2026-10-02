import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/services/progress_service.dart'; 
import 'alphabet/alphabet_interface.dart'; 
import 'numbers/numbers_interface.dart';  
import 'phrases/phrase_interface.dart'; 
import 'civic/civic_interface.dart';
import '../profile/profile.dart';  
import '../home/home.dart';  
import '../leaderboard/arena.dart'; 
import '../home/notification_bell.dart';
import '../home/settings_screen.dart';

Route _fadeRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 180),
  );
}

class SnedInterface2 extends StatelessWidget {
  const SnedInterface2({super.key}); 

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    final Color adaptiveProgressColor = theme.colorScheme.secondary;

    const double baseWidth = 393; 
    const double baseHeight = 680;  
    const int targetXp = 1000; 

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(), 
      builder: (context, snapshot) { 
        int alphabetXp = 0; 
        int numbersXp = 0; 
        int wordsXp = 0; 
        int civicsXp = 0; 

        if (snapshot.hasData && snapshot.data!.exists) { 
          final data = snapshot.data!.data() as Map<String, dynamic>?; 
          if (data != null) { 
            alphabetXp = data['alphabetXp'] ?? 0; 
            numbersXp = data['numbersXp'] ?? 0; 
            wordsXp = data['phraseXp'] ?? data['wordsXp'] ?? 0; 
            civicsXp = data['civicsXp'] ?? 0; 

            if (data['progress'] != null) {
              Map<String, dynamic> progressMap = Map<String, dynamic>.from(data['progress']);
              int mappedAlphabetXp = 0;
              int mappedNumbersXp = 0;
              int mappedWordsXp = 0;
              int mappedCivicsXp = 0;

              progressMap.forEach((key, value) {
                int xpValue = (value as num).toInt();
                final lowerKey = key.toLowerCase();
                
                if (lowerKey.startsWith('alphabet')) mappedAlphabetXp += xpValue;
                if (lowerKey.startsWith('number')) mappedNumbersXp += xpValue;
                if (lowerKey.startsWith('phrase') || lowerKey.startsWith('word')) mappedWordsXp += xpValue;
                if (lowerKey.startsWith('civic')) mappedCivicsXp += xpValue;
              });

              if (mappedAlphabetXp > alphabetXp) alphabetXp = mappedAlphabetXp;
              if (mappedNumbersXp > numbersXp) numbersXp = mappedNumbersXp;
              if (mappedWordsXp > wordsXp) wordsXp = mappedWordsXp;
              if (mappedCivicsXp > civicsXp) civicsXp = mappedCivicsXp;
            }
          }
        }

        final bool isWordsLocked = alphabetXp < targetXp; 
        final bool isCivicsLocked = isWordsLocked || (wordsXp < targetXp); 

        int displayAlpXp = alphabetXp > targetXp ? targetXp : alphabetXp; 
        int displayNumXp = numbersXp > targetXp ? targetXp : numbersXp; 
        int displayWordsXp = wordsXp > targetXp ? targetXp : wordsXp; 
        int displayCivicsXp = civicsXp > targetXp ? targetXp : civicsXp;

        return LayoutBuilder(
          builder: (context, constraints) { 
            final double scale = constraints.maxWidth / baseWidth; 

            return Scaffold(
              extendBodyBehindAppBar: true, 
              extendBody: true, 
              backgroundColor: theme.scaffoldBackgroundColor, 
              
              drawer: Drawer(
                backgroundColor: theme.cardColor.withOpacity(0.95), 
                elevation: 0,
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(top: 60, bottom: 20, left: 20, right: 20),
                      decoration: BoxDecoration(
                        color: theme.primaryColor, 
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Image.asset("assets/pictures/logo.png", width: 60),
                              const SizedBox(width: 10),
                              Image.asset("assets/pictures/image 66.png", width: 60),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Menu',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        children: [
                          ListTile(
                            leading: Icon(Icons.settings, color: theme.primaryColor),
                            title: Text('Settings', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, _fadeRoute(const SettingsScreen()));
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.help_outline, color: theme.primaryColor),
                            title: Text('Help & Support', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, _fadeRoute(const InfoDetailScreen(
                                title: 'Help & Support',
                                sections: [
                                  InfoSection(title: 'The Learning Loop', body: 'Your Filipino Sign Language learning path is divided into four stages: Tutorials, Practice, Activities, and Challenges. Achieve 1000 XP points to unlock the next module.', icon: Icons.loop_rounded),
                                  InfoSection(title: 'Camera Combat', body: 'Ensure you are in a well-lit area and use the Mirror-Mode Camera. A green checkmark means you scored a hit, while a red "X" means you need to adjust your form.', icon: Icons.camera_alt_rounded),
                                  InfoSection(title: 'Leveling Up & Streaks', body: 'Keep practicing to earn Experience Points (XP) and fill your Level Progress Bar. Enable Streak Reminders to keep your momentum going.', icon: Icons.local_fire_department_rounded),
                                  InfoSection(title: 'Multiplayer Challenges', body: 'Challenge your classmates by tapping "Join a Room" and entering a Room Code, or act as the host by selecting "Create a Room".', icon: Icons.group_rounded),
                                  InfoSection(title: 'Customizing Experience', body: 'Visit the Settings screen to change your game Theme (like Galaxy Explorer or Deep Ocean), and toggle your Background Music on or off.', icon: Icons.palette_rounded),
                                  InfoSection(title: 'Reporting Bugs', body: 'Teachers can submit a bug report directly to the admin using the "Feedback & Support" tool. Students should report issues to their teachers.', icon: Icons.bug_report_rounded),
                                ],
                              )));
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.info_outline, color: theme.primaryColor),
                            title: Text('About Us', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, _fadeRoute(const AboutUsScreen()));
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.gavel_rounded, color: theme.primaryColor),
                            title: Text('Terms & Privacy Policy', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, _fadeRoute(const InfoDetailScreen(
                                title: 'Terms of Service & Privacy Policy',
                                sections: [
                                  InfoSection(title: '1. Acceptance of Terms', body: 'By downloading, installing, accessing, or using the HandSpeak application, you acknowledge that you have read, understood, and agree to be bound by these Terms of Service. If you do not agree to these terms, you must discontinue use immediately.', icon: Icons.handshake_rounded),
                                  InfoSection(title: '2. Eligibility & Access', body: 'Access to the HandSpeak platform is expressly restricted to authorized personnel, faculty, and enrolled students of Sto. Tomas North Central School (STNCS). All new registrations are subject to administrative review and remain in a "Pending" status until formally verified.', icon: Icons.admin_panel_settings_rounded),
                                  InfoSection(title: '3. Account Security', body: 'Users are solely responsible for maintaining the confidentiality of their account credentials. HandSpeak assumes no liability for any loss, damage, or unauthorized access arising from a user\'s failure to secure their account information.', icon: Icons.lock_person_rounded),
                                  InfoSection(title: '4. Device Permissions', body: 'The application requires access to your device\'s camera to facilitate real-time gesture recognition. By using the app, you grant explicit consent for this hardware access required for core functionality.', icon: Icons.perm_camera_mic_rounded),
                                  InfoSection(title: '5. Content & Moderation', body: 'All user-generated content, instructional materials, and dataset modifications submitted by faculty members are subject to administrative review. We reserve the right to modify, restrict, or remove any content at our sole discretion to maintain educational integrity.', icon: Icons.rule_rounded),
                                  InfoSection(title: '6. Limitation of Liability', body: 'HandSpeak is provided on an "AS IS" and "AS AVAILABLE" basis. The developers disclaim all warranties, express or implied, including accuracy of gesture recognition. In no event shall the developers be liable for direct, indirect, incidental, or consequential damages resulting from app usage.', icon: Icons.warning_amber_rounded),
                                  InfoSection(title: '7. Data Collection (Player Profiles)', body: 'We collect essential details to build your player profile—such as your Full Name, Email, Student ID, Grade Level, and Section. This information is required for account generation and system security.', icon: Icons.person_rounded),
                                  InfoSection(title: '8. Privacy & Stats Tracking', body: 'We track your gameplay stats—including module completion rates, experience points (XP), earned badges, and gesture accuracy scores. This ensures your progress is accurately recorded and saved.', icon: Icons.analytics_rounded),
                                  InfoSection(title: '9. Teacher Analytics', body: 'Your performance data is securely beamed to a cloud database so your teachers can view descriptive and predictive analytics. This aids educators in tailoring your learning interventions while maintaining strict role-based access control (RBAC).', icon: Icons.school_rounded),
                                ],
                              )));
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              appBar: AppBar(
                backgroundColor: theme.cardColor.withOpacity(0.4),
                elevation: 0,
                centerTitle: true,
                iconTheme: theme.iconTheme.copyWith(color: textColor),
                flexibleSpace: ClipRRect(
                  clipBehavior: Clip.antiAlias,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                title: Text(
                  "Modules",
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w800, letterSpacing: -0.5, fontSize: 22),
                ),
                actions: [
                  const NotificationBell(),
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0, left: 4.0),
                    child: ClipOval(
                      child: Image.asset("assets/pictures/image 66.png", width: 40, height: 40, fit: BoxFit.cover),
                    ), 
                  ),
                ],
              ),
      
              bottomNavigationBar: SafeArea(
                child: Container(
                  width: double.infinity,
                  height: 74,
                  margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    clipBehavior: Clip.antiAlias,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.cardColor.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withOpacity(isDark ? 0.15 : 0.4),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildNavIconButton(theme, Icons.home_rounded, false, () => Navigator.pushAndRemoveUntil(context, _fadeRoute(const SnedInterafce1(userName: "Student")), (route) => false)),
                            _buildNavIconButton(theme, Icons.auto_stories_rounded, true, () {}),
                            _buildNavIconButton(theme, Icons.sports_esports_rounded, false, () => Navigator.pushReplacement(context, _fadeRoute(const LeaderboardScreen()))),
                            _buildNavIconButton(theme, Icons.person_rounded, false, () => Navigator.pushReplacement(context, _fadeRoute(const ProfileScreen()))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              body: Stack(
                children: [
                  Positioned(
                    top: -50,
                    left: -50,
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.primaryColor.withOpacity(0.20),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 400,
                    right: -100,
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.secondary.withOpacity(0.15),
                      ),
                    ),
                  ),

                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.only(top: 70 * scale, bottom: 120 * scale),
                      child: SizedBox(
                        height: baseHeight * scale,
                        width: constraints.maxWidth,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildGridNode(
                              context: context,
                              scale: scale,
                              leftOffset: 12,
                              topOffset: 0,
                              title: "Alphabets",
                              imagePath: "assets/pictures/abc.png",
                              currentXp: displayAlpXp,
                              targetXp: targetXp,
                              isLocked: false,
                              progressColor: adaptiveProgressColor,
                              onTap: () => Navigator.push(
                                context, 
                                _fadeRoute(AlphabetInterface(currentXp: displayAlpXp, targetXp: targetXp)),
                              ),
                            ),
                            _buildGridNode(
                              context: context,
                              scale: scale,
                              leftOffset: 201, 
                              topOffset: 0, 
                              title: "Numbers",
                              imagePath: "assets/pictures/numbers.png",
                              currentXp: displayNumXp,
                              targetXp: targetXp,
                              isLocked: false,
                              progressColor: adaptiveProgressColor,
                              onTap: () => Navigator.push(
                                context, 
                                _fadeRoute(NumbersInterface(currentXp: displayNumXp, targetXp: targetXp)),
                              ),
                            ),
                            _buildGridNode(
                              context: context,
                              scale: scale,
                              leftOffset: 12,
                              topOffset: 330, 
                              title: "Words/Phrases",
                              imagePath: "assets/pictures/words.png",
                              currentXp: displayWordsXp,
                              targetXp: targetXp,
                              isLocked: isWordsLocked,
                              progressColor: adaptiveProgressColor,
                              onTap: () => Navigator.push(
                                context, 
                                _fadeRoute(PhraseInterface(currentXp: displayWordsXp, targetXp: targetXp)),
                              ),
                            ),
                            _buildGridNode(
                              context: context,
                              scale: scale,
                              leftOffset: 201,
                              topOffset: 330, 
                              title: "Civic\nObservances",
                              imagePath: "assets/pictures/civic.png",
                              currentXp: displayCivicsXp,
                              targetXp: targetXp,
                              isLocked: isCivicsLocked,
                              progressColor: adaptiveProgressColor,
                              onTap: () => Navigator.push(
                                context, 
                                _fadeRoute(CivicInterface(currentXp: displayCivicsXp, targetXp: targetXp)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNavIconButton(ThemeData theme, IconData icon, bool isSelected, VoidCallback onPressed) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: isSelected
          ? BoxDecoration(
              color: theme.primaryColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
            )
          : null,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(
          icon,
          color: isSelected ? theme.primaryColor : theme.colorScheme.onSurface.withOpacity(0.5),
          size: isSelected ? 30 : 28,
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildGridNode({
    required BuildContext context,
    required double scale,
    required double leftOffset,
    required double topOffset,
    required String title,
    required String imagePath,
    required int currentXp,
    required int targetXp,
    required bool isLocked,
    required Color progressColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return Positioned(
      left: leftOffset * scale,
      top: topOffset * scale,
      width: 180 * scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: isLocked ? null : onTap,
            child: Opacity(
              opacity: isLocked ? 0.6 : 1.0,
              child: SizedBox(
                height: 65 * scale, 
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 24 * scale,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.2,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 12 * scale),

          GestureDetector(
            onTap: isLocked ? null : onTap,
            child: Opacity(
              opacity: isLocked ? 0.5 : 1.0,
              child: SizedBox(
                width: 150 * scale,
                height: 150 * scale,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(imagePath),
                          fit: BoxFit.contain,
                        ),
                        boxShadow: isLocked ? [] : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                    ),
                    if (isLocked)
                      Container(
                        width: 70 * scale,
                        height: 90 * scale,
                        decoration: const BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage("assets/pictures/locked.png"),
                            fit: BoxFit.fill,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 16 * scale),

          Opacity(
            opacity: isLocked ? 0.45 : 1.0,
            child: _buildProgressPanel(
              context: context,
              scale: scale,
              title: "Progress",
              xp: "$currentXp XP",
              xpNext: "${targetXp - currentXp} to next",
              progressRatio: currentXp / targetXp,
              progressColor: progressColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressPanel({
    required BuildContext context,
    required double scale, 
    required String title, 
    required String xp, 
    required String xpNext,
    required double progressRatio,
    required Color progressColor,
  }) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16 * scale),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 178 * scale, height: 76 * scale,
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.75), 
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06), 
                blurRadius: 12, 
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 14 * scale, top: 10 * scale, 
                child: Text(
                  title, 
                  style: TextStyle(
                    color: textColor, 
                    fontSize: 13 * scale, 
                    fontFamily: 'Inter', 
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ), 
              Positioned(
                left: 12 * scale, top: 28 * scale, 
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded, 
                      color: Colors.amber.shade500, 
                      size: 20 * scale,
                    ),
                    SizedBox(width: 4 * scale),
                    Text(
                      xp, 
                      style: TextStyle(
                        color: theme.primaryColor, 
                        fontSize: 18 * scale, 
                        fontFamily: 'Inter', 
                        fontWeight: FontWeight.w900, 
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ), 
              
              Positioned(
                left: 12 * scale, top: 58 * scale,
                child: Container(
                  width: 154 * scale, height: 6 * scale,
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withOpacity(0.2), 
                    borderRadius: BorderRadius.circular(25 * scale),
                  ),
                ),
              ),
              
              Positioned(
                left: 12 * scale, top: 58 * scale,
                child: Container(
                  width: (154 * progressRatio.clamp(0.0, 1.0)) * scale, height: 6 * scale,
                  decoration: BoxDecoration(
                    color: progressColor, 
                    borderRadius: BorderRadius.circular(25 * scale),
                    boxShadow: [BoxShadow(color: progressColor.withOpacity(0.4), blurRadius: 4)],
                  ),
                ),
              ),
              
              Positioned(
                right: 12 * scale, top: 11 * scale, 
                child: Text(
                  xpNext, 
                  style: TextStyle(
                    color: textColor.withOpacity(0.5), 
                    fontSize: 9 * scale, 
                    fontFamily: 'Inter', 
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ), 
            ],
          ),
        ),
      ),
    );
  }
}