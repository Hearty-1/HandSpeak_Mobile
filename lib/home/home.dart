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
import '../module/phrases/phrase_interface.dart';
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
        primaryColor: const Color(0xFFFFB800),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFFFB800),
          secondary: Color(0xFFFF8227),
          onPrimary: Colors.white,
          onSurface: Color(0xFF222222),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        primaryColor: const Color(0xFFFFB800),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB800),
          secondary: Color(0xFFFF8227),
          onPrimary: Colors.black,
          onSurface: Colors.white,
        ),
      ),
      home: const SnedInterafce1(userName: "Student"), 
    );
  }
}

class SnedInterafce1 extends StatelessWidget {
  final String userName; 

  const SnedInterafce1({super.key, required this.userName}); 

  Widget _buildAvatarImage(BuildContext context, String? avatarData, double scale, {double size = 48}) {
    final theme = Theme.of(context);
    if (avatarData == null || avatarData.isEmpty) {
      return Icon(Icons.person, color: theme.primaryColor, size: 26 * scale);
    }
    
    if (avatarData.startsWith('data:image')) {
      try {
        final String base64String = avatarData.split(',').last;
        final Uint8List bytes = base64Decode(base64String);
        return Image.memory(bytes, width: size * scale, height: size * scale, fit: BoxFit.cover);
      } catch (e) {
        return Icon(Icons.broken_image_rounded, color: theme.disabledColor, size: 26 * scale);
      }
    } else {
      return Image.network(
        avatarData,
        width: size * scale,
        height: size * scale,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(Icons.person, color: theme.primaryColor, size: 26 * scale),
      );
    }
  }

