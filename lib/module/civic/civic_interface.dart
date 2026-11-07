import '/module/custom_category_screen.dart' show ModuleProgressPanel, ModuleSource;
import '/widgets/button_3d.dart';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import '/services/progress_service.dart'; 
import 'civic_tutorial_interface.dart';
import 'civic_practice.dart';
import 'civic_difficulty_selection.dart';
import '/leaderboard/arena.dart';

import '/services/performance_monitor.dart';
import '/services/role_service.dart';
import '/providers/language_provider.dart';

class CivicInterface extends StatelessWidget {
  final int currentXp; 
  final int targetXp; 

  const CivicInterface({
    super.key, 
    this.currentXp = 0, 
    this.targetXp = 1000, 
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    // Role-based access: Faculty / Parent only get Tutorial + Practice in a module.
    // Activities, Challenges, XP and stars are for students.
    final roles = context.roles;
    final bool canProgress = roles.can(AppFeature.progress);
    final bool canActivities = roles.can(AppFeature.activities);
    final bool canPractice = roles.can(AppFeature.practice);
    final bool canTutorials = roles.can(AppFeature.tutorials);

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(), 
      builder: (context, snapshot) {    

        

        return Scaffold(
          extendBodyBehindAppBar: true, 
          backgroundColor: theme.scaffoldBackgroundColor, 
          
          appBar: AppBar(
            backgroundColor: theme.cardColor.withValues(alpha: 0.4),
            elevation: 0, 
            centerTitle: true, 
            iconTheme: IconThemeData(color: textColor), 
            flexibleSpace: ClipRRect(
              child: SmartBlur(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(color: Colors.transparent),
              ),
            ),
            title: Text(
              L.t('Civic Observances', 'Pagdiriwang Pansibiko'), 
              style: TextStyle(
                color: textColor, 
                fontSize: 22, 
                fontFamily: 'Inter', 
                fontWeight: FontWeight.w800, 
                letterSpacing: -0.96,
              ), 
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16.0), 
                child: Image.asset("assets/pictures/image 66.png", width: 45), 
              ),
            ],
          ),
          
          body: LayoutBuilder(
            builder: (context, constraints) { 
              final double scale = constraints.maxWidth / 393; 

              // Fill the screen: with only Tutorial + Practice (guests) the page is
              // short, and the background circles were cut where the content ended.
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: -50, left: -50,
                    child: Container(
                      width: 250, height: 250,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primaryColor.withValues(alpha: 0.3)),
                    ),
                  ),
                  Positioned(
                    top: 400, right: -100,
                    child: Container(
                      width: 300, height: 300,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.secondary.withValues(alpha: 0.2)),
                    ),
                  ),

                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(), 
                    child: Padding(
                      padding: EdgeInsets.only(top: 110 * scale, bottom: 40 * scale, left: 16 * scale, right: 16 * scale), 
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          
                          // 1. MAIN PROGRESS PANEL (Combined Level)
                          if (canProgress) ...[
                          ModuleProgressPanel(source: ModuleSource.civic, title: L.t('Civic', 'Pansibiko'), scale: scale),
                          
                          SizedBox(height: 24 * scale),
                          ],

                          if (canTutorials) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Image.asset("assets/pictures/tutor.png", width: 130 * scale, height: 110 * scale, fit: BoxFit.fill),
                              SizedBox(width: 24 * scale),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      L.t('Tutorial', 'Tutorial'),
                                      style: TextStyle(color: textColor, fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5),
                                    ),
                                    SizedBox(height: 8 * scale),
                                    _buildActionButton(
                                      context: context,
                                      scale: scale,
                                      icon: Icons.play_arrow_rounded,
                                      label: L.t('Start Learn', 'Simulang Matuto'),
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CivicTutorialInterface())),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 16 * scale),
                          ],

                          if (canPractice) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Image.asset("assets/pictures/practice.png", width: 135 * scale, height: 135 * scale, fit: BoxFit.cover),
                              SizedBox(width: 20 * scale),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      L.t('Practice', 'Pagsasanay'),
                                      style: TextStyle(color: textColor, fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5),
                                    ),
                                    SizedBox(height: 8 * scale),
                                    _buildActionButton(
                                      context: context,
                                      scale: scale,
                                      icon: Icons.camera_alt_rounded,
                                      label: L.t('Train Sign', 'Sanayin ang Senyas'),
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CivicPractice())),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 24 * scale),
                          ],

                          if (!canActivities) GuestModuleGuide(scale: scale),


                          if (canActivities) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      L.t('Activity', 'Aktibidad'),
                                      style: TextStyle(color: textColor, fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44),
                                    ),
                                    SizedBox(height: 12 * scale),
                                    GestureDetector(
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CivicDifficultySelectionScreen())),
                                      child: PictureButton3D(picture: Image.asset("assets/pictures/actt.png", width: 164 * scale, height: 160 * scale, fit: BoxFit.cover)),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 16 * scale),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      L.t('Challenges', 'Mga Hamon'),
                                      style: TextStyle(color: textColor, fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44),
                                    ),
                                    SizedBox(height: 12 * scale),
                                    GestureDetector(
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LeaderboardScreen(initialTab: 'challenges'))),
                                      child: PictureButton3D(picture: Image.asset("assets/pictures/battle.png", width: 159 * scale, height: 159 * scale, fit: BoxFit.cover)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 32 * scale),

                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildActionButton({required BuildContext context, required double scale, required IconData icon, required String label, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 4,
        shadowColor: theme.primaryColor.withValues(alpha: 0.5),
        padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
        shape: Button3DBorder(borderRadius: BorderRadius.circular(20 * scale)),
      ),
      icon: Icon(icon, size: 18 * scale),
      label: Text(label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 14 * scale)),
      onPressed: onTap,
    );
  }

}