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

        // XP unlock chain applies to students only; guests have no XP to unlock with.
        final bool isWordsLocked = canProgress && alphabetXp < targetXp; 
        final bool isCivicsLocked = canProgress && (isWordsLocked || (wordsXp < targetXp)); 

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
                          ListTile(
                            leading: Icon(Icons.settings, color: theme.primaryColor),
                            title: Text(L.t('Settings', 'Mga Setting'), style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, _fadeRoute(const SettingsScreen()));
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.help_outline, color: theme.primaryColor),
                            title: Text(L.t('Help & Support', 'Tulong at Suporta'), style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, _fadeRoute(InfoDetailScreen(
                                title: L.t('Help & Support', 'Tulong at Suporta'),
                                sections: [
                                  InfoSection(title: L.t('The Learning Loop', 'Ang Paraan ng Pag-aaral'), body: L.t('Your Filipino Sign Language learning path is divided into four stages: Tutorials, Practice, Activities, and Challenges. Achieve 1000 XP points to unlock the next module.', 'Ang pag-aaral mo ng Filipino Sign Language ay may apat na yugto: Tutorials, Practice, Activities at Challenges. Makakuha ng 1000 XP para mabuksan ang susunod na module.'), icon: Icons.loop_rounded),
                                  InfoSection(title: L.t('Camera Combat', 'Camera Combat'), body: L.t('Ensure you are in a well-lit area and use the Mirror-Mode Camera. A green checkmark means you scored a hit, while a red "X" means you need to adjust your form.', 'Siguraduhing maliwanag ang lugar at gamitin ang Mirror-Mode Camera. Ang berdeng tsek ay tama, at ang pulang "X" ay kailangan pang ayusin ang porma.'), icon: Icons.camera_alt_rounded),
                                  InfoSection(title: L.t('Leveling Up & Streaks', 'Pag-level Up at Streaks'), body: L.t('Keep practicing to earn Experience Points (XP) and fill your Level Progress Bar. Enable Streak Reminders to keep your momentum going.', 'Patuloy na magsanay para makakuha ng XP at mapuno ang Level Progress Bar. I-on ang Streak Reminders para tuloy-tuloy ang pag-aaral.'), icon: Icons.local_fire_department_rounded),
                                  InfoSection(title: L.t('Multiplayer Challenges', 'Multiplayer Challenges'), body: L.t('Challenge your classmates by tapping "Join a Room" and entering a Room Code, or act as the host by selecting "Create a Room".', 'Hamunin ang mga kaklase: pindutin ang "Join a Room" at ilagay ang Room Code, o maging host sa pagpili ng "Create a Room".'), icon: Icons.group_rounded),
                                  InfoSection(title: L.t('Customizing Experience', 'Pag-customize ng App'), body: L.t('Visit the Settings screen to change your game Theme (like Galaxy Explorer or Deep Ocean), and toggle your Background Music on or off.', 'Pumunta sa Settings para palitan ang Tema (tulad ng Galaxy Explorer o Deep Ocean) at i-on o i-off ang Background Music.'), icon: Icons.palette_rounded),
                                  InfoSection(title: L.t('Reporting Bugs', 'Pag-uulat ng Problema'), body: L.t('Teachers can submit a bug report directly to the admin using the "Feedback & Support" tool. Students should report issues to their teachers.', 'Maaaring magpadala ang mga guro ng bug report sa admin gamit ang "Feedback & Support". Ang mga estudyante ay mag-ulat sa kanilang guro.'), icon: Icons.bug_report_rounded),
                                ],
                              )));
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.info_outline, color: theme.primaryColor),
                            title: Text(L.t('About Us', 'Tungkol sa Amin'), style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, _fadeRoute(const AboutUsScreen()));
                            },
                          ),
                          ListTile(
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
                          ),
                          ListTile(
  leading: Icon(isGuest ? Icons.swap_horiz_rounded : Icons.logout_rounded, color: const Color(0xFFF34B1B)), 
  title: Text(isGuest ? L.t('Change Role', 'Palitan ang Role') : L.t('Sign Out', 'Mag-sign Out'), style: const TextStyle(color: Color(0xFFF34B1B), fontWeight: FontWeight.w600)), 
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
),
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
                      padding: EdgeInsets.only(top: 70 * scale, bottom: 120 * scale),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      SizedBox(
                        // Guests: no XP panels, so the grid is shorter.
                        height: (canProgress ? baseHeight : baseHeight - 90) * scale,
                        width: constraints.maxWidth,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildGridNode(
                              context: context,
                              scale: scale,
                              leftOffset: 12,
                              topOffset: 0,
                              title: L.t('Alphabets', 'Alpabeto'),
                              imagePath: "assets/pictures/abc.png",
                              currentXp: displayAlpXp,
                              targetXp: targetXp,
                              isLocked: false,
                              progressColor: adaptiveProgressColor,
                              showProgress: canProgress,
                              onTap: () => _openModule(
                                context, 'alphabet',
                                _fadeRoute(AlphabetInterface(currentXp: displayAlpXp, targetXp: targetXp)),
                              ),
                            ),
                            _buildGridNode(
                              context: context,
                              scale: scale,
                              leftOffset: 201, 
                              topOffset: 0, 
                              title: L.t('Numbers', 'Mga Numero'),
                              imagePath: "assets/pictures/numbers.png",
                              currentXp: displayNumXp,
                              targetXp: targetXp,
                              isLocked: false,
                              progressColor: adaptiveProgressColor,
                              showProgress: canProgress,
                              onTap: () => _openModule(
                                context, 'numbers',
                                _fadeRoute(NumbersInterface(currentXp: displayNumXp, targetXp: targetXp)),
                              ),
                            ),
                            _buildGridNode(
                              context: context,
                              scale: scale,
                              leftOffset: 12,
                              topOffset: canProgress ? 330 : 300, 
                              title: L.t('Words/Phrases', 'Mga Salita/Parirala'),
                              imagePath: "assets/pictures/words.png",
                              currentXp: displayWordsXp,
                              targetXp: targetXp,
                              isLocked: isWordsLocked,
                              progressColor: adaptiveProgressColor,
                              showProgress: canProgress,
                              onTap: () => _openModule(
                                context, 'common words',
                                _fadeRoute(PhraseInterface(currentXp: displayWordsXp, targetXp: targetXp)),
                              ),
                            ),
                            _buildGridNode(
                              context: context,
                              scale: scale,
                              leftOffset: 201,
                              topOffset: canProgress ? 330 : 300, 
                              title: L.t('Civic\nObservances', 'Pagdiriwang\nPansibiko'),
                              imagePath: "assets/pictures/civic.png",
                              currentXp: displayCivicsXp,
                              targetXp: targetXp,
                              isLocked: isCivicsLocked,
                              progressColor: adaptiveProgressColor,
                              showProgress: canProgress,
                              onTap: () => _openModule(
                                context, 'civic',
                                _fadeRoute(CivicInterface(currentXp: displayCivicsXp, targetXp: targetXp)),
                              ),
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
    bool showProgress = true,
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
                            color: Colors.black.withValues(alpha: 0.08),
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
          if (!showProgress) ...[
            // Guests: an L.t('Explore', 'Tuklasin') pill instead of the XP panel (keeps the grid tight).
            SizedBox(height: 14 * scale),
            GestureDetector(
              onTap: isLocked ? null : onTap,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 8 * scale),
                decoration: BoxDecoration(
                  color: theme.primaryColor,
                  borderRadius: BorderRadius.circular(20 * scale),
                  boxShadow: [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(L.t('Explore', 'Tuklasin'), style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 14 * scale, fontWeight: FontWeight.w800)),
                    SizedBox(width: 4 * scale),
                    Icon(Icons.arrow_forward_rounded, size: 16 * scale, color: theme.colorScheme.onPrimary),
                  ],
                ),
              ),
            ),
          ],
          if (showProgress) ...[
          SizedBox(height: 16 * scale),

          Opacity(
            opacity: isLocked ? 0.45 : 1.0,
            child: _buildProgressPanel(
              context: context,
              scale: scale,
              title: L.t('Progress', 'Progreso'),
              xp: "$currentXp XP",
              xpNext: L.t('${targetXp - currentXp} to next', '${targetXp - currentXp} pa sa susunod'),
              progressRatio: currentXp / targetXp,
              progressColor: progressColor,
            ),
          ),
          ],
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
      child: SmartBlur(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 178 * scale, height: 76 * scale,
          decoration: BoxDecoration(
            color: theme.cardColor.withValues(alpha: 0.75), 
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06), 
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
                    color: theme.dividerColor.withValues(alpha: 0.2), 
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
                    boxShadow: [BoxShadow(color: progressColor.withValues(alpha: 0.4), blurRadius: 4)],
                  ),
                ),
              ),
              
              Positioned(
                right: 12 * scale, top: 11 * scale, 
                child: Text(
                  xpNext, 
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.5), 
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