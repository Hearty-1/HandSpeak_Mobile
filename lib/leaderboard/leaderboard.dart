import 'dart:ui'; // Crucial for structural ImageFilter blurs
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import '../services/progress_service.dart'; 
import '../home/home.dart';
import '../module/module.dart';
import '../profile/profile.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _activeLeaderboardTab = 'weekly'; 
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _checkAndResetDailyStats(); 
  }

  // ==========================================
  // STREAK & DAILY RESET LOGIC (Maintained)
  // ==========================================
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
              'lastActiveDate': FieldValue.serverTimestamp(),
            };
            
            if (difference == 1) {
              updates['streak'] = currentStreak + 1;
            } else if (difference > 1) {
              updates['streak'] = 1; 
            }
            
            await userRef.update(updates);
          }
        } else {
          await userRef.update({
            'lastActiveDate': FieldValue.serverTimestamp(),
            'streak': 1,
            'dailyXp': 0,
            'completedLessons': 0,
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

    final String xpSortField = _activeLeaderboardTab == 'weekly' ? 'weeklyXp' : 'dailyXp';

    return Scaffold(
      extendBodyBehindAppBar: true, 
      extendBody: true, 
      backgroundColor: const Color(0xFFFFF9E5),
      
      // --- PREMIUM GLASS APP BAR ---
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.4),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: true, 
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded, 
                  color: Colors.black87, 
                  size: 20,
                ),
                onPressed: () => Navigator.maybePop(context),
              )
            : null,
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
          "Leaderboard",
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
                child: Image.asset("assets/pictures/image 66.png", width: 40, height: 40, fit: BoxFit.cover,
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
                      onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const SnedInterafce1(userName: "Student")), (route) => false),
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_stories_rounded, color: Colors.black45, size: 28), 
                      onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SnedInterface2())),
                    ),
                    IconButton(
                      icon: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFB800), size: 30), 
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.person_rounded, color: Colors.black45, size: 28), 
                      onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProfileScreen())),
                    ),
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
                top: 120 * scale, right: -40 * scale,
                child: Container(
                  width: 200 * scale, height: 200 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFB800).withOpacity(0.25),
                  ),
                ),
              ),
              Positioned(
                top: 400 * scale, left: -60 * scale,
                child: Container(
                  width: 240 * scale, height: 240 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF34B1B).withOpacity(0.12),
                  ),
                ),
              ),

              SafeArea(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: ProgressService().getUserProgressStream(),
                  builder: (context, userSnapshot) {
                    int currentStreak = 0;
                    int dailyXp = 0;
                    int completedLessons = 0;

                    if (userSnapshot.hasData && userSnapshot.data!.exists) {
                      final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                      if (userData != null) {
                        currentStreak = userData['streak'] ?? 0;
                        dailyXp = userData['dailyXp'] ?? 0;
                        completedLessons = userData['completedLessons'] ?? 0;
                      }
                    }

                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .orderBy(xpSortField, descending: true)
                          .limit(10)
                          .snapshots(),
                      builder: (context, leaderboardSnapshot) {
                        List<Map<String, dynamic>> players = [];
                        if (leaderboardSnapshot.hasData) {
                          players = leaderboardSnapshot.data!.docs.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return {
                              'uid': doc.id,
                              'name': data['name'] ?? 'Anonymous',
                              'xp': data[xpSortField] ?? 0,
                            };
                          }).toList();
                        }

                        if (players.isEmpty) {
                          players = [
                            {'uid': '1', 'name': 'Jane Doe', 'xp': 2019},
                            {'uid': '2', 'name': 'Alice G.', 'xp': 1932},
                            {'uid': '3', 'name': 'Bob M.', 'xp': 1431},
                            {'uid': '4', 'name': 'Sarah Lee', 'xp': 1205},
                            {'uid': _currentUserId, 'name': 'You', 'xp': dailyXp},
                            {'uid': '6', 'name': 'Mike Chen', 'xp': 890},
                          ];
                          players.sort((a, b) => b['xp'].compareTo(a['xp']));
                        }

                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.only(
                            left: 20 * scale, 
                            right: 20 * scale, 
                            top: 12 * scale, 
                            bottom: 110 * scale 
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Compete in real time with fellow learners!',
                                style: TextStyle(
                                  color: Colors.black.withOpacity(0.5),
                                  fontSize: 14 * scale,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Inter',
                                ),
                              ),
                              SizedBox(height: 16 * scale),

                              _buildLeaderboardTabs(scale),
                              SizedBox(height: 20 * scale),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildStatCard(scale, '🔥', '$currentStreak DAYS', 'Streak Active', const Color(0xFFFF8227)),
                                  _buildStatCard(scale, '⚡', '$dailyXp XP Today', 'Daily Progress', const Color(0xFFF34B1B)),
                                ],
                              ),
                              
                              SizedBox(height: 16 * scale),
                              _buildDailyQuestsCard(scale, dailyXp, completedLessons, currentStreak),
                              SizedBox(height: 24 * scale),

                              // --- THE PODIUM DOCK DISPLAY ---
                              Container(
                                height: 260 * scale, 
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    if (players.isNotEmpty)
                                      Positioned(
                                        bottom: 0,
                                        child: _buildPodiumColumn(scale, players[0]['name'], '${players[0]['xp']} XP', 1, const Color(0xFFFFB800), 145 * scale),
                                      ),
                                    if (players.length > 1)
                                      Positioned(
                                        left: 4 * scale,
                                        bottom: 0,
                                        child: _buildPodiumColumn(scale, players[1]['name'], '${players[1]['xp']} XP', 2, const Color(0xFFBAC3D6), 115 * scale),
                                      ),
                                    if (players.length > 2)
                                      Positioned(
                                        right: 4 * scale,
                                        bottom: 0,
                                        child: _buildPodiumColumn(scale, players[2]['name'], '${players[2]['xp']} XP', 3, const Color(0xFFFF8227), 95 * scale),
                                      ),
                                  ],
                                ),
                              ),

                              SizedBox(height: 24 * scale),

                              // --- GLASS LIST CONTAINER ---
                              ClipRRect(
                                borderRadius: BorderRadius.circular(24 * scale),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.4),
                                      borderRadius: BorderRadius.circular(24 * scale),
                                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5 * scale),
                                    ),
                                    child: Column(
                                      children: List.generate(
                                        players.length > 3 ? players.length - 3 : 0,
                                        (index) {
                                          final playerIndex = index + 3;
                                          final player = players[playerIndex];
                                          final isCurrent = player['uid'] == _currentUserId;

                                          return Column(
                                            children: [
                                              _buildListRow(
                                                scale, 
                                                playerIndex + 1, 
                                                player['name'], 
                                                '${player['xp']} XP', 
                                                isCurrent
                                              ),
                                              if (playerIndex < players.length - 1) _buildDivider(),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLeaderboardTabs(double scale) {
    return Container(
      height: 48 * scale,
      padding: EdgeInsets.all(4 * scale),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16 * scale),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeLeaderboardTab = 'weekly'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _activeLeaderboardTab == 'weekly' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12 * scale),
                  boxShadow: _activeLeaderboardTab == 'weekly' 
                    ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))]
                    : null,
                ),
                child: Text(
                  'Weekly League',
                  style: TextStyle(
                    fontSize: 14 * scale,
                    fontWeight: _activeLeaderboardTab == 'weekly' ? FontWeight.w800 : FontWeight.w600,
                    fontFamily: 'Inter',
                    color: _activeLeaderboardTab == 'weekly' ? Colors.black : Colors.black45,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeLeaderboardTab = 'daily'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _activeLeaderboardTab == 'daily' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12 * scale),
                  boxShadow: _activeLeaderboardTab == 'daily' 
                    ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))]
                    : null,
                ),
                child: Text(
                  'Daily Rank',
                  style: TextStyle(
                    fontSize: 14 * scale,
                    fontWeight: _activeLeaderboardTab == 'daily' ? FontWeight.w800 : FontWeight.w600,
                    fontFamily: 'Inter',
                    color: _activeLeaderboardTab == 'daily' ? Colors.black : Colors.black45,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyQuestsCard(double scale, int dailyXp, int completedLessons, int currentStreak) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20 * scale),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale), 
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.4),
            borderRadius: BorderRadius.circular(20 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5 * scale),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily Quests',
                    style: TextStyle(
                      fontSize: 16 * scale, 
                      fontWeight: FontWeight.w800, 
                      fontFamily: 'Inter',
                      color: Colors.black,
                      letterSpacing: -0.4
                    ),
                  ),
                  const Icon(Icons.stars_rounded, color: Color(0xFFFFB800), size: 20),
                ],
              ),
              SizedBox(height: 4 * scale),
              _buildQuestRow(scale, '⚡ Earn 50 XP today', dailyXp, 50),
              _buildDivider(),
              _buildQuestRow(scale, '📚 Complete 1 lesson', completedLessons, 1),
              _buildDivider(),
              _buildQuestRow(scale, '🔥 Reach a 3-Day streak', currentStreak, 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestRow(double scale, String description, int currentVal, int targetVal) {
    double progressRatio = (currentVal / targetVal).clamp(0.0, 1.0);
    bool isCompleted = progressRatio >= 1.0;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8 * scale), 
      child: Row(
        children: [
          Icon(
            isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: isCompleted ? const Color(0xFF27AE60) : Colors.black26,
            size: 20 * scale,
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                    color: isCompleted ? Colors.black38 : Colors.black87,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
                SizedBox(height: 4 * scale),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10 * scale),
                  child: LinearProgressIndicator(
                    value: progressRatio,
                    backgroundColor: Colors.black.withOpacity(0.05),
                    color: isCompleted ? const Color(0xFF27AE60) : const Color(0xFFFFB800),
                    minHeight: 5 * scale, 
                  ),
                )
              ],
            ),
          ),
          SizedBox(width: 12 * scale),
          Text(
            '$currentVal/$targetVal',
            style: TextStyle(
              fontSize: 12 * scale, 
              fontWeight: FontWeight.w800, 
              fontFamily: 'Inter',
              color: Colors.black45
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatCard(double scale, String emoji, String value, String label, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20 * scale),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: 170 * scale,
          padding: EdgeInsets.symmetric(vertical: 14 * scale, horizontal: 14 * scale),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.4),
            borderRadius: BorderRadius.circular(20 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5 * scale),
          ),
          child: Row(
            children: [
              Text(emoji, style: TextStyle(fontSize: 24 * scale)),
              SizedBox(width: 10 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value, 
                      style: TextStyle(color: color, fontSize: 14 * scale, fontWeight: FontWeight.w800, fontFamily: 'Inter'),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2 * scale),
                    Text(
                      label, 
                      style: TextStyle(color: Colors.black45, fontSize: 11 * scale, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // --- UPDATED FLOATING BADGE DISPLAY TO SHOW XP POINTS ---
  Widget _buildPodiumColumn(double scale, String name, String pts, int rank, Color themeColor, double columnHeight) {
    return SizedBox(
      width: 110 * scale,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 12 * scale),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: themeColor, width: 3.0 * scale),
                    boxShadow: [
                      BoxShadow(color: themeColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))
                    ]
                  ),
                  child: CircleAvatar(
                    radius: rank == 1 ? 35 * scale : 29 * scale,
                    backgroundColor: Colors.white.withOpacity(0.7),
                    child: Icon(Icons.person_rounded, color: Colors.black45, size: rank == 1 ? 42 * scale : 34 * scale),
                  ),
                ),
              ),
              
              // --- THIS BADGE NOW DISPLAYS THE XP POINTS INSTEAD OF RANK NUMBER ---
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
                decoration: BoxDecoration(
                  color: themeColor, 
                  borderRadius: BorderRadius.circular(10 * scale),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))
                  ]
                ),
                child: Text(
                  pts, // Swap out '$rank' for the 'pts' string (e.g. "2019 XP")
                  style: TextStyle(
                    color: Colors.white, 
                    fontSize: 9.5 * scale, // Scaled down to cleanly fit the full XP text
                    fontWeight: FontWeight.w900, 
                    fontFamily: 'Inter',
                  ),
                ),
              )
            ],
          ),
          SizedBox(height: 4 * scale),
          
          ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(18 * scale)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                height: columnHeight,
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 12 * scale),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      themeColor.withOpacity(0.35), 
                      themeColor.withOpacity(0.08),
                    ]
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18 * scale)),
                  border: Border(
                    top: BorderSide(color: themeColor.withOpacity(0.8), width: 2.5 * scale),
                    left: BorderSide(color: themeColor.withOpacity(0.4), width: 1.5 * scale),
                    right: BorderSide(color: themeColor.withOpacity(0.4), width: 1.5 * scale),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, 
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded, 
                      color: themeColor.withOpacity(0.6), 
                      size: rank == 1 ? 32 * scale : 24 * scale
                    ),
                    SizedBox(height: 8 * scale),
                    Text(
                      name, 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis, 
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13 * scale, fontFamily: 'Inter', color: Colors.black87)
                    ),
                    SizedBox(height: 2 * scale),
                    Text(
                      pts, 
                      style: TextStyle(color: themeColor == const Color(0xFFBAC3D6) ? Colors.black54 : themeColor, fontSize: 12 * scale, fontWeight: FontWeight.w800, fontFamily: 'Inter')
                    ),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildListRow(double scale, int rank, String name, String pts, bool isCurrentUser) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 15 * scale),
      decoration: BoxDecoration(
        color: isCurrentUser ? const Color(0xFFFFB800).withOpacity(0.12) : Colors.transparent,
        border: isCurrentUser ? Border.symmetric(horizontal: BorderSide(color: const Color(0xFFFFB800).withOpacity(0.2), width: 1)) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24 * scale,
            child: Text(
              '$rank', 
              style: TextStyle(
                fontSize: 15 * scale, 
                fontWeight: FontWeight.w800, 
                fontFamily: 'Inter', 
                color: isCurrentUser ? const Color(0xFFFFB800) : Colors.black45
              ),
            ),
          ),
          SizedBox(width: 8 * scale),
          CircleAvatar(
            radius: 18 * scale, 
            backgroundColor: Colors.white.withOpacity(0.5), 
            child: Icon(Icons.person_rounded, size: 22 * scale, color: Colors.black38)
          ),
          SizedBox(width: 14 * scale),
          Expanded(
            child: Text(
              name, 
              style: TextStyle(
                fontSize: 15 * scale, 
                fontWeight: isCurrentUser ? FontWeight.w800 : FontWeight.w600, 
                fontFamily: 'Inter',
                color: Colors.black,
              ),
            ),
          ),
          Text(
            pts, 
            style: TextStyle(
              fontSize: 14 * scale, 
              fontWeight: FontWeight.w800, 
              fontFamily: 'Inter',
              color: const Color(0xFFFFB800)
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() => Divider(height: 1, thickness: 0.8, color: Colors.black.withOpacity(0.05));
}