import 'package:flutter/material.dart';
import './alphabet/alphabet_interface.dart';
import 'numbers/numbers_interface.dart'; // Added import for the Numbers interface
import '../profile/profile.dart'; // Added import for the Profile interface

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
          child: SnedInterface2(),
        ),
      ),
    );
  }
}

class SnedInterface2 extends StatelessWidget {
  const SnedInterface2({super.key});

  @override
  Widget build(BuildContext context) {
    // Base design dimensions adjusted for removed status bar (852 - 59 = 793)
    const double baseWidth = 393;
    const double baseHeight = 793;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Automatically determine scaling factor based on the current device screen size
        final double scale = constraints.maxWidth / baseWidth;

        return Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFFFFF9E5),
          child: Column(
            children: [
              // --- SCROLLABLE BODY LAYER PREVENTS DEVICE OVERFLOW ---
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    height: baseHeight * scale,
                    width: constraints.maxWidth,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        
                        // Yellow Decorative Banner Component (Shifted to top: 0)
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

                        // Avatar Widget (Image 66 aligned with the yellow banner)
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

                        // Search Bar Card Frame
                        Positioned(
                          left: 11.45 * scale,
                          top: 58.22 * scale,
                          child: Container(
                            width: 370.11 * scale,
                            height: 48 * scale,
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14 * scale),
                              ),
                              shadows: const [
                                BoxShadow(
                                  color: Color(0x05132C4A),
                                  blurRadius: 16,
                                  offset: Offset(0, 6),
                                )
                              ],
                            ),
                          ),
                        ),

                        // Search Box Placeholder Hint Text
                        Positioned(
                          left: 70.48 * scale,
                          top: 74.22 * scale,
                          child: Text(
                            'Search now...',
                            style: TextStyle(
                              color: const Color(0xFFAEAEAE),
                              fontSize: 16 * scale,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),

                        // Search Leading Icon Area
                        Positioned(
                          left: 32.70 * scale,
                          top: 72 * scale,
                          child: Icon(
                            Icons.search,
                            color: const Color(0xFFAEAEAE),
                            size: 20 * scale,
                          ),
                        ),

                        // ==========================================
                        // MODULE: ALPHABETS (ACTIVE INTERFACE)
                        // ==========================================
                        Positioned(
                          left: 7 * scale,
                          top: 151 * scale,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const AlphabetInterface()),
                              );
                            },
                            child: Container(
                              width: 171 * scale,
                              height: 171 * scale,
                              decoration: const BoxDecoration(
                                image: DecorationImage(
                                  image: AssetImage("assets/pictures/abc.png"),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          left: 27 * scale,
                          top: 139 * scale,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const AlphabetInterface()),
                              );
                            },
                            child: Text(
                              'Alphabets',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 32 * scale,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.92,
                              ),
                            ),
                          ),
                        ),

                        // Alphabets Stats Progress Bar Card
                        Positioned(
                          left: 12 * scale,
                          top: 315 * scale,
                          child: _buildProgressPanel(scale: scale, level: "Level  1", xp: "0 XP", xpNext: "1000 to next"),
                        ),

                        // Star Indicator Graphic for Alphabets
                        Positioned(
                          left: 22 * scale,
                          top: 350 * scale,
                          child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, e, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale)),
                        ),

                        // ==========================================
                        // MODULE: NUMBERS (NOW ACTIVE)
                        // ==========================================
                        Positioned(
                          left: 214 * scale,
                          top: 177 * scale,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const NumbersInterface()),
                              );
                            },
                            child: Container(
                              width: 165 * scale,
                              height: 121 * scale,
                              decoration: const BoxDecoration(
                                image: DecorationImage(
                                  image: AssetImage("assets/pictures/numbers.png"),
                                  fit: BoxFit.fill,
                                ),
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          left: 228 * scale,
                          top: 137 * scale,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const NumbersInterface()),
                              );
                            },
                            child: Text(
                              'Numbers',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 32 * scale,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.92,
                              ),
                            ),
                          ),
                        ),

                        // Numbers Stats Progress Bar Card
                        Positioned(
                          left: 205 * scale,
                          top: 315 * scale,
                          child: _buildProgressPanel(scale: scale, level: "Level  1", xp: "0 XP", xpNext: "1000 to next"),
                        ),

                        // Star Indicator Graphic for Numbers
                        Positioned(
                          left: 218 * scale,
                          top: 349 * scale,
                          child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, e, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale)),
                        ),

                        // ==========================================
                        // MODULE: WORDS / PHRASES (LOCKED STYLE)
                        // ==========================================
                        Positioned(
                          left: 30 * scale,
                          top: 486 * scale,
                          child: Opacity(
                            opacity: 0.50,
                            child: Container(
                              width: 144 * scale,
                              height: 144 * scale,
                              decoration: const BoxDecoration(
                                image: DecorationImage(
                                  image: AssetImage("assets/pictures/commons.png"),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          left: 18 * scale,
                          top: 462 * scale,
                          child: Text(
                            'Words/ Phrases',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFF312244),
                              fontSize: 24 * scale,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.44,
                            ),
                          ),
                        ),

                        // Locked Asset Overlay for Phrases
                        Positioned(
                          left: 55 * scale,
                          top: 486 * scale,
                          child: Container(
                            width: 90 * scale,
                            height: 119 * scale,
                            decoration: const BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage("assets/pictures/locked.png"),
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                        ),

                        // Words/Phrases Locked Progress Block
                        Positioned(
                          left: 13 * scale,
                          top: 626 * scale,
                          child: Opacity(
                            opacity: 0.50,
                            child: _buildProgressPanel(scale: scale, level: "Level  1", xp: "0 XP", xpNext: "1000 to next"),
                          ),
                        ),

                        // Star Element overlay for Words
                        Positioned(
                          left: 24 * scale,
                          top: 661 * scale,
                          child: Opacity(
                            opacity: 0.50,
                            child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, e, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale)),
                          ),
                        ),

                        // ==========================================
                        // MODULE: CIVIC OBSERVANCES (LOCKED STYLE)
                        // ==========================================
                        Positioned(
                          left: 217 * scale,
                          top: 481 * scale,
                          child: Opacity(
                            opacity: 0.50,
                            child: Container(
                              width: 154 * scale,
                              height: 153 * scale,
                              decoration: const BoxDecoration(
                                image: DecorationImage(
                                  image: AssetImage("assets/pictures/civic.png"),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          left: 218 * scale,
                          top: 453 * scale,
                          child: Text(
                            'Civic Observances',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFF312244),
                              fontSize: 24 * scale,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.44,
                            ),
                          ),
                        ),

                        // Locked Asset Overlay for Civic
                        Positioned(
                          left: 253.50 * scale,
                          top: 486 * scale,
                          child: Container(
                            width: 90 * scale,
                            height: 119 * scale,
                            decoration: const BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage("assets/pictures/locked.png"),
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                        ),

                        // Civic Locked Progress Block
                        Positioned(
                          left: 205 * scale,
                          top: 626 * scale,
                          child: Opacity(
                            opacity: 0.50,
                            child: _buildProgressPanel(scale: scale, level: "Level  1", xp: "0 XP", xpNext: "1000 to next"),
                          ),
                        ),

                        // Star Element overlay for Civic
                        Positioned(
                          left: 216 * scale,
                          top: 661 * scale,
                          child: Opacity(
                            opacity: 0.50,
                            child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, e, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // --- FIXED BOTTOM SYSTEM NAVIGATION FOOTER PANEL ---
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
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.auto_stories, color: Colors.black, size: 26 * scale),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: Icon(Icons.person, color: Colors.grey, size: 26 * scale),
                      onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
                    },
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

  // Helper widget builder for progress metrics panels
  Widget _buildProgressPanel({
    required double scale,
    required String level,
    required String xp,
    required String xpNext,
  }) {
    return Container(
      width: 178 * scale,
      height: 76 * scale,
      decoration: ShapeDecoration(
        color: Colors.white.withOpacity(0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14 * scale),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 12 * scale,
            top: 5 * scale,
            child: Text(
              level,
              style: TextStyle(
                color: const Color(0xFF322144),
                fontSize: 20 * scale,
                fontFamily: 'Google Sans Flex',
                fontWeight: FontWeight.w400,
                letterSpacing: -1.20,
              ),
            ),
          ),
          Positioned(
            left: 34 * scale,
            top: 35 * scale,
            child: Text(
              xp,
              style: TextStyle(
                color: const Color(0xFFBA8E23),
                fontSize: 20 * scale,
                fontFamily: 'Holtwood One SC',
                fontWeight: FontWeight.w400,
                letterSpacing: -1.20,
              ),
            ),
          ),
          Positioned(
            left: 11 * scale,
            top: 60 * scale,
            child: Container(
              width: 159 * scale,
              height: 5 * scale,
              decoration: ShapeDecoration(
                color: const Color(0xFFF1F1FA),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25 * scale),
                ),
              ),
            ),
          ),
          Positioned(
            left: 105 * scale,
            top: 8 * scale,
            child: Text(
              xpNext,
              style: TextStyle(
                color: const Color(0xFF888888),
                fontSize: 10 * scale,
                fontFamily: 'Google Sans Flex',
                fontWeight: FontWeight.w400,
                letterSpacing: -0.60,
              ),
            ),
          ),
        ],
      ),
    );
  }
}