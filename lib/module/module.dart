import '/widgets/button_3d.dart';
import 'dart:ui'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
import '../widgets/app_nav_bar.dart';
import '/auth/login_screen.dart';
import '/auth/role_selection_screen.dart';
import '/services/role_service.dart';
import 'custom_category_screen.dart';

import '/services/performance_monitor.dart';
import '/providers/language_provider.dart';
import '/widgets/responsive.dart';

Route _fadeRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 180),
  );
}

/// Opens a module and records it as the most recently used one (the home
/// screen's "Continue Learning" shows the two latest).
void _openModule(BuildContext context, String moduleKey, Route route) {
  ProgressService().trackRecentModule(moduleKey);
  Navigator.push(context, route);
}

class SnedInterface2 extends StatelessWidget {
  const SnedInterface2({super.key}); 

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    // Role-based access: Faculty / Parent see every module unlocked (no XP gates,
    // no progress) and only reach tutorials + practice inside each module.
    final roles = context.roles;
    final bool isGuest = roles.isGuest;
    final bool canProgress = roles.can(AppFeature.progress);


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
        // users/{uid}: completion on the module cards (ModuleCard).
        Map<String, dynamic> userData = const {};

        if (snapshot.hasData && snapshot.data!.exists) { 
          final data = snapshot.data!.data() as Map<String, dynamic>?; 
          if (data != null) { 
            userData = data;
            alphabetXp = data['alphabetXp'] ?? 0; 
            numbersXp = data['numbersXp'] ?? 0; 
            wordsXp = data['phraseXp'] ?? data['wordsXp'] ?? 0; 
            // Civic screens write 'civicXp'; older data may have 'civicsXp'.
            civicsXp = ((data['civicXp'] ?? 0) as num).toInt() > ((data['civicsXp'] ?? 0) as num).toInt()
                ? (data['civicXp'] as num).toInt()
                : ((data['civicsXp'] ?? 0) as num).toInt();

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


        int displayAlpXp = alphabetXp > targetXp ? targetXp : alphabetXp; 
        int displayNumXp = numbersXp > targetXp ? targetXp : numbersXp; 
        int displayWordsXp = wordsXp > targetXp ? targetXp : wordsXp; 
        int displayCivicsXp = civicsXp > targetXp ? targetXp : civicsXp;

        // Every module is open to everyone (no unlock order).
        return LayoutBuilder(
          builder: (context, constraints) { 
            final double scale = Responsive.scale(constraints.maxWidth); 

            return Scaffold(
              extendBodyBehindAppBar: true, 
              extendBody: true, 
              backgroundColor: theme.scaffoldBackgroundColor, 
              
              drawer: Drawer(
                backgroundColor: theme.cardColor.withValues(alpha: 0.95), 
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
                            L.t('Menu', 'Menu'),
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (isGuest) ...[
                            const SizedBox(height: 4),
                            Text(
                              L.t('${roles.roleLabel} access', 'Access ng ${roles.roleLabel}'),
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        children: [
                          MenuCapsule(child: ListTile(
                            leading: Icon(Icons.settings_outlined, color: theme.primaryColor),
                            title: Text(L.t('Settings', 'Mga Setting'), style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, _fadeRoute(const SettingsScreen()));
                            },
                          )),
                          MenuCapsule(child: ListTile(
                            leading: Icon(Icons.help_outline, color: theme.primaryColor),
                            title: Text(L.t('Help & Support', 'Tulong at Suporta'), style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, _fadeRoute(InfoDetailScreen(
                                title: L.t('Help & Support', 'Tulong at Suporta'),
                                sections: [
                                  InfoSection(title: L.t('The Learning Loop', 'Ang Paraan ng Pag-aaral'), body: L.t('Your Filipino Sign Language learning path is divided into four stages: Tutorials, Practice, Activities, and Challenges.', 'Ang pag-aaral mo ng Filipino Sign Language ay may apat na yugto: Tutorials, Practice, Activities at Challenges.'), icon: Icons.loop_rounded),
                                  InfoSection(title: L.t('Camera Combat', 'Camera Combat'), body: L.t('Ensure you are in a well-lit area and use the Mirror-Mode Camera. A green checkmark means you scored a hit, while a red "X" means you need to adjust your form.', 'Siguraduhing maliwanag ang lugar at gamitin ang Mirror-Mode Camera. Ang berdeng tsek ay tama, at ang pulang "X" ay kailangan pang ayusin ang porma.'), icon: Icons.camera_alt_rounded),
                                  InfoSection(title: L.t('Leveling Up & Streaks', 'Pag-level Up at Streaks'), body: L.t('Keep practicing to earn Experience Points (XP) and fill your Level Progress Bar. Enable Streak Reminders to keep your momentum going.', 'Patuloy na magsanay para makakuha ng XP at mapuno ang Level Progress Bar. I-on ang Streak Reminders para tuloy-tuloy ang pag-aaral.'), icon: Icons.local_fire_department_rounded),
                                  InfoSection(title: L.t('Multiplayer Challenges', 'Multiplayer Challenges'), body: L.t('Challenge your classmates by tapping "Join a Room" and entering a Room Code, or act as the host by selecting "Create a Room".', 'Hamunin ang mga kaklase: pindutin ang "Join a Room" at ilagay ang Room Code, o maging host sa pagpili ng "Create a Room".'), icon: Icons.group_rounded),
                                  InfoSection(title: L.t('Customizing Experience', 'Pag-customize ng App'), body: L.t('Visit the Settings screen to change your game Theme (like Galaxy Explorer or Deep Ocean), and toggle your Background Music on or off.', 'Pumunta sa Settings para palitan ang Tema (tulad ng Galaxy Explorer o Deep Ocean) at i-on o i-off ang Background Music.'), icon: Icons.palette_rounded),
                                  InfoSection(title: L.t('Reporting Bugs', 'Pag-uulat ng Problema'), body: L.t('Teachers can submit a bug report directly to the admin using the "Feedback & Support" tool. Students should report issues to their teachers.', 'Maaaring magpadala ang mga guro ng bug report sa admin gamit ang "Feedback & Support". Ang mga estudyante ay mag-ulat sa kanilang guro.'), icon: Icons.bug_report_rounded),
                                ],
                              )));
                            },
                          )),
                          MenuCapsule(child: ListTile(
                            leading: Icon(Icons.info_outline, color: theme.primaryColor),
                            title: Text(L.t('About Us', 'Tungkol sa Amin'), style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, _fadeRoute(const AboutUsScreen()));
                            },
                          )),
                          MenuCapsule(child: ListTile(
                            leading: Icon(Icons.gavel_rounded, color: theme.primaryColor),
                            title: Text(L.t('Terms & Privacy Policy', 'Mga Tuntunin at Privacy Policy'), style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, _fadeRoute(InfoDetailScreen(
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
                          )),
                          MenuCapsule(solid: true, child: ListTile(
  leading: Icon(isGuest ? Icons.swap_horiz_rounded : Icons.logout_rounded, color: Colors.white), 
  title: Text(isGuest ? L.t('Change Role', 'Palitan ang Role') : L.t('Sign Out', 'Mag-sign Out'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)), 
  onTap: () async {
    if (isGuest) {
      // Faculty / Parent have no account: leave guest mode and ask for a role again.
      await context.read<RoleProvider>().clear();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
        (route) => false,
      );
      return;
    }
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const SnedStudentLogin()), 
      (route) => false
    );
  }, 
)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              appBar: AppBar(
                toolbarHeight: 65,
                backgroundColor: theme.cardColor.withValues(alpha: 0.4),
                elevation: 0,
                centerTitle: true,
                iconTheme: theme.iconTheme.copyWith(color: textColor),
                flexibleSpace: ClipRRect(
                  clipBehavior: Clip.antiAlias,
                  child: SmartBlur(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                title: Text(
                  L.t('Modules', 'Mga Module'),
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w800, letterSpacing: -0.5, fontSize: 22),
                ),
                actions: [
                  if (roles.can(AppFeature.notifications)) const NotificationBell(),
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0, left: 8.0),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.0),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          "assets/pictures/image 66.png", 
                          width: 40, 
                          height: 40, 
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.account_circle, 
                            size: 40, 
                            color: Theme.of(context).disabledColor
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      
              bottomNavigationBar: AppNavBar(
                currentIndex: 1,
                onTap: (i) {
                  switch (i) {
                    case 0:
                      Navigator.pushAndRemoveUntil(context, _fadeRoute(const SnedInterafce1(userName: "Student")), (route) => false);
                    case 2:
                      Navigator.pushReplacement(context, _fadeRoute(const LeaderboardScreen()));
                    case 3:
                      Navigator.pushReplacement(context, _fadeRoute(const ProfileScreen()));
                  }
                },
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
                        color: theme.primaryColor.withValues(alpha: 0.20),
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
                        color: theme.colorScheme.secondary.withValues(alpha: 0.15),
                      ),
                    ),
                  ),

                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      // Below the transparent app bar (status bar + toolbar), so the
                      // cards never slide under it.
                      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kToolbarHeight + 12, bottom: 120 * scale),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      // The 4 built-in modules as cards with their XP progress (ModuleCard).
                      Padding(
                        padding: EdgeInsets.fromLTRB(16 * scale, 0, 16 * scale, 24 * scale),
                        child: GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          mainAxisSpacing: 14 * scale,
                          crossAxisSpacing: 14 * scale,
                          childAspectRatio: canProgress ? 0.66 : 0.78,
                          children: [
                            ModuleCard(
                              scale: scale,
                              title: L.t('Alphabets', 'Alpabeto'),
                              picture: Image.asset("assets/pictures/abc.png", fit: BoxFit.contain),
                              source: ModuleSource.alphabet,
                              userData: userData,
                              showProgress: canProgress,
                              onTap: () => _openModule(context, 'alphabet', _fadeRoute(AlphabetInterface(currentXp: displayAlpXp, targetXp: targetXp))),
                            ),
                            ModuleCard(
                              scale: scale,
                              title: L.t('Numbers', 'Mga Numero'),
                              picture: Image.asset("assets/pictures/numbers.png", fit: BoxFit.contain),
                              source: ModuleSource.numbers,
                              userData: userData,
                              showProgress: canProgress,
                              onTap: () => _openModule(context, 'numbers', _fadeRoute(NumbersInterface(currentXp: displayNumXp, targetXp: targetXp))),
                            ),
                            ModuleCard(
                              scale: scale,
                              title: L.t('Greetings', 'Mga Pagbati'),
                              picture: Image.asset("assets/pictures/words.png", fit: BoxFit.contain),
                              source: ModuleSource.greetings,
                              userData: userData,
                              showProgress: canProgress,
                              onTap: () => _openModule(context, 'common words', _fadeRoute(PhraseInterface(currentXp: displayWordsXp, targetXp: targetXp))),
                            ),
                            ModuleCard(
                              scale: scale,
                              title: L.t('Civic Observances', 'Pagdiriwang Pansibiko'),
                              picture: Image.asset("assets/pictures/civic.png", fit: BoxFit.contain),
                              source: ModuleSource.civic,
                              userData: userData,
                              showProgress: canProgress,
                              onTap: () => _openModule(context, 'civic', _fadeRoute(CivicInterface(currentXp: displayCivicsXp, targetXp: targetXp))),
                            ),
                          ],
                        ),
                      ),
                      // Categories added in the web app (activity_categories), live.
                      CloudCategoriesSection(scale: scale),
                        ],
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


}