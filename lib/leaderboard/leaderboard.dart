import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import '../services/progress_service.dart'; // Ensure this service exists or adjust imports
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
    // RUNS AUTOMATICALLY WHEN THE SCREEN LOADS
    _checkAndResetDailyStats(); 
  }

  // ==========================================
  // STREAK & DAILY RESET LOGIC
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
        
        // Get Midnight of today to ensure time-of-day doesn't mess up the streak
        final DateTime now = DateTime.now();
        final DateTime today = DateTime(now.year, now.month, now.day);
        
        if (lastActiveTimestamp != null) {
          final DateTime lastDate = lastActiveTimestamp.toDate();
          final DateTime lastActiveDay = DateTime(lastDate.year, lastDate.month, lastDate.day);
          
          final int difference = today.difference(lastActiveDay).inDays;
          
          if (difference > 0) {
            // It is a brand new day! Reset daily goals.
            Map<String, dynamic> updates = {
              'dailyXp': 0, 
              'completedLessons': 0,
              'lastActiveDate': FieldValue.serverTimestamp(),
            };
            
            if (difference == 1) {
              // Logged in exactly one day later - Streak continues!
              updates['streak'] = currentStreak + 1;
            } else if (difference > 1) {
              // Missed a day - Streak broken!
              updates['streak'] = 1; 
            }
            
            await userRef.update(updates);
          }
        } else {
          // First time they've ever opened the app
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
    final double scale = screenWidth / 393 > 1.2 ? 1.2 : screenWidth / 393; 

    final String xpSortField = _activeLeaderboardTab == 'weekly' ? 'weeklyXp' : 'dailyXp';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      
      // --- NEW APP BAR ADDED HERE ---
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFB800),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Leaderboard",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Image.asset("assets/pictures/image 66.png", width: 45),
          ),
        ],
      ),

      // --- 4-TAB BOTTOM NAVIGATION BAR ---
      bottomNavigationBar: SafeArea(
        child: Container(
          width: double.infinity,
          height: 78,
          margin: const EdgeInsets.only(bottom: 12, left: 10, right: 10),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            shadows: const [
              BoxShadow(
                color: Color(0x0C132C4A),
                blurRadius: 16,
                offset: Offset(0, 5),
              )
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.home, color: Colors.grey, size: 28), 
                onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const SnedInterafce1(userName: "Student")), (route) => false),
              ),
              IconButton(
                icon: const Icon(Icons.auto_stories, color: Colors.grey, size: 28), 
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SnedInterface2())),
              ),
              IconButton(
                icon: const Icon(Icons.emoji_events, color: Colors.black, size: 28), 
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.person, color: Colors.grey, size: 28), 
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProfileScreen())),
              ),
            ],
          ),
        ),
      ),

      body: SafeArea(
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
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 20 * scale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Subtitle kept, Main title removed to prevent duplication with AppBar
                      Text(
                        'Compete in real time with fellow learners!',
                        style: TextStyle(
                          color: const Color(0x99222222),
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 15 * scale),

                      _buildLeaderboardTabs(scale),
                      SizedBox(height: 20 * scale),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatCard(scale, '🔥', '$currentStreak DAYS', 'Streak Active', const Color(0xFFFF8227)),
                          _buildStatCard(scale, '🎯', '$dailyXp XP Today', 'Daily Goal Progress', const Color(0xFFF34B1B)),
                        ],
                      ),
                      
                      SizedBox(height: 25 * scale),
                      _buildDailyQuestsCard(scale, dailyXp, completedLessons, currentStreak),
                      SizedBox(height: 35 * scale),

                      SizedBox(
                        height: 220 * scale,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            if (players.length > 1)
                              Positioned(
                                left: 10 * scale,
                                bottom: 0,
                                child: _buildPodiumAvatar(scale, players[1]['name'], '${players[1]['xp']} pts', 2, const Color(0xFFF34B1B), 70, 60),
                              ),
                            if (players.length > 2)
                              Positioned(
                                right: 10 * scale,
                                bottom: 0,
                                child: _buildPodiumAvatar(scale, players[2]['name'], '${players[2]['xp']} pts', 3, const Color(0xFFFF8227), 60, 50),
                              ),
                            if (players.isNotEmpty)
                              Positioned(
                                bottom: 20 * scale,
                                child: _buildPodiumAvatar(scale, players[0]['name'], '${players[0]['xp']} pts', 1, const Color(0xFFFFCA28), 90, 80),
                              ),
                          ],
                        ),
                      ),

                      SizedBox(height: 30 * scale),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24 * scale),
                          boxShadow: const [
                            BoxShadow(color: Color(0x0A000000), blurRadius: 15, offset: Offset(0, 5))
                          ],
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
                                    '${player['xp']} pts', 
                                    isCurrent
                                  ),
                                  if (playerIndex < players.length - 1) _buildDivider(),
                                ],
                              );
                            },
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
    );
  }

  Widget _buildLeaderboardTabs(double scale) {
    return Container(
      height: 45 * scale,
      decoration: BoxDecoration(
        color: const Color(0x1F222222),
        borderRadius: BorderRadius.circular(16 * scale),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeLeaderboardTab = 'weekly'),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _activeLeaderboardTab == 'weekly' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(14 * scale),
                  boxShadow: _activeLeaderboardTab == 'weekly' 
                    ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 2))]
                    : null,
                ),
                child: Text(
                  'Weekly League',
                  style: TextStyle(
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.bold,
                    color: _activeLeaderboardTab == 'weekly' ? Colors.black : Colors.black45,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeLeaderboardTab = 'daily'),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _activeLeaderboardTab == 'daily' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(14 * scale),
                  boxShadow: _activeLeaderboardTab == 'daily' 
                    ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 2))]
                    : null,
                ),
                child: Text(
                  'Daily Rank',
                  style: TextStyle(
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.bold,
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
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24 * scale),
        border: Border.all(color: const Color(0xFFF0F0F0), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daily Quests',
                style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w800, color: const Color(0xFF222222)),
              ),
              const Icon(Icons.stars, color: Color(0xFFFFB800)),
            ],
          ),
          SizedBox(height: 12 * scale),
          _buildQuestRow(scale, '🎯 Earn 50 XP today', dailyXp, 50),
          _buildDivider(),
          _buildQuestRow(scale, '📚 Complete 1 lesson', completedLessons, 1),
          _buildDivider(),
          _buildQuestRow(scale, '🔥 Reach a 3-Day streak', currentStreak, 3),
        ],
      ),
    );
  }

  Widget _buildQuestRow(double scale, String description, int currentVal, int targetVal) {
    double progressRatio = (currentVal / targetVal).clamp(0.0, 1.0);
    bool isCompleted = progressRatio >= 1.0;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10 * scale),
      child: Row(
        children: [
          Icon(
            isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isCompleted ? Colors.green : Colors.grey,
            size: 24 * scale,
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.bold,
                    color: isCompleted ? Colors.black45 : Colors.black87,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
                SizedBox(height: 4 * scale),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10 * scale),
                  child: LinearProgressIndicator(
                    value: progressRatio,
                    backgroundColor: const Color(0xFFF1F1FA),
                    color: isCompleted ? Colors.green : const Color(0xFFFFB800),
                    minHeight: 6 * scale,
                  ),
                )
              ],
            ),
          ),
          SizedBox(width: 12 * scale),
          Text(
            '$currentVal/$targetVal',
            style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.bold, color: Colors.grey),
          )
        ],
      ),
    );
  }

  Widget _buildStatCard(double scale, String emoji, String value, String label, Color color) {
    return Container(
      width: 165 * scale,
      padding: EdgeInsets.symmetric(vertical: 16 * scale, horizontal: 12 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16 * scale),
        boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Text(emoji, style: TextStyle(fontSize: 24 * scale)),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value, 
                  style: TextStyle(color: color, fontSize: 14 * scale, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label, 
                  style: TextStyle(color: Colors.black45, fontSize: 11 * scale),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPodiumAvatar(double scale, String name, String pts, int rank, Color color, double size, double heightOffset) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            CircleAvatar(
              radius: size / 2 * scale,
              backgroundColor: color.withOpacity(0.2),
              child: Icon(Icons.person, color: color, size: (size / 1.5) * scale),
            ),
            Container(
              padding: EdgeInsets.all(6 * scale),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              child: Text('$rank', style: TextStyle(color: Colors.white, fontSize: 12 * scale, fontWeight: FontWeight.bold)),
            )
          ],
        ),
        SizedBox(height: 8 * scale),
        Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14 * scale, color: const Color(0xFF222222))),
        Text(pts, style: TextStyle(color: color, fontSize: 12 * scale, fontWeight: FontWeight.w600)),
        SizedBox(height: heightOffset * scale),
      ],
    );
  }

  Widget _buildListRow(double scale, int rank, String name, String pts, bool isCurrentUser) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 16 * scale),
      decoration: BoxDecoration(
        color: isCurrentUser ? const Color(0xFFFFB800).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(isCurrentUser ? 24 * scale : 0),
      ),
      child: Row(
        children: [
          Text('$rank', style: TextStyle(fontSize: 16 * scale, fontWeight: FontWeight.bold, color: Colors.black54)),
          SizedBox(width: 16 * scale),
          CircleAvatar(radius: 18 * scale, backgroundColor: const Color(0xFFFFF9E5), child: Icon(Icons.person, size: 20 * scale, color: Colors.grey)),
          SizedBox(width: 12 * scale),
          Expanded(child: Text(name, style: TextStyle(fontSize: 16 * scale, fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w600, color: const Color(0xFF222222)))),
          Text(pts, style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.bold, color: const Color(0xFFFFB800))),
        ],
      ),
    );
  }

  Widget _buildDivider() => const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0));
}