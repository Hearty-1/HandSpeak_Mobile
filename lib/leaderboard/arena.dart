import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/progress_service.dart';
import '../home/home.dart';
import '../module/module.dart';
import '../profile/profile.dart';
import '../profile/add_friend_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  final String initialTab;

  const LeaderboardScreen({
    super.key,
    this.initialTab = 'rankings',
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late String _mainHubTab;
  String _rankTimeframe = 'weekly'; // 'weekly' or 'alltime'

  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _mainHubTab = widget.initialTab;
    _checkAndResetDailyStats();
  }
  
  /// Helper to safely build avatars, including Base64 database strings
  Widget _buildSafeAvatar({
    required String? photoUrl,
    required String name,
    required double radius,
    Color textColor = Colors.black54,
  }) {
    Widget fallback = CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE5E7EB),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : "?",
        style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: radius * 0.8),
      ),
    );

    if (photoUrl == null || photoUrl.isEmpty) {
      return fallback;
    }

    Widget imageWidget;

    if (photoUrl.startsWith('data:image')) {
      // Handle Base64 Database Image
      try {
        final String base64String = photoUrl.split(',').last;
        imageWidget = Image.memory(
          base64Decode(base64String),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback,
        );
      } catch (e) {
        return fallback; 
      }
    } else if (photoUrl.startsWith('http')) {
      // Handle Network URL
      imageWidget = Image.network(
        photoUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } else {
      // Handle Local Asset
      imageWidget = Image.asset(
        photoUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    return ClipOval(child: imageWidget);
  }

  /// Pool of available challenges for dynamic daily assignment
  List<Map<String, dynamic>> _generateRandomChallenges() {
    final List<Map<String, dynamic>> challengePool = [
      {'id': 'lessons', 'title': 'Complete 3 Lessons', 'target': 3, 'reward': 50},
      {'id': 'stars', 'title': 'Earn 5 Stars Today', 'target': 5, 'reward': 75},
      {'id': 'xp', 'title': 'Earn 100 XP Today', 'target': 100, 'reward': 100},
      {'id': 'perfect', 'title': 'Get 1 Perfect Quiz', 'target': 1, 'reward': 150},
      {'id': 'lessons', 'title': 'Complete 1 Lesson', 'target': 1, 'reward': 20},
      {'id': 'stars', 'title': 'Earn 3 Stars Today', 'target': 3, 'reward': 40},
    ];

    challengePool.shuffle(Random());
    return challengePool.take(2).toList();
  }

  /// Checks if a new calendar day has started and updates daily stats & challenges
  Future<void> _checkAndResetDailyStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      final snapshot = await userRef.get();
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final Timestamp? lastActiveTimestamp = data['lastActiveDate'];
        final int currentStreak = data['streak'] ?? 0;

        final DateTime now = DateTime.now();
        final DateTime today = DateTime(now.year, now.month, now.day);

        if (lastActiveTimestamp != null) {
          final DateTime lastDate = lastActiveTimestamp.toDate();
          final DateTime lastActiveDay = DateTime(lastDate.year, lastDate.month, lastDate.day);
          final int difference = today.difference(lastActiveDay).inDays;

          if (difference > 0) {
            Map<String, dynamic> updates = {
              'dailyXp': 0,
              'completedLessons': 0,
              'dailyStars': 0,
              'perfectScores': 0,
              'lastActiveDate': FieldValue.serverTimestamp(),
              'dailyChallenges': _generateRandomChallenges(),
            };

            if (difference == 1) {
              updates['streak'] = currentStreak + 1;
            } else if (difference > 1) {
              updates['streak'] = 1;
            }

            await userRef.update(updates);
          } else if (data['dailyChallenges'] == null) {
            // Assign initial challenges if field is missing for today
            await userRef.update({
              'dailyChallenges': _generateRandomChallenges(),
            });
          }
        } else {
          // First-time initialization
          await userRef.update({
            'lastActiveDate': FieldValue.serverTimestamp(),
            'streak': 1,
            'dailyXp': 0,
            'completedLessons': 0,
            'dailyStars': 0,
            'perfectScores': 0,
            'dailyChallenges': _generateRandomChallenges(),
          });
        }
      }
    } catch (e) {
      debugPrint("Error updating daily stats: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    const double baseWidth = 393;
    final double scale = screenWidth / baseWidth > 1.2 ? 1.2 : screenWidth / baseWidth;

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      backgroundColor: const Color(0xFFFFF9E5),
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
          "Student Arena",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
            fontSize: 22,
            letterSpacing: -0.5,
          ),
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
          height: 76,
          margin: EdgeInsets.only(bottom: 12 * scale, left: 16 * scale, right: 16 * scale),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30 * scale),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(30 * scale),
                  border: Border.all(color: Colors.white, width: 2 * scale),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 6)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavIconButton(Icons.home_rounded, false, () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const SnedInterafce1(userName: "Student")), (route) => false)),
                    _buildNavIconButton(Icons.auto_stories_rounded, false, () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SnedInterface2()))),
                    _buildNavIconButton(Icons.sports_esports_rounded, true, () {}),
                    _buildNavIconButton(Icons.person_rounded, false, () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProfileScreen()))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),

      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Positioned(
                top: 100 * scale, right: -30 * scale,
                child: Container(
                  width: 180 * scale, height: 180 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFB800).withOpacity(0.20),
                  ),
                ),
              ),
              Positioned(
                top: 380 * scale, left: -50 * scale,
                child: Container(
                  width: 220 * scale, height: 220 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF34B1B).withOpacity(0.12),
                  ),
                ),
              ),

              SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: 20 * scale,
                    right: 20 * scale,
                    top: 12 * scale,
                    bottom: 110 * scale,
                  ),
                  child: Column(
                    children: [
                      _buildMainHubSegmentControl(scale),
                      SizedBox(height: 16 * scale),

                      _mainHubTab == 'rankings'
                          ? _buildLeaderboardTimeframeToggle(scale)
                          : const SizedBox.shrink(),

                      SizedBox(height: 18 * scale),

                      _mainHubTab == 'rankings'
                          ? _buildRankingsView(scale)
                          : _buildChallengesView(scale),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNavIconButton(IconData icon, bool isSelected, VoidCallback onPressed) {
    return Container(
      decoration: isSelected ? BoxDecoration(
        color: const Color(0xFFFFB800).withOpacity(0.18),
        shape: BoxShape.circle,
      ) : null,
      child: IconButton(
        icon: Icon(
          icon,
          color: isSelected ? const Color(0xFFFFB800) : Colors.black38,
          size: isSelected ? 32 : 28,
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildMainHubSegmentControl(double scale) {
    return Container(
      height: 52 * scale,
      padding: EdgeInsets.all(4 * scale),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(22 * scale),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _mainHubTab = 'rankings'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _mainHubTab == 'rankings' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(18 * scale),
                  boxShadow: _mainHubTab == 'rankings'
                    ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 3))]
                    : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '🏆 Leaderboard',
                    style: TextStyle(
                      fontSize: 14.5 * scale,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Inter',
                      color: _mainHubTab == 'rankings' ? Colors.black : Colors.black45,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _mainHubTab = 'challenges'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _mainHubTab == 'challenges' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(18 * scale),
                  boxShadow: _mainHubTab == 'challenges'
                    ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 3))]
                    : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '🎯 Challenges',
                    style: TextStyle(
                      fontSize: 14.5 * scale,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Inter',
                      color: _mainHubTab == 'challenges' ? Colors.black : Colors.black45,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTimeframeToggle(double scale) {
    return Container(
      height: 44 * scale,
      padding: EdgeInsets.all(4 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16 * scale),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Row(
        children: [
          _buildSubTabOption('weekly', '📅 Weekly League', _rankTimeframe, (val) => setState(() => _rankTimeframe = val), scale),
          _buildSubTabOption('alltime', '🌍 Global Rank', _rankTimeframe, (val) => setState(() => _rankTimeframe = val), scale),
        ],
      ),
    );
  }

  Widget _buildSubTabOption(String id, String label, String currentValue, Function(String) onSelect, double scale) {
    bool isSelected = id == currentValue;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFB800) : Colors.transparent,
            borderRadius: BorderRadius.circular(12 * scale),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13 * scale,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                color: isSelected ? Colors.white : Colors.black45,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRankingsView(double scale) {
    return Column(
      children: [
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(_currentUserId).snapshots(),
          builder: (context, userSnapshot) {
            int currentUserXp = 0;
            int currentUserStreak = 0;

            if (userSnapshot.hasData && userSnapshot.data != null && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>;
              currentUserXp = userData[_rankTimeframe == 'weekly' ? 'dailyXp' : 'xp'] ?? 0;
              currentUserStreak = userData['streak'] ?? 0;
            }

            return Container(
              padding: EdgeInsets.all(16 * scale),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24 * scale),
                border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.4), width: 2 * scale),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFB800).withOpacity(0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildEnhancedStatBadge(
                      Icons.local_fire_department_rounded,
                      "$currentUserStreak",
                      "Day Streak",
                      const Color(0xFFF34B1B),
                      scale,
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: _buildEnhancedStatBadge(
                      Icons.star_rounded,
                      "$currentUserXp",
                      _rankTimeframe == 'weekly' ? "Weekly XP" : "Total XP",
                      const Color(0xFFFFB800),
                      scale,
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        SizedBox(height: 24 * scale),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _rankTimeframe == 'weekly' ? "Top Students This Week" : "Global Top Students",
              style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w900, fontFamily: 'Inter', color: Colors.black87),
            ),
            Icon(Icons.military_tech_rounded, color: const Color(0xFFFFB800), size: 24 * scale),
          ],
        ),
        SizedBox(height: 16 * scale),

        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .orderBy(_rankTimeframe == 'weekly' ? 'dailyXp' : 'xp', descending: true)
              .limit(50)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Padding(
                padding: EdgeInsets.all(20 * scale),
                child: const CircularProgressIndicator(color: Color(0xFFFFB800)),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Padding(
                padding: EdgeInsets.all(20 * scale),
                child: const Text("No leaderboard data available."),
              );
            }

            final docs = snapshot.data!.docs;
            final top3 = docs.take(3).toList();
            final remainingDocs = docs.skip(3).toList();

            return Column(
              children: [
                if (top3.isNotEmpty) _buildPodium(top3, scale),
                SizedBox(height: 20 * scale),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: remainingDocs.length,
                  itemBuilder: (context, index) {
                    final data = remainingDocs[index].data() as Map<String, dynamic>;
                    final int rank = index + 4;
                    final String playerName = data['displayName'] ?? data['name'] ?? "Student";
                    final int playerXp = data[_rankTimeframe == 'weekly' ? 'dailyXp' : 'xp'] ?? 0;
                    final String playerGrade = data['grade'] ?? "Player";
                    
                    final String? photoUrl = data['avatar'] ?? data['photoUrl'] ?? data['avatarUrl'];

                    return _buildLeaderboardTile(rank, playerName, playerGrade, playerXp, photoUrl, scale);
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildChallengesView(double scale) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChallengeCard(
            title: "Group Challenges",
            subtitle: "Team up & compete with friends",
            icon: Icons.groups_rounded,
            iconColor: const Color(0xFFF34B1B),
            xpText: "Earn XP",
            scale: scale,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const GroupChallengeHubScreen()),
              );
            },
          ),
          SizedBox(height: 16 * scale),

          _buildChallengeCard(
            title: "Solo Challenges",
            subtitle: "Test your skills independently",
            icon: Icons.person_rounded,
            iconColor: const Color(0xFFFFB800),
            xpText: "Earn XP",
            scale: scale,
            onTap: () {},
          ),

          SizedBox(height: 28 * scale),

          Row(
            children: [
              Text(
                "Daily Quests",
                style: TextStyle(
                  fontSize: 18 * scale,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Inter',
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Icon(Icons.local_fire_department_rounded, color: const Color(0xFFF34B1B), size: 24 * scale),
            ],
          ),
          SizedBox(height: 14 * scale),

          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(_currentUserId).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: EdgeInsets.all(20 * scale),
                  child: const Center(child: CircularProgressIndicator(color: Color(0xFFFFB800))),
                );
              }

              if (!snapshot.hasData || snapshot.data == null || !snapshot.data!.exists) {
                return const Text("No active challenges found.");
              }

              final data = snapshot.data!.data() as Map<String, dynamic>;

              int completedLessons = data['completedLessons'] ?? 0;
              int dailyXp = data['dailyXp'] ?? 0;
              int dailyStars = data['dailyStars'] ?? 0;
              int perfectScores = data['perfectScores'] ?? 0;

              List<dynamic> dailyChallenges = data['dailyChallenges'] ?? [];

              if (dailyChallenges.isEmpty) {
                return Padding(
                  padding: EdgeInsets.all(12 * scale),
                  child: const Text(
                    "Check back tomorrow for new daily quests!",
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
                  ),
                );
              }

              return Column(
                children: dailyChallenges.map((challenge) {
                  final String id = challenge['id'] ?? 'lessons';
                  final String title = challenge['title'] ?? 'Daily Quest';
                  final int target = challenge['target'] ?? 1;
                  final int reward = challenge['reward'] ?? 50;

                  int currentProgress = 0;
                  if (id == 'lessons') currentProgress = completedLessons;
                  else if (id == 'stars') currentProgress = dailyStars;
                  else if (id == 'xp') currentProgress = dailyXp;
                  else if (id == 'perfect') currentProgress = perfectScores;

                  return _buildDailyChallengeCard(title, reward, currentProgress, target, scale);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required String xpText,
    required double scale,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(18 * scale),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24 * scale),
          border: Border.all(color: Colors.black.withOpacity(0.04), width: 1.5 * scale),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 18,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60 * scale,
              height: 60 * scale,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18 * scale),
              ),
              child: Icon(icon, color: iconColor, size: 30 * scale),
            ),
            SizedBox(width: 16 * scale),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17 * scale,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Inter',
                      color: Colors.black87,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.w600,
                      color: Colors.black45,
                    ),
                  ),
                  SizedBox(height: 8 * scale),
                  Row(
                    children: [
                      Icon(Icons.star_rounded, color: const Color(0xFFFFB800), size: 16 * scale),
                      SizedBox(width: 4 * scale),
                      Text(
                        xpText,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFFFB800),
                          fontSize: 12.5 * scale,
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),

            Container(
              padding: EdgeInsets.all(8 * scale),
              decoration: const BoxDecoration(
                color: Color(0xFFF0F4F8),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14 * scale,
                color: Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyChallengeCard(String title, int xpReward, int currentProgress, int targetProgress, double scale) {
    double progressPercent = (currentProgress / targetProgress).clamp(0.0, 1.0);
    bool isComplete = currentProgress >= targetProgress;

    return Container(
      margin: EdgeInsets.only(bottom: 12 * scale),
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20 * scale),
        border: Border.all(color: Colors.black.withOpacity(0.04), width: 1.5 * scale),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44 * scale,
            height: 44 * scale,
            decoration: BoxDecoration(
              color: isComplete ? const Color(0xFF4CAF50).withOpacity(0.15) : const Color(0xFFF0F4F8),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isComplete ? Icons.check_circle_rounded : Icons.star_border_rounded,
              color: isComplete ? const Color(0xFF4CAF50) : Colors.black45,
              size: 22 * scale,
            ),
          ),
          SizedBox(width: 14 * scale),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5 * scale, color: Colors.black87)),
                    Text("+$xpReward XP", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5 * scale, color: const Color(0xFFFFB800))),
                  ],
                ),
                SizedBox(height: 8 * scale),

                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10 * scale),
                        child: LinearProgressIndicator(
                          value: progressPercent,
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isComplete ? const Color(0xFF4CAF50) : const Color(0xFFFFB800),
                          ),
                          minHeight: 8 * scale,
                        ),
                      ),
                    ),
                    SizedBox(width: 12 * scale),
                    Text(
                      "$currentProgress / $targetProgress",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12 * scale, color: Colors.black54),
                    )
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEnhancedStatBadge(IconData icon, String value, String label, Color color, double scale) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16 * scale),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5 * scale),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(6 * scale),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Icon(icon, color: color, size: 20 * scale),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18 * scale, color: Colors.black87, height: 1.1),
                ),
                Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11 * scale, color: color, height: 1.1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodium(List<QueryDocumentSnapshot> top3Docs, double scale) {
    Map<String, dynamic>? rank1 = top3Docs.isNotEmpty ? top3Docs[0].data() as Map<String, dynamic> : null;
    Map<String, dynamic>? rank2 = top3Docs.length > 1 ? top3Docs[1].data() as Map<String, dynamic> : null;
    Map<String, dynamic>? rank3 = top3Docs.length > 2 ? top3Docs[2].data() as Map<String, dynamic> : null;

    return Padding(
      padding: EdgeInsets.only(top: 20 * scale, bottom: 10 * scale),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (rank2 != null) _buildPodiumProfile(rank2, 2, 100, const Color(0xFFC0C0C0), scale),
          if (rank2 != null) SizedBox(width: 12 * scale),

          if (rank1 != null) _buildPodiumProfile(rank1, 1, 140, const Color(0xFFFFD700), scale),

          if (rank3 != null) SizedBox(width: 12 * scale),
          if (rank3 != null) _buildPodiumProfile(rank3, 3, 80, const Color(0xFFCD7F32), scale),
        ],
      ),
    );
  }

  Widget _buildPodiumProfile(Map<String, dynamic> data, int rank, double height, Color color, double scale) {
    String name = data['displayName'] ?? data['name'] ?? "User";
    int xp = data[_rankTimeframe == 'weekly' ? 'dailyXp' : 'xp'] ?? 0;
    
    String? photoUrl = data['avatar'] ?? data['photoUrl'] ?? data['avatarUrl'];

    if (name.length > 8) name = "${name.substring(0, 7)}...";

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (rank == 1)
          Icon(Icons.emoji_events_rounded, color: color, size: 32 * scale),

        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3 * scale),
          ),
          child: _buildSafeAvatar(
            photoUrl: photoUrl,
            name: name,
            radius: (rank == 1 ? 28 : 24) * scale,
            textColor: color,
          ),
        ),
        SizedBox(height: 8 * scale),

        Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13 * scale, color: Colors.black87)),
        Text("$xp XP", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12 * scale, color: color)),
        SizedBox(height: 8 * scale),

        Container(
          width: 70 * scale,
          height: height * scale,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12 * scale)),
            border: Border(
              top: BorderSide(color: color, width: 4 * scale),
              left: BorderSide(color: color.withOpacity(0.5), width: 1),
              right: BorderSide(color: color.withOpacity(0.5), width: 1),
            ),
          ),
          alignment: Alignment.topCenter,
          padding: EdgeInsets.only(top: 8 * scale),
          child: Text(
            "$rank",
            style: TextStyle(fontSize: 24 * scale, fontWeight: FontWeight.w900, color: color),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardTile(int rank, String name, String grade, int xp, String? photoUrl, double scale) {
    return Container(
      margin: EdgeInsets.only(bottom: 12 * scale),
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 14 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20 * scale),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 32 * scale, height: 32 * scale,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFF0F4F8),
              shape: BoxShape.circle,
            ),
            child: Text(
              "$rank",
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16 * scale, color: Colors.black54),
            ),
          ),
          SizedBox(width: 14 * scale),
          _buildSafeAvatar(
            photoUrl: photoUrl,
            name: name,
            radius: 20 * scale,
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15 * scale, color: Colors.black87)),
                Text(grade, style: TextStyle(fontSize: 12 * scale, color: Colors.black45, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Row(
            children: [
              Icon(Icons.star_rounded, color: const Color(0xFFFFB800), size: 18 * scale),
              SizedBox(width: 4 * scale),
              Text(
                "$xp",
                style: TextStyle(fontWeight: FontWeight.w900, color: const Color(0xFFFFB800), fontSize: 16 * scale),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- FUNCTIONAL GROUP CHALLENGE HUB SCREEN ---
class GroupChallengeHubScreen extends StatefulWidget {
  const GroupChallengeHubScreen({super.key});

  @override
  State<GroupChallengeHubScreen> createState() => _GroupChallengeHubScreenState();
}

class _GroupChallengeHubScreenState extends State<GroupChallengeHubScreen> {
  bool isJoinMode = true;
  bool isLoading = false;
  final TextEditingController _codeController = TextEditingController();
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Track friends selected for dynamic room invitation
  final List<String> _invitedFriendUids = [];

  Widget _buildSafeAvatar({
    required String? photoUrl,
    required String name,
    required double radius,
    Color textColor = Colors.black54,
  }) {
    Widget fallback = CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE5E7EB),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : "?",
        style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: radius * 0.8),
      ),
    );

    if (photoUrl == null || photoUrl.isEmpty) {
      return fallback;
    }

    Widget imageWidget;

    if (photoUrl.startsWith('data:image')) {
      try {
        final String base64String = photoUrl.split(',').last;
        imageWidget = Image.memory(
          base64Decode(base64String),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        );
      } catch (e) {
        return fallback; 
      }
    } else if (photoUrl.startsWith('http')) {
      imageWidget = Image.network(
        photoUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else {
      imageWidget = Image.asset(
        photoUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return ClipOval(child: imageWidget);
  }

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    Random rnd = Random();
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Future<void> _handleJoinRoom() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a room code.")));
      return;
    }

    setState(() => isLoading = true);

    try {
      final roomRef = FirebaseFirestore.instance.collection('rooms').doc(code);
      final roomSnapshot = await roomRef.get();

      if (!roomSnapshot.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Room code not found.")));
        }
        setState(() => isLoading = false);
        return;
      }

      await roomRef.update({
        'playerUids': FieldValue.arrayUnion([_currentUserId]),
      });

      if (mounted) {
        final data = roomSnapshot.data() as Map<String, dynamic>;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RoomLobbyScreen(
              roomCode: code,
              challengeTitle: data['title'] ?? "Group Challenge",
              isHost: data['hostUid'] == _currentUserId,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error joining room: $e")));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _handleCreateRoom() async {
    setState(() => isLoading = true);

    try {
      final String code = _generateRoomCode();
      const String title = "Classroom Challenge";

      await FirebaseFirestore.instance.collection('rooms').doc(code).set({
        'code': code,
        'title': title,
        'hostUid': _currentUserId,
        'playerUids': [_currentUserId],
        'invitedUids': _invitedFriendUids, // Saved list of selected player invites
        'status': 'waiting',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RoomLobbyScreen(
              roomCode: code,
              challengeTitle: title,
              isHost: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error creating room: $e")));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showInviteFriendsSheet() async {
    // 1. Fetch the logged-in user's document to get their follower/following lists
    DocumentSnapshot currentUserDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .get();

    if (!currentUserDoc.exists) return;

    Map<String, dynamic> currentUserData =
        currentUserDoc.data() as Map<String, dynamic>? ?? {};

    // Get arrays of UIDs from current user
    List<dynamic> myFollowers = currentUserData['followers'] ?? [];
    List<dynamic> myFollowing = currentUserData['following'] ?? [];

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Invite Friends",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                              child: Text('Error loading users: ${snapshot.error}'));
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFFFFB800)));
                        }

                        // Filter docs for MUTUAL FOLLOWERS
                        final users = snapshot.data!.docs.where((doc) {
                          final String otherUserId = doc.id;

                          // Skip current user
                          if (otherUserId == _currentUserId) return false;

                          final userData =
                              doc.data() as Map<String, dynamic>;

                          List<dynamic> targetFollowers =
                              userData['followers'] ?? [];
                          List<dynamic> targetFollowing =
                              userData['following'] ?? [];

                          // MUTUAL CHECK: 
                          // You follow them (their ID in your following OR your ID in their followers)
                          // AND They follow you (your ID in their following OR their ID in your followers)
                          bool iFollowThem = myFollowing.contains(otherUserId) ||
                              targetFollowers.contains(_currentUserId);

                          bool theyFollowMe = myFollowers.contains(otherUserId) ||
                              targetFollowing.contains(_currentUserId);

                          return iFollowThem && theyFollowMe;
                        }).toList();

                        if (users.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.group_off_rounded,
                                    size: 48, color: Colors.black26),
                                SizedBox(height: 12),
                                Text(
                                  "No mutual friends found.",
                                  style: TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Follow each other to invite them to games!",
                                  style: TextStyle(
                                      color: Colors.black45,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            final userData =
                                users[index].data() as Map<String, dynamic>;
                            final String uid = users[index].id;

                            // Parse display names based on your database schema
                            final String name = userData['firstName'] ??
                                userData['displayName'] ??
                                userData['name'] ??
                                'Student';

                            final String? photoUrl = userData['avatar'] ??
                                userData['photoUrl'] ??
                                userData['avatarUrl'];

                            final bool isSelected =
                                _invitedFriendUids.contains(uid);

                            // Online status check
                            final bool isOnline = userData['isOnline'] == true ||
                                userData['presence']
                                        ?.toString()
                                        .toLowerCase() ==
                                    'online' ||
                                userData['status']
                                        ?.toString()
                                        .toLowerCase() ==
                                    'online';

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: _buildSafeAvatar(
                                photoUrl: photoUrl,
                                name: name,
                                radius: 20,
                              ),
                              title: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 4,
                                    backgroundColor: isOnline
                                        ? const Color(0xFF4CAF50)
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isOnline ? "Online" : "Offline",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isOnline
                                          ? const Color(0xFF4CAF50)
                                          : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.circle_outlined,
                                  color: isSelected
                                      ? const Color(0xFF4CAF50)
                                      : Colors.black26,
                                ),
                                onPressed: () {
                                  setModalState(() {
                                    if (isSelected) {
                                      _invitedFriendUids.remove(uid);
                                    } else {
                                      _invitedFriendUids.add(uid);
                                    }
                                  });
                                  setState(() {});
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB800),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Text("Done",
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900)),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Group Challenges",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontFamily: 'Inter', fontSize: 20),
        ),
        centerTitle: true,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.06), width: 0.5)),
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(_currentUserId).snapshots(),
              builder: (context, snapshot) {
                int userXp = 0;
                int streak = 0;
                if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  userXp = data['xp'] ?? 0;
                  streak = data['streak'] ?? 0;
                }

                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 6))
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Classroom Challenge", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, fontFamily: 'Inter')),
                            const SizedBox(height: 6),
                            const Text("Join your teacher's room or host one for your group.", style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                _buildStatSquare("$userXp", "Your XP"),
                                const SizedBox(width: 10),
                                _buildStatSquare("$streak 🔥", "Streak"),
                              ],
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB800).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.groups_rounded, size: 36, color: Color(0xFFFFB800)),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            Container(
              height: 48,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => isJoinMode = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isJoinMode ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: isJoinMode ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))] : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.login_rounded, color: isJoinMode ? const Color(0xFFF34B1B) : Colors.black45, size: 18),
                            const SizedBox(width: 6),
                            Text("Join Room", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isJoinMode ? Colors.black87 : Colors.black45)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => isJoinMode = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: !isJoinMode ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: !isJoinMode ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))] : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline_rounded, color: !isJoinMode ? const Color(0xFFF34B1B) : Colors.black45, size: 18),
                            const SizedBox(width: 6),
                            Text("Create Room", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: !isJoinMode ? Colors.black87 : Colors.black45)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            isJoinMode ? _buildJoinView() : _buildCreateView(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatSquare(String val, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB800).withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(val, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.black87)),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFFB800))),
        ],
      ),
    );
  }

  Widget _buildJoinView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Enter Room Code", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.black87)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: "e.g. FSL001",
                    hintStyle: const TextStyle(color: Colors.black38, fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: isLoading ? null : _handleJoinRoom,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF34B1B),
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
            )
          ],
        ),
      ],
    );
  }

  Widget _buildCreateView() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF34B1B).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_circle_rounded, size: 36, color: Color(0xFFF34B1B)),
          ),
          const SizedBox(height: 12),
          const Text("Host a Challenge", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, fontFamily: 'Inter')),
          const SizedBox(height: 6),
          const Text("Create a custom room and invite friends to compete.", textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 13)),
          
          const SizedBox(height: 20),
          
          // Invite Friends Selection Field
          InkWell(
            onTap: _showInviteFriendsSheet,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black.withOpacity(0.08)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_add_rounded, color: Color(0xFFF34B1B), size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text("Invite Players", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                  if (_invitedFriendUids.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "${_invitedFriendUids.length} Selected", 
                        style: const TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    )
                  else
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black38),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: isLoading ? null : _handleCreateRoom,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB800),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text("+ Create New Room", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          )
        ],
      ),
    );
  }
}

