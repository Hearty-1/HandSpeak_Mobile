import 'dart:ui';
import 'dart:convert'; 
import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart'; 

import '../services/progress_service.dart'; 
import '../auth/login_screen.dart';        
import '../home/home.dart'; 
import '../module/module.dart'; 
import '../leaderboard/leaderboard.dart';
import '../home/settings_screen.dart'; 
import 'add_friend_screen.dart'; 

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // Helper to safely render either a Base64 image, a network URL, or a fallback icon
  Widget _buildAvatarImage(String avatarData, double scale, {double size = 100}) {
    if (avatarData.isEmpty) {
      return Icon(Icons.person_rounded, size: size * 0.55 * scale, color: const Color(0xFFFFB800));
    }
    
    if (avatarData.startsWith('data:image')) {
      try {
        final String base64String = avatarData.split(',').last;
        final Uint8List bytes = base64Decode(base64String);
        return Image.memory(bytes, width: size * scale, height: size * scale, fit: BoxFit.cover);
      } catch (e) {
        return Icon(Icons.broken_image_rounded, size: size * 0.55 * scale, color: Colors.grey);
      }
    } else {
      return Image.network(
        avatarData,
        width: size * scale,
        height: size * scale,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, size: size * 0.55 * scale, color: const Color(0xFFFFB800)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    final double screenWidth = MediaQuery.of(context).size.width;
    const double baseWidth = 393;
    final double scale = screenWidth / baseWidth > 1.2 ? 1.2 : screenWidth / baseWidth;
    
    if (currentUser == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFF9E5),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_circle, size: 80, color: Color(0xFFFFB800)),
              const SizedBox(height: 16),
              const Text('No student account found.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF222222))),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB800), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const SnedStudentLogin()), (route) => false),
                child: const Text('Go to Login', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      );
    }

    final ProgressService progressService = ProgressService();

    return Scaffold(
      extendBodyBehindAppBar: true, 
      extendBody: true, 
      backgroundColor: const Color(0xFFFFF9E5),
      
      // --- PREMIUM TRANSLUCENT IOS APP BAR ---
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.4),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, 
        leading: IconButton( 
          icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.black87, size: 26),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddFriendScreen()),
            );
          },
        ),
        iconTheme: const IconThemeData(color: Colors.black87), 
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: Colors.black.withOpacity(0.06),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: const Text(
          "My Profile",
          style: TextStyle(
            color: Colors.black, 
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
            fontSize: 22,
            letterSpacing: -0.5
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20.0),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: Image.asset(
                  "assets/pictures/image 66.png", 
                  width: 40, 
                  height: 40, 
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.account_circle, size: 40, color: Colors.grey),
                ),
              ),
            ),
          ),
        ],
      ),

      // --- TRANSLUCENT FLOATING NAVIGATION ENVIRONMENT ---
      bottomNavigationBar: SafeArea(
        child: Container(
          width: double.infinity,
          height: 74,
          margin: EdgeInsets.only(bottom: 12 * scale, left: 16 * scale, right: 16 * scale),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28 * scale),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(28 * scale),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.65),
                    width: 1.5 * scale,
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
                        String displayName = currentUser.displayName ?? currentUser.email?.split('@')[0] ?? "Student";
                        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => SnedInterafce1(userName: displayName)), (route) => false);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_stories_rounded, color: Colors.black45, size: 28), 
                      onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SnedInterface2())),
                    ),
                    IconButton(
                      icon: const Icon(Icons.emoji_events_rounded, color: Colors.black45, size: 28), 
                      onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LeaderboardScreen())),
                    ),
                    IconButton(
                      icon: const Icon(Icons.person_rounded, color: Color(0xFFFFB800), size: 30), 
                      onPressed: () {}, 
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
            top: 120 * scale, left: -40 * scale,
            child: Container(
              width: 200 * scale, height: 200 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFB800).withOpacity(0.2),
              ),
            ),
          ),
          Positioned(
            top: 380 * scale, right: -50 * scale,
            child: Container(
              width: 220 * scale, height: 220 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF34B1B).withOpacity(0.08),
              ),
            ),
          ),

          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: progressService.getUserProgressStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFB800))));
                }

                String name = currentUser.displayName ?? "Guest Student";
                String email = currentUser.email ?? "student@handspeak.edu";
                String avatarUrl = "";
                int stars = 0, xp = 0, streak = 0, followersCount = 0, followingCount = 0;
                
                List<dynamic> followersList = [];
                List<dynamic> followingList = [];
                List<dynamic> outgoingRequests = [];

                Map<String, dynamic> progressMap = {};

                if (snapshot.hasData && snapshot.data!.exists) {
                  final userData = snapshot.data!.data() as Map<String, dynamic>?;
                  if (userData != null) {
                    name = userData['name'] ?? name;
                    email = userData['email'] ?? email;
                    avatarUrl = userData['avatar'] ?? ""; 
                    stars = userData['stars'] ?? 0;
                    streak = userData['streak'] ?? 0;
                    
                    followersList = userData['followers'] as List<dynamic>? ?? [];
                    followingList = userData['following'] as List<dynamic>? ?? [];
                    outgoingRequests = userData['outgoingRequests'] as List<dynamic>? ?? [];
                    
                    followersCount = followersList.length;
                    followingCount = followingList.length + outgoingRequests.length;
                    
                    if (userData.containsKey('progress') && userData['progress'] is Map) {
                      progressMap = Map<String, dynamic>.from(userData['progress']);
                      xp = userData['xp'] ?? 0;
                      if (xp == 0) progressMap.forEach((key, val) { if (val is num) xp += val.toInt(); });
                    }
                  }
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
                      // --- AVATAR LAYOUT WITH MICRO-EDIT ACTION ---
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4 * scale),
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
                              backgroundColor: const Color(0xFFFFEFA7),
                              child: ClipOval(
                                child: _buildAvatarImage(avatarUrl, scale),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _showEditAvatarDialog(context, currentUser, currentAvatar: avatarUrl, scale: scale),
                            child: Container(
                              height: 32 * scale,
                              width: 32 * scale,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2))
                                ],
                                border: Border.all(color: Colors.black.withOpacity(0.04), width: 0.5)
                              ),
                              child: Icon(Icons.edit_rounded, size: 16 * scale, color: const Color(0xFF222222)),
                            ),
                          )
                        ],
                      ),
                      
                      SizedBox(height: 16 * scale),
                      Text(
                        name, 
                        style: TextStyle(
                          color: const Color(0xFF222222), 
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
                          color: Colors.black45, 
                          fontSize: 14 * scale,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500
                        )
                      ),
                      
                      SizedBox(height: 20 * scale),

                      // --- NATIVE FOLLOWERS DISPLAY (CLICKABLE WITH UNFOLLOW/REMOVE OPTION) ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => _showFriendsList(context, "Followers", List.from(followersList), scale, currentUser.uid, false),
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              children: [
                                Text('$followersCount', style: TextStyle(color: const Color(0xFF222222), fontSize: 18 * scale, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
                                SizedBox(height: 2 * scale),
                                Text('Followers', style: TextStyle(color: Colors.black45, fontSize: 13 * scale, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                              ],
                            ),
                          ),
                          Container(
                            height: 24 * scale,
                            width: 1,
                            color: Colors.black.withOpacity(0.1),
                            margin: EdgeInsets.symmetric(horizontal: 30 * scale),
                          ),
                          GestureDetector(
                            onTap: () {
                              List<dynamic> combinedList = [...followingList, ...outgoingRequests];
                              _showFriendsList(context, "Following", List.from(combinedList), scale, currentUser.uid, true);
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              children: [
                                Text('$followingCount', style: TextStyle(color: const Color(0xFF222222), fontSize: 18 * scale, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
                                SizedBox(height: 2 * scale),
                                Text('Following', style: TextStyle(color: Colors.black45, fontSize: 13 * scale, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      SizedBox(height: 24 * scale),

                      // --- TRANSLUCENT PREMIUM METRICS DASHBOARD ---
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24 * scale),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 16 * scale),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.45), 
                              borderRadius: BorderRadius.circular(24 * scale), 
                              border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5 * scale),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatItem(scale, "Streak", "$streak", Icons.local_fire_department_rounded, const Color(0xFFFF8227)),
                                _buildStatItem(scale, "Stars", "$stars", Icons.star_rounded, const Color(0xFFFFB800)),
                                _buildStatItem(scale, "XP Total", "$xp", Icons.bolt_rounded, const Color(0xFF2196F3)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      SizedBox(height: 28 * scale),

                      // --- ACCOMPLISHMENTS SECTION ---
                      Align(
                        alignment: Alignment.centerLeft, 
                        child: Text(
                          'My Badges', 
                          style: TextStyle(
                            color: const Color(0xFF222222), 
                            fontSize: 18 * scale, 
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Inter',
                            letterSpacing: -0.4
                          )
                        )
                      ),
                      SizedBox(height: 14 * scale),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(24 * scale),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            padding: EdgeInsets.all(18 * scale),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(24 * scale),
                              border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5 * scale),
                            ),
                            child: GridView.count(
                              crossAxisCount: 3, 
                              shrinkWrap: true, 
                              physics: const NeverScrollableScrollPhysics(), 
                              mainAxisSpacing: 12 * scale, 
                              crossAxisSpacing: 12 * scale, 
                              childAspectRatio: 0.82,
                              children: [
                                _buildBadge(scale, "First Sign", "assets/pictures/alphabet.png", isUnlocked: xp > 0),
                                _buildBadge(scale, "Star Scholar", "assets/pictures/large star.png", isUnlocked: stars >= 10),
                                _buildBadge(scale, "Sign Master", "assets/pictures/sign.png", isUnlocked: xp >= 1000), 
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      SizedBox(height: 28 * scale),

                      // --- IOS GROUPED OPTIONS CELL VIEW ---
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20 * scale),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(20 * scale),
                              border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5 * scale),
                            ),
                            child: Column(
                              children: [
                                _buildActionRow(
                                  scale: scale,
                                  icon: Icons.settings_rounded,
                                  iconColor: const Color(0xFFFFB800),
                                  title: "Settings",
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                                    );
                                  },
                                ),
                                Divider(height: 1, thickness: 0.8, color: Colors.black.withOpacity(0.06)),
                                _buildActionRow(
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

  // --- SHOW FRIENDS LIST BOTTOM SHEET (WITH UNFOLLOW/REMOVE ABILITY) ---
  void _showFriendsList(BuildContext context, String title, List<dynamic> initialUids, double scale, String currentUserId, bool isFollowingList) {
    List<dynamic> uids = List.from(initialUids);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFFF9E5),
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
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10))
                    ),
                  ),
                  SizedBox(height: 20 * scale),
                  Text(
                    title, 
                    style: TextStyle(
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
                              style: TextStyle(color: Colors.black54, fontSize: 14 * scale, fontWeight: FontWeight.w600, fontFamily: 'Inter')
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
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16 * scale),
                                      border: Border.all(color: Colors.black.withOpacity(0.04)),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 20 * scale,
                                          backgroundColor: const Color(0xFFFFEFA7),
                                          child: ClipOval(child: _buildAvatarImage(avatar, scale, size: 40)),
                                        ),
                                        SizedBox(width: 12 * scale),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name, 
                                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14 * scale, fontFamily: 'Inter'),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              SizedBox(height: 2 * scale),
                                              Row(
                                                children: [
                                                  Icon(Icons.bolt_rounded, size: 12 * scale, color: Colors.blue.shade400),
                                                  SizedBox(width: 2 * scale),
                                                  Text(
                                                    "$xp XP", 
                                                    style: TextStyle(color: Colors.blue.shade600, fontSize: 11 * scale, fontWeight: FontWeight.w700)
                                                  ),
                                                ],
                                              )
                                            ],
                                          ),
                                        ),
                                        // --- ACTION BUTTONS (UNFOLLOW vs REMOVE) ---
                                        SizedBox(width: 8 * scale),
                                        if (isFollowingList) 
                                          GestureDetector(
                                            onTap: () async {
                                              setState(() {
                                                uids.removeAt(index);
                                              });
                                              try {
                                                final currentRef = FirebaseFirestore.instance.collection('users').doc(currentUserId);
                                                final targetRef = FirebaseFirestore.instance.collection('users').doc(targetUid);
                                                final batch = FirebaseFirestore.instance.batch();
                                                
                                                batch.update(currentRef, {
                                                  'following': FieldValue.arrayRemove([targetUid]),
                                                  'outgoingRequests': FieldValue.arrayRemove([targetUid]),
                                                });
                                                
                                                batch.update(targetRef, {
                                                  'followers': FieldValue.arrayRemove([currentUserId]),
                                                  'incomingRequests': FieldValue.arrayRemove([currentUserId]),
                                                });
                                                await batch.commit();
                                              } catch (e) {
                                                debugPrint("Error unfollowing: $e");
                                              }
                                            },
                                            child: Container(
                                              padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(12 * scale),
                                              ),
                                              child: Text(
                                                "Unfollow", 
                                                style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 12 * scale, fontFamily: 'Inter')
                                              ),
                                            ),
                                          )
                                        else 
                                          GestureDetector(
                                            onTap: () async {
                                              // Optimistic UI Update for removing a follower
                                              setState(() {
                                                uids.removeAt(index);
                                              });
                                              try {
                                                final currentRef = FirebaseFirestore.instance.collection('users').doc(currentUserId);
                                                final targetRef = FirebaseFirestore.instance.collection('users').doc(targetUid);
                                                final batch = FirebaseFirestore.instance.batch();
                                                
                                                // Remove the target user from YOUR followers list
                                                batch.update(currentRef, {
                                                  'followers': FieldValue.arrayRemove([targetUid]),
                                                });
                                                
                                                // Remove YOU from the target user's following list
                                                batch.update(targetRef, {
                                                  'following': FieldValue.arrayRemove([currentUserId]),
                                                });
                                                await batch.commit();
                                              } catch (e) {
                                                debugPrint("Error removing follower: $e");
                                              }
                                            },
                                            child: Container(
                                              padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(12 * scale),
                                              ),
                                              child: Text(
                                                "Remove", 
                                                style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 12 * scale, fontFamily: 'Inter')
                                              ),
                                            ),
                                          ),
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

  // --- IOS ROW CELL VIEW ---
  Widget _buildActionRow({
    required double scale,
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
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
          color: isDestructive ? const Color(0xFFF34B1B) : Colors.black87,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14 * scale,
        color: Colors.black26,
      ),
    );
  }

  // --- EDIT AVATAR SHEET DIALOG (LOCAL IMAGE UPLOAD ONLY) ---
  void _showEditAvatarDialog(BuildContext context, User user, {String? currentAvatar, required double scale}) {
    final ImagePicker picker = ImagePicker();
    String selectedAvatarData = currentAvatar ?? ""; 

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isSaving = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFFFFFDF6),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24 * scale)),
              title: Row(
                children: [
                  Container(padding: EdgeInsets.all(6 * scale), decoration: BoxDecoration(color: const Color(0xFFFFB800).withOpacity(0.15), shape: BoxShape.circle), child: Icon(Icons.photo_camera_rounded, color: const Color(0xFFFFB800), size: 22 * scale)),
                  SizedBox(width: 10 * scale),
                  Text("Update Avatar", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19 * scale, fontFamily: 'Inter', color: Colors.black87)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- AVATAR UPLOAD PREVIEW ---
                  GestureDetector(
                    onTap: () async {
                      try {
                        final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 40);
                        if (image != null) {
                          final bytes = await image.readAsBytes();
                          final String base64Image = base64Encode(bytes);
                          
                          String mimeType = 'image/jpeg';
                          if (image.name.toLowerCase().endsWith('.png')) mimeType = 'image/png';
                          
                          setState(() {
                            selectedAvatarData = 'data:$mimeType;base64,$base64Image';
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
                        color: Colors.black.withOpacity(0.05),
                        border: Border.all(color: const Color(0xFFFFB800), width: 2),
                      ),
                      child: ClipOval(
                        child: selectedAvatarData.isNotEmpty
                            ? _buildAvatarImage(selectedAvatarData, scale, size: 80)
                            : Icon(Icons.add_a_photo_rounded, color: Colors.black45, size: 30 * scale),
                      ),
                    ),
                  ),
                  SizedBox(height: 8 * scale),
                  Text("Tap to upload photo", style: TextStyle(color: Colors.black45, fontSize: 11 * scale, fontWeight: FontWeight.w600)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                ),
                ElevatedButton(
                  onPressed: isSaving 
                    ? null 
                    : () async {
                        setState(() => isSaving = true);
                        try {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(user.uid)
                              .set({
                                'avatar': selectedAvatarData, 
                              }, SetOptions(merge: true));

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Avatar updated successfully!"), backgroundColor: Colors.green));
                          }
                        } catch (e) {
                          setState(() => isSaving = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error updating avatar: $e"), backgroundColor: Colors.red));
                          }
                        }
                      },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB800), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * scale))),
                  child: isSaving 
                      ? SizedBox(width: 18 * scale, height: 18 * scale, child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
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
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const SnedStudentLogin()), (route) => false);
  }

  // --- STAT ITEM WIDGET ---
  Widget _buildStatItem(double scale, String label, String value, IconData icon, Color elementColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: elementColor, size: 26 * scale), 
        SizedBox(height: 4 * scale),
        Text(
          value, 
          style: TextStyle(color: Colors.black87, fontSize: 22 * scale, fontWeight: FontWeight.w900, fontFamily: 'Inter')
        ),
        Text(
          label, 
          style: TextStyle(color: Colors.black45, fontSize: 11 * scale, fontWeight: FontWeight.w700, fontFamily: 'Inter')
        ),
      ],
    );
  }

  // --- BADGE WIDGET ---
  Widget _buildBadge(double scale, String label, String imagePath, {required bool isUnlocked}) {
    return Opacity(
      opacity: isUnlocked ? 1.0 : 0.3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 68 * scale, 
            height: 68 * scale,
            decoration: BoxDecoration(
              color: isUnlocked ? Colors.white.withOpacity(0.8) : Colors.black.withOpacity(0.04), 
              borderRadius: BorderRadius.circular(16 * scale),
              border: Border.all(
                color: isUnlocked ? const Color(0xFFFFB800).withOpacity(0.5) : Colors.transparent, 
                width: 1.5 * scale
              ),
              boxShadow: isUnlocked ? [
                BoxShadow(color: const Color(0xFFFFB800).withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 3))
              ] : null,
              image: DecorationImage(image: AssetImage(imagePath), fit: BoxFit.contain),
            ),
          ),
          SizedBox(height: 6 * scale),
          Text(
            label, 
            textAlign: TextAlign.center, 
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.black87, 
              fontSize: 11 * scale, 
              fontFamily: 'Inter',
              fontWeight: isUnlocked ? FontWeight.w800 : FontWeight.w600
            )
          ),
        ],
      ),
    );
  }
}