import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '/profile/add_friend_screen.dart'; // Ensure you have this import for the Add Players screen

class ChallengesInterface extends StatefulWidget {
  final String initialCategory;

  const ChallengesInterface({
    super.key, 
    this.initialCategory = 'all',
  });

  @override
  State<ChallengesInterface> createState() => _ChallengesInterfaceState();
}

class _ChallengesInterfaceState extends State<ChallengesInterface> {
  String _activeTab = 'solo'; // 'solo' or 'group'
  late String _selectedCategory;
  final TextEditingController _pinController = TextEditingController();

  final List<Map<String, String>> _categories = [
    {'id': 'all', 'label': '🌟 All'},
    {'id': 'alphabets', 'label': '🔤 Alphabets'},
    {'id': 'numbers', 'label': '🔢 Numbers'},
    {'id': 'words', 'label': '💬 Common Words'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double baseWidth = 393;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFFF9E5),

      // --- GLASS APP BAR ---
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.4),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: const Text(
          'Challenge Zone 🎮',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 22,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
      ),

      body: LayoutBuilder(
        builder: (context, constraints) {
          final double scale = constraints.maxWidth / baseWidth;

          return Stack(
            children: [
              // --- Ambient Background Shapes ---
              Positioned(
                top: 80 * scale, left: -40 * scale,
                child: Container(width: 220 * scale, height: 220 * scale, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFB800).withOpacity(0.25))),
              ),
              Positioned(
                top: 380 * scale, right: -50 * scale,
                child: Container(width: 260 * scale, height: 260 * scale, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7DC579).withOpacity(0.2))),
              ),

