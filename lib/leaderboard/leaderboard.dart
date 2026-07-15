import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import '../services/progress_service.dart'; // Make sure this path points to your service
import '../home/home.dart';
import '../module/module.dart';
import '../profile/profile.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double scale = screenWidth / 393 > 1.2 ? 1.2 : screenWidth / 393; 

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
                icon: const Icon(Icons.home, color: Colors.grey, size: 28), 
                onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const SnedInterafce1(userName: "Student")), (route) => false),
              ),
              IconButton(
                icon: const Icon(Icons.auto_stories, color: Colors.grey, size: 28), 
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SnedInterface2())),
              ),
              IconButton(
                icon: const Icon(Icons.emoji_events, color: Colors.black, size: 28), // ACTIVE TAB
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
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 20 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- HEADER ---
              Text(
                'Leaderboard',
                style: TextStyle(
                  color: const Color(0xFF222222),
                  fontSize: 28 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 8 * scale),
              Text(
                'See how you rank against other students!',
                style: TextStyle(
                  color: const Color(0x99222222),
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 25 * scale),

              // --- DYNAMIC STREAK & ACCURACY STATS ---
              StreamBuilder<DocumentSnapshot>(
                stream: ProgressService().getUserProgressStream(),
                builder: (context, snapshot) {
                  int currentStreak = 0;
                  
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    if (data != null) {
                      currentStreak = data['streak'] ?? 0;
                    }
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatCard(scale, '🔥', '$currentStreak DAYS', 'Active Streak', const Color(0xFFFF8227)),
                      _buildStatCard(scale, '🎯', '88%', 'Avg Accuracy', const Color(0xFFF34B1B)),
                    ],
                  );
                },
              ),
              
              SizedBox(height: 35 * scale),

              // --- TOP 3 PODIUM ---
              SizedBox(
                height: 220 * scale,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // 2nd Place (Left)
                    Positioned(
                      left: 20 * scale,
                      bottom: 0,
                      child: _buildPodiumAvatar(scale, 'Alice G.', '1932 pts', 2, const Color(0xFFF34B1B), 70, 60),
                    ),
                    // 3rd Place (Right)
                    Positioned(
                      right: 20 * scale,
                      bottom: 0,
                      child: _buildPodiumAvatar(scale, 'Bob M.', '1431 pts', 3, const Color(0xFFFF8227), 60, 50),
                    ),
                    // 1st Place (Center)
                    Positioned(
                      bottom: 20 * scale,
                      child: _buildPodiumAvatar(scale, 'Jane Doe', '2019 pts', 1, const Color(0xFFFFCA28), 90, 80),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 30 * scale),

              // --- RANKING LIST ---
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24 * scale),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0A000000), blurRadius: 15, offset: Offset(0, 5))
                  ],
                ),
                child: Column(
                  children: [
                    _buildListRow(scale, 4, 'Sarah Lee', '1205 pts', false),
                    _buildDivider(),
                    _buildListRow(scale, 5, 'You', '950 pts', true),
                    _buildDivider(),
                    _buildListRow(scale, 6, 'Mike Chen', '890 pts', false),
                    _buildDivider(),
                    _buildListRow(scale, 7, 'Emma Watson', '720 pts', false),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(double scale, String emoji, String value, String label, Color color) {
    return Container(
      width: 160 * scale,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(color: color, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
              Text(label, style: TextStyle(color: Colors.black45, fontSize: 11 * scale)),
            ],
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
        color: isCurrentUser ? const Color(0xFFFFB800).withOpacity(0.1) : Colors.transparent,
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