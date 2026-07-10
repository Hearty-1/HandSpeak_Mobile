import 'package:flutter/material.dart';
import '../module/module.dart'; // Matches your module file name
import '../profile/profile.dart';

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
          child: SnedInterafce1(userName: "Student"),
        ),
      ),
    );
  }
}

class SnedInterafce1 extends StatelessWidget {
  final String userName;

  const SnedInterafce1({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    // Reference design dimensions from original Figma template
    const double baseWidth = 393;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate scale factor dynamically based on viewport width
        final double scale = constraints.maxWidth / baseWidth;

        return Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFFFFF9E5),
          child: Column(
            children: [
              // --- RESPONSIVE SCROLLABLE MAIN CONTENT AREA ---
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    // Canvas height hosts the updated features seamlessly
                    height: 1120 * scale, 
                    width: constraints.maxWidth,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        
                        // --- SECTION 1: USER BANNER & PROGRESS ---
                        // Yellow Greeting Banner Base Card
                        Positioned(
                          left: 8.60 * scale,
                          top: 25 * scale,
                          child: Container(
                            width: 376 * scale,
                            height: 134.48 * scale,
                            decoration: ShapeDecoration(
                              color: const Color(0xFFFFB800),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14 * scale),
                              ),
                              shadows: const [
                                BoxShadow(
                                  color: Color(0x0A132C4A),
                                  blurRadius: 18,
                                  offset: Offset(0, 10),
                                )
                              ],
                            ),
                          ),
                        ),
                        
                        // "Mabuhay," Text Heading
                        Positioned(
                          left: 20 * scale,
                          top: 37 * scale,
                          child: SizedBox(
                            width: 102 * scale,
                            child: Text(
                              'Mabuhay, ',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 20 * scale,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w800,
                                height: 1,
                                letterSpacing: -1.20 * scale,
                              ),
                            ),
                          ),
                        ),
                        
                        // User Name Title
                        Positioned(
                          left: 17 * scale,
                          top: 63 * scale,
                          child: SizedBox(
                            width: 300 * scale,
                            child: Text(
                              userName,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 32 * scale,
                                fontFamily: 'Coiny',
                                fontWeight: FontWeight.w400,
                                height: 0.63,
                                letterSpacing: -1.92 * scale,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),

                        // Welcome exclamation mark
                        Positioned(
                          left: (17 + (userName.length * 14.0)).clamp(94.34, 340.0) * scale,
                          top: 65 * scale,
                          child: Text(
                            '!',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 32 * scale,
                              fontFamily: 'Coiny',
                              fontWeight: FontWeight.w400,
                              height: 0.63,
                            ),
                          ),
                        ),

                        // Level 1 Indicator Tag
                        Positioned(
                          left: 19.60 * scale,
                          top: 107 * scale,
                          child: Text(
                            'Level 1',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20 * scale,
                              fontFamily: 'Google Sans Flex',
                              fontWeight: FontWeight.w400,
                              height: 1,
                              letterSpacing: -1.20 * scale,
                            ),
                          ),
                        ),

