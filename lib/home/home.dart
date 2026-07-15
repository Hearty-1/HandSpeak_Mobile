import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/progress_service.dart'; 
import '../module/module.dart'; 
import '../profile/profile.dart';
import '../leaderboard/leaderboard.dart'; 

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

  // --- AUTOMATIC CHALLENGE VERIFICATION LOGIC ---
  bool _verifyChallengeMet({
    required Map<String, dynamic> challenge, 
    required Map<String, dynamic>? dailyActivityData,
    required int currentStreak,
  }) {
    if (dailyActivityData == null) return false;

    final String title = challenge['title'] ?? '';

    // Challenge 1: Perfect the Sign Letter "G"
    if (title.contains('Perfect the Sign Letter "G"')) {
      final List<dynamic> verifiedSigns = dailyActivityData['verified_signs'] ?? [];
      return verifiedSigns.contains('G');
    } 
    
    // Challenge 2: Learn 3 New Numbers
    if (title.contains('Learn 3 New Numbers')) {
      final List<dynamic> lessons = dailyActivityData['lessons_completed'] ?? [];
      final numNumbers = lessons.where((l) => l.toString().startsWith('number')).length;
      return numNumbers >= 3;
    } 
    
    // Challenge 3: Review Alphabet A-F
    if (title.contains('Review Alphabet A-F')) {
      final List<dynamic> lessons = dailyActivityData['lessons_completed'] ?? [];
      return lessons.contains('alphabet_a_f_review');
    }

    // Challenge 4: Practice "Thank You"
    if (title.contains('Practice "Thank You"')) {
      final List<dynamic> verifiedSigns = dailyActivityData['verified_signs'] ?? [];
      return verifiedSigns.contains('thank_you');
    }

    // Challenge 5: Score 100% on a Quiz
    if (title.contains('Score 100% on a Quiz')) {
      return dailyActivityData['perfect_quiz_completed'] ?? false;
    } 

    // Challenge 6: Maintain a 3-Day Streak
    if (title.contains('Maintain a 3-Day Streak')) {
      return currentStreak >= 3;
    }

    // Challenge 7: Complete Module 1
    if (title.contains('Complete Module 1')) {
      return dailyActivityData['module_1_completed'] ?? false;
    }

    return false; // Default fallback
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double scale = screenWidth / 393 > 1.2 ? 1.2 : screenWidth / 393; 

    // --- DAILY CHALLENGE LOGIC ---
    final List<Map<String, dynamic>> dailyChallenges = [
      {'title': 'Perfect the Sign Letter "G"', 'xp': 150, 'icon': Icons.back_hand_rounded},
      {'title': 'Learn 3 New Numbers', 'xp': 200, 'icon': Icons.onetwothree_rounded},
      {'title': 'Review Alphabet A-F', 'xp': 100, 'icon': Icons.abc_rounded},
      {'title': 'Practice "Thank You"', 'xp': 120, 'icon': Icons.sign_language_rounded},
      {'title': 'Score 100% on a Quiz', 'xp': 250, 'icon': Icons.workspace_premium_rounded},
      {'title': 'Maintain a 3-Day Streak', 'xp': 300, 'icon': Icons.local_fire_department_rounded},
      {'title': 'Complete Module 1', 'xp': 500, 'icon': Icons.auto_stories_rounded},
    ];

    final DateTime now = DateTime.now();
    final int dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final currentChallenge = dailyChallenges[dayOfYear % dailyChallenges.length];
    final int hoursLeft = 24 - now.hour;
    final todayStr = now.toIso8601String().split('T')[0];

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      
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
                icon: const Icon(Icons.home, color: Colors.black, size: 28), // ACTIVE
                onPressed: () {}, 
              ),
              IconButton(
                icon: const Icon(Icons.auto_stories, color: Colors.grey, size: 28), 
                onPressed: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SnedInterface2()));
                },
              ),
              IconButton(
                icon: const Icon(Icons.emoji_events, color: Colors.grey, size: 28), 
                onPressed: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LeaderboardScreen()));
                },
              ),
              IconButton(
                icon: const Icon(Icons.person, color: Colors.grey, size: 28), 
                onPressed: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
                },
              ),
            ],
          ),
        ),
      ),

      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: ProgressService().getUserProgressStream(),
          builder: (context, userSnapshot) {
            String studentName = userName;
            int streak = 0;
            bool isChallengeCompleted = false;

            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
              if (userData != null) {
                studentName = userData['name'] ?? userData['displayName'] ?? userName;
                streak = userData['streak'] ?? 0;
                isChallengeCompleted = userData['lastCompletedChallengeDate'] == todayStr;
              }
            }

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 20 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- HEADER (NAME & REAL-TIME STREAK) ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello, $studentName! 👋',
                            style: TextStyle(color: const Color(0xFF222222), fontSize: 26 * scale, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                          ),
                          SizedBox(height: 4 * scale),
                          Text(
                            'Ready to learn new signs today?',
                            style: TextStyle(color: const Color(0x99222222), fontSize: 14 * scale, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // Dynamic Fire Streak Badge
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20 * scale),
                              border: Border.all(color: const Color(0xFFFF8227), width: 1.5),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.local_fire_department_rounded, color: const Color(0xFFFF8227), size: 18 * scale),
                                SizedBox(width: 4 * scale),
                                Text(
                                  '$streak',
                                  style: TextStyle(
                                    color: const Color(0xFFFF8227),
                                    fontSize: 14 * scale,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 8 * scale),
                          GestureDetector(
                            onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProfileScreen())),
                            child: CircleAvatar(
                              radius: 26 * scale,
                              backgroundColor: const Color(0xFFFFEFA7),
                              child: Icon(Icons.person, color: const Color(0xFFFFB800), size: 30 * scale),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 30 * scale),

                  // --- HERO CARD ---
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(22 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800),
                      borderRadius: BorderRadius.circular(24 * scale),
                      boxShadow: [BoxShadow(color: const Color(0xFFFFB800).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12 * scale)),
                          child: Text('CURRENT MODULE', style: TextStyle(color: Colors.white, fontSize: 10 * scale, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        ),
                        SizedBox(height: 12 * scale),
                        Text('Alphabet: Level 1', style: TextStyle(color: Colors.white, fontSize: 24 * scale, fontWeight: FontWeight.bold)),
                        SizedBox(height: 6 * scale),
                        Text('Learn the basics of hand spelling.', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14 * scale)),
                        SizedBox(height: 20 * scale),
                        ElevatedButton(
                          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SnedInterface2())),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFFFFB800),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16 * scale)),
                            padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 12 * scale),
                          ),
                          child: Text('Continue Learning', style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 25 * scale),

                  // --- VERIFIABLE DAILY CHALLENGE CARD ---
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(FirebaseAuth.instance.currentUser?.uid)
                        .collection('daily_activity')
                        .doc(todayStr)
                        .snapshots(),
                    builder: (context, activitySnapshot) {
                      final dailyActivityData = activitySnapshot.data?.data() as Map<String, dynamic>?;

                      // Automatically checks if task conditions are met
                      final bool isTaskDone = _verifyChallengeMet(
                        challenge: currentChallenge,
                        dailyActivityData: dailyActivityData,
                        currentStreak: streak,
                      );

                      return Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(20 * scale),
                        decoration: BoxDecoration(
                          color: const Color(0xFF322144), 
                          borderRadius: BorderRadius.circular(20 * scale),
                          boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 15, offset: Offset(0, 8))],
                        ),
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
                                  decoration: BoxDecoration(
                                    color: isTaskDone ? Colors.green : const Color(0xFFFF8227), 
                                    borderRadius: BorderRadius.circular(10 * scale),
                                  ),
                                  child: Text(
                                    isTaskDone ? 'CHALLENGE COMPLETED!' : 'DAILY CHALLENGE', 
                                    style: TextStyle(color: Colors.white, fontSize: 10 * scale, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                                  ),
                                ),
                                SizedBox(height: 12 * scale),
                                SizedBox(
                                  width: 220 * scale,
                                  child: Text(
                                    currentChallenge['title'], 
                                    style: TextStyle(
                                      color: Colors.white, 
                                      fontSize: 18 * scale, 
                                      fontWeight: FontWeight.w800,
                                      decoration: isChallengeCompleted ? TextDecoration.lineThrough : TextDecoration.none,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 14 * scale),
                                Row(
                                  children: [
                                    Icon(Icons.bolt_rounded, color: const Color(0xFFFFCA28), size: 18 * scale),
                                    SizedBox(width: 4 * scale),
                                    Text('Reward: +${currentChallenge['xp']} XP', style: TextStyle(color: const Color(0xFFFFCA28), fontSize: 13 * scale, fontWeight: FontWeight.bold)),
                                    SizedBox(width: 16 * scale),
                                    Icon(Icons.timer_outlined, color: Colors.white60, size: 16 * scale),
                                    SizedBox(width: 4 * scale),
                                    Text('${hoursLeft}h left', style: TextStyle(color: Colors.white60, fontSize: 12 * scale, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                                SizedBox(height: 16 * scale),
                                
                                // Claim Button (Enabled only if real challenge completed)
                                SizedBox(
                                  width: double.infinity,
                                  height: 40 * scale,
                                  child: ElevatedButton(
                                    onPressed: (isTaskDone && !isChallengeCompleted)
                                      ? () async {
                                          try {
                                            final user = FirebaseAuth.instance.currentUser;
                                            if (user == null) return;
                                            
                                            final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
                                            
                                            await FirebaseFirestore.instance.runTransaction((transaction) async {
                                              final snapshotDoc = await transaction.get(userRef);
                                              if (!snapshotDoc.exists) return;
                                              
                                              final data = snapshotDoc.data() as Map<String, dynamic>;
                                              final currentXp = data['xp'] ?? 0;
                                              
                                              transaction.update(userRef, {
                                                'xp': currentXp + currentChallenge['xp'],
                                                'lastCompletedChallengeDate': todayStr,
                                              });
                                            });
                                            
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Awesome! You earned +${currentChallenge['xp']} XP! 🎉'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          } catch (e) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Could not complete challenge: $e'),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        }
                                      : null, // Disabled when requirements aren't met
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF8227),
                                      disabledBackgroundColor: Colors.grey[800],
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * scale)),
                                      elevation: 0,
                                    ),
                                    child: Text(
                                      isChallengeCompleted 
                                          ? 'Reward Claimed! 🏆' 
                                          : (isTaskDone ? 'Claim +${currentChallenge['xp']} XP! 🎁' : 'Complete the task to unlock'),
                                      style: TextStyle(
                                        fontSize: 13 * scale, 
                                        fontWeight: FontWeight.bold, 
                                        color: (isTaskDone && !isChallengeCompleted) ? Colors.white : Colors.white54
                                      ),
                                    ),
                                  ),
                                )
                              ],
                            ),
                            Positioned(
                              right: 0,
                              top: 10 * scale,
                              child: Container(
                                width: 60 * scale,
                                height: 60 * scale,
                                decoration: BoxDecoration(
                                  color: isTaskDone ? Colors.green.withOpacity(0.2) : Colors.white.withOpacity(0.08), 
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isTaskDone ? Icons.check_circle_rounded : currentChallenge['icon'], 
                                  color: isTaskDone ? Colors.greenAccent : const Color(0xFFFFCA28), 
                                  size: 32 * scale,
                                ),
                              ),
                            )
                          ],
                        ),
                      );
                    },
                  ),

                  SizedBox(height: 30 * scale),

                  // Categories
                  Text('Explore Categories', style: TextStyle(color: const Color(0xFF222222), fontSize: 18 * scale, fontWeight: FontWeight.bold)),
                  SizedBox(height: 16 * scale),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildCategoryCard(context: context, title: 'Alphabet', icon: Icons.abc_rounded, scale: scale, onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SnedInterface2()))),
                      _buildCategoryCard(context: context, title: 'Numbers', icon: Icons.onetwothree_rounded, scale: scale, onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SnedInterface2()))),
                    ],
                  ),
                  SizedBox(height: 20 * scale),
                ],
              ),
            );
          },
        ),
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
            Container(padding: EdgeInsets.all(12 * scale), decoration: const BoxDecoration(color: Color(0xFFFFF9E5), shape: BoxShape.circle), child: Icon(icon, color: const Color(0xFFFFB800), size: 36 * scale)),
            SizedBox(height: 12 * scale),
            Text(title, style: TextStyle(color: const Color(0xFF222222), fontSize: 16 * scale, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}