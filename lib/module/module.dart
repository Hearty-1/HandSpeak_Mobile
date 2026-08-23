import 'dart:ui'; // Required for ImageFilter (Glassmorphism)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import '/services/progress_service.dart'; 
import 'alphabet/alphabet_interface.dart'; 
import 'numbers/numbers_interface.dart';  
import 'phrases/phrase_interface.dart'; 
import '../profile/profile.dart';  
import '../home/home.dart';  
import '../leaderboard/leaderboard.dart'; 

class SnedInterface2 extends StatelessWidget {
  const SnedInterface2({super.key}); 

  @override
  Widget build(BuildContext context) {
    const double baseWidth = 393; 
    const double baseHeight = 693;  
    const int targetXp = 1000; 

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
        // Unlocks Words/Phrases as soon as Alphabet reaches 1000 XP
        final bool isWordsLocked = alphabetXp < targetXp; 
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
              extendBodyBehindAppBar: true, 
              extendBody: true, 
              backgroundColor: const Color(0xFFFFF9E5), 
              
              // --- GLASSMORPHISM APP BAR ---
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
                  "Modules", 
                  style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800, letterSpacing: -0.5), 
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0), 
                    child: Image.asset("assets/pictures/image 66.png", width: 45), 
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
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
                          children: [
                            IconButton(
                              icon: const Icon(Icons.home, color: Colors.black54, size: 28), 
                              onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const SnedInterafce1(userName: "Student")), (route) => false), 
                            ),
                            IconButton(
                              icon: const Icon(Icons.auto_stories, color: Color(0xFFFFB800), size: 30), 
                              onPressed: () {},  
                            ),
                            IconButton(
                              icon: const Icon(Icons.emoji_events, color: Colors.black54, size: 28), 
                              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LeaderboardScreen())), 
                            ),
                            IconButton(
                              icon: const Icon(Icons.person, color: Colors.black54, size: 28), 
                              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProfileScreen())), 
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
                        color: const Color(0xFF7DC579).withOpacity(0.2), 
                      ),
                    ),
                  ),

                  // 2. Main Content
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(), 
                    child: Padding(
                      padding: EdgeInsets.only(top: 100 * scale, bottom: 120 * scale), 
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
                            Positioned(
                              left: 20 * scale, top: 250 * scale, 
                              child: _buildGlassIcon(scale)
                            ), 
                            
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
                            Positioned(
                              left: 214 * scale, top: 250 * scale, 
                              child: _buildGlassIcon(scale)
                            ),
                            
                            // --- MODULE: WORDS / PHRASES (UNLOCKED AT 1000 ALPHABET XP) ---
                            Positioned(
                              left: 30 * scale, top: 386 * scale,  
                              child: GestureDetector(
                                onTap: isWordsLocked 
                                  ? null 
                                  : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PhraseInterface(
                                          currentXp: displayWordsXp,
                                          targetXp: targetXp,
                                        ),
                                      ),
                                    ),
                                child: Opacity(
                                  opacity: isWordsLocked ? 0.40 : 1.0,  
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
                            ),
                            Positioned(
                              left: 18 * scale, top: 362 * scale,  
                              child: GestureDetector(
                                onTap: isWordsLocked 
                                  ? null 
                                  : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PhraseInterface(
                                          currentXp: displayWordsXp,
                                          targetXp: targetXp,
                                        ),
                                      ),
                                    ),
                                child: Opacity(
                                  opacity: isWordsLocked ? 0.60 : 1.0, 
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
                              ),
                            ),
                            if (isWordsLocked) 
                              Positioned(
                                left: 55 * scale, top: 386 * scale, 
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
                            Positioned(
                              left: 22 * scale, top: 561 * scale, 
                              child: Opacity(
                                opacity: isWordsLocked ? 0.40 : 1.0, 
                                child: _buildGlassIcon(scale),
                              ),
                            ),
                            
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
                            Positioned(
                              left: 214 * scale, top: 561 * scale, 
                              child: Opacity(
                                opacity: isCivicsLocked ? 0.40 : 1.0, 
                                child: _buildGlassIcon(scale), 
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
          width: 178 * scale, height: 76 * scale, 
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65), 
            borderRadius: BorderRadius.circular(16 * scale), 
            border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5), 
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
            ],
          ),
          child: Stack(
            children: [
              Positioned(left: 12 * scale, top: 5 * scale, child: Text(title, style: TextStyle(color: const Color(0xFF322144), fontSize: 16 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.bold))), 
              Positioned(left: 36 * scale, top: 28 * scale, child: Text(xp, style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 18 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.20))), 
              
              // Background Bar Track
              Positioned(
                left: 11 * scale, top: 58 * scale,  
                child: Container(
                  width: 154 * scale, height: 5 * scale,  
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.05), 
                    borderRadius: BorderRadius.circular(25 * scale), 
                  ),
                ),
              ),
              // Fill Layer
              Positioned(
                left: 11 * scale, top: 58 * scale,  
                child: Container(
                  width: (154 * progressRatio.clamp(0.0, 1.0)) * scale, height: 5 * scale,  
                  decoration: BoxDecoration(
                    color: const Color(0xFF7DC579), 
                    borderRadius: BorderRadius.circular(25 * scale), 
                    boxShadow: [BoxShadow(color: const Color(0xFF7DC579).withOpacity(0.5), blurRadius: 4)], 
                  ),
                ),
              ),
              Positioned(left: 105 * scale, top: 8 * scale, child: Text(xpNext, style: TextStyle(color: const Color(0xFF888888), fontSize: 9 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.w500))), 
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget to render glass icon
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