  Widget _buildDynamicModuleCard(BuildContext context, String moduleType, double scale) {
    String title;
    String imagePath;
    Widget targetScreen;

    final String key = moduleType.toLowerCase().trim();

    if (key.contains('phrase') || key.contains('word') || key.contains('common')) {
      title = 'Common Words';
      imagePath = 'assets/pictures/commons.png';
      targetScreen = const PhraseInterface();
    } else if (key.contains('number')) {
      title = 'Numbers';
      imagePath = 'assets/pictures/numbers.png';
      targetScreen = const NumbersInterface();
    } else {
      title = 'Alphabet';
      imagePath = 'assets/pictures/abc.png';
      targetScreen = const AlphabetInterface();
    }

    return _buildGlassCategoryCard(
      context: context,
      title: title,
      imagePath: imagePath,
      scale: scale,
      onTap: () async {
        await ProgressService().trackRecentModule(key);
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => targetScreen),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    final double screenWidth = MediaQuery.of(context).size.width; 
    final double scale = screenWidth / 393 > 1.2 ? 1.2 : screenWidth / 393; 

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

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
          "Home", 
          style: TextStyle(color: textColor, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0), 
            child: Image.asset("assets/pictures/image 66.png", width: 45), 
          ),
        ],
      ),
      
      bottomNavigationBar: SafeArea(
        child: Container(
          width: double.infinity,
          height: 74,
          margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.cardColor.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.15),
                    width: 1.0,
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
                      icon: Icon(Icons.home_rounded, color: theme.primaryColor, size: 28),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: Icon(Icons.auto_stories_rounded, color: textColor.withOpacity(0.6), size: 28),
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const SnedInterface2()),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.sports_esports_rounded, color: textColor.withOpacity(0.6), size: 28), 
                      onPressed: () => Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
                      ), 
                    ),
                    IconButton(
                      icon: Icon(Icons.person_rounded, color: textColor.withOpacity(0.6), size: 28),
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
            top: 300,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary.withOpacity(0.15),
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
              List<String> recentModules = [];

              String normalizeKey(String raw) {
                final k = raw.toLowerCase().trim();
                if (k.contains('number')) return 'numbers';
                if (k.contains('phrase') || k.contains('word') || k.contains('common')) return 'common words';
                return 'alphabet';
              }

              if (userSnapshot.hasData && userSnapshot.data!.exists) { 
                final userData = userSnapshot.data!.data() as Map<String, dynamic>?; 
                if (userData != null) {
                  studentName = userData['name'] ?? userData['displayName'] ?? userName; 
                  streak = userData['streak'] ?? 0; 
                  totalXp = userData['xp'] ?? 0; 
                  stars = userData['stars'] ?? (totalXp ~/ 1000);  
                  avatarUrl = userData['avatar'] ?? userData['photoURL']; 

                  final List<dynamic> rawNotifications = userData['notifications'] ?? [];
                  hasUnreadNotifications = rawNotifications.any(
                    (n) => (n is Map) && (n['isRead'] == false),
                  );

                  List<String> userLoggedModules = [];

                  if (userData['recentModules'] != null && (userData['recentModules'] as List).isNotEmpty) {
                    userLoggedModules = (userData['recentModules'] as List)
                        .map((e) => normalizeKey(e.toString()))
                        .toSet()
                        .toList();
                  } 
                  else if (userData['progress'] != null && (userData['progress'] as Map).isNotEmpty) {
                    userLoggedModules = (userData['progress'] as Map<String, dynamic>)
                        .keys
                        .map((key) => normalizeKey(key))
                        .toSet()
                        .toList();
                  }

                  // Always backfill missing modules so all 3 categories remain available on Home
                  const defaultCategories = ['alphabet', 'numbers', 'common words'];
                  recentModules = [
                    ...userLoggedModules,
                    ...defaultCategories.where((cat) => !userLoggedModules.contains(cat)),
                  ];
                }
              }

              if (recentModules.isEmpty) {
                recentModules = ['alphabet', 'numbers', 'common words'];
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
                              color: theme.cardColor.withOpacity(0.6),
                              border: Border.all(color: theme.primaryColor.withOpacity(0.5), width: 1.5),
                            ),
                            child: ClipOval(
                              child: _buildAvatarImage(context, avatarUrl, scale),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _buildGlassStatBadge(context, Icons.local_fire_department_rounded, '$streak', theme.colorScheme.secondary, scale), 
                            SizedBox(width: 8 * scale), 
                            _buildGlassStatBadge(context, Icons.bolt_rounded, '$totalXp', const Color(0xFF2196F3), scale), 
                            SizedBox(width: 8 * scale), 
                            _buildGlassStatBadge(context, Icons.star_rounded, '$stars', theme.primaryColor, scale), 
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 25 * scale), 

                    _buildGlassContainer(
                      context: context,
                      scale: scale,
                      color: theme.primaryColor.withOpacity(0.85), 
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
                                  style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 18 * scale, fontWeight: FontWeight.w800, letterSpacing: -0.5), 
                                ),
                                Text(
                                  '$studentName!', 
                                  style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 32 * scale, fontWeight: FontWeight.w900, height: 1.0, letterSpacing: -1.0), 
                                ),
                                SizedBox(height: 12 * scale), 
                                Text(
                                  'Level $currentLevel', 
                                  style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.9), fontSize: 16 * scale, fontWeight: FontWeight.w700), 
                                ),
                                SizedBox(height: 6 * scale), 
                                
                                Container(
                                  height: 26 * scale, 
                                  width: double.infinity, 
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onPrimary.withOpacity(0.3), 
                                    borderRadius: BorderRadius.circular(13 * scale), 
                                  ),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: (MediaQuery.of(context).size.width - 150) * progressRatio.clamp(0.0, 1.0),  
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.onPrimary, 
                                          borderRadius: BorderRadius.circular(13 * scale), 
                                          boxShadow: [BoxShadow(color: theme.colorScheme.onPrimary.withOpacity(0.5), blurRadius: 8)],
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.centerLeft, 
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 12 * scale), 
                                          child: Text(
                                            '$xpInLevel XP', 
                                            style: TextStyle(
                                              color: theme.primaryColor,  
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
                              color: theme.colorScheme.onPrimary.withOpacity(0.2),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.onPrimary.withOpacity(0.2), 
                                  blurRadius: 20, 
                                  spreadRadius: 5
                                )
                              ],
                            ),
                            child: Icon(
                              Icons.waving_hand_rounded, 
                              color: theme.colorScheme.onPrimary,
                              size: 56 * scale,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 25 * scale), 

                    GestureDetector(
                      onTap: () {
                        Navigator.push( 
                          context,
                          MaterialPageRoute(builder: (context) => const NotificationsScreen()), 
                        );
                      },
                      child: _buildGlassContainer(
                        context: context,
                        scale: scale,
                        child: Row(
                          children: [
                            Stack(
                              clipBehavior: Clip.none, 
                              children: [
                                Icon(
                                  Icons.notifications_active_rounded, 
                                  color: theme.primaryColor, 
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
                                        border: Border.all(color: theme.cardColor, width: 2),
                                      ), 
                                    ),
                                  )
                              ],
                            ),
                            SizedBox(width: 16 * scale), 
                            Text(
                              'Notifications', 
                              style: TextStyle(
                                color: textColor, 
                                fontSize: 18 * scale, 
                                fontWeight: FontWeight.w800, 
                                letterSpacing: -0.5,
                              ), 
                            ),
                            const Spacer(), 
                            Icon(Icons.arrow_forward_ios_rounded, color: textColor.withOpacity(0.6), size: 22 * scale), 
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 32 * scale),  

                    Text(
                      'Continue Learning',  
                      style: TextStyle(color: textColor, fontSize: 20 * scale, fontWeight: FontWeight.bold, letterSpacing: -0.5), 
                    ),
                    SizedBox(height: 16 * scale), 
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: recentModules.map((moduleKey) {
                          return Padding(
                            padding: EdgeInsets.only(right: 16 * scale),
                            child: _buildDynamicModuleCard(context, moduleKey, scale),
                          );
                        }).toList(),
                      ),
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

  Widget _buildGlassContainer({
    required BuildContext context, 
    required Widget child, 
    required double scale, 
    Color? color
  }) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24 * scale), 
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(22 * scale),
          decoration: BoxDecoration(
            color: color ?? theme.cardColor.withOpacity(0.6),
            borderRadius: BorderRadius.circular(24 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildGlassStatBadge(BuildContext context, IconData icon, String value, Color iconColor, double scale) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20 * scale), 
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale), 
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.6), 
            borderRadius: BorderRadius.circular(20 * scale), 
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0), 
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 18 * scale), 
              SizedBox(width: 4 * scale), 
              Text(
                value, 
                style: TextStyle(
                  color: textColor, 
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
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap, 
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24 * scale), 
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 160 * scale, 
            padding: EdgeInsets.symmetric(vertical: 24 * scale, horizontal: 20 * scale), 
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(24 * scale), 
              border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, 
              children: [
                Container(
                  height: 70 * scale,
                  width: 70 * scale,
                  padding: EdgeInsets.all(12 * scale),  
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor.withOpacity(0.8), 
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
                    color: textColor, 
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