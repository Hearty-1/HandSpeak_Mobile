import 'dart:ui'; // Required for ImageFilter (Glassmorphism)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; //[cite: 8]
import '/services/progress_service.dart'; //[cite: 8]
import 'practice.dart'; //[cite: 8]
import 'tutorial.dart'; //[cite: 8]
import 'activity_interface.dart'; //[cite: 8]

class AlphabetInterface extends StatelessWidget {
  final int currentXp; //[cite: 8]
  final int targetXp; //[cite: 8]

  const AlphabetInterface({
    super.key, //[cite: 8]
    this.currentXp = 0, //[cite: 8]
    this.targetXp = 1000, //[cite: 8]
  });

  @override
  Widget build(BuildContext context) {
    const double baseWidth = 393; //[cite: 8]
    const double baseHeight = 693; //[cite: 8]

    // Set iOS-style transparent status bar
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(), //[cite: 8]
      builder: (context, snapshot) { //[cite: 8]
        
        int alphabetXp = 0; //[cite: 8]
        int alphabetStars = 0;  //[cite: 8]

        if (snapshot.hasData && snapshot.data!.exists) { //[cite: 8]
          final data = snapshot.data!.data() as Map<String, dynamic>?; //[cite: 8]
          if (data != null) { //[cite: 8]
            // Read the single unified alphabetXp field
            alphabetXp = data['alphabetXp'] ?? 0; //[cite: 8]
            
            // Fetch Alphabet-specific activity stars
            if (data['progress'] != null) { //[cite: 8]
              Map<String, dynamic> progressMap = Map<String, dynamic>.from(data['progress']); //[cite: 8]
              progressMap.forEach((key, value) { //[cite: 8]
                if (key.startsWith('alphabet_')) { //[cite: 8]
                  alphabetStars += (value as num).toInt(); //[cite: 8]
                }
              });
            }
          }
        }
        
        // Track raw XP, capping at targetXp (1000) so the progress bar stops perfectly full
        int displayXp = alphabetXp > targetXp ? targetXp : alphabetXp; //[cite: 8]

        return Scaffold(
          extendBodyBehindAppBar: true, // Allow glass app bar
          backgroundColor: const Color(0xFFFFF9E5), //[cite: 8]
          
          // --- GLASSMORPHISM APP BAR ---
          appBar: AppBar(
            backgroundColor: Colors.white.withOpacity(0.4), // Frosted
            elevation: 0, //[cite: 8]
            centerTitle: true, //[cite: 8]
            iconTheme: const IconThemeData(color: Colors.black87), //[cite: 8]
            flexibleSpace: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(color: Colors.transparent),
              ),
            ),
            title: const Text(
              'Alphabets', //[cite: 8]
              style: TextStyle(color: Colors.black87, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96), //[cite: 8]
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16.0), //[cite: 8]
                child: Image.asset("assets/pictures/image 66.png", width: 45), //[cite: 8]
              ),
            ],
          ),
          
          body: LayoutBuilder(
            builder: (context, constraints) { //[cite: 8]
              final double scale = constraints.maxWidth / baseWidth; //[cite: 8]

              return Stack(
                children: [
                  // --- 1. Ambient Background Shapes ---
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

                  // --- 2. Main Content ---
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(), //[cite: 8]
                    child: Padding(
                      padding: EdgeInsets.only(top: 100 * scale, bottom: 40 * scale), // Added top padding for Glass AppBar
                      child: SizedBox(
                        height: baseHeight * scale, //[cite: 8]
                        width: constraints.maxWidth, //[cite: 8]
                        child: Stack(
                          clipBehavior: Clip.none, //[cite: 8]
                          children: [
                            // Dynamic Live Progress Bar
                            Positioned(
                              left: 6 * scale, top: 12 * scale, //[cite: 8]
                              child: _buildMainProgressPanel(
                                scale: scale, //[cite: 8]
                                currentXp: displayXp, //[cite: 8]
                                targetXp: targetXp, //[cite: 8]
                              ),
                            ),

                            // Tutorial Row Container
                            Positioned(
                              left: 24 * scale, top: 80 * scale, //[cite: 8]
                              child: Container(width: 130 * scale, height: 110 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/tutor.png"), fit: BoxFit.fill))), //[cite: 8]
                            ),
                            Positioned(
                              left: 165 * scale, top: 95 * scale, //[cite: 8]
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, //[cite: 8]
                                children: [
                                  Text('Tutorial', style: TextStyle(color: Colors.black, fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5)), //[cite: 8]
                                  SizedBox(height: 6 * scale), //[cite: 8]
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB800), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale))), //[cite: 8]
                                    icon: Icon(Icons.play_arrow, size: 16 * scale), //[cite: 8]
                                    label: Text('Start Learn', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13 * scale)), //[cite: 8]
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => TutorialInterface())), //[cite: 8]
                                  ),
                                ],
                              ),
                            ),

                            // Practice Row Container
                            Positioned(
                              left: 16 * scale, top: 200 * scale, //[cite: 8]
                              child: Container(width: 135 * scale, height: 135 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/practice.png"), fit: BoxFit.cover))), //[cite: 8]
                            ),
                            Positioned(
                              left: 165 * scale, top: 225 * scale, //[cite: 8]
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, //[cite: 8]
                                children: [
                                  Text('Practice', style: TextStyle(color: Colors.black, fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5)), //[cite: 8]
                                  SizedBox(height: 6 * scale), //[cite: 8]
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB800), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale))), //[cite: 8]
                                    icon: Icon(Icons.camera_alt, size: 14 * scale), //[cite: 8]
                                    label: Text('Train Sign', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13 * scale)), //[cite: 8]
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PracticeInterface())), //[cite: 8]
                                  ),
                                ],
                              ),
                            ),

                            // Sub Activity Metrics Section
                            Positioned(left: 56.75 * scale, top: 355 * scale, child: Text('Activity', style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44))), //[cite: 8]
                            Positioned(left: 233.75 * scale, top: 355 * scale, child: Text('Challenges', style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44))), //[cite: 8]
                            
                            Positioned(
                              left: 20.75 * scale, top: 392 * scale, //[cite: 8]
                              child: GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ActivityInterface())), //[cite: 8]
                                child: Container(width: 164 * scale, height: 160 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/activity.png"), fit: BoxFit.cover))), //[cite: 8]
                              ),
                            ),
                            Positioned(
                              left: 215.75 * scale, top: 392 * scale, //[cite: 8]
                              child: GestureDetector(
                                onTap: () {}, //[cite: 8]
                                child: Container(width: 159 * scale, height: 159 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/challenge.png"), fit: BoxFit.cover))), //[cite: 8]
                              ),
                            ),

                            // Activity & Challenge progress bars
                            Positioned(
                              left: 13.75 * scale,  //[cite: 8]
                              top: 565 * scale,  //[cite: 8]
                              child: _buildSubMetricPanel(scale: scale, valueDisplay: "$alphabetStars Stars", progress: (alphabetStars / 27).clamp(0.0, 1.0)) //[cite: 8]
                            ),
                            Positioned(
                              left: 203.75 * scale,  //[cite: 8]
                              top: 565 * scale,  //[cite: 8]
                              child: _buildSubMetricPanel(scale: scale, valueDisplay: "0 XP", progress: 0.0) //[cite: 8]
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

  // Refactored Glassmorphism Main Progress Panel
  Widget _buildMainProgressPanel({required double scale, required int currentXp, required int targetXp}) {
    final double progressRatio = (currentXp / targetXp).clamp(0.0, 1.0); //[cite: 8]
    const double maxTrackWidth = 235.0; //[cite: 8]

    return ClipRRect(
      borderRadius: BorderRadius.circular(14 * scale), 
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 381 * scale, height: 55 * scale, //[cite: 8]
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65), 
            borderRadius: BorderRadius.circular(14 * scale), //[cite: 8]
            border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5), 
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Stack(
            children: [
              Positioned(left: 56 * scale, top: 5 * scale, child: Text('Progress', style: TextStyle(color: const Color(0xFF322144), fontSize: 14 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.w600, letterSpacing: -0.90))), //[cite: 8]
              Positioned(left: 56 * scale, top: 24 * scale, child: Text('$currentXp / $targetXp XP', style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 16 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.0))), //[cite: 8]
              
              // Background track
              Positioned(
                left: 130 * scale, top: 26 * scale, //[cite: 8]
                child: Container(
                  width: maxTrackWidth * scale, height: 6 * scale, //[cite: 8]
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(25 * scale)), 
                ),
              ),
              // Fill layer
              Positioned(
                left: 130 * scale, top: 26 * scale, //[cite: 8]
                child: Container(
                  width: (maxTrackWidth * progressRatio) * scale, height: 6 * scale, //[cite: 8]
                  decoration: BoxDecoration(
                    color: const Color(0xFF7DC579),  //[cite: 8]
                    borderRadius: BorderRadius.circular(25 * scale), //[cite: 8]
                    boxShadow: [BoxShadow(color: const Color(0xFF7DC579).withOpacity(0.5), blurRadius: 4)],
                  ),
                ),
              ),
              
              // Glass Waving Hand Icon
              Positioned(left: 16 * scale, top: 12 * scale, child: _buildGlassIcon(scale, 20 * scale)),
            ],
          ),
        ),
      ),
    );
  }

  // Refactored Glassmorphism Sub Metric Panel
  Widget _buildSubMetricPanel({required double scale, required String valueDisplay, required double progress}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14 * scale),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 178 * scale, height: 37 * scale, //[cite: 8]
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65), 
            borderRadius: BorderRadius.circular(14 * scale), //[cite: 8]
            border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 45 * scale,  //[cite: 8]
                top: 8 * scale,  
                child: Text(valueDisplay, style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 13 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.20)) //[cite: 8]
              ),
              Positioned(
                left: 12 * scale, top: 28 * scale, //[cite: 8]
                child: Container(
                  width: 154 * scale, height: 4 * scale, //[cite: 8]
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(25 * scale)), 
                ),
              ),
              Positioned(
                left: 12 * scale, top: 28 * scale, //[cite: 8]
                child: Container(
                  width: (154 * progress) * scale, height: 4 * scale, //[cite: 8]
                  decoration: BoxDecoration(
                    color: const Color(0xFF7DC579), //[cite: 8]
                    borderRadius: BorderRadius.circular(25 * scale), //[cite: 8]
                    boxShadow: [BoxShadow(color: const Color(0xFF7DC579).withOpacity(0.5), blurRadius: 4)],
                  ), 
                ),
              ),

              // Glass Waving Hand Icon
              Positioned(left: 10 * scale, top: 2 * scale, child: _buildGlassIcon(scale, 16 * scale)),
            ],
          ),
        ),
      ),
    );
  }

  // Reusable widget to render the waving hand icon in a glass circle (replacing stars)
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
      child:  Positioned(left: 12 * scale, top: 3 * scale, child: Image.asset("assets/pictures/star.png", width: 18 * scale, height: 17 * scale, errorBuilder: (c, o, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 14 * scale)))
    );
  }
}