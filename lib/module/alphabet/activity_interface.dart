import 'package:flutter/material.dart';

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
          child: ActivityInterface(
            easyXp: 350,   // Change these values to test dynamic backend progress binding
            mediumXp: 0,
            hardXp: 0,
            targetXp: 1000,
          ),
        ),
      ),
    );
  }
}

class ActivityInterface extends StatelessWidget {
  // --- BACKEND PASSTHROUGH CHANNELS ---
  final int easyXp;
  final int mediumXp;
  final int hardXp;
  final int targetXp;

  const ActivityInterface({
    super.key,
    this.easyXp = 350,
    this.mediumXp = 0,
    this.hardXp = 0,
    this.targetXp = 1000,
  });

  @override
  Widget build(BuildContext context) {
    const double baseWidth = 393;
    const double baseHeight = 852;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double scale = constraints.maxWidth / baseWidth;

        return Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFFFFF9E5),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              height: baseHeight * scale,
              width: constraints.maxWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ==========================================
                  // ORIGINAL DESIGN HEADERS
                  // ==========================================
                  // Top Banner
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

                  // Subtitle Banner
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

                  // Header Text
                  Positioned(
                    left: 162 * scale,
                    top: 61 * scale,
                    child: Text(
                      'Activity',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 20 * scale,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.96,
                      ),
                    ),
                  ),

                  // Functional Back Button
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

                  // Avatar Component (Image 66)
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

                  // ==========================================
                  // UNLOCKED ACTIVITY LEVELS (1:1 with Figma)
                  // ==========================================
                  // EASY
                  ..._buildLevelBlock(
                    scale: scale,
                    startY: 204.0,
                    title: 'Easy',
                    currentXp: easyXp,
                    targetXp: targetXp,
                  ),

                  // MEDIUM
                  ..._buildLevelBlock(
                    scale: scale,
                    startY: 406.0,
                    title: 'Medium',
                    currentXp: mediumXp,
                    targetXp: targetXp,
                  ),

                  // HARD
                  ..._buildLevelBlock(
                    scale: scale,
                    startY: 608.0,
                    title: 'Hard',
                    currentXp: hardXp,
                    targetXp: targetXp,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- HELPER METHOD TO REPLICATE EXACT FIGMA BLOCK STRUCTURING ---
  List<Widget> _buildLevelBlock({
    required double scale,
    required double startY,
    required String title,
    required int currentXp,
    required int targetXp,
  }) {
    final double progressRatio = (currentXp / targetXp).clamp(0.0, 1.0);
    const double trackWidth = 312.64;

    return [
      // Main Yellow Base Container
      Positioned(
        left: 21.50 * scale,
        top: startY * scale,
        child: Container(
          width: 350 * scale,
          height: 85.82 * scale,
          decoration: ShapeDecoration(
            color: const Color(0xFFFFB800),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14 * scale),
            ),
          ),
        ),
      ),

      // Title Text
      Positioned(
        left: 36 * scale,
        top: (startY + 16.08) * scale,
        child: SizedBox(
          width: 265 * scale,
          child: Text(
            title,
            style: TextStyle(
              color: Colors.black,
              fontSize: 54 * scale, // Slightly adjusted from 64 to prevent clipping in Flutter
              fontFamily: 'Inter',
              fontWeight: FontWeight.w800,
              letterSpacing: -3.84 * scale,
            ),
          ),
        ),
      ),

      // White Translucent XP Sub-Container
      Positioned(
        left: 21.50 * scale,
        top: (startY + 93.5) * scale,
        child: Container(
          width: 350 * scale,
          height: 66.50 * scale,
          decoration: ShapeDecoration(
            color: Colors.white.withOpacity(0.18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14 * scale),
            ),
          ),
        ),
      ),

      // Star Icon
      Positioned(
        left: 42.88 * scale,
        top: (startY + 102.93) * scale,
        child: Image.asset(
          "assets/pictures/star.png",
          width: 39.54 * scale,
          height: 37.90 * scale,
          errorBuilder: (c, o, s) => Icon(
            Icons.star, 
            color: const Color(0xFFFFB800), 
            size: 36 * scale
          ),
        ),
      ),

      // XP Text
      Positioned(
        left: 88.47 * scale,
        top: (startY + 105.4) * scale,
        child: SizedBox(
          child: Text(
            '$currentXp XP',
            style: TextStyle(
              color: const Color(0xFFBA8E23),
              fontSize: 20 * scale,
              fontFamily: 'Holtwood One SC',
              fontWeight: FontWeight.w400,
              letterSpacing: -1.20 * scale,
            ),
          ),
        ),
      ),

      // Background Progress Track (Grey)
      Positioned(
        left: 43.13 * scale,
        top: (startY + 143.82) * scale,
        child: Container(
          width: trackWidth * scale,
          height: 8.99 * scale,
          decoration: ShapeDecoration(
            color: const Color(0xFFF1F1FA),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25 * scale),
            ),
          ),
        ),
      ),

      // Active Progress Track 
      Positioned(
        left: 43.13 * scale,
        top: (startY + 143.82) * scale,
        child: Container(
          width: (trackWidth * progressRatio) * scale,
          height: 8.99 * scale,
          decoration: ShapeDecoration(
            color: const Color(0xFF7DC579),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25 * scale),
            ),
          ),
        ),
      ),
    ];
  }
}