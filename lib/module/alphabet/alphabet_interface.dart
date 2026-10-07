import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/services/progress_service.dart';
import 'practice.dart';
import 'tutorial.dart';
import 'difficulty_selection.dart';
import '/leaderboard/arena.dart'; 

import '/services/performance_monitor.dart';

class AlphabetInterface extends StatelessWidget {
  final int currentXp;
  final int targetXp;

  const AlphabetInterface({
    super.key,
    this.currentXp = 0,
    this.targetXp = 1000,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(),
      builder: (context, snapshot) {
        int moduleXp = 0;
        int challengeXp = 0;
        int alphabetStars = 0;
        const int maxStars = 27;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            // Correctly read root-level alphabetXp from your Firestore schema
            moduleXp = (data['alphabetXp'] ?? 0).toInt();

            // Read challenge XP safely from the progress map
            if (data['progress'] != null) {
              Map<String, dynamic> progressMap = Map<String, dynamic>.from(data['progress']);
              challengeXp = (progressMap['alphabet_challenge_xp'] ?? 0).toInt();

              progressMap.forEach((key, value) {
                if (key.startsWith('alphabet_') && !key.toLowerCase().contains('xp') && !key.toLowerCase().contains('challenge')) {
                  alphabetStars += (value as num).toInt();
                }
              });
            }
          }
        }

        // Calculate combined level and progress within the level
        int totalCategoryXp = moduleXp + challengeXp;
        int currentLevel = (totalCategoryXp ~/ targetXp) + 1;
        int xpInLevel = totalCategoryXp % targetXp;

        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: theme.scaffoldBackgroundColor,
          
          appBar: AppBar(
            backgroundColor: theme.cardColor.withOpacity(0.4),
            elevation: 0,
            centerTitle: true,
            iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
            flexibleSpace: ClipRRect(
              child: SmartBlur(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(color: Colors.transparent),
              ),
            ),
            title: Text(
              'Alphabets',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
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

              return Stack(
                children: [
                  Positioned(
                    top: -50, left: -50,
                    child: Container(
                      width: 250, height: 250,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primaryColor.withOpacity(0.3)),
                    ),
                  ),
                  Positioned(
                    top: 400, right: -100,
                    child: Container(
                      width: 300, height: 300,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.secondary.withOpacity(0.2)),
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
                          _buildMainProgressPanel(
                            context: context,
                            scale: scale,
                            level: currentLevel,
                            currentXp: xpInLevel,
                            targetXp: targetXp,
                          ),
                          
                          SizedBox(height: 24 * scale),

                          // 2. TUTORIAL SECTION
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
                                      'Tutorial',
                                      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5),
                                    ),
                                    SizedBox(height: 8 * scale),
                                    _buildActionButton(
                                      context: context,
                                      scale: scale,
                                      icon: Icons.play_arrow_rounded,
                                      label: 'Start Learn',
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => TutorialInterface())),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 16 * scale),

                          // 3. PRACTICE SECTION
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
                                      'Practice',
                                      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5),
                                    ),
                                    SizedBox(height: 8 * scale),
                                    _buildActionButton(
                                      context: context,
                                      scale: scale,
                                      icon: Icons.camera_alt_rounded,
                                      label: 'Train Sign',
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PracticeInterface())),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 24 * scale),

                          // 4. ACTIVITY & CHALLENGES 
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      'Activity',
                                      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44),
                                    ),
                                    SizedBox(height: 12 * scale),
                                    GestureDetector(
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DifficultySelectionScreen())),
                                      child: Image.asset("assets/pictures/actt.png", width: 164 * scale, height: 160 * scale, fit: BoxFit.cover),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 16 * scale),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      'Challenges',
                                      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44),
                                    ),
                                    SizedBox(height: 12 * scale),
                                    GestureDetector(
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LeaderboardScreen(initialTab: 'challenges'))),
                                      child: Image.asset("assets/pictures/battle.png", width: 159 * scale, height: 159 * scale, fit: BoxFit.cover),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 32 * scale),

                          // 5. SUB METRICS
                          Row(
                            children: [
                              Expanded(
                                child: _buildSubMetricPanel(
                                  context: context,
                                  scale: scale,
                                  valueDisplay: "$alphabetStars Stars",
                                  progress: (alphabetStars / maxStars).clamp(0.0, 1.0),
                                  icon: Icons.star_rounded, 
                                  iconColor: Colors.amber.shade500,
                                ),
                              ),
                              SizedBox(width: 12 * scale),
                              // FIXED: Strictly bound to challengeXp so it starts at 0 independently
                              Expanded(
                                child: _buildSubMetricPanel(
                                  context: context,
                                  scale: scale,
                                  valueDisplay: "$challengeXp XP",
                                  progress: (challengeXp / targetXp).clamp(0.0, 1.0),
                                  icon: Icons.bolt_rounded, 
                                  iconColor: Colors.amber.shade500,
                                ),
                              ),
                            ],
                          ),
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
        shadowColor: theme.primaryColor.withOpacity(0.5),
        padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale)),
      ),
      icon: Icon(icon, size: 18 * scale),
      label: Text(
        label,
        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 14 * scale),
      ),
      onPressed: onTap,
    );
  }

  Widget _buildMainProgressPanel({required BuildContext context, required double scale, required int level, required int currentXp, required int targetXp}) {
    final theme = Theme.of(context);
    final double progressRatio = (currentXp / targetXp).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16 * scale), 
      child: SmartBlur(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.65), 
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5), 
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Row(
            children: [
              _buildGlassIcon(context, scale, 24 * scale, Icons.bolt_rounded, Colors.amber.shade500),
              SizedBox(width: 16 * scale),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Level $level Progress', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.w700)),
                  Text('$currentXp / $targetXp XP', style: TextStyle(color: theme.primaryColor, fontSize: 15 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400)),
                ],
              ),
              SizedBox(width: 16 * scale),
              Expanded(
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(height: 8 * scale, decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.1), borderRadius: BorderRadius.circular(25 * scale))),
                    FractionallySizedBox(
                      widthFactor: progressRatio,
                      child: Container(
                        height: 8 * scale, 
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary, 
                          borderRadius: BorderRadius.circular(25 * scale),
                          boxShadow: [BoxShadow(color: theme.colorScheme.secondary.withOpacity(0.5), blurRadius: 4)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubMetricPanel({
    required BuildContext context, 
    required double scale, 
    required String valueDisplay, 
    required double progress,
    required IconData icon,
    required Color iconColor,
  }) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16 * scale),
      child: SmartBlur(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(12 * scale),
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.65), 
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildGlassIcon(context, scale, 18 * scale, icon, iconColor),
                  SizedBox(width: 8 * scale),
                  Expanded(
                    child: Text(
                      valueDisplay,
                      style: TextStyle(color: theme.primaryColor, fontSize: 13 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12 * scale),
              Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(height: 6 * scale, decoration: BoxDecoration(color: theme.colorScheme.onSurface.withOpacity(0.1), borderRadius: BorderRadius.circular(25 * scale))),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 6 * scale,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(25 * scale),
                        boxShadow: [BoxShadow(color: theme.colorScheme.secondary.withOpacity(0.5), blurRadius: 4)],
                      ), 
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassIcon(BuildContext context, double scale, double size, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(6 * scale),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.8),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 8, spreadRadius: 1)],
      ),
      child: Icon(icon, color: color, size: size),
    );
  }
}