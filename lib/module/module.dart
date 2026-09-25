import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/services/progress_service.dart'; 
import 'alphabet/alphabet_interface.dart'; 
import 'numbers/numbers_interface.dart';  
import 'phrases/phrase_interface.dart'; 
import 'civic/civic_interface.dart';
import '../profile/profile.dart';  
import '../home/home.dart';  
import '../leaderboard/arena.dart'; 
import '../home/notification_bell.dart';
import '../home/settings_screen.dart';

class SnedInterface2 extends StatelessWidget {
  const SnedInterface2({super.key}); 

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    const double baseWidth = 393; 
    const double baseHeight = 693;  
    const int targetXp = 1000; 

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(), 
      builder: (context, snapshot) { 
        int alphabetXp = 0; 
        int numbersXp = 0; 
        int wordsXp = 0; 
        int civicsXp = 0; 

        if (snapshot.hasData && snapshot.data!.exists) { 
          final data = snapshot.data!.data() as Map<String, dynamic>?; 
          if (data != null) { 
            alphabetXp = data['alphabetXp'] ?? 0; 
            numbersXp = data['numbersXp'] ?? 0; 
            wordsXp = data['phraseXp'] ?? data['wordsXp'] ?? 0; 
            civicsXp = data['civicsXp'] ?? 0; 

            if (data['progress'] != null) {
              Map<String, dynamic> progressMap = Map<String, dynamic>.from(data['progress']);
              int mappedAlphabetXp = 0;
              int mappedNumbersXp = 0;
              int mappedWordsXp = 0;
              int mappedCivicsXp = 0;

              progressMap.forEach((key, value) {
                int xpValue = (value as num).toInt();
                final lowerKey = key.toLowerCase();
                
                if (lowerKey.startsWith('alphabet')) mappedAlphabetXp += xpValue;
                if (lowerKey.startsWith('number')) mappedNumbersXp += xpValue;
                if (lowerKey.startsWith('phrase') || lowerKey.startsWith('word')) mappedWordsXp += xpValue;
                if (lowerKey.startsWith('civic')) mappedCivicsXp += xpValue;
              });

              if (mappedAlphabetXp > alphabetXp) alphabetXp = mappedAlphabetXp;
              if (mappedNumbersXp > numbersXp) numbersXp = mappedNumbersXp;
              if (mappedWordsXp > wordsXp) wordsXp = mappedWordsXp;
              if (mappedCivicsXp > civicsXp) civicsXp = mappedCivicsXp;
            }
          }
        }

        final bool isWordsLocked = alphabetXp < targetXp; 
        final bool isCivicsLocked = isWordsLocked || (wordsXp < targetXp); 

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
          backgroundColor: theme.scaffoldBackgroundColor, 
          
          drawer: Drawer(
            backgroundColor: theme.cardColor.withOpacity(0.95), 
            elevation: 0,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 60, bottom: 20, left: 20, right: 20), 
                  decoration: BoxDecoration(
                    color: theme.primaryColor, 
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset("assets/pictures/image 1.png", width: 60), 
                          const SizedBox(width: 10),
                          Image.asset("assets/pictures/image 66.png", width: 60), 
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Menu', 
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 10), 
                    children: [
                      ListTile(
                        leading: Icon(Icons.settings, color: theme.primaryColor), 
                        title: Text('Settings', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)), 
                        onTap: () {
                          Navigator.pop(context); 
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
                        }, 
                      ),
                      ListTile(
                        leading: Icon(Icons.help_outline, color: theme.primaryColor), 
                        title: Text('Help & Support', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)), 
                        onTap: () => Navigator.pop(context), 
                      ),
                      ListTile(
                        leading: Icon(Icons.info_outline, color: theme.primaryColor), 
                        title: Text('About Us', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)), 
                        onTap: () => Navigator.pop(context), 
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          appBar: AppBar(
            backgroundColor: theme.cardColor.withOpacity(0.4),
            elevation: 0,
            centerTitle: true,
            iconTheme: theme.iconTheme.copyWith(color: textColor),
            flexibleSpace: ClipRRect(
              clipBehavior: Clip.antiAlias,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(color: Colors.transparent),
              ),
            ),
            title: Text(
              "Modules", 
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700, letterSpacing: -0.5),
            ),
            actions: [
  const NotificationBell(),
  Padding(
    padding: const EdgeInsets.only(right: 16.0, left: 4.0), 
    child: Image.asset("assets/pictures/image 66.png", width: 45), 
  ),
],
                ),
  
              bottomNavigationBar: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    clipBehavior: Clip.antiAlias,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        height: 72,
                        decoration: BoxDecoration(
                          color: theme.cardColor.withOpacity(0.6), 
                          borderRadius: BorderRadius.circular(32), 
                          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0), 
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
                          children: [
                            IconButton(
                              icon: Icon(Icons.home, color: textColor.withOpacity(0.6), size: 28), 
                              onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const SnedInterafce1(userName: "Student")), (route) => false), 
                            ),
                            IconButton(
                              icon: Icon(Icons.auto_stories, color: theme.primaryColor, size: 30), 
                              onPressed: () {},  
                            ),
                            IconButton(
                              icon: Icon(Icons.sports_esports, color: textColor.withOpacity(0.6), size: 28), 
                              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LeaderboardScreen())), 
                            ),
                            IconButton(
                              icon: Icon(Icons.person, color: textColor.withOpacity(0.6), size: 28), 
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
                  Positioned(
                    top: -50,
                    left: -50,
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.primaryColor.withOpacity(0.25),
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
                        color: theme.colorScheme.secondary.withOpacity(0.2), 
                      ),
                    ),
                  ),

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
                                child: Text('Alphabets', style: TextStyle(color: textColor, fontSize: 32 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.92)), 
                              ),
                            ),
                            Positioned(
                              left: 12 * scale, top: 215 * scale,  
                              child: _buildProgressPanel(
                                context: context,
                                scale: scale,  
                                title: "Progress",  
                                xp: "$displayAlpXp XP",  
                                xpNext: "${targetXp - displayAlpXp} to next", 
                                progressRatio: displayAlpXp / targetXp, 
                              ),
                            ),
                            Positioned(
                              left: 20 * scale, top: 250 * scale, 
                              child: _buildGlassIcon(context, scale)
                            ), 
                            
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
                                child: Text('Numbers', style: TextStyle(color: textColor, fontSize: 32 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.92)), 
                              ),
                            ),
                            Positioned(
                              left: 205 * scale, top: 215 * scale,  
                              child: _buildProgressPanel(
                                context: context,
                                scale: scale,  
                                title: "Progress",  
                                xp: "$displayNumXp XP",  
                                xpNext: "${targetXp - displayNumXp} to next", 
                                progressRatio: displayNumXp / targetXp, 
                              ),
                            ),
                            Positioned(
                              left: 214 * scale, top: 250 * scale, 
                              child: _buildGlassIcon(context, scale)
                            ),
                            
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
                                    width: 150 * scale, 
                                    height: 150 * scale, 
                                    decoration: const BoxDecoration(
                                      image: DecorationImage(
                                        image: AssetImage("assets/pictures/words.png"), 
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
                                      color: textColor, 
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
                                  context: context,
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
                                child: _buildGlassIcon(context, scale),
                              ),
                            ),
                            
                            Positioned(
                              left: 200 * scale, top: 360 * scale,  
                              child: GestureDetector(
                                onTap: isCivicsLocked 
                                  ? null 
                                  : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CivicInterface(
                                          currentXp: displayCivicsXp,
                                          targetXp: targetXp,
                                        ),
                                      ),
                                    ),
                                child: Opacity(
                                  opacity: isCivicsLocked ? 0.40 : 1.0,  
                                  child: Container(
                                    width: 180 * scale, 
                                    height: 180 * scale, 
                                    decoration: const BoxDecoration(
                                      image: DecorationImage(
                                        image: AssetImage("assets/pictures/civic.png"), 
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ), 
                                ),
                              ),
                            ),
                            Positioned(
                              left: 218 * scale, top: 353 * scale,  
                              child: GestureDetector(
                                onTap: isCivicsLocked 
                                  ? null 
                                  : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CivicInterface(
                                          currentXp: displayCivicsXp,
                                          targetXp: targetXp,
                                        ),
                                      ),
                                    ),
                                child: Opacity(
                                  opacity: isCivicsLocked ? 0.60 : 1.0, 
                                  child: Text(
                                    'Civic Observances', 
                                    textAlign: TextAlign.center, 
                                    style: TextStyle(
                                      color: textColor, 
                                      fontSize: 24 * scale, 
                                      fontFamily: 'Inter', 
                                      fontWeight: FontWeight.w800, 
                                      letterSpacing: -1.44,
                                    ),
                                  ), 
                                ),
                              ),
                            ),
                            if (isCivicsLocked) 
                              Positioned(
                                left: 253.50 * scale, top: 386 * scale, 
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
                              ) 
                            else 
                              Positioned(
                                left: 253.50 * scale, top: 386 * scale, 
                                child: GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CivicInterface(
                                        currentXp: displayCivicsXp,
                                        targetXp: targetXp,
                                      ),
                                    ),
                                  ),
                                  child: SizedBox(width: 90 * scale, height: 119 * scale), 
                                ),
                              ),
                            Positioned(
                              left: 205 * scale, top: 526 * scale,  
                              child: Opacity(
                                opacity: isCivicsLocked ? 0.40 : 1.0,  
                                child: _buildProgressPanel(
                                  context: context,
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
                                child: _buildGlassIcon(context, scale), 
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

  Widget _buildProgressPanel({
    required BuildContext context,
    required double scale, 
    required String title, 
    required String xp, 
    required String xpNext,
    required double progressRatio,
  }) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16 * scale), 
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 178 * scale, height: 76 * scale, 
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.7), 
            borderRadius: BorderRadius.circular(16 * scale), 
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0), 
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
            ],
          ),
          child: Stack(
            children: [
              Positioned(left: 12 * scale, top: 5 * scale, child: Text(title, style: TextStyle(color: textColor, fontSize: 16 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.bold))), 
              Positioned(left: 36 * scale, top: 28 * scale, child: Text(xp, style: TextStyle(color: theme.primaryColor, fontSize: 18 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.20))), 
              
              Positioned(
                left: 11 * scale, top: 58 * scale,  
                child: Container(
                  width: 154 * scale, height: 5 * scale,  
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withOpacity(0.2), 
                    borderRadius: BorderRadius.circular(25 * scale), 
                  ),
                ),
              ),
              Positioned(
                left: 11 * scale, top: 58 * scale,  
                child: Container(
                  width: (154 * progressRatio.clamp(0.0, 1.0)) * scale, height: 5 * scale,  
                  decoration: BoxDecoration(
                    color: theme.primaryColor, 
                    borderRadius: BorderRadius.circular(25 * scale), 
                    boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.5), blurRadius: 4)], 
                  ),
                ),
              ),
              Positioned(left: 105 * scale, top: 8 * scale, child: Text(xpNext, style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 9 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.w500))), 
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassIcon(BuildContext context, double scale) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(4 * scale),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.85),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withOpacity(0.3), 
            blurRadius: 8, 
            spreadRadius: 1
          )
        ],
      ),
      child: Icon(
        Icons.bolt_rounded, 
        color: theme.primaryColor,
        size: 16 * scale, 
      ),
    );
  }
}