import 'dart:ui'; 
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:flutter_application_1/module/alphabet/alphabet_interface.dart'; 
import 'package:flutter_application_1/module/numbers/numbers_interface.dart'; 
import '../services/progress_service.dart'; 
import '../module/module.dart'; 
import '../profile/profile.dart'; 
import '../leaderboard/arena.dart'; 
import '../home/settings_screen.dart';
import '../home/notifications.dart';

void main() {
  runApp(const FigmaToCodeApp()); 
}

class FigmaToCodeApp extends StatelessWidget {
  const FigmaToCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, 
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFFFF9E5), 
      ),
      home: const SnedInterafce1(userName: "Student"), 
    );
  }
}

class SnedInterafce1 extends StatelessWidget {
  final String userName; 

  const SnedInterafce1({super.key, required this.userName}); 

  Widget _buildAvatarImage(String? avatarData, double scale, {double size = 48}) {
    if (avatarData == null || avatarData.isEmpty) {
      return Icon(Icons.person, color: const Color(0xFFFFB800), size: 26 * scale);
    }
    
    if (avatarData.startsWith('data:image')) {
      try {
        final String base64String = avatarData.split(',').last;
        final Uint8List bytes = base64Decode(base64String);
        return Image.memory(bytes, width: size * scale, height: size * scale, fit: BoxFit.cover);
      } catch (e) {
        return Icon(Icons.broken_image_rounded, color: Colors.grey, size: 26 * scale);
      }
    } else {
      return Image.network(
        avatarData,
        width: size * scale,
        height: size * scale,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(Icons.person, color: const Color(0xFFFFB800), size: 26 * scale),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width; 
    final double scale = screenWidth / 393 > 1.2 ? 1.2 : screenWidth / 393; 

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true, 
      extendBody: true, 
      backgroundColor: const Color(0xFFFFF9E5), 
      
      // --- SIDE MENU (DRAWER) ---
      drawer: Drawer(
        backgroundColor: Colors.white.withOpacity(0.9), 
        elevation: 0,
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
                    title: const Text('Settings', style: TextStyle(color: Color(0xFF222222), fontWeight: FontWeight.w600)), 
                    onTap: () {
                      Navigator.pop(context); 
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
                    }, 
                  ),
                  ListTile(
                    leading: const Icon(Icons.help_outline, color: Color(0xFFFFB800)), 
                    title: const Text('Help & Support', style: TextStyle(color: Color(0xFF222222), fontWeight: FontWeight.w600)), 
                    onTap: () => Navigator.pop(context), 
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline, color: Color(0xFFFFB800)), 
                    title: const Text('About Us', style: TextStyle(color: Color(0xFF222222), fontWeight: FontWeight.w600)), 
                    onTap: () => Navigator.pop(context), 
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

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
          "Home", 
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0), 
            child: Image.asset("assets/pictures/image 66.png", width: 45), 
          ),
        ],
      ),
      
      // --- GLASSMORPHISM 4-TAB BOTTOM NAVIGATION BAR ---
      bottomNavigationBar: SafeArea(
  child: Container(
    width: double.infinity,
    height: 74,
    margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.45),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withOpacity(0.65),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08132C4A),
                blurRadius: 20,
                offset: Offset(0, 8),
              )
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.home_rounded, color: Colors.black45, size: 28),
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const SnedInterafce1(userName: "Student")),
                    (route) => false,
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.auto_stories_rounded, color: Colors.black45, size: 28),
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const SnedInterface2()),
                ),
              ),
              // Highlighted Arena Icon
              IconButton(
                icon: const Icon(Icons.sports_esports_rounded, color: Colors.black54, size: 28), 
                onPressed: () => Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
                ), 
              ),
              IconButton(
                icon: const Icon(Icons.person_rounded, color: Colors.black45, size: 28),
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
),

      // --- BODY WITH AMBIENT BACKGROUND ---
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
                color: const Color(0xFFFFB800).withOpacity(0.3),
              ),
            ),
          ),
          Positioned(
            top: 300,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF8227).withOpacity(0.15),
              ),
            ),
          ),

          StreamBuilder<DocumentSnapshot>(
            stream: ProgressService().getUserProgressStream(), 
            builder: (context, userSnapshot) {
              String studentName = userName; 
              int streak = 0; 
              int totalXp = 0; 
              int stars = 0; 
              String? avatarUrl; 
              bool hasUnreadNotifications = false;

              if (userSnapshot.hasData && userSnapshot.data!.exists) { 
                final userData = userSnapshot.data!.data() as Map<String, dynamic>?; 
                if (userData != null) {
                  studentName = userData['name'] ?? userData['displayName'] ?? userName; 
                  streak = userData['streak'] ?? 0; 
                  totalXp = userData['xp'] ?? 0; 
                  stars = userData['stars'] ?? (totalXp ~/ 1000);  
                  avatarUrl = userData['avatar'] ?? userData['photoURL']; 

                  // Check if there are any unread notifications
                  final List<dynamic> rawNotifications = userData['notifications'] ?? [];
                  hasUnreadNotifications = rawNotifications.any(
                    (n) => (n is Map) && (n['isRead'] == false),
                  );
                }
              }

              int targetXp = 1000; 
              int currentLevel = (totalXp ~/ targetXp) + 1; 
              int xpInLevel = totalXp % targetXp; 
              double progressRatio = xpInLevel / targetXp; 

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(), 
                padding: EdgeInsets.only(
                  left: 24 * scale, 
                  right: 24 * scale, 
                  top: 110 * scale, 
                  bottom: 120 * scale, 
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    
                    // --- TOP MOTIVATION STATS BAR ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen())), 
                          child: Container(
                            width: 48 * scale,
                            height: 48 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.6),
                              border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.5), width: 1.5),
                            ),
                            child: ClipOval(
                              child: _buildAvatarImage(avatarUrl, scale),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _buildGlassStatBadge(Icons.local_fire_department_rounded, '$streak', const Color(0xFFFF8227), scale), 
                            SizedBox(width: 8 * scale), 
                            _buildGlassStatBadge(Icons.bolt_rounded, '$totalXp', const Color(0xFF2196F3), scale), 
                            SizedBox(width: 8 * scale), 
                            _buildGlassStatBadge(Icons.star_rounded, '$stars', const Color(0xFFFFB800), scale), 
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 25 * scale), 

                    // --- "MABUHAY" GLASS HERO CARD ---
                    _buildGlassContainer(
                      scale: scale,
                      color: const Color(0xFFFFB800).withOpacity(0.85), 
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
                                  style: TextStyle(color: const Color(0xFF222222), fontSize: 18 * scale, fontWeight: FontWeight.w800, letterSpacing: -0.5), 
                                ),
                                Text(
                                  '$studentName!', 
                                  style: TextStyle(color: const Color(0xFF222222), fontSize: 32 * scale, fontWeight: FontWeight.w900, height: 1.0, letterSpacing: -1.0), 
                                ),
                                SizedBox(height: 12 * scale), 
                                Text(
                                  'Level $currentLevel', 
                                  style: TextStyle(color: Colors.white, fontSize: 16 * scale, fontWeight: FontWeight.w700), 
                                ),
                                SizedBox(height: 6 * scale), 
                                
                                // Progress Bar
                                Container(
                                  height: 26 * scale, 
                                  width: double.infinity, 
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.3), 
                                    borderRadius: BorderRadius.circular(13 * scale), 
                                  ),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: (MediaQuery.of(context).size.width - 150) * progressRatio.clamp(0.0, 1.0),  
                                        decoration: BoxDecoration(
                                          color: Colors.white, 
                                          borderRadius: BorderRadius.circular(13 * scale), 
                                          boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.5), blurRadius: 8)],
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
                          
                          Container(
                            padding: EdgeInsets.all(12 * scale),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.2), 
                                  blurRadius: 20, 
                                  spreadRadius: 5
                                )
                              ],
                            ),
                            child: Icon(
                              Icons.waving_hand_rounded, 
                              color: Colors.white,
                              size: 56 * scale,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 25 * scale), 

                    // --- NOTIFICATIONS GLASS BANNER (REPLACES DAILY CHALLENGES) ---
                    GestureDetector(
                      onTap: () {
                        Navigator.push( 
                          context,
                          MaterialPageRoute(builder: (context) => const NotificationsScreen()), 
                        );
                      },
                      child: _buildGlassContainer(
                        scale: scale,
                        color: Colors.white.withOpacity(0.6),
                        child: Row(
                          children: [
                            Stack(
                              clipBehavior: Clip.none, 
                              children: [
                                Icon(
                                  Icons.notifications_active_rounded, 
                                  color: const Color(0xFFFFB800), 
                                  size: 36 * scale,
                                ), 
                                if (hasUnreadNotifications) 
                                  Positioned(
                                    top: -2, right: -2, 
                                    child: Container(
                                      width: 12 * scale, 
                                      height: 12 * scale, 
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF3B30), 
                                        shape: BoxShape.circle, 
                                        border: Border.all(color: Colors.white, width: 2),
                                      ), 
                                    ),
                                  )
                              ],
                            ),
                            SizedBox(width: 16 * scale), 
                            Text(
                              'Notifications', 
                              style: TextStyle(
                                color: const Color(0xFF222222), 
                                fontSize: 18 * scale, 
                                fontWeight: FontWeight.w800, 
                                letterSpacing: -0.5,
                              ), 
                            ),
                            const Spacer(), 
                            Icon(Icons.arrow_forward_ios_rounded, color: Colors.black45, size: 22 * scale), 
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 32 * scale),  

                    // --- CONTINUE LEARNING ---
                    Text(
                      'Continue Learning',  
                      style: TextStyle(color: const Color(0xFF222222), fontSize: 20 * scale, fontWeight: FontWeight.bold, letterSpacing: -0.5), 
                    ),
                    SizedBox(height: 16 * scale), 
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                      children: [
                        _buildGlassCategoryCard(
                          context: context,  
                          title: 'Alphabet',  
                          imagePath: 'assets/pictures/abc.png', 
                          scale: scale,  
                          onTap: () {
                            Navigator.push( 
                              context, 
                              MaterialPageRoute(builder: (context) => const AlphabetInterface()), 
                            );
                          },
                        ),
                        _buildGlassCategoryCard(
                          context: context,  
                          title: 'Numbers',  
                          imagePath: 'assets/pictures/numbers.png', 
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
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGlassContainer({required Widget child, required double scale, Color? color}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24 * scale), 
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(22 * scale),
          decoration: BoxDecoration(
            color: color ?? Colors.white.withOpacity(0.4),
            borderRadius: BorderRadius.circular(24 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildGlassStatBadge(IconData icon, String value, Color iconColor, double scale) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20 * scale), 
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale), 
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.6), 
            borderRadius: BorderRadius.circular(20 * scale), 
            border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5), 
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 18 * scale), 
              SizedBox(width: 4 * scale), 
              Text(
                value, 
                style: TextStyle(
                  color: const Color(0xFF222222), 
                  fontSize: 14 * scale, 
                  fontWeight: FontWeight.w800, 
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCategoryCard({
    required BuildContext context, 
    required String title, 
    required String imagePath, 
    required double scale, 
    required VoidCallback onTap
  }) {
    return GestureDetector(
      onTap: onTap, 
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24 * scale), 
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 160 * scale, 
            padding: EdgeInsets.symmetric(vertical: 24 * scale, horizontal: 20 * scale), 
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(24 * scale), 
              border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, 
              children: [
                Container(
                  height: 70 * scale,
                  width: 70 * scale,
                  padding: EdgeInsets.all(12 * scale),  
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8), 
                    shape: BoxShape.circle, 
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                    ],
                  ), 
                  child: Image.asset(imagePath, fit: BoxFit.contain), 
                ),
                SizedBox(height: 16 * scale), 
                Text(
                  title, 
                  style: TextStyle(
                    color: const Color(0xFF222222), 
                    fontSize: 16 * scale, 
                    fontWeight: FontWeight.bold, 
                    letterSpacing: -0.3
                  ), 
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}