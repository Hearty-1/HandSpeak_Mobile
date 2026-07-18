import 'dart:ui'; // Required for ImageFilter (Glassmorphism)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; //[cite: 8]
import '/services/progress_service.dart'; //[cite: 8]
import 'alphabet/alphabet_interface.dart'; //[cite: 8]
import 'numbers/numbers_interface.dart';  //[cite: 8]
import '../profile/profile.dart';  //[cite: 8]
import '../home/home.dart';  //[cite: 8]
import '../leaderboard/leaderboard.dart'; //[cite: 8]

class SnedInterface2 extends StatelessWidget {
  const SnedInterface2({super.key}); //[cite: 8]

  @override
  Widget build(BuildContext context) {
    const double baseWidth = 393; //[cite: 8]
    const double baseHeight = 693;  //[cite: 8]
    const int targetXp = 1000; //[cite: 8]

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
        // --- 1. FETCH CATEGORY-SPECIFIC XP ---
        int alphabetXp = 0; //[cite: 8]
        int numbersXp = 0; //[cite: 8]
        int wordsXp = 0; //[cite: 8]
        int civicsXp = 0; //[cite: 8]

        if (snapshot.hasData && snapshot.data!.exists) { //[cite: 8]
          final data = snapshot.data!.data() as Map<String, dynamic>?; //[cite: 8]
          if (data != null) { //[cite: 8]
            alphabetXp = data['alphabetXp'] ?? 0; //[cite: 8]
            numbersXp = data['numbersXp'] ?? 0; //[cite: 8]
            wordsXp = data['wordsXp'] ?? 0; //[cite: 8]
            civicsXp = data['civicsXp'] ?? 0; //[cite: 8]
          }
        }

        // --- 2. DYNAMIC PROGRESSION LOCKS ---
        final bool isWordsLocked = (alphabetXp < targetXp) || (numbersXp < targetXp); //[cite: 8]
        final bool isCivicsLocked = isWordsLocked || (wordsXp < targetXp); //[cite: 8]

        // --- 3. DISPLAY XP (Capped at Target for the visual bars) ---
        int displayAlpXp = alphabetXp > targetXp ? targetXp : alphabetXp; //[cite: 8]
        int displayNumXp = numbersXp > targetXp ? targetXp : numbersXp; //[cite: 8]
        int displayWordsXp = wordsXp > targetXp ? targetXp : wordsXp; //[cite: 8]
        int displayCivicsXp = civicsXp > targetXp ? targetXp : civicsXp; //[cite: 8]

        return LayoutBuilder(
          builder: (context, constraints) { //[cite: 8]
            final double scale = constraints.maxWidth / baseWidth; //[cite: 8]

            return Scaffold(
              extendBodyBehindAppBar: true, // Allow glass app bar
              extendBody: true, // Allow glass bottom nav
              backgroundColor: const Color(0xFFFFF9E5), //[cite: 8]
              
              // --- GLASSMORPHISM APP BAR ---
              appBar: AppBar(
                backgroundColor: Colors.white.withOpacity(0.4), // Frosted
                elevation: 0, //[cite: 8]
                centerTitle: true,  //[cite: 8]
                iconTheme: const IconThemeData(color: Colors.black87),
                flexibleSpace: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                title: const Text(
                  "Modules", //[cite: 8]
                  style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800, letterSpacing: -0.5), //[cite: 8]
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0), //[cite: 8]
                    child: Image.asset("assets/pictures/image 66.png", width: 45), //[cite: 8]
                  ),
                ],
              ),
              
              // --- GLASSMORPHISM BOTTOM NAVIGATION BAR ---
              bottomNavigationBar: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.5), 
                          borderRadius: BorderRadius.circular(32), 
                          border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5), 
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly, //[cite: 8]
                          children: [
                            IconButton(
                              icon: const Icon(Icons.home, color: Colors.black54, size: 28), //[cite: 8]
                              onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const SnedInterafce1(userName: "Student")), (route) => false), //[cite: 8]
                            ),
                            IconButton(
                              icon: const Icon(Icons.auto_stories, color: Color(0xFFFFB800), size: 30), // Highlighted state
                              onPressed: () {},  //[cite: 8]
                            ),
                            IconButton(
                              icon: const Icon(Icons.emoji_events, color: Colors.black54, size: 28), //[cite: 8]
                              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LeaderboardScreen())), //[cite: 8]
                            ),
                            IconButton(
                              icon: const Icon(Icons.person, color: Colors.black54, size: 28), //[cite: 8]
                              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProfileScreen())), //[cite: 8]
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              body: Stack(
                children: [
                  // 1. Ambient Background Shapes
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
                        color: const Color(0xFF7DC579).withOpacity(0.2), // Matches module accents
                      ),
                    ),
                  ),

                  // 2. Main Content
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(), //[cite: 8]
                    child: Padding(
                      padding: EdgeInsets.only(top: 100 * scale, bottom: 120 * scale), // Padding for glass app bar and nav
                      child: SizedBox(
                        height: baseHeight * scale, //[cite: 8]
                        width: constraints.maxWidth, //[cite: 8]
                        child: Stack(
                          clipBehavior: Clip.none, //[cite: 8]
                          children: [
                            // --- MODULE: ALPHABETS ---
                            Positioned(
                              left: 7 * scale, top: 51 * scale, //[cite: 8]
                              child: GestureDetector(
                                onTap: () => Navigator.push( //[cite: 8]
                                  context, //[cite: 8]
                                  MaterialPageRoute( //[cite: 8]
                                    builder: (context) => AlphabetInterface( //[cite: 8]
                                      currentXp: displayAlpXp, //[cite: 8]
                                      targetXp: targetXp, //[cite: 8]
                                    ),
                                  ),
                                ),
                                child: Container(width: 171 * scale, height: 171 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/abc.png"), fit: BoxFit.cover))), //[cite: 8]
                              ),
                            ),
                            Positioned(
                              left: 27 * scale, top: 39 * scale, //[cite: 8]
                              child: GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AlphabetInterface(currentXp: displayAlpXp, targetXp: targetXp))), //[cite: 8]
                                child: Text('Alphabets', style: TextStyle(color: Colors.black, fontSize: 32 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.92)), //[cite: 8]
                              ),
                            ),
                            Positioned(
                              left: 12 * scale, top: 215 * scale,  //[cite: 8]
                              child: _buildProgressPanel(
                                scale: scale,  //[cite: 8]
                                title: "Progress",  //[cite: 8]
                                xp: "$displayAlpXp XP",  //[cite: 8]
                                xpNext: "${targetXp - displayAlpXp} to next", //[cite: 8]
                                progressRatio: displayAlpXp / targetXp, //[cite: 8]
                              ),
                            ),
                            Positioned(
                              left: 20 * scale, top: 250 * scale, 
                              child: _buildGlassIcon(scale) // Replaced star.png
                            ), 
                            
                            // --- MODULE: NUMBERS ---
                            Positioned(
                              left: 214 * scale, top: 77 * scale, //[cite: 8]
                              child: GestureDetector(
                                onTap: () => Navigator.push( //[cite: 8]
                                  context,  //[cite: 8]
                                  MaterialPageRoute( //[cite: 8]
                                    builder: (context) => NumbersInterface( //[cite: 8]
                                      currentXp: displayNumXp, //[cite: 8]
                                      targetXp: targetXp, //[cite: 8]
                                    ),
                                  ),
                                ),
                                child: Container(width: 165 * scale, height: 121 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/numbers.png"), fit: BoxFit.fill))), //[cite: 8]
                              ),
                            ),
                            Positioned(
                              left: 228 * scale, top: 37 * scale, //[cite: 8]
                              child: GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => NumbersInterface(currentXp: displayNumXp, targetXp: targetXp))), //[cite: 8]
                                child: Text('Numbers', style: TextStyle(color: Colors.black, fontSize: 32 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.92)), //[cite: 8]
                              ),
                            ),
                            Positioned(
                              left: 205 * scale, top: 215 * scale,  //[cite: 8]
                              child: _buildProgressPanel(
                                scale: scale,  //[cite: 8]
                                title: "Progress",  //[cite: 8]
                                xp: "$displayNumXp XP",  //[cite: 8]
                                xpNext: "${targetXp - displayNumXp} to next", //[cite: 8]
                                progressRatio: displayNumXp / targetXp, //[cite: 8]
                              ),
                            ),
                            Positioned(
                              left: 214 * scale, top: 250 * scale, 
                              child: _buildGlassIcon(scale) // Replaced star.png
                            ),
                            
                            // --- MODULE: WORDS / PHRASES (LOCKED/UNLOCKED) ---
                            Positioned(
                              left: 30 * scale, top: 386 * scale,  //[cite: 8]
                              child: Opacity(
                                opacity: isWordsLocked ? 0.40 : 1.0,  //[cite: 8]
                                child: Container(width: 144 * scale, height: 144 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/commons.png"), fit: BoxFit.cover))), //[cite: 8]
                              ),
                            ),
                            Positioned(
                              left: 18 * scale, top: 362 * scale,  //[cite: 8]
                              child: Opacity(
                                opacity: isWordsLocked ? 0.60 : 1.0, //[cite: 8]
                                child: Text('Words/ Phrases', textAlign: TextAlign.center, style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44)), //[cite: 8]
                              ),
                            ),
                            if (isWordsLocked) //[cite: 8]
                              Positioned(left: 55 * scale, top: 386 * scale, child: Container(width: 90 * scale, height: 119 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/locked.png"), fit: BoxFit.fill)))) //[cite: 8]
                            else //[cite: 8]
                              Positioned(
                                left: 55 * scale, top: 386 * scale, //[cite: 8]
                                child: GestureDetector(
                                  onTap: () { //[cite: 8]
                                    // Router pathway to words interface screen
                                  },
                                  child: SizedBox(width: 90 * scale, height: 119 * scale), //[cite: 8]
                                ),
                              ),
                            Positioned(
                              left: 13 * scale, top: 526 * scale,  //[cite: 8]
                              child: Opacity(
                                opacity: isWordsLocked ? 0.40 : 1.0,  //[cite: 8]
                                child: _buildProgressPanel(
                                  scale: scale,  //[cite: 8]
                                  title: "Progress",  //[cite: 8]
                                  xp: "$displayWordsXp XP",  //[cite: 8]
                                  xpNext: "${targetXp - displayWordsXp} to next", //[cite: 8]
                                  progressRatio: displayWordsXp / targetXp, //[cite: 8]
                                ),
                              ),
                            ),
                            Positioned(
                              left: 22 * scale, top: 561 * scale, 
                              child: Opacity(
                                opacity: isWordsLocked ? 0.40 : 1.0, //[cite: 8]
                                child: _buildGlassIcon(scale), // Replaced star.png
                              ),
                            ),
                            
                            // --- MODULE: CIVIC OBSERVANCES (LOCKED/UNLOCKED) ---
                            Positioned(
                              left: 217 * scale, top: 381 * scale,  //[cite: 8]
                              child: Opacity(
                                opacity: isCivicsLocked ? 0.40 : 1.0,  //[cite: 8]
                                child: Container(width: 154 * scale, height: 153 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/civic.png"), fit: BoxFit.cover))), //[cite: 8]
                              ),
                            ),
                            Positioned(
                              left: 218 * scale, top: 353 * scale,  //[cite: 8]
                              child: Opacity(
                                opacity: isCivicsLocked ? 0.60 : 1.0, //[cite: 8]
                                child: Text('Civic Observances', textAlign: TextAlign.center, style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44)), //[cite: 8]
                              ),
                            ),
                            if (isCivicsLocked) //[cite: 8]
                              Positioned(left: 253.50 * scale, top: 386 * scale, child: Container(width: 90 * scale, height: 119 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/locked.png"), fit: BoxFit.fill)))) //[cite: 8]
                            else //[cite: 8]
                              Positioned(
                                left: 253.50 * scale, top: 386 * scale, //[cite: 8]
                                child: GestureDetector(
                                  onTap: () { //[cite: 8]
                                    // Router pathway to civics interface screen
                                  },
                                  child: SizedBox(width: 90 * scale, height: 119 * scale), //[cite: 8]
                                ),
                              ),
                            Positioned(
                              left: 205 * scale, top: 526 * scale,  //[cite: 8]
                              child: Opacity(
                                opacity: isCivicsLocked ? 0.40 : 1.0,  //[cite: 8]
                                child: _buildProgressPanel(
                                  scale: scale,  //[cite: 8]
                                  title: "Progress",  //[cite: 8]
                                  xp: "$displayCivicsXp XP",  //[cite: 8]
                                  xpNext: "${targetXp - displayCivicsXp} to next", //[cite: 8]
                                  progressRatio: displayCivicsXp / targetXp, //[cite: 8]
                                ),
                              ),
                            ),
                            Positioned(
                              left: 214 * scale, top: 561 * scale, 
                              child: Opacity(
                                opacity: isCivicsLocked ? 0.40 : 1.0, //[cite: 8]
                                child: _buildGlassIcon(scale), // Replaced star.png
                              ),
                            ),
                          ],
                        ),
                      ),
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

  // Refactored Helper widget to render Glassmorphism progress status card
  Widget _buildProgressPanel({
    required double scale, 
    required String title, 
    required String xp, 
    required String xpNext,
    required double progressRatio,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16 * scale), 
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 178 * scale, height: 76 * scale, //[cite: 8]
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65), // Semi-transparent
            borderRadius: BorderRadius.circular(16 * scale), 
            border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5), // Subtle glass border
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
            ],
          ),
          child: Stack(
            children: [
              Positioned(left: 12 * scale, top: 5 * scale, child: Text(title, style: TextStyle(color: const Color(0xFF322144), fontSize: 16 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.bold))), //[cite: 8]
              Positioned(left: 36 * scale, top: 28 * scale, child: Text(xp, style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 18 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.20))), //[cite: 8]
              
              // Background Bar Track (Translucent)
              Positioned(
                left: 11 * scale, top: 58 * scale,  //[cite: 8]
                child: Container(
                  width: 154 * scale, height: 5 * scale,  //[cite: 8]
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.05), 
                    borderRadius: BorderRadius.circular(25 * scale), //[cite: 8]
                  ),
                ),
              ),
              // Fill Layer
              Positioned(
                left: 11 * scale, top: 58 * scale,  //[cite: 8]
                child: Container(
                  width: (154 * progressRatio.clamp(0.0, 1.0)) * scale, height: 5 * scale,  //[cite: 8]
                  decoration: BoxDecoration(
                    color: const Color(0xFF7DC579), //[cite: 8]
                    borderRadius: BorderRadius.circular(25 * scale), //[cite: 8]
                    boxShadow: [BoxShadow(color: const Color(0xFF7DC579).withOpacity(0.5), blurRadius: 4)], // Glow effect
                  ),
                ),
              ),
              Positioned(left: 105 * scale, top: 8 * scale, child: Text(xpNext, style: TextStyle(color: const Color(0xFF888888), fontSize: 9 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.w500))), //[cite: 8]
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget to render the waving hand icon in a glass circle (replacing stars)
  Widget _buildGlassIcon(double scale) {
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
      child: Icon(
        Icons.bolt_rounded, 
        color: const Color(0xFFFFB800),
        size: 16 * scale, 
      ),
    );
  }
}