import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/services/progress_service.dart';
import 'alphabet/alphabet_interface.dart';
import 'numbers/numbers_interface.dart'; 
import '../profile/profile.dart'; 
import '../home/home.dart'; 
import '../leaderboard/leaderboard.dart';

class SnedInterface2 extends StatelessWidget {
  const SnedInterface2({super.key});

  @override
  Widget build(BuildContext context) {
    const double baseWidth = 393;
    const double baseHeight = 793;
    const int targetXp = 1000;

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(),
      builder: (context, snapshot) {
        // --- 1. DEFAULT BACKEND PROGRESS VALUES ---
        int alpEasyXp = 0;
        int alpMediumXp = 0;
        int alpHardXp = 0;

        int numEasyXp = 0;
        int numMediumXp = 0;
        int numHardXp = 0;

        int wordsEasyXp = 0;
        int civicEasyXp = 0;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            alpEasyXp = (data['alpEasyXp'] ?? 0).clamp(0, targetXp);
            alpMediumXp = (data['alpMediumXp'] ?? 0).clamp(0, targetXp);
            alpHardXp = (data['alpHardXp'] ?? 0).clamp(0, targetXp);

            numEasyXp = (data['numEasyXp'] ?? 0).clamp(0, targetXp);
            numMediumXp = (data['numMediumXp'] ?? 0).clamp(0, targetXp);
            numHardXp = (data['numHardXp'] ?? 0).clamp(0, targetXp);

            wordsEasyXp = (data['wordsEasyXp'] ?? 0).clamp(0, targetXp);
            civicEasyXp = (data['civicEasyXp'] ?? 0).clamp(0, targetXp);
          }
        }

        // --- 2. ACTIVE LEVEL CALCULATION ---
        // Alphabets
        int alpDisplayLevel = 1;
        int alpDisplayXp = alpEasyXp;
        if (alpEasyXp >= targetXp) {
          alpDisplayLevel = 2;
          alpDisplayXp = alpMediumXp;
        }
        if (alpMediumXp >= targetXp) {
          alpDisplayLevel = 3;
          alpDisplayXp = alpHardXp;
        }

        // Numbers
        int numDisplayLevel = 1;
        int numDisplayXp = numEasyXp;
        if (numEasyXp >= targetXp) {
          numDisplayLevel = 2;
          numDisplayXp = numMediumXp;
        }
        if (numMediumXp >= targetXp) {
          numDisplayLevel = 3;
          numDisplayXp = numHardXp;
        }

        // --- 3. DYNAMIC PROGRESSION LOCKS ---
        final bool isWordsLocked = (alpEasyXp < targetXp) || (numEasyXp < targetXp);
        final bool isCivicsLocked = isWordsLocked || (wordsEasyXp < targetXp);

