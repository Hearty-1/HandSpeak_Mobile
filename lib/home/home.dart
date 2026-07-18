import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/module/alphabet/alphabet_interface.dart';
import 'package:flutter_application_1/module/numbers/numbers_interface.dart';
import '../services/progress_service.dart'; 
import '../module/module.dart'; 
import '../profile/profile.dart';
import '../leaderboard/leaderboard.dart'; 
import '../database/database_seeder.dart';

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
      home: const SnedInterafce1(userName: "Student"),
    );
  }
}

class SnedInterafce1 extends StatelessWidget {
  final String userName;

  const SnedInterafce1({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double scale = screenWidth / 393 > 1.2 ? 1.2 : screenWidth / 393; 

    final DateTime now = DateTime.now();
    final todayStr = now.toIso8601String().split('T')[0];

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      
      // --- SIDE MENU (DRAWER) ---
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 60, bottom: 20, left: 20, right: 20),
              decoration: const BoxDecoration(
                color: Color(0xFFFFB800),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- IMAGE 1.PNG BESIDE THE LOGO ONLY INSIDE THE MENU ---
                  Row(
                    children: [
                      Image.asset("assets/pictures/image 1.png", width: 60),
                      const SizedBox(width: 10),
                      Image.asset("assets/pictures/image 66.png", width: 60),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Menu',
                    style: TextStyle(
                      color: Colors.black,
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
                    leading: const Icon(Icons.settings, color: Color(0xFFFFB800)),
                    title: const Text('Settings', style: TextStyle(color: Color(0xFF222222), fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context); // Close the drawer
                      // Add your settings logic/routing here
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.help_outline, color: Color(0xFFFFB800)),
                    title: const Text('Help & Support', style: TextStyle(color: Color(0xFF222222), fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context); // Close the drawer
                      // Add your help logic/routing here
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline, color: Color(0xFFFFB800)),
                    title: const Text('About Us', style: TextStyle(color: Color(0xFF222222), fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context); // Close the drawer
                      // Add your about logic/routing here
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // --- APP BAR ---
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFB800),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          "Home",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            // --- REVERTED TO ONLY SHOWING LOGO IN APPBAR ---
            child: Image.asset("assets/pictures/image 66.png", width: 45),
          ),
        ],
      ),
      
      // --- DEV TOOL SEED BUTTON ---
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 90.0), 
        child: ElevatedButton.icon(
          onPressed: () => DatabaseSeeder.seedActivities(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red, 
          ),
          icon: const Icon(Icons.cloud_upload, color: Colors.white),
          label: const Text(
            "DEV: SEED DATABASE", 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    
      // --- 4-TAB BOTTOM NAVIGATION BAR ---
      bottomNavigationBar: SafeArea(
        child: Container(
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
              IconButton(icon: const Icon(Icons.home, color: Colors.black, size: 28), onPressed: () {}),
              IconButton(
                icon: const Icon(Icons.auto_stories, color: Colors.grey, size: 28), 
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SnedInterface2())),
              ),
              IconButton(
                icon: const Icon(Icons.emoji_events, color: Colors.grey, size: 28), 
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LeaderboardScreen())),
              ),
              IconButton(
                icon: const Icon(Icons.person, color: Colors.grey, size: 28), 
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen())),
              ),
            ],
          ),
        ),
      ),

      body: StreamBuilder<DocumentSnapshot>(
        stream: ProgressService().getUserProgressStream(),
        builder: (context, userSnapshot) {
          String studentName = userName;
          int streak = 0;
          int totalXp = 0;
          int stars = 0;
          bool isChallengeCompleted = false;

          if (userSnapshot.hasData && userSnapshot.data!.exists) {
            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
            if (userData != null) {
              studentName = userData['name'] ?? userData['displayName'] ?? userName;
              streak = userData['streak'] ?? 0;
              totalXp = userData['xp'] ?? 0;
              stars = userData['stars'] ?? (totalXp ~/ 1000); 
              isChallengeCompleted = userData['lastCompletedChallengeDate'] == todayStr;
            }
          }

          int targetXp = 1000;
          int currentLevel = (totalXp ~/ targetXp) + 1;
          int xpInLevel = totalXp % targetXp;
          double progressRatio = xpInLevel / targetXp;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 15 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                
                // --- TOP MOTIVATION STATS BAR ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen())),
                      child: CircleAvatar(
                        radius: 22 * scale,
                        backgroundColor: const Color(0xFFFFEFA7),
                        child: Icon(Icons.person, color: const Color(0xFFFFB800), size: 28 * scale),
                      ),
                    ),
                    Row(
                      children: [
                        _buildStatBadge(Icons.local_fire_department_rounded, '$streak', const Color(0xFFFF8227), scale),
                        SizedBox(width: 8 * scale),
                        _buildStatBadge(Icons.bolt_rounded, '$totalXp', const Color(0xFF2196F3), scale),
                        SizedBox(width: 8 * scale),
                        _buildStatBadge(Icons.star_rounded, '$stars', const Color(0xFFFFB800), scale),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 25 * scale),

                // --- "MABUHAY" HERO CARD ---
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(22 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB800),
                    borderRadius: BorderRadius.circular(24 * scale),
                    boxShadow: [BoxShadow(color: const Color(0xFFFFB800).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mabuhay,',
                              style: TextStyle(color: const Color(0xFF222222), fontSize: 18 * scale, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                            ),
                            Text(
                              '$studentName!',
                              style: TextStyle(color: const Color(0xFF222222), fontSize: 32 * scale, fontWeight: FontWeight.w900, height: 1.0, letterSpacing: -1.0),
                            ),
                            SizedBox(height: 12 * scale),
                            Text(
                              'Level $currentLevel',
                              style: TextStyle(color: Colors.white, fontSize: 16 * scale, fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: 4 * scale),
                            
                            Container(
                              height: 26 * scale,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(13 * scale),
                              ),
                              child: Stack(
                                children: [
                                  Container(
                                    width: (MediaQuery.of(context).size.width - 150) * progressRatio.clamp(0.0, 1.0), 
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(13 * scale),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 12 * scale),
                                      child: Text(
                                        '$xpInLevel XP',
                                        style: TextStyle(
                                          color: const Color(0xFFBA8E23), 
                                          fontWeight: FontWeight.w900, 
                                          fontSize: 13 * scale,
                                        ),
                                      ),
                                    ),
                                  )
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      SizedBox(width: 15 * scale),
                      Image.asset(
                        "assets/pictures/star.png", 
                        width: 80 * scale, 
                        height: 80 * scale,
                        errorBuilder: (context, error, stackTrace) => Icon(Icons.star_rounded, color: Colors.white, size: 80 * scale),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 25 * scale),

                // --- DAILY CHALLENGES BANNER ---
                GestureDetector(
                  onTap: () {
                    Navigator.push( 
                      context,
                      MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 16 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800),
                      borderRadius: BorderRadius.circular(20 * scale),
                    ),
                    child: Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(Icons.notifications_active_rounded, color: const Color(0xFF222222), size: 34 * scale),
                            if (!isChallengeCompleted)
                              Positioned(
                                top: -2, right: -2,
                                child: Container(
                                  width: 12 * scale, height: 12 * scale,
                                  decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFFFB800), width: 2)),
                                ),
                              )
                          ],
                        ),
                        SizedBox(width: 16 * scale),
                        Text(
                          'Daily\nChallenges!',
                          style: TextStyle(color: const Color(0xFF222222), fontSize: 18 * scale, fontWeight: FontWeight.w900, height: 1.1),
                        ),
                        const Spacer(),
                        Icon(Icons.arrow_forward_rounded, color: const Color(0xFF222222), size: 28 * scale),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 30 * scale), 

                // --- CONTINUE LEARNING ---
                Text(
                  'Continue Learning', 
                  style: TextStyle(color: const Color(0xFF222222), fontSize: 18 * scale, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16 * scale),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildCategoryCard(
                      context: context, 
                      title: 'Alphabet', 
                      icon: Icons.abc_rounded, 
                      scale: scale, 
                      onTap: () {
                        Navigator.push( 
                          context, 
                          MaterialPageRoute(builder: (context) => const AlphabetInterface()), 
                        );
                      },
                    ),
                    _buildCategoryCard(
                      context: context, 
                      title: 'Numbers', 
                      icon: Icons.onetwothree_rounded, 
                      scale: scale, 
                      onTap: () {
                        Navigator.push( 
                          context, 
                          MaterialPageRoute(builder: (context) => const NumbersInterface()), 
                        );
                      },
                    ),
                  ],
                ),
                SizedBox(height: 20 * scale),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatBadge(IconData icon, String value, Color color, double scale) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20 * scale),
        border: Border.all(color: const Color(0xFFE5E5E5), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18 * scale),
          SizedBox(width: 4 * scale),
          Text(
            value,
            style: TextStyle(
              color: const Color(0xFF222222),
              fontSize: 14 * scale,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({required BuildContext context, required String title, required IconData icon, required double scale, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160 * scale,
        padding: EdgeInsets.all(20 * scale),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20 * scale),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 15, offset: Offset(0, 5))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(12 * scale), 
              decoration: const BoxDecoration(color: Color(0xFFFFF9E5), shape: BoxShape.circle), 
              child: Icon(icon, color: const Color(0xFFFFB800), size: 36 * scale),
            ),
            SizedBox(height: 12 * scale),
            Text(title, style: TextStyle(color: const Color(0xFF222222), fontSize: 16 * scale, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}