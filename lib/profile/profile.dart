import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../home/home.dart';
import '../module/module.dart';
import '../leaderboard/arena.dart';
import '../home/notification_bell.dart';
import '../home/settings_screen.dart';
import 'add_friend_screen.dart';
import '/auth/login_screen.dart';
import '../widgets/app_nav_bar.dart';
import 'achievements.dart';

import '/services/performance_monitor.dart';

Route _fadeRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 180),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  Widget _buildAvatarImage(BuildContext context, String avatarData, double scale, {double size = 100}) {
    final theme = Theme.of(context);
    if (avatarData.isEmpty) {
      return Icon(Icons.person_rounded, size: size * 0.55 * scale, color: theme.primaryColor);
    }
    
    if (avatarData.startsWith('data:image')) {
      try {
        final String base64String = avatarData.split(',').last;
        final Uint8List bytes = base64Decode(base64String);
        return Image.memory(bytes, width: size * scale, height: size * scale, fit: BoxFit.cover);
      } catch (e) {
        return Icon(Icons.broken_image_rounded, size: size * 0.55 * scale, color: theme.disabledColor);
      }
    } else {
      return Image.network(
        avatarData,
        width: size * scale,
        height: size * scale,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: size * 0.3 * scale,
              height: size * 0.3 * scale,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, size: size * 0.55 * scale, color: theme.primaryColor),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    final User? currentUser = FirebaseAuth.instance.currentUser;
    final double screenWidth = MediaQuery.of(context).size.width;
    const double baseWidth = 393;
    final double scale = screenWidth / baseWidth > 1.2 ? 1.2 : screenWidth / baseWidth;
    
    if (currentUser == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_circle, size: 80, color: theme.primaryColor),
              const SizedBox(height: 16),
              Text('No student account found.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                onPressed: () {},
                child: Text('Go to Login', style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true, 
      extendBody: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      
      appBar: AppBar(
        toolbarHeight: 65,
        backgroundColor: theme.cardColor.withOpacity(0.4),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(Icons.person_add_alt_1_rounded, color: textColor, size: 26),
          onPressed: () {
            Navigator.push(
              context,
              _fadeRoute(const AddFriendScreen()),
            );
          },
        ),
        iconTheme: theme.iconTheme.copyWith(color: textColor),
        flexibleSpace: ClipRRect(
          clipBehavior: Clip.antiAlias,
          child: SmartBlur(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.15),
                    width: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          "My Profile",
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
            fontSize: 22,
            letterSpacing: -0.5
          ),
        ),
        actions: [
          const NotificationBell(),
          Padding(
            padding: const EdgeInsets.only(right: 16.0, left: 8.0),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
              ),
              child: ClipOval(
                child: Image.asset(
                  "assets/pictures/image 66.png", 
                  width: 40, 
                  height: 40, 
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.account_circle, 
                    size: 40, 
                    color: Theme.of(context).disabledColor
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: AppNavBar(
        currentIndex: 3,
        onTap: (i) {
          switch (i) {
            case 0:
              Navigator.pushAndRemoveUntil(context, _fadeRoute(const SnedInterafce1(userName: "Student")), (route) => false);
            case 1:
              Navigator.pushReplacement(context, _fadeRoute(const SnedInterface2()));
            case 2:
              Navigator.pushReplacement(context, _fadeRoute(const LeaderboardScreen()));
          }
        },
      ),
      
      body: Stack(
        children: [
          Positioned(
            top: 120 * scale, left: -40 * scale,
            child: Container(
              width: 200 * scale, height: 200 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.primaryColor.withOpacity(0.2),
              ),
            ),
          ),
          Positioned(
            top: 380 * scale, right: -50 * scale,
            child: Container(
              width: 220 * scale, height: 220 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary.withOpacity(0.12),
              ),
            ),
          ),

          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).snapshots(), 
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor)));
                }

                String name = currentUser.displayName ?? "Guest Student";
                String email = currentUser.email ?? "student@handspeak.edu";
                String avatarUrl = "";
                
                int stars = 0, xp = 0, streak = 0, followersCount = 0, followingCount = 0;

                List<dynamic> followersList = [];
                List<dynamic> followingList = [];
                Map<String, dynamic> storedBadgesMap = {};
                Map<String, dynamic> userData = {};

                if (snapshot.hasData && snapshot.data!.exists) {
                  userData = (snapshot.data!.data() as Map<String, dynamic>?) ?? {};
                  name = userData['name'] ?? name;
                  email = userData['email'] ?? email;
                  avatarUrl = userData['avatar'] ?? "";
                  stars = userData['stars'] ?? 0;
                  streak = userData['streak'] ?? 0;

                  followersList = userData['followers'] as List<dynamic>? ?? [];
                  followingList = userData['following'] as List<dynamic>? ?? [];
                  followersCount = followersList.length;
                  followingCount = followingList.length;

                  // Already-synced badges (title -> unlock time).
                  storedBadgesMap = userData['badges'] as Map<String, dynamic>? ?? {};

                  xp = userData['xp'] ?? 0;
                  if (xp == 0 && userData['progress'] is Map) {
                    (userData['progress'] as Map).forEach((key, val) { if (val is num) xp += val.toInt(); });
                  }
                }

                // Every achievement (achievements.dart): learning, mastery,
                // consistency, arena, social and daily-quest badges.
                final List<BadgeData> badges = buildAchievements(userData);
                final List<BadgeData> previewBadges = highlightBadges(badges);

                // Sync newly unlocked badges to Firestore for web reporting tracking
                Map<String, dynamic> newBadgesToSync = {};
                for (var badge in badges) {
                  if (badge.isUnlocked && !storedBadgesMap.containsKey(badge.title)) {
                    newBadgesToSync[badge.title] = FieldValue.serverTimestamp();
                  }
                }

                if (newBadgesToSync.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set({
                      'badges': newBadgesToSync, 
                      'unlockedBadgesList': FieldValue.arrayUnion(newBadgesToSync.keys.toList()),
                    }, SetOptions(merge: true)).catchError((e) => debugPrint("Error syncing badges: $e"));
                  });
                }

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: 20 * scale,
                    right: 20 * scale,
                    top: 24 * scale,
                    bottom: 110 * scale
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.cardColor, width: 4 * scale),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                )
                              ]
                            ),
                            child: CircleAvatar(
                              radius: 50 * scale,
                              backgroundColor: theme.primaryColor.withOpacity(0.2),
                              child: ClipOval(
                                child: _buildAvatarImage(context, avatarUrl, scale),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _showEditAvatarDialog(context, currentUser, currentAvatar: avatarUrl, scale: scale),
                            child: Container(
                              height: 32 * scale,
                              width: 32 * scale,
                              decoration: BoxDecoration(
                                color: theme.cardColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2))
                                ],
                                border: Border.all(color: theme.dividerColor.withOpacity(0.3), width: 0.5)
                              ),
                              child: Icon(Icons.edit_rounded, size: 16 * scale, color: textColor),
                            ),
                          )
                        ],
                      ),
                      
                      SizedBox(height: 16 * scale),
                      Text(
                        name,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 24 * scale,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                          letterSpacing: -0.5
                        )
                      ),
                      SizedBox(height: 2 * scale),
                      Text(
                        email,
                        style: TextStyle(
                          color: textColor.withOpacity(0.6),
                          fontSize: 14 * scale,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500
                        )
                      ),
                      
                      SizedBox(height: 20 * scale),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => _showFriendsList(context, "Followers", List.from(followersList), scale, currentUser.uid, false),
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              children: [
                                Text('$followersCount', style: TextStyle(color: textColor, fontSize: 18 * scale, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
                                SizedBox(height: 2 * scale),
                                Text('Followers', style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 13 * scale, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                              ],
                            ),
                          ),
                          Container(
                            height: 24 * scale,
                            width: 1,
                            color: theme.dividerColor.withOpacity(0.4),
                            margin: EdgeInsets.symmetric(horizontal: 30 * scale),
                          ),
                          GestureDetector(
                            onTap: () => _showFriendsList(context, "Following", List.from(followingList), scale, currentUser.uid, true),
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              children: [
                                Text('$followingCount', style: TextStyle(color: textColor, fontSize: 18 * scale, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
                                SizedBox(height: 2 * scale),
                                Text('Following', style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 13 * scale, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      SizedBox(height: 24 * scale),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(24 * scale),
                        clipBehavior: Clip.antiAlias,
                        child: SmartBlur(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 16 * scale),
                            decoration: BoxDecoration(
                              color: theme.cardColor.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(24 * scale),
                              border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatItem(context, scale, "Streak", "$streak", Icons.local_fire_department_rounded, theme.colorScheme.secondary),
                                _buildStatItem(context, scale, "Stars", "$stars", Icons.star_rounded, theme.primaryColor),
                                _buildStatItem(context, scale, "XP Total", "$xp", Icons.bolt_rounded, const Color(0xFF2196F3)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      SizedBox(height: 28 * scale),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Achievement Badges',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 18 * scale,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Inter',
                              letterSpacing: -0.4,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                "${badges.where((b) => b.isUnlocked).length} / ${badges.length}",
                                style: TextStyle(
                                  color: theme.primaryColor,
                                  fontSize: 14 * scale,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(width: 12 * scale),
                              GestureDetector(
                                onTap: () => AchievementsSheet.show(
                                  context,
                                  badges: badges,
                                  scale: scale,
                                  onBadgeTap: (b) => _showBadgeDetails(context, b, scale),
                                ),
                                child: Text(
                                  "See All",
                                  style: TextStyle(
                                    color: textColor.withOpacity(0.6),
                                    fontSize: 14 * scale,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 16 * scale),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(24 * scale),
                        child: SmartBlur(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            padding: EdgeInsets.all(20 * scale),
                            decoration: BoxDecoration(
                              color: theme.cardColor.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(24 * scale),
                              border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
                            ),
                            child: GridView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 24 * scale,
                                crossAxisSpacing: 16 * scale,
                                childAspectRatio: 0.75,
                              ),
                              itemCount: previewBadges.length,
                              itemBuilder: (context, index) {
                                return BadgeTile(
                                  badge: previewBadges[index],
                                  scale: scale,
                                  onTap: () => _showBadgeDetails(context, previewBadges[index], scale),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      
                      SizedBox(height: 28 * scale),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(20 * scale),
                        clipBehavior: Clip.antiAlias,
                        child: SmartBlur(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.cardColor.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20 * scale),
                              border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
                            ),
                            child: Column(
                              children: [
                                _buildActionRow(
                                  context: context,
                                  scale: scale,
                                  icon: Icons.settings_rounded,
                                  iconColor: theme.primaryColor,
                                  title: "Settings",
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      _fadeRoute(const SettingsScreen()),
                                    );
                                  },
                                ),
                                Divider(height: 1, thickness: 0.8, color: theme.dividerColor.withOpacity(0.2)),
                                _buildActionRow(
                                  context: context,
                                  scale: scale,
                                  icon: Icons.logout_rounded,
                                  iconColor: const Color(0xFFF34B1B),
                                  title: "Sign Out",
                                  isDestructive: true,
                                  onTap: () => _handleSignOut(context),
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
            ),
          ),
        ],
      ),
    );
  }


  void _showBadgeDetails(BuildContext context, BadgeData badge, double scale) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(24 * scale),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28 * scale)),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40 * scale,
                height: 4 * scale,
                decoration: BoxDecoration(
                  color: textColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              SizedBox(height: 24 * scale),
              Container(
                width: 100 * scale,
                height: 100 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: badge.isUnlocked ? [
                    BoxShadow(color: badge.themeColor.withOpacity(0.3), blurRadius: 30, spreadRadius: 5)
                  ] : [],
                ),
                child: BadgeMedallion(badge: badge, size: 100 * scale),
              ),
              SizedBox(height: 20 * scale),
              Text(
                badge.title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 22 * scale,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Inter',
                ),
              ),
              SizedBox(height: 8 * scale),
              Text(
                badge.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor.withOpacity(0.7),
                  fontSize: 14 * scale,
                  fontFamily: 'Inter',
                  height: 1.4,
                ),
              ),
              SizedBox(height: 24 * scale),
              Container(
                padding: EdgeInsets.all(16 * scale),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16 * scale),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          badge.isUnlocked ? "Completed!" : "Progress",
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 14 * scale,
                          ),
                        ),
                        Text(
                          "${badge.shownProgress} / ${badge.targetProgress}",
                          style: TextStyle(
                            color: badge.isUnlocked ? badge.themeColor : textColor.withOpacity(0.5),
                            fontWeight: FontWeight.w900,
                            fontSize: 14 * scale,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12 * scale),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8 * scale),
                      child: LinearProgressIndicator(
                        value: badge.progressPercent,
                        minHeight: 8 * scale,
                        backgroundColor: textColor.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          badge.isUnlocked ? badge.themeColor : badge.themeColor.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 32 * scale),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    padding: EdgeInsets.symmetric(vertical: 16 * scale),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16 * scale)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Awesome", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  void _showFriendsList(BuildContext context, String title, List<dynamic> initialUids, double scale, String currentUserId, bool isFollowingList) {
    List<dynamic> uids = List.from(initialUids);
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24 * scale))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.6,
              padding: EdgeInsets.all(20 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40 * scale, 
                      height: 5 * scale, 
                      decoration: BoxDecoration(color: textColor.withOpacity(0.2), borderRadius: BorderRadius.circular(10))
                    ),
                  ),
                  SizedBox(height: 20 * scale),
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Inter',
                      letterSpacing: -0.5
                    )
                  ),
                  SizedBox(height: 16 * scale),
                  Expanded(
                    child: uids.isEmpty
                        ? Center(
                            child: Text(
                              "No $title yet.",
                              style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 14 * scale, fontWeight: FontWeight.w600, fontFamily: 'Inter')
                            )
                          )
                        : ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            itemCount: uids.length,
                            separatorBuilder: (_, __) => SizedBox(height: 12 * scale),
                            itemBuilder: (context, index) {
                              String targetUid = uids[index];

                              return FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance.collection('users').doc(targetUid).get(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData || !snapshot.data!.exists) {
                                    return const SizedBox.shrink();
                                  }
                                  final data = snapshot.data!.data() as Map<String, dynamic>;
                                  String name = data['name'] ?? 'Student';
                                  String avatar = data['avatar'] ?? '';
                                  int xp = data['xp'] ?? 0;

                                  return Container(
                                    padding: EdgeInsets.all(12 * scale),
                                    decoration: BoxDecoration(
                                      color: theme.cardColor,
                                      borderRadius: BorderRadius.circular(16 * scale),
                                      border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 20 * scale,
                                          backgroundColor: theme.primaryColor.withOpacity(0.2),
                                          child: ClipOval(child: _buildAvatarImage(context, avatar, scale, size: 40)),
                                        ),
                                        SizedBox(width: 12 * scale),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 14 * scale, fontFamily: 'Inter'),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              SizedBox(height: 2 * scale),
                                              Row(
                                                children: [
                                                  Icon(Icons.bolt_rounded, size: 12 * scale, color: const Color(0xFF2196F3)),
                                                  SizedBox(width: 2 * scale),
                                                  Text(
                                                    "$xp XP",
                                                    style: TextStyle(color: const Color(0xFF2196F3), fontSize: 11 * scale, fontWeight: FontWeight.w700)
                                                  ),
                                                ],
                                              )
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: 8 * scale),
                                        GestureDetector(
                                          onTap: () async {
                                            setState(() {
                                              uids.removeAt(index);
                                            });
                                            try {
                                              final currentRef = FirebaseFirestore.instance.collection('users').doc(currentUserId);
                                              final targetRef = FirebaseFirestore.instance.collection('users').doc(targetUid);
                                              final batch = FirebaseFirestore.instance.batch();
                                              
                                              if (isFollowingList) {
                                                batch.update(currentRef, {
                                                  'following': FieldValue.arrayRemove([targetUid]),
                                                });
                                                batch.update(targetRef, {
                                                  'followers': FieldValue.arrayRemove([currentUserId]),
                                                  'incomingRequests': FieldValue.arrayRemove([currentUserId]),
                                                });
                                              } else {
                                                batch.update(currentRef, {
                                                  'followers': FieldValue.arrayRemove([targetUid]),
                                                  'incomingRequests': FieldValue.arrayRemove([targetUid]),
                                                });
                                                batch.update(targetRef, {
                                                  'following': FieldValue.arrayRemove([currentUserId]),
                                                });
                                              }
                                              await batch.commit();
                                            } catch (e) {
                                              debugPrint("Error updating social relation: $e");
                                            }
                                          },
                                          child: Container(
                                            padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                                            decoration: BoxDecoration(
                                              color: textColor.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(12 * scale),
                                            ),
                                            child: Text(
                                              isFollowingList ? "Unfollow" : "Remove",
                                              style: TextStyle(color: textColor.withOpacity(0.7), fontWeight: FontWeight.w700, fontSize: 12 * scale, fontFamily: 'Inter')
                                            ),
                                          ),
                                        )
                                      ],
                                    ),
                                  );
                                }
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildActionRow({
    required BuildContext context,
    required double scale,
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 4 * scale),
      leading: Container(
        padding: EdgeInsets.all(6 * scale),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10 * scale),
        ),
        child: Icon(icon, color: iconColor, size: 20 * scale),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15 * scale,
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
          color: isDestructive ? const Color(0xFFF34B1B) : textColor,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14 * scale,
        color: textColor.withOpacity(0.3),
      ),
    );
  }

  void _showEditAvatarDialog(BuildContext context, User user, {String? currentAvatar, required double scale}) {
    final ImagePicker picker = ImagePicker();
    Uint8List? pickedImageBytes;
    String? pickedMimeType;
    String existingAvatarUrl = currentAvatar ?? "";
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isSaving = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: theme.cardColor,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24 * scale)),
              title: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(6 * scale),
                    decoration: BoxDecoration(color: theme.primaryColor.withOpacity(0.15), shape: BoxShape.circle),
                    child: Icon(Icons.photo_camera_rounded, color: theme.primaryColor, size: 22 * scale)
                  ),
                  SizedBox(width: 10 * scale),
                  Text("Update Avatar", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19 * scale, fontFamily: 'Inter', color: textColor)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      try {
                        final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                        if (image != null) {
                          final bytes = await image.readAsBytes();
                          String mimeType = 'image/jpeg';
                          if (image.name.toLowerCase().endsWith('.png')) mimeType = 'image/png';

                          setState(() {
                            pickedImageBytes = bytes;
                            pickedMimeType = mimeType;
                          });
                        }
                      } catch (e) {
                        debugPrint("Image picking error: $e");
                      }
                    },
                    child: Container(
                      height: 80 * scale,
                      width: 80 * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: textColor.withOpacity(0.05),
                        border: Border.all(color: theme.primaryColor, width: 2),
                      ),
                      child: ClipOval(
                        child: pickedImageBytes != null
                            ? Image.memory(pickedImageBytes!, width: 80 * scale, height: 80 * scale, fit: BoxFit.cover)
                            : existingAvatarUrl.isNotEmpty
                                ? _buildAvatarImage(context, existingAvatarUrl, scale, size: 80)
                                : Icon(Icons.add_a_photo_rounded, color: textColor.withOpacity(0.4), size: 30 * scale),
                      ),
                    ),
                  ),
                  SizedBox(height: 8 * scale),
                  Text("Tap to upload photo", style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 11 * scale, fontWeight: FontWeight.w600)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: Text("Cancel", style: TextStyle(color: textColor.withOpacity(0.6), fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                ),
                ElevatedButton(
                  onPressed: isSaving 
                    ? null 
                    : () async {
                        if (pickedImageBytes == null) {
                          Navigator.pop(context);
                          return;
                        }

                        setState(() => isSaving = true);
                        try {
                          final storageRef = FirebaseStorage.instance
                              .ref()
                              .child('user_avatars')
                              .child('${user.uid}.jpg');

                          final uploadTask = await storageRef.putData(
                            pickedImageBytes!,
                            SettableMetadata(contentType: pickedMimeType ?? 'image/jpeg'),
                          );

                          final String downloadUrl = await uploadTask.ref.getDownloadURL();

                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(user.uid)
                              .set({
                                'avatar': downloadUrl,
                              }, SetOptions(merge: true));

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Avatar updated successfully!"), backgroundColor: Colors.green));
                          }
                        } catch (e) {
                          setState(() => isSaving = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error uploading avatar: $e"), backgroundColor: Colors.red));
                          }
                        }
                      },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor, 
                    elevation: 0, 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * scale))
                  ),
                  child: isSaving 
                      ? SizedBox(width: 18 * scale, height: 18 * scale, child: CircularProgressIndicator(color: theme.colorScheme.onPrimary, strokeWidth: 2))
                      : Text("Save", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _handleSignOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const SnedStudentLogin()), 
      (route) => false
    );
  }

  Widget _buildStatItem(BuildContext context, double scale, String label, String value, IconData icon, Color elementColor) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: elementColor, size: 26 * scale), 
        SizedBox(height: 4 * scale),
        Text(
          value, 
          style: TextStyle(color: textColor, fontSize: 22 * scale, fontWeight: FontWeight.w900, fontFamily: 'Inter')
        ),
        Text(
          label, 
          style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 11 * scale, fontWeight: FontWeight.w700, fontFamily: 'Inter')
        ),
      ],
    );
  }
}