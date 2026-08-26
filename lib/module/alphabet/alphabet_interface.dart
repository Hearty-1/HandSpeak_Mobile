import 'dart:ui'; // Required for ImageFilter (Glassmorphism)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/services/progress_service.dart';
import 'practice.dart';
import 'tutorial.dart';
import 'activity_interface.dart';
import '/leaderboard/arena.dart'; // Target Leaderboard / Challenge screen import

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
    const double baseWidth = 393;
    const double baseHeight = 693;

    // Set iOS-style transparent status bar
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(),
      builder: (context, snapshot) {
        
        int alphabetXp = 0;
        int alphabetStars = 0; 

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            alphabetXp = data['alphabetXp'] ?? 0;
            
            if (data['progress'] != null) {
              Map<String, dynamic> progressMap = Map<String, dynamic>.from(data['progress']);
              progressMap.forEach((key, value) {
                if (key.startsWith('alphabet_')) {
                  alphabetStars += (value as num).toInt();
                }
              });
            }
          }
        }
        
        int displayXp = alphabetXp > targetXp ? targetXp : alphabetXp;

        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: const Color(0xFFFFF9E5),
          
          appBar: AppBar(
            backgroundColor: Colors.white.withOpacity(0.4),
            elevation: 0,
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.black87),
            flexibleSpace: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(color: Colors.transparent),
              ),
            ),
            title: const Text(
              'Alphabets',
              style: TextStyle(color: Colors.black87, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96),
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
              final double scale = constraints.maxWidth / baseWidth;

              return Stack(
                children: [
                  Positioned(
                    top: -50,
                    left: -50,
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFFB800).withOpacity(0.3),
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
                        color: const Color(0xFF7DC579).withOpacity(0.2), 
                      ),
                    ),
                  ),

                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.only(top: 100 * scale, bottom: 40 * scale),
                      child: SizedBox(
                        height: baseHeight * scale,
                        width: constraints.maxWidth,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 6 * scale, top: 12 * scale,
                              child: _buildMainProgressPanel(
                                scale: scale,
                                currentXp: displayXp,
                                targetXp: targetXp,
                              ),
                            ),

                            Positioned(
                              left: 24 * scale, top: 80 * scale,
                              child: Container(width: 130 * scale, height: 110 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/tutor.png"), fit: BoxFit.fill))),
                            ),
                            Positioned(
                              left: 165 * scale, top: 95 * scale,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Tutorial', style: TextStyle(color: Colors.black, fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5)),
                                  SizedBox(height: 6 * scale),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB800), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale))),
                                    icon: Icon(Icons.play_arrow, size: 16 * scale),
                                    label: Text('Start Learn', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13 * scale)),
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => TutorialInterface())),
                                  ),
                                ],
                              ),
                            ),

                            Positioned(
                              left: 16 * scale, top: 200 * scale,
                              child: Container(width: 135 * scale, height: 135 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/practice.png"), fit: BoxFit.cover))),
                            ),
                            Positioned(
                              left: 165 * scale, top: 225 * scale,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Practice', style: TextStyle(color: Colors.black, fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5)),
                                  SizedBox(height: 6 * scale),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB800), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale))),
                                    icon: Icon(Icons.camera_alt, size: 14 * scale),
                                    label: Text('Train Sign', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13 * scale)),
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PracticeInterface())),
                                  ),
                                ],
                              ),
                            ),

                            Positioned(left: 56.75 * scale, top: 355 * scale, child: Text('Activity', style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44))),
                            Positioned(left: 233.75 * scale, top: 355 * scale, child: Text('Challenges', style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44))),
                            
                            Positioned(
                              left: 20.75 * scale, top: 392 * scale,
                              child: GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ActivityInterface())),
                                child: Container(width: 164 * scale, height: 160 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/activity.png"), fit: BoxFit.cover))),
                              ),
                            ),
                            
                            // Updated Challenge Card GestureDetector: Navigates directly to Challenge Tab
                            Positioned(
                              left: 215.75 * scale, top: 392 * scale,
                              child: GestureDetector(
                                onTap: () => Navigator.push(
                                  context, 
                                  MaterialPageRoute(
                                    builder: (context) => const LeaderboardScreen(initialTab: 'challenges'),
                                  ),
                                ),
                                child: Container(width: 159 * scale, height: 159 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/challenge.png"), fit: BoxFit.cover))),
                              ),
                            ),

                            Positioned(
                              left: 13.75 * scale, 
                              top: 565 * scale, 
                              child: _buildSubMetricPanel(scale: scale, valueDisplay: "$alphabetStars Stars", progress: (alphabetStars / 27).clamp(0.0, 1.0))
                            ),
                            Positioned(
                              left: 203.75 * scale, 
                              top: 565 * scale, 
                              child: _buildSubMetricPanel(scale: scale, valueDisplay: "$alphabetXp XP", progress: (alphabetXp / targetXp).clamp(0.0, 1.0))
                            ),
                          ],
                        ),
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

  Widget _buildMainProgressPanel({required double scale, required int currentXp, required int targetXp}) {
    final double progressRatio = (currentXp / targetXp).clamp(0.0, 1.0);
    const double maxTrackWidth = 235.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14 * scale), 
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 381 * scale, height: 55 * scale,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65), 
            borderRadius: BorderRadius.circular(14 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5), 
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Stack(
            children: [
              Positioned(left: 56 * scale, top: 5 * scale, child: Text('Progress', style: TextStyle(color: const Color(0xFF322144), fontSize: 14 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.w600, letterSpacing: -0.90))),
              Positioned(left: 56 * scale, top: 24 * scale, child: Text('$currentXp / $targetXp XP', style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 16 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.0))),
              
              Positioned(
                left: 130 * scale, top: 26 * scale,
                child: Container(
                  width: maxTrackWidth * scale, height: 6 * scale,
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(25 * scale)), 
                ),
              ),
              Positioned(
                left: 130 * scale, top: 26 * scale,
                child: Container(
                  width: (maxTrackWidth * progressRatio) * scale, height: 6 * scale,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7DC579), 
                    borderRadius: BorderRadius.circular(25 * scale),
                    boxShadow: [BoxShadow(color: const Color(0xFF7DC579).withOpacity(0.5), blurRadius: 4)],
                  ),
                ),
              ),
              
              Positioned(left: 16 * scale, top: 12 * scale, child: _buildGlassIcon(scale, 20 * scale)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubMetricPanel({required double scale, required String valueDisplay, required double progress}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14 * scale),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 178 * scale, height: 37 * scale,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65), 
            borderRadius: BorderRadius.circular(14 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 45 * scale, 
                top: 8 * scale,  
                child: Text(valueDisplay, style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 13 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.20))
              ),
              Positioned(
                left: 12 * scale, top: 28 * scale,
                child: Container(
                  width: 154 * scale, height: 4 * scale,
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(25 * scale)), 
                ),
              ),
              Positioned(
                left: 12 * scale, top: 28 * scale,
                child: Container(
                  width: (154 * progress) * scale, height: 4 * scale,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7DC579),
                    borderRadius: BorderRadius.circular(25 * scale),
                    boxShadow: [BoxShadow(color: const Color(0xFF7DC579).withOpacity(0.5), blurRadius: 4)],
                  ), 
                ),
              ),

              Positioned(left: 10 * scale, top: 2 * scale, child: _buildGlassIcon(scale, 16 * scale)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassIcon(double scale, double size) {
    return Container(
      padding: EdgeInsets.all(4 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB800).withOpacity(0.3), 
            blurRadius: 8, 
            spreadRadius: 1
          )
        ],
      ),
      child: Image.asset("assets/pictures/star.png", width: 18 * scale, height: 17 * scale, errorBuilder: (c, o, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 14 * scale)),
    );
  }
}