        return LayoutBuilder(
          builder: (context, constraints) {
            final double scale = constraints.maxWidth / baseWidth;

            return Container(
              width: double.infinity,
              height: double.infinity,
              color: const Color(0xFFFFF9E5),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: SizedBox(
                        height: baseHeight * scale,
                        width: constraints.maxWidth,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Title & Search Row
                            Positioned(
                              left: 0, top: 0,
                              child: Container(
                                width: 393 * scale, height: 50 * scale,
                                decoration: const BoxDecoration(color: Color(0xFFFFB800), boxShadow: [BoxShadow(color: Color(0x0C132C4A), blurRadius: 16)]),
                              ),
                            ),
                            Positioned(
                              left: 346.46 * scale, top: 0,
                              child: Container(
                                width: 45.39 * scale, height: 50.11 * scale,
                                decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/image 66.png"), fit: BoxFit.fill)),
                              ),
                            ),
                            Positioned(
                              left: 11.45 * scale, top: 58.22 * scale,
                              child: Container(
                                width: 370.11 * scale, height: 48 * scale,
                                decoration: ShapeDecoration(color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale)), shadows: const [BoxShadow(color: Color(0x05132C4A), blurRadius: 16, offset: Offset(0, 6))]),
                              ),
                            ),
                            Positioned(
                              left: 70.48 * scale, top: 74.22 * scale,
                              child: Text('Search now...', style: TextStyle(color: const Color(0xFFAEAEAE), fontSize: 16 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w500)),
                            ),
                            Positioned(
                              left: 32.70 * scale, top: 72 * scale,
                              child: Icon(Icons.search, color: const Color(0xFFAEAEAE), size: 20 * scale),
                            ),

                            // --- MODULE: ALPHABETS ---
                            Positioned(
                              left: 7 * scale, top: 151 * scale,
                              child: GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AlphabetInterface(
                                      currentLevel: alpDisplayLevel,
                                      currentXp: alpDisplayXp,
                                      targetXp: targetXp,
                                    ),
                                  ),
                                ),
                                child: Container(width: 171 * scale, height: 171 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/abc.png"), fit: BoxFit.cover))),
                              ),
                            ),
                            Positioned(
                              left: 27 * scale, top: 139 * scale,
                              child: GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AlphabetInterface(currentLevel: alpDisplayLevel, currentXp: alpDisplayXp))),
                                child: Text('Alphabets', style: TextStyle(color: Colors.black, fontSize: 32 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.92)),
                              ),
                            ),
                            Positioned(
                              left: 12 * scale, top: 315 * scale, 
                              child: _buildProgressPanel(
                                scale: scale, 
                                level: "Level $alpDisplayLevel", 
                                xp: "$alpDisplayXp XP", 
                                xpNext: "${targetXp - alpDisplayXp} to next",
                                progressRatio: alpDisplayXp / targetXp,
                              ),
                            ),
                            Positioned(left: 22 * scale, top: 350 * scale, child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, e, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale))),
                            
                            // --- MODULE: NUMBERS ---
                            Positioned(
                              left: 214 * scale, top: 177 * scale,
                              child: GestureDetector(
                                onTap: () => Navigator.push(
                                  context, 
                                  MaterialPageRoute(
                                    builder: (context) => NumbersInterface(
                                      currentLevel: numDisplayLevel,
                                      currentXp: numDisplayXp,
                                      targetXp: targetXp,
                                    ),
                                  ),
                                ),
                                child: Container(width: 165 * scale, height: 121 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/numbers.png"), fit: BoxFit.fill))),
                              ),
                            ),
                            Positioned(
                              left: 228 * scale, top: 137 * scale,
                              child: GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => NumbersInterface(currentLevel: numDisplayLevel, currentXp: numDisplayXp))),
                                child: Text('Numbers', style: TextStyle(color: Colors.black, fontSize: 32 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.92)),
                              ),
                            ),
                            Positioned(
                              left: 205 * scale, top: 315 * scale, 
                              child: _buildProgressPanel(
                                scale: scale, 
                                level: "Level $numDisplayLevel", 
                                xp: "$numDisplayXp XP", 
                                xpNext: "${targetXp - numDisplayXp} to next",
                                progressRatio: numDisplayXp / targetXp,
                              ),
                            ),
                            Positioned(left: 218 * scale, top: 349 * scale, child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, e, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale))),
                            
                            // --- MODULE: WORDS / PHRASES (LOCKED/UNLOCKED) ---
                            Positioned(
                              left: 30 * scale, top: 486 * scale, 
                              child: Opacity(
                                opacity: isWordsLocked ? 0.40 : 1.0, 
                                child: Container(width: 144 * scale, height: 144 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/commons.png"), fit: BoxFit.cover))),
                              ),
                            ),
                            Positioned(
                              left: 18 * scale, top: 462 * scale, 
                              child: Opacity(
                                opacity: isWordsLocked ? 0.60 : 1.0,
                                child: Text('Words/ Phrases', textAlign: TextAlign.center, style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44)),
                              ),
                            ),
                            if (isWordsLocked)
                              Positioned(left: 55 * scale, top: 486 * scale, child: Container(width: 90 * scale, height: 119 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/locked.png"), fit: BoxFit.fill))))
                            else
                              Positioned(
                                left: 55 * scale, top: 486 * scale,
                                child: GestureDetector(
                                  onTap: () {
                                    // Router pathway to words interface screen
                                  },
                                  child: SizedBox(width: 90 * scale, height: 119 * scale),
                                ),
                              ),
                            Positioned(
                              left: 13 * scale, top: 626 * scale, 
                              child: Opacity(
                                opacity: isWordsLocked ? 0.40 : 1.0, 
                                child: _buildProgressPanel(
                                  scale: scale, 
                                  level: "Level 1", 
                                  xp: "$wordsEasyXp XP", 
                                  xpNext: "${targetXp - wordsEasyXp} to next",
                                  progressRatio: wordsEasyXp / targetXp,
                                ),
                              ),
                            ),
                            Positioned(left: 24 * scale, top: 661 * scale, child: Opacity(opacity: isWordsLocked ? 0.40 : 1.0, child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, e, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale)))),
                            
                            // --- MODULE: CIVIC OBSERVANCES (LOCKED/UNLOCKED) ---
                            Positioned(
                              left: 217 * scale, top: 481 * scale, 
                              child: Opacity(
                                opacity: isCivicsLocked ? 0.40 : 1.0, 
                                child: Container(width: 154 * scale, height: 153 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/civic.png"), fit: BoxFit.cover))),
                              ),
                            ),
                            Positioned(
                              left: 218 * scale, top: 453 * scale, 
                              child: Opacity(
                                opacity: isCivicsLocked ? 0.60 : 1.0,
                                child: Text('Civic Observances', textAlign: TextAlign.center, style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44)),
                              ),
                            ),
                            if (isCivicsLocked)
                              Positioned(left: 253.50 * scale, top: 486 * scale, child: Container(width: 90 * scale, height: 119 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/locked.png"), fit: BoxFit.fill))))
                            else
                              Positioned(
                                left: 253.50 * scale, top: 486 * scale,
                                child: GestureDetector(
                                  onTap: () {
                                    // Router pathway to civics interface screen
                                  },
                                  child: SizedBox(width: 90 * scale, height: 119 * scale),
                                ),
                              ),
                            Positioned(
                              left: 205 * scale, top: 626 * scale, 
                              child: Opacity(
                                opacity: isCivicsLocked ? 0.40 : 1.0, 
                                child: _buildProgressPanel(
                                  scale: scale, 
                                  level: "Level 1", 
                                  xp: "$civicEasyXp XP", 
                                  xpNext: "${targetXp - civicEasyXp} to next",
                                  progressRatio: civicEasyXp / targetXp,
                                ),
                              ),
                            ),
                            Positioned(left: 216 * scale, top: 661 * scale, child: Opacity(opacity: isCivicsLocked ? 0.40 : 1.0, child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, e, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale)))),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Bottom Bar Navigation
                  Container(
                    width: double.infinity,
                    height: 78,
                    margin: const EdgeInsets.only(bottom: 12, left: 10, right: 10),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      shadows: const [BoxShadow(color: Color(0x0C132C4A), blurRadius: 16, offset: Offset(0, 5))],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.home, color: Colors.grey, size: 28), 
                          onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const SnedInterafce1(userName: "Student")), (route) => false),
                        ),
                        IconButton(
                          icon: const Icon(Icons.auto_stories, color: Colors.black, size: 28), 
                          onPressed: () {}, 
                        ),
                        IconButton(
                          icon: const Icon(Icons.emoji_events, color: Colors.grey, size: 28), 
                          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LeaderboardScreen())),
                        ),
                        IconButton(
                          icon: const Icon(Icons.person, color: Colors.grey, size: 28), 
                          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProfileScreen())),
                        ),
                      ],
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

  // Helper widget to render progress status card directly over images with responsive layout metrics
  Widget _buildProgressPanel({
    required double scale, 
    required String level, 
    required String xp, 
    required String xpNext,
    required double progressRatio,
  }) {
    return Container(
      width: 178 * scale, height: 76 * scale,
      decoration: ShapeDecoration(
        color: Colors.white.withOpacity(0.9), 
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14 * scale),
          side: const BorderSide(color: Color(0xFFFFB800), width: 1.5),
        ),
      ),
      child: Stack(
        children: [
          Positioned(left: 12 * scale, top: 5 * scale, child: Text(level, style: TextStyle(color: const Color(0xFF322144), fontSize: 16 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.bold))),
          Positioned(left: 34 * scale, top: 28 * scale, child: Text(xp, style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 18 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.20))),
          
          // Background Bar Track
          Positioned(
            left: 11 * scale, top: 58 * scale, 
            child: Container(
              width: 154 * scale, height: 5 * scale, 
              decoration: ShapeDecoration(color: const Color(0xFFF1F1FA), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale))),
            ),
          ),
          // Fill Layer
          Positioned(
            left: 11 * scale, top: 58 * scale, 
            child: Container(
              width: (154 * progressRatio.clamp(0.0, 1.0)) * scale, height: 5 * scale, 
              decoration: ShapeDecoration(color: const Color(0xFF7DC579), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale))),
            ),
          ),
          Positioned(left: 105 * scale, top: 8 * scale, child: Text(xpNext, style: TextStyle(color: const Color(0xFF888888), fontSize: 9 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}