                        // Level Progress Bar Outer Accent Track
                        Positioned(
                          left: 12 * scale,
                          top: 127 * scale,
                          child: Container(
                            width: 368 * scale,
                            height: 24 * scale,
                            decoration: ShapeDecoration(
                              color: Colors.white.withOpacity(0.18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14 * scale),
                              ),
                            ),
                          ),
                        ),

                        // XP text indicator
                        Positioned(
                          left: 24 * scale,
                          top: 129 * scale,
                          child: Text(
                            '0 xp',
                            style: TextStyle(
                              color: const Color(0xFFBA8E23),
                              fontSize: 16 * scale,
                              fontFamily: 'Holtwood One SC',
                              fontWeight: FontWeight.w400,
                              height: 1,
                            ),
                          ),
                        ),

                        // Inner Progress Line
                        Positioned(
                          left: 24 * scale,
                          top: 147 * scale,
                          child: Container(
                            width: 344.73 * scale,
                            height: 3.51 * scale,
                            decoration: ShapeDecoration(
                              color: const Color(0xFFF1F1FA),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25 * scale),
                              ),
                            ),
                          ),
                        ),

                        // --- SECTION 2: GAMIFIED DAILY CHALLENGE CARD ---
                        Positioned(
                          left: 8.60 * scale,
                          top: 175 * scale,
                          child: Container(
                            width: 376 * scale,
                            height: 105 * scale,
                            decoration: ShapeDecoration(
                              color: const Color(0xFF322144), 
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20 * scale),
                              ),
                              shadows: const [
                                BoxShadow(
                                  color: Color(0x1A000000),
                                  blurRadius: 12,
                                  offset: Offset(0, 6),
                                )
                              ],
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 16 * scale,
                                  top: 14 * scale,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF8227),
                                      borderRadius: BorderRadius.circular(12 * scale),
                                    ),
                                    child: Text(
                                      'DAILY CHALLENGE',
                                      style: TextStyle(color: Colors.white, fontSize: 10 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 16 * scale,
                                  top: 42 * scale,
                                  child: Text(
                                    'Perfect the Sign Letter "G"',
                                    style: TextStyle(color: Colors.white, fontSize: 18 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Positioned(
                                  left: 16 * scale,
                                  top: 68 * scale,
                                  child: Row(
                                    children: [
                                      Icon(Icons.bolt, color: const Color(0xFFFFCA28), size: 16 * scale),
                                      SizedBox(width: 4 * scale),
                                      Text('Reward: +150 XP', style: TextStyle(color: const Color(0xFFFFCA28), fontSize: 13 * scale, fontFamily: 'NATS', fontWeight: FontWeight.bold)),
                                      SizedBox(width: 16 * scale),
                                      Icon(Icons.timer_outlined, color: Colors.white60, size: 14 * scale),
                                      SizedBox(width: 4 * scale),
                                      Text('14h left', style: TextStyle(color: Colors.white60, fontSize: 12 * scale, fontFamily: 'NATS')),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  right: 12 * scale,
                                  top: 18 * scale,
                                  child: Container(
                                    width: 65 * scale,
                                    height: 65 * scale,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.07),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.psychology_alt_outlined, color: const Color(0xFFFFCA28), size: 36 * scale),
                                  ),
                                )
                              ],
                            ),
                          ),
                        ),

                        // --- SECTION 3: QUICK STREAK & STATS MODULE ---
                        Positioned(
                          left: 8.60 * scale,
                          top: 295 * scale,
                          child: SizedBox(
                            width: 376 * scale,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Streak Tracker Panel
                                Container(
                                  width: 182 * scale,
                                  height: 62 * scale,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16 * scale),
                                    border: Border.all(color: const Color(0xFFEFEFEF), width: 1),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(width: 12 * scale),
                                      Text('🔥', style: TextStyle(fontSize: 24 * scale)),
                                      SizedBox(width: 8 * scale),
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('5 DAYS', style: TextStyle(color: const Color(0xFF312244), fontSize: 16 * scale, fontFamily: 'Coiny')),
                                          Text('Active Streak', style: TextStyle(color: Colors.black45, fontSize: 11 * scale, fontFamily: 'Inter')),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                                // Accuracy Tracker Panel
                                Container(
                                  width: 182 * scale,
                                  height: 62 * scale,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16 * scale),
                                    border: Border.all(color: const Color(0xFFEFEFEF), width: 1),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(width: 12 * scale),
                                      Text('🎯', style: TextStyle(fontSize: 22 * scale)),
                                      SizedBox(width: 8 * scale),
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('88%', style: TextStyle(color: const Color(0xFFF34B1B), fontSize: 16 * scale, fontFamily: 'Coiny')),
                                          Text('Avg Accuracy', style: TextStyle(color: Colors.black45, fontSize: 11 * scale, fontFamily: 'Inter')),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // --- SECTION 4: REAL-TIME READY LEADERBOARD ---
                        // Dark gold background plate for leaderboard module
                        Positioned(
                          left: 5.26 * scale,
                          top: 380 * scale,
                          child: Container(
                            width: 383.65 * scale,
                            height: 485 * scale,
                            decoration: ShapeDecoration(
                              color: const Color(0xCCD8A426),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(40 * scale),
                              ),
                              shadows: const [
                                BoxShadow(
                                  color: Color(0x0A132C4A),
                                  blurRadius: 18,
                                  offset: Offset(0, 10),
                                )
                              ],
                            ),
                          ),
                        ),

                        // --- THE PODIUM ELEMENT MATRIX GROUP ---
                        Positioned(
                          left: 0,
                          top: 340 * scale,
                          child: SizedBox(
                            width: 393 * scale,
                            height: 344.62 * scale,
                            child: Stack(
                              children: [
                                // Level Sub-labels for positions
                                Positioned(left: 47 * scale, top: 207 * scale, child: Text('level 2', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14 * scale, fontFamily: 'NATS'))),
                                Positioned(left: 173 * scale, top: 224 * scale, child: Text('level 32', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14 * scale, fontFamily: 'NATS'))),
                                Positioned(left: 298 * scale, top: 199 * scale, child: Text('Level 3', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14 * scale, fontFamily: 'NATS'))),
                                
                                // User display tags
                                Positioned(left: 120 * scale, top: 205 * scale, child: SizedBox(width: 148 * scale, child: Text('Jane Doe', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 17 * scale, fontFamily: 'NATS')))),
                                Positioned(left: 266 * scale, top: 182 * scale, child: SizedBox(width: 110 * scale, child: Text('Bob Marley', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 17 * scale, fontFamily: 'NATS')))),
                                Positioned(left: 0, top: 188 * scale, child: SizedBox(width: 148 * scale, child: Text('Alice Guo', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 17 * scale, fontFamily: 'NATS')))),

                                // 1st Place Central Podium Frame
                                Positioned(
                                  left: 132.30 * scale,
                                  top: 73.22 * scale,
                                  child: Container(
                                    width: 126.39 * scale,
                                    height: 126.65 * scale,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF322144),
                                      shape: BoxShape.circle,
                                      border: Border.all(width: 3.70 * scale, color: const Color(0xFFFFCA28)),
                                    ),
                                    child: Icon(Icons.person, size: 55 * scale, color: Colors.white24),
                                  ),
                                ),

                                // 3rd Place Right Podium Frame
                                Positioned(
                                  left: 277 * scale,
                                  top: 96 * scale,
                                  child: Container(
                                    width: 83 * scale,
                                    height: 81 * scale,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF8227),
                                      shape: BoxShape.circle,
                                      border: Border.all(width: 3.70 * scale, color: const Color(0xFF342145)),
                                    ),
                                    child: Icon(Icons.person, size: 38 * scale, color: Colors.white24),
                                  ),
                                ),

                                // 2nd Place Left Podium Frame
                                Positioned(
                                  left: 35 * scale,
                                  top: 102 * scale,
                                  child: Container(
                                    width: 83 * scale,
                                    height: 81 * scale,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF34B1B),
                                      shape: BoxShape.circle,
                                      border: Border.all(width: 3.70 * scale, color: const Color(0xFF322244)),
                                    ),
                                    child: Icon(Icons.person, size: 38 * scale, color: Colors.white24),
                                  ),
                                ),

                                // Number Badges (1, 2, 3)
                                Positioned(
                                  left: 303.88 * scale, top: 162.27 * scale,
                                  child: Container(width: 29.62 * scale, height: 29.68 * scale, decoration: const BoxDecoration(color: Color(0xFFFF8227), shape: BoxShape.circle), child: Center(child: Text('3', style: TextStyle(color: const Color(0xFF342145), fontSize: 14 * scale, fontWeight: FontWeight.bold)))),
                                ),
                                Positioned(
                                  left: 61 * scale, top: 162.27 * scale,
                                  child: Container(width: 29.62 * scale, height: 29.68 * scale, decoration: const BoxDecoration(color: Color(0xFFF34B1B), shape: BoxShape.circle), child: Center(child: Text('2', style: TextStyle(color: const Color(0xFF342145), fontSize: 14 * scale, fontWeight: FontWeight.bold)))),
                                ),
                                Positioned(
                                  left: 181.44 * scale, top: 185.03 * scale,
                                  child: Container(width: 29.62 * scale, height: 29.68 * scale, decoration: const BoxDecoration(color: Color(0xFFFFCA28), shape: BoxShape.circle), child: Center(child: Text('1', style: TextStyle(color: const Color(0xFF342145), fontSize: 14 * scale, fontWeight: FontWeight.bold)))),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // --- LOWER LEADERBOARD LIST ROWS ---
                        // Row 1: Jane Doe
                        Positioned(
                          left: 77 * scale,
                          top: 660 * scale,
                          child: Container(
                            width: 243.94 * scale,
                            height: 48.05 * scale,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFCA28),
                              borderRadius: BorderRadius.circular(22.18 * scale),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0 * scale),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('1  Jane Doe', style: TextStyle(color: const Color(0xFF312244), fontSize: 15 * scale, fontFamily: 'NATS')),
                                  Text('2019 pts.', style: TextStyle(color: const Color(0xB2312244), fontSize: 13 * scale, fontFamily: 'NATS')),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Row 2: Alice Guo
                        Positioned(
                          left: 77 * scale,
                          top: 718 * scale,
                          child: Container(
                            width: 243.94 * scale,
                            height: 48.05 * scale,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F4F4),
                              borderRadius: BorderRadius.circular(22.18 * scale),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0 * scale),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('2  Alice Guo', style: TextStyle(color: const Color(0xFF312244), fontSize: 15 * scale, fontFamily: 'NATS')),
                                  Text('1932 pts.', style: TextStyle(color: const Color(0xB2312244), fontSize: 13 * scale, fontFamily: 'NATS')),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Row 3: Bob Marley
                        Positioned(
                          left: 77 * scale,
                          top: 776 * scale,
                          child: Container(
                            width: 243.94 * scale,
                            height: 48.05 * scale,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F4F4),
                              borderRadius: BorderRadius.circular(22.18 * scale),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0 * scale),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('3  Bob Marley', style: TextStyle(color: const Color(0xFF312244), fontSize: 15 * scale, fontFamily: 'NATS')),
                                  Text('1431 pts.', style: TextStyle(color: const Color(0xB2312244), fontSize: 13 * scale, fontFamily: 'NATS')),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // --- FIXED RESPONSIVE BOTTOM NAVIGATION BAR ---
              Container(
                width: constraints.maxWidth,
                height: 76,
                margin: EdgeInsets.only(
                  left: 16 * scale,
                  right: 16 * scale,
                  bottom: 12 * scale,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0C132C4A),
                      blurRadius: 16,
                      offset: Offset(0, 0),
                    )
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.home, color: Colors.black, size: 26),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_stories, color: Colors.grey, size: 26),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => SnedInterface2()),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.person, color: Colors.grey, size: 26),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ProfileScreen()),
                        );
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
}