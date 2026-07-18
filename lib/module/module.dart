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
    // Adjusted height since we removed the search bar gap
    const double baseHeight = 693; 
    const int targetXp = 1000;

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(),
      builder: (context, snapshot) {
        // --- 1. FETCH CATEGORY-SPECIFIC XP ---
        int alphabetXp = 0;
        int numbersXp = 0;
        int wordsXp = 0;
        int civicsXp = 0;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            alphabetXp = data['alphabetXp'] ?? 0;
            numbersXp = data['numbersXp'] ?? 0;
            wordsXp = data['wordsXp'] ?? 0;
            civicsXp = data['civicsXp'] ?? 0;
          }
        }

        // --- 2. DYNAMIC PROGRESSION LOCKS ---
        final bool isWordsLocked = (alphabetXp < targetXp) || (numbersXp < targetXp);
        final bool isCivicsLocked = isWordsLocked || (wordsXp < targetXp);

        // --- 3. DISPLAY XP (Capped at Target for the visual bars) ---
        int displayAlpXp = alphabetXp > targetXp ? targetXp : alphabetXp;
        int displayNumXp = numbersXp > targetXp ? targetXp : numbersXp;
        int displayWordsXp = wordsXp > targetXp ? targetXp : wordsXp;
        int displayCivicsXp = civicsXp > targetXp ? targetXp : civicsXp;

        return LayoutBuilder(
          builder: (context, constraints) {
            final double scale = constraints.maxWidth / baseWidth;

            return Scaffold(
              backgroundColor: const Color(0xFFFFF9E5),
              appBar: AppBar(
                backgroundColor: const Color(0xFFFFB800),
                elevation: 0,
                centerTitle: true, // ADD THIS LINE 
                title: const Text(
                  "Modules",
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Image.asset("assets/pictures/image 66.png", width: 45),
                  ),
                ],
              ),
              body: Column(
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
                            // --- MODULE: ALPHABETS ---
                            Positioned(
                              left: 7 * scale, top: 51 * scale,
                              child: GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AlphabetInterface(
                                      currentXp: displayAlpXp,
                                      targetXp: targetXp,
                                    ),
                                  ),
                                ),
                                child: Container(width: 171 * scale, height: 171 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/abc.png"), fit: BoxFit.cover))),
                              ),
                            ),
                            Positioned(
                              left: 27 * scale, top: 39 * scale,
                              child: GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AlphabetInterface(currentXp: displayAlpXp, targetXp: targetXp))),
                                child: Text('Alphabets', style: TextStyle(color: Colors.black, fontSize: 32 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.92)),
                              ),
                            ),
                            Positioned(
                              left: 12 * scale, top: 215 * scale, 
                              child: _buildProgressPanel(
                                scale: scale, 
                                title: "Progress", 
                                xp: "$displayAlpXp XP", 
                                xpNext: "${targetXp - displayAlpXp} to next",
                                progressRatio: displayAlpXp / targetXp,
                              ),
                            ),
                            Positioned(left: 22 * scale, top: 250 * scale, child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, e, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale))),
                            
                            // --- MODULE: NUMBERS ---
                            Positioned(
                              left: 214 * scale, top: 77 * scale,
                              child: GestureDetector(
                                onTap: () => Navigator.push(
                                  context, 
                                  MaterialPageRoute(
                                    builder: (context) => NumbersInterface(
                                      currentXp: displayNumXp,
                                      targetXp: targetXp,
                                    ),
                                  ),
                                ),
                                child: Container(width: 165 * scale, height: 121 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/numbers.png"), fit: BoxFit.fill))),
                              ),
                            ),
                            Positioned(
                              left: 228 * scale, top: 37 * scale,
                              child: GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => NumbersInterface(currentXp: displayNumXp, targetXp: targetXp))),
                                child: Text('Numbers', style: TextStyle(color: Colors.black, fontSize: 32 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.92)),
                              ),
                            ),
                            Positioned(
                              left: 205 * scale, top: 215 * scale, 
                              child: _buildProgressPanel(
                                scale: scale, 
                                title: "Progress", 
                                xp: "$displayNumXp XP", 
                                xpNext: "${targetXp - displayNumXp} to next",
                                progressRatio: displayNumXp / targetXp,
                              ),
                            ),
                            Positioned(left: 218 * scale, top: 249 * scale, child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, e, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale))),
                            
                            // --- MODULE: WORDS / PHRASES (LOCKED/UNLOCKED) ---
                            Positioned(
                              left: 30 * scale, top: 386 * scale, 
                              child: Opacity(
                                opacity: isWordsLocked ? 0.40 : 1.0, 
                                child: Container(width: 144 * scale, height: 144 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/commons.png"), fit: BoxFit.cover))),
                              ),
                            ),
                            Positioned(
                              left: 18 * scale, top: 362 * scale, 
                              child: Opacity(
                                opacity: isWordsLocked ? 0.60 : 1.0,
                                child: Text('Words/ Phrases', textAlign: TextAlign.center, style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44)),
                              ),
                            ),
                            if (isWordsLocked)
                              Positioned(left: 55 * scale, top: 386 * scale, child: Container(width: 90 * scale, height: 119 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/locked.png"), fit: BoxFit.fill))))
                            else
                              Positioned(
                                left: 55 * scale, top: 386 * scale,
                                child: GestureDetector(
                                  onTap: () {
                                    // Router pathway to words interface screen
                                  },
                                  child: SizedBox(width: 90 * scale, height: 119 * scale),
                                ),
                              ),
                            Positioned(
                              left: 13 * scale, top: 526 * scale, 
                              child: Opacity(
                                opacity: isWordsLocked ? 0.40 : 1.0, 
                                child: _buildProgressPanel(
                                  scale: scale, 
                                  title: "Progress", 
                                  xp: "$displayWordsXp XP", 
                                  xpNext: "${targetXp - displayWordsXp} to next",
                                  progressRatio: displayWordsXp / targetXp,
                                ),
                              ),
                            ),
                            Positioned(left: 24 * scale, top: 561 * scale, child: Opacity(opacity: isWordsLocked ? 0.40 : 1.0, child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, e, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale)))),
                            
                            // --- MODULE: CIVIC OBSERVANCES (LOCKED/UNLOCKED) ---
                            Positioned(
                              left: 217 * scale, top: 381 * scale, 
                              child: Opacity(
                                opacity: isCivicsLocked ? 0.40 : 1.0, 
                                child: Container(width: 154 * scale, height: 153 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/civic.png"), fit: BoxFit.cover))),
                              ),
                            ),
                            Positioned(
                              left: 218 * scale, top: 353 * scale, 
                              child: Opacity(
                                opacity: isCivicsLocked ? 0.60 : 1.0,
                                child: Text('Civic Observances', textAlign: TextAlign.center, style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44)),
                              ),
                            ),
                            if (isCivicsLocked)
                              Positioned(left: 253.50 * scale, top: 386 * scale, child: Container(width: 90 * scale, height: 119 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/locked.png"), fit: BoxFit.fill))))
                            else
                              Positioned(
                                left: 253.50 * scale, top: 386 * scale,
                                child: GestureDetector(
                                  onTap: () {
                                    // Router pathway to civics interface screen
                                  },
                                  child: SizedBox(width: 90 * scale, height: 119 * scale),
                                ),
                              ),
                            Positioned(
                              left: 205 * scale, top: 526 * scale, 
                              child: Opacity(
                                opacity: isCivicsLocked ? 0.40 : 1.0, 
                                child: _buildProgressPanel(
                                  scale: scale, 
                                  title: "Progress", 
                                  xp: "$displayCivicsXp XP", 
                                  xpNext: "${targetXp - displayCivicsXp} to next",
                                  progressRatio: displayCivicsXp / targetXp,
                                ),
                              ),
                            ),
                            Positioned(left: 216 * scale, top: 561 * scale, child: Opacity(opacity: isCivicsLocked ? 0.40 : 1.0, child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, e, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale)))),
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

  // Helper widget to render progress status card
  Widget _buildProgressPanel({
    required double scale, 
    required String title, 
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
          Positioned(left: 12 * scale, top: 5 * scale, child: Text(title, style: TextStyle(color: const Color(0xFF322144), fontSize: 16 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.bold))),
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