// --- FUNCTIONAL ROOM LOBBY SCREEN ---
class RoomLobbyScreen extends StatelessWidget {
  final String roomCode;
  final String challengeTitle;
  final bool isHost;

  const RoomLobbyScreen({
    super.key,
    required this.roomCode,
    required this.challengeTitle,
    this.isHost = false,
  });

  Widget _buildSafeAvatar({
    required String? photoUrl,
    required String name,
    required double radius,
  }) {
    Widget fallback = CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE5E7EB),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : "?",
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: radius * 0.8),
      ),
    );

    if (photoUrl == null || photoUrl.isEmpty) {
      return fallback;
    }

    Widget imageWidget;

    if (photoUrl.startsWith('data:image')) {
      try {
        final String base64String = photoUrl.split(',').last;
        imageWidget = Image.memory(
          base64Decode(base64String),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        );
      } catch (e) {
        return fallback; 
      }
    } else if (photoUrl.startsWith('http')) {
      imageWidget = Image.network(
        photoUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else {
      imageWidget = Image.asset(
        photoUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return ClipOval(child: imageWidget);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Room Lobby",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontFamily: 'Inter'),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('rooms').doc(roomCode).snapshots(),
        builder: (context, roomSnapshot) {
          if (roomSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB800)));
          }

          if (!roomSnapshot.hasData || !roomSnapshot.data!.exists) {
            return const Center(child: Text("Room no longer exists."));
          }

          final roomData = roomSnapshot.data!.data() as Map<String, dynamic>;
          final List<dynamic> playerUids = roomData['playerUids'] ?? [];
          final String hostUid = roomData['hostUid'] ?? '';

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 5))],
                    ),
                    child: Column(
                      children: [
                        Text(
                          challengeTitle,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildInfoPill("Room Code", roomCode),
                            const SizedBox(width: 12),
                            _buildInfoPill("Players", "${playerUids.length}/10"),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Players Waiting (${playerUids.length})",
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Expanded(
                    child: playerUids.isEmpty
                        ? const Center(child: Text("Waiting for players to join..."))
                        : StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .where(FieldPath.documentId, whereIn: playerUids)
                                .snapshots(),
                            builder: (context, playersSnapshot) {
                              if (playersSnapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB800)));
                              }

                              final playerDocs = playersSnapshot.data?.docs ?? [];

                              return ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                itemCount: playerDocs.length,
                                itemBuilder: (context, index) {
                                  final pData = playerDocs[index].data() as Map<String, dynamic>;
                                  final String uid = playerDocs[index].id;
                                  final String name = pData['displayName'] ?? pData['name'] ?? "Student";
                                  
                                  final String? photoUrl = pData['avatar'] ?? pData['photoUrl'] ?? pData['avatarUrl'];
                                  final bool playerIsHost = uid == hostUid;

                                  return _buildPlayerTile(name, playerIsHost, photoUrl);
                                },
                              );
                            },
                          ),
                  ),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: isHost
                          ? () async {
                              await FirebaseFirestore.instance.collection('rooms').doc(roomCode).update({
                                'status': 'active',
                              });
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isHost ? const Color(0xFFF34B1B) : Colors.grey.shade400,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        elevation: 0,
                      ),
                      child: Text(
                        isHost ? "START MATCH" : "WAITING FOR HOST...",
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoPill(String topText, String bottomText) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4F8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(topText, style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(bottomText, style: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerTile(String name, bool playerIsHost, String? photoUrl) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          _buildSafeAvatar(
            photoUrl: photoUrl,
            name: name,
            radius: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.black87),
            ),
          ),
          if (playerIsHost)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB800).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text("HOST", style: TextStyle(color: Color(0xFFFFB800), fontWeight: FontWeight.w900, fontSize: 11)),
            )
          else
            const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 22)
        ],
      ),
    );
  }
}