              // --- Main Scrollable Body ---
              SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 12 * scale),
                  child: Column(
                    children: [
                      _buildTabSwitcher(scale),
                      SizedBox(height: 14 * scale),
                      _buildCategorySelector(scale),
                      SizedBox(height: 20 * scale),
                      _activeTab == 'solo' ? _buildSoloTab(scale) : _buildGroupTab(scale),
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

  Widget _buildTabSwitcher(double scale) {
    return Container(
      height: 48 * scale,
      padding: EdgeInsets.all(4 * scale),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.06), borderRadius: BorderRadius.circular(16 * scale)),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = 'solo'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200), alignment: Alignment.center,
                decoration: BoxDecoration(color: _activeTab == 'solo' ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(12 * scale)),
                child: Text('🚀 Solo Quests', style: TextStyle(fontSize: 14 * scale, fontWeight: _activeTab == 'solo' ? FontWeight.w800 : FontWeight.w600, color: _activeTab == 'solo' ? Colors.black : Colors.black45)),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = 'group'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200), alignment: Alignment.center,
                decoration: BoxDecoration(color: _activeTab == 'group' ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(12 * scale)),
                child: Text('⚔️ Group Battles', style: TextStyle(fontSize: 14 * scale, fontWeight: _activeTab == 'group' ? FontWeight.w800 : FontWeight.w600, color: _activeTab == 'group' ? Colors.black : Colors.black45)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySelector(double scale) {
    return SizedBox(
      height: 38 * scale,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final bool isSelected = _selectedCategory == cat['id'];

          return Padding(
            padding: EdgeInsets.only(right: 8 * scale),
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat['id']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF312244) : Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20 * scale),
                  border: Border.all(color: isSelected ? const Color(0xFF312244) : Colors.white.withOpacity(0.8), width: 1.5),
                ),
                child: Text(
                  cat['label']!,
                  style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w800, color: isSelected ? Colors.white : Colors.black87),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSoloTab(double scale) {
    final challenges = _getFilteredChallenges('solo');
    if (challenges.isEmpty) return _buildEmptyState(scale);

    return Column(
      children: challenges.map((item) {
        return Padding(
          padding: EdgeInsets.only(bottom: 16 * scale),
          child: _buildChallengeCard(scale: scale, item: item),
        );
      }).toList(),
    );
  }

  Widget _buildGroupTab(double scale) {
    final groupChallenges = _getFilteredChallenges('group');

    return Column(
      children: [
        // KAHOOT STYLE BANNER
        ClipRRect(
          borderRadius: BorderRadius.circular(22 * scale),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: EdgeInsets.all(16 * scale),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.55), borderRadius: BorderRadius.circular(22 * scale),
                border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10 * scale),
                        decoration: BoxDecoration(color: const Color(0xFF312244), borderRadius: BorderRadius.circular(14 * scale)),
                        child: Icon(Icons.pin_rounded, color: Colors.white, size: 24 * scale),
                      ),
                      SizedBox(width: 12 * scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Have a Live Game PIN?', style: TextStyle(fontSize: 16 * scale, fontWeight: FontWeight.w800)),
                            Text('Join your teacher or friend\'s quiz room!', style: TextStyle(fontSize: 12 * scale, color: Colors.black54)),
                          ],
                        ),
                      )
                    ],
                  ),
                  SizedBox(height: 14 * scale),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF312244), foregroundColor: Colors.white, minimumSize: Size(double.infinity, 44 * scale), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale))),
                    onPressed: () => _showJoinRoomDialog(context, scale),
                    child: Text('Enter Room Code', style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w800)),
                  )
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 20 * scale),

        if (groupChallenges.isEmpty)
          _buildEmptyState(scale)
        else
          ...groupChallenges.map((item) {
            return Padding(
              padding: EdgeInsets.only(bottom: 16 * scale),
              child: _buildChallengeCard(scale: scale, item: item),
            );
          }),
      ],
    );
  }

  Widget _buildChallengeCard({required double scale, required Map<String, dynamic> item}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22 * scale),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: EdgeInsets.all(16 * scale),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.45),
            borderRadius: BorderRadius.circular(22 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.65), width: 1.5 * scale),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                        decoration: BoxDecoration(color: item['badgeColor'].withOpacity(0.15), borderRadius: BorderRadius.circular(8 * scale)),
                        child: Text(item['badge'], style: TextStyle(color: item['badgeColor'], fontSize: 10 * scale, fontWeight: FontWeight.w900)),
                      ),
                      SizedBox(width: 6 * scale),
                      Text('•  ${item['categoryLabel']}', style: TextStyle(color: Colors.black45, fontSize: 11 * scale, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.stars_rounded, color: Color(0xFFFFB800), size: 16),
                      SizedBox(width: 4 * scale),
                      Text(item['reward'], style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w800, color: Colors.black87)),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 12 * scale),
              Row(
                children: [
                  Container(
                    width: 48 * scale, height: 48 * scale,
                    decoration: BoxDecoration(color: item['accentColor'].withOpacity(0.12), shape: BoxShape.circle),
                    child: Icon(item['icon'], color: item['accentColor'], size: 26 * scale),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['title'], style: TextStyle(fontSize: 16 * scale, fontWeight: FontWeight.w800, color: Colors.black)),
                        SizedBox(height: 2 * scale),
                        Text(item['subtitle'], style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w500, color: Colors.black54)),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14 * scale),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB800), foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale)),
                    padding: EdgeInsets.symmetric(vertical: 10 * scale),
                  ),
                  onPressed: item['onTap'],
                  child: Text(item['buttonText'] ?? "Start Challenge", style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w800)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(double scale) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 30 * scale), alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 48 * scale, color: Colors.black26),
          SizedBox(height: 8 * scale),
          Text("No challenges found for this category.", style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w700, color: Colors.black45)),
        ],
      ),
    );
  }

  void _showJoinRoomDialog(BuildContext context, double scale) {
    // ... [Same Join Room Dialog as previous] ...
  }

 // --- UPDATED DYNAMIC FRIEND INVITE SHEET (REAL-TIME STATUS) ---
  void _showFriendInviteSheet(BuildContext context, double scale) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, 
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.65, 
        padding: EdgeInsets.all(20 * scale),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9E5),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28 * scale)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40 * scale, height: 4 * scale,
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            SizedBox(height: 16 * scale),
            Text('Challenge a Friend ⚔️', style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w900, fontFamily: 'Inter')),
            SizedBox(height: 12 * scale),
            
            Expanded(
              child: currentUserId == null 
                  ? const Center(child: Text("Please log in to challenge friends."))
                  : StreamBuilder<DocumentSnapshot>(
                      // 1. Stream the current user's data to keep the friend list updated
                      stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB800)));
                        }

                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return const Center(child: Text("Could not load friends."));
                        }

                        final data = snapshot.data!.data() as Map<String, dynamic>;
                        final List<dynamic> following = data['following'] ?? [];
                        final List<dynamic> followers = data['followers'] ?? [];

                        // MLBB-Style Mutuals Logic: Friends are those in BOTH lists
                        final List<String> mutualFriends = following
                            .where((id) => followers.contains(id))
                            .map((e) => e.toString())
                            .toList();

                        if (mutualFriends.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline_rounded, size: 54 * scale, color: Colors.black26),
                                SizedBox(height: 12 * scale),
                                Text(
                                  "You don't have any mutual friends yet.",
                                  style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600, fontSize: 14 * scale),
                                ),
                                SizedBox(height: 16 * scale),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB800)),
                                  icon: const Icon(Icons.search, color: Colors.white),
                                  label: const Text("Find Players", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AddFriendScreen()));
                                  },
                                )
                              ],
                            ),
                          );
                        }

                        return ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          itemCount: mutualFriends.length,
                          separatorBuilder: (context, index) => const Divider(color: Colors.black12),
                          itemBuilder: (context, index) {
                            final friendId = mutualFriends[index];
                            
                            // 2. Stream EACH friend's document for Real-Time Online/Offline Status
                            return StreamBuilder<DocumentSnapshot>(
                              stream: FirebaseFirestore.instance.collection('users').doc(friendId).snapshots(),
                              builder: (context, friendSnapshot) {
                                if (!friendSnapshot.hasData) return const SizedBox.shrink();

                                final friendData = friendSnapshot.data!.data() as Map<String, dynamic>?;
                                if (friendData == null) return const SizedBox.shrink();

                                final name = friendData['name'] ?? friendData['displayName'] ?? 'Player';
                                final avatar = friendData['avatar'] ?? '';
                                final int xp = friendData['xp'] ?? 0;
                                
                                // Parse the isActive status from your database
                                final bool isActive = friendData['isActive'] ?? false;
                                final String statusText = isActive ? "Online" : "Offline";
                                final Color statusColor = isActive ? Colors.green.shade500 : Colors.grey.shade400;

                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Stack(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: const Color(0xFFFFB800).withOpacity(0.2),
                                        backgroundImage: (avatar.isNotEmpty && !avatar.startsWith('data:image')) ? NetworkImage(avatar) : null,
                                        child: (avatar.isEmpty || avatar.startsWith('data:image')) ? const Icon(Icons.person, color: Color(0xFFFFB800)) : null,
                                      ),
                                      // Real-time green dot indicator
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 12 * scale,
                                          height: 12 * scale,
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 2),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Row(
                                    children: [
                                      Icon(Icons.bolt_rounded, size: 14, color: Colors.blue.shade400),
                                      const SizedBox(width: 2),
                                      Text("$xp XP • ", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      Text(statusText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
                                    ],
                                  ),
                                  trailing: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      // Disable the button if the user is offline
                                      backgroundColor: isActive ? const Color(0xFFF34B1B) : Colors.grey.shade300,
                                      foregroundColor: isActive ? Colors.white : Colors.black45,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * scale)),
                                      elevation: 0,
                                    ),
                                    onPressed: isActive ? () {
                                      // TODO: Insert Firestore Challenge Creation Logic Here
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Challenge invite sent to $name!'),
                                          behavior: SnackBarBehavior.floating,
                                          backgroundColor: Colors.green.shade600,
                                        )
                                      );
                                      Navigator.pop(context);
                                    } : null, // Set to null if offline
                                    child: Text(isActive ? 'Invite' : 'Offline', style: const TextStyle(fontWeight: FontWeight.w800)),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // --- FILTERING DATA ENGINE ---
  List<Map<String, dynamic>> _getFilteredChallenges(String mode) {
    final List<Map<String, dynamic>> allChallenges = [
      // Solo Challenges
      {
        'mode': 'solo', 'category': 'alphabets', 'categoryLabel': 'Alphabets',
        'title': 'Alphabet Speed Dash', 'subtitle': 'Recognize A-Z alphabet signs in under 60 seconds!',
        'badge': 'TIME ATTACK', 'badgeColor': const Color(0xFFF34B1B), 'reward': '+150 XP',
        'icon': Icons.timer_rounded, 'accentColor': const Color(0xFFF34B1B),
        'onTap': () {},
      },
      // Group Challenges
      {
        'mode': 'group', 'category': 'alphabets', 'categoryLabel': 'Alphabets',
        'title': '1v1 Alphabet Duel', 'subtitle': 'Race live against a friend to sign the alphabet fastest!',
        'badge': 'LIVE DUEL', 'badgeColor': const Color(0xFFF34B1B), 'reward': '+250 XP',
        'icon': Icons.sports_esports_rounded, 'accentColor': const Color(0xFFF34B1B),
        'buttonText': 'Challenge Friend',
        'onTap': () => _showFriendInviteSheet(context, MediaQuery.of(context).size.width / 393),
      },
      {
        'mode': 'group', 'category': 'words', 'categoryLabel': 'Common Words',
        'title': 'Classroom Boss Raid', 'subtitle': 'Team up with classmates to complete 50 word puzzles!',
        'badge': 'TEAM CO-OP', 'badgeColor': const Color(0xFF27AE60), 'reward': 'Trophy 🏆',
        'icon': Icons.groups_rounded, 'accentColor': const Color(0xFF27AE60),
        'buttonText': 'View Raid', 'onTap': () {},
      },
    ];

    return allChallenges.where((item) {
      final matchesMode = item['mode'] == mode;
      final matchesCategory = _selectedCategory == 'all' || item['category'] == _selectedCategory;
      return matchesMode && matchesCategory;
    }).toList();
  }
}