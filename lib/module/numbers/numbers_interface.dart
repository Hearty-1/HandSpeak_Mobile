import 'package:flutter/material.dart';
// Note: Update these imports to point to your specific Numbers practice and tutorial files if they are named differently.
import '../alphabet/practice.dart'; 
import 'numbers_tutorial.dart';
import 'numbers_activity.dart';

void main() {
  runApp(const FigmaToCodeApp());
}

class FigmaToCodeApp extends StatelessWidget {
  const FigmaToCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFFFFF9E5),
      ),
      home: const Scaffold(
        body: SafeArea(
          child: NumbersInterface(
            currentLevel: 1,
            currentXp: 150,  // Backend binding preview value
            targetXp: 1000, 
          ),
        ),
      ),
    );
  }
}

class NumbersInterface extends StatelessWidget {
  // --- BACKEND PASSTHROUGH CHANNELS ---
  final int currentLevel;
  final int currentXp;
  final int targetXp;

  const NumbersInterface({
    super.key,
    this.currentLevel = 1,
    this.currentXp = 0,
    this.targetXp = 1000,
  });

  @override
  Widget build(BuildContext context) {
    // Base design workspace dimensions
    const double baseWidth = 393;
    const double baseHeight = 793;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Compute dynamic responsive scaling factor
        final double scale = constraints.maxWidth / baseWidth;

        return Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFFFFF9E5),
          child: Column(
            children: [
              // --- SCROLLABLE MAIN BODY CANVAS ---
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    height: baseHeight * scale,
                    width: constraints.maxWidth,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        
                        // Yellow Decorative Banner Component
                        Positioned(
                          left: 0,
                          top: 0,
                          child: Container(
                            width: 393 * scale,
                            height: 50 * scale,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFB800),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x0C132C4A),
                                  blurRadius: 16,
                                )
                              ],
                            ),
                          ),
                        ),

                        // Subtitle Section Base Accent Bar
                        Positioned(
                          left: 0,
                          top: 50 * scale,
                          child: Container(
                            width: 393 * scale,
                            height: 50 * scale,
                            decoration: const BoxDecoration(
                              color: Color(0xCCF39C12),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x0C132C4A),
                                  blurRadius: 16,
                                )
                              ],
                            ),
                          ),
                        ),

                        // Title Text Display Block
                        Positioned(
                          left: 150 * scale,
                          top: 61 * scale,
                          child: Text(
                            'Numbers',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 20 * scale,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.96,
                            ),
                          ),
                        ),

                        // Functional Back Navigation Button
                        Positioned(
                          left: 16 * scale,
                          top: 51 * scale,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 46 * scale,
                              height: 46 * scale,
                              decoration: ShapeDecoration(
                                color: const Color(0x33FFF8E7),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14 * scale),
                                ),
                              ),
                              child: Icon(
                                Icons.arrow_back,
                                color: Colors.black87,
                                size: 22 * scale,
                              ),
                            ),
                          ),
                        ),

                        // Avatar Widget (Image 66)
                        Positioned(
                          left: 346.46 * scale,
                          top: 0,
                          child: Container(
                            width: 45.39 * scale,
                            height: 50.11 * scale,
                            decoration: const BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage("assets/pictures/image 66.png"),
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                        ),

                        // Functional Progress Track Panel
                        Positioned(
                          left: 6 * scale,
                          top: 112 * scale,
                          child: _buildMainProgressPanel(
                            scale: scale,
                            level: currentLevel,
                            currentXp: currentXp,
                            targetXp: targetXp,
                          ),
                        ),

                        // ==========================================
                        // TUTORIAL INTERACTIVE ROW
                        // ==========================================
                        Positioned(
                          left: 24 * scale,
                          top: 180 * scale,
                          child: Container(
                            width: 130 * scale,
                            height: 110 * scale,
                            decoration: const BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage("assets/pictures/tutor.png"),
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          left: 165 * scale,
                          top: 195 * scale,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tutorial',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 28 * scale,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.5,
                                ),
                              ),
                              SizedBox(height: 6 * scale),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFB800),
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20 * scale),
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16 * scale,
                                    vertical: 6 * scale,
                                  ),
                                ),
                                icon: Icon(Icons.play_arrow, size: 16 * scale),
                                label: Text(
                                  'Start Learn',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13 * scale,
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => NumbersTutorialInterface()),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        // ==========================================
                        // PRACTICE INTERACTIVE ROW
                        // ==========================================
                        Positioned(
                          left: 16 * scale,
                          top: 300 * scale,
                          child: Container(
                            width: 135 * scale,
                            height: 135 * scale,
                            decoration: const BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage("assets/pictures/practice.png"),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          left: 165 * scale,
                          top: 325 * scale,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Practice',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 28 * scale,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.5,
                                ),
                              ),
                              SizedBox(height: 6 * scale),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFB800),
                                  foregroundColor: Colors.white,            
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20 * scale),
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16 * scale,                 
                                    vertical: 6 * scale,
                                  ),
                                ),
                                icon: Icon(Icons.camera_alt, size: 16 * scale), 
                                label: Text(
                                  'Train Sign',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13 * scale,
                                  ),
                                ),
                                onPressed: () {
                                  // Update this route to point to your specific Numbers practice page
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const PracticeInterface()),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        // ==========================================
                        // UNLOCKED MODULE ARTIFACT LAYER METRICS
                        // ==========================================
                        Positioned(
                          left: 56.75 * scale,
                          top: 455 * scale,
                          child: Text(
                            'Activity',
                            style: TextStyle(
                              color: const Color(0xFF312244),
                              fontSize: 24 * scale,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.44,
                            ),
                          ),
                        ),

                        Positioned(
                          left: 233.75 * scale,
                          top: 455 * scale,
                          child: Text(
                            'Challenges',
                            style: TextStyle(
                              color: const Color(0xFF312244),
                              fontSize: 24 * scale,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.44,
                            ),
                          ),
                        ),

                        // Activity Unlocked Asset Card
                        Positioned(
                          left: 20.75 * scale,
                          top: 492 * scale,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const NumbersActivityInterface()),
                      );
                            },
                            child: Container(
                              width: 164 * scale,
                              height: 160 * scale,
                              decoration: const BoxDecoration(
                                image: DecorationImage(
                                  image: AssetImage("assets/pictures/activity.png"),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Challenges Unlocked Asset Card
                        Positioned(
                          left: 215.75 * scale,
                          top: 492 * scale,
                          child: GestureDetector(
                            onTap: () {
                              // TODO: Connect navigation context for Challenges Interface
                            },
                            child: Container(
                              width: 159 * scale,
                              height: 159 * scale,
                              decoration: const BoxDecoration(
                                image: DecorationImage(
                                  image: AssetImage("assets/pictures/challenge.png"),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Sub Metric Panels (Unlocked)
                        Positioned(
                          left: 13.75 * scale,
                          top: 665 * scale,
                          child: _buildSubMetricPanel(scale: scale, xpDisplay: "0 XP"),
                        ),

                        Positioned(
                          left: 203.75 * scale,
                          top: 665 * scale,
                          child: _buildSubMetricPanel(scale: scale, xpDisplay: "0 XP"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // --- FIXED BOTTOM NAVIGATION FOOTER BAR ---
              Container(
                width: 375 * scale,
                height: 78 * scale,
                margin: EdgeInsets.only(bottom: 12 * scale),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24 * scale),
                  ),
                  shadows: const [
                    BoxShadow(
                      color: Color(0x0C132C4A),
                      blurRadius: 16,
                    )
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(Icons.home, color: Colors.grey, size: 26 * scale),
                      onPressed: () => Navigator.pop(context),
                    ),
                    IconButton(
                      icon: Icon(Icons.auto_stories, color: Colors.black, size: 26 * scale),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: Icon(Icons.person, color: Colors.grey, size: 26 * scale),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- DYNAMICALLY CALCULATED XP PROGRESS GENERATOR ---
  Widget _buildMainProgressPanel({
    required double scale,
    required int level,
    required int currentXp,
    required int targetXp,
  }) {
    final double progressRatio = (currentXp / targetXp).clamp(0.0, 1.0);
    const double maxTrackWidth = 235.0;

    return Container(
      width: 381 * scale,
      height: 55 * scale,
      decoration: ShapeDecoration(
        color: Colors.white.withOpacity(0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14 * scale),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 56 * scale,
            top: 5 * scale,
            child: Text(
              'Level $level',
              style: TextStyle(
                color: const Color(0xFF322144),
                fontSize: 14 * scale,
                fontFamily: 'Google Sans Flex',
                fontWeight: FontWeight.w600,
                letterSpacing: -0.90,
              ),
            ),
          ),
          Positioned(
            left: 56 * scale,
            top: 24 * scale,
            child: Text(
              '$currentXp XP',
              style: TextStyle(
                color: const Color(0xFFBA8E23),
                fontSize: 17 * scale,
                fontFamily: 'Holtwood One SC',
                fontWeight: FontWeight.w400,
                letterSpacing: -1.20,
              ),
            ),
          ),
          // Background Bar Track
          Positioned(
            left: 130 * scale,
            top: 26 * scale,
            child: Container(
              width: maxTrackWidth * scale,
              height: 6 * scale,
              decoration: ShapeDecoration(
                color: const Color(0xFFF1F1FA),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25 * scale),
                ),
              ),
            ),
          ),
          // Dynamic Active Fill Layer
          Positioned(
            left: 130 * scale,
            top: 26 * scale,
            child: Container(
              width: (maxTrackWidth * progressRatio) * scale,
              height: 6 * scale,
              decoration: ShapeDecoration(
                color: const Color(0xFFFFB800),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25 * scale),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20 * scale,
            top: 16 * scale,
            child: Image.asset(
              "assets/pictures/star.png",
              width: 22 * scale,
              height: 21 * scale,
              errorBuilder: (c, o, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale),
            ),
          ),
        ],
      ),
    );
  }

  // Sub indicator tracker cards layout helper (Unlocked)
  Widget _buildSubMetricPanel({required double scale, required String xpDisplay}) {
    return Container(
      width: 178 * scale,
      height: 37 * scale,
      decoration: ShapeDecoration(
        color: Colors.white.withOpacity(0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14 * scale),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 45 * scale,
            top: 3 * scale,
            child: Text(
              xpDisplay,
              style: TextStyle(
                color: const Color(0xFFBA8E23),
                fontSize: 16 * scale,
                fontFamily: 'Holtwood One SC',
                fontWeight: FontWeight.w400,
                letterSpacing: -1.20,
              ),
            ),
          ),
          Positioned(
            left: 12 * scale,
            top: 24 * scale,
            child: Container(
              width: 154 * scale,
              height: 4 * scale,
              decoration: ShapeDecoration(
                color: const Color(0xFFF1F1FA),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25 * scale),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12 * scale,
            top: 3 * scale,
            child: Image.asset(
              "assets/pictures/star.png",
              width: 18 * scale,
              height: 17 * scale,
              errorBuilder: (c, o, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 14 * scale),
            ),
          ),
        ],
      ),
    );
  }
}