import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../profile/friend_requests_screen.dart'; 

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = ""; 

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold( 
      backgroundColor: const Color(0xFFFFF9E5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Find Players",
          style: TextStyle(
            color: Colors.black87, 
            fontWeight: FontWeight.w800, 
            fontFamily: 'Inter', 
            fontSize: 22, 
            letterSpacing: -0.5
          ),
        ),
        actions: [
          if (currentUserId != null)
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).snapshots(),
              builder: (context, snapshot) {
                int requestCount = 0;
                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  requestCount = (data?['incomingRequests'] as List?)?.length ?? 0;
                }

                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_rounded, color: Colors.black87, size: 28),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const FriendRequestsScreen()),
                          );
                        },
                      ),
                      if (requestCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                              color: Colors.redAccent, 
                              shape: BoxShape.circle
                            ),
                            child: Text(
                              '$requestCount',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))
                ]
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                decoration: InputDecoration(
                  hintText: "Search by username...",
                  hintStyle: const TextStyle(color: Colors.black38, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
                  prefixIcon: const Icon(CupertinoIcons.search, color: Color(0xFFFFB800)),
                  suffixIcon: _searchQuery.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.black38),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = "");
                          },
                        ) 
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
                style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter'),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(left: 24.0, top: 16.0, bottom: 8.0),
            child: Text(
              _searchQuery.isEmpty ? "Suggested Players" : "Search Results",
              style: const TextStyle(
                color: Colors.black54, 
                fontWeight: FontWeight.w800, 
                fontFamily: 'Inter', 
                fontSize: 14, 
                letterSpacing: 0.5
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB800)));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("No users found.", style: TextStyle(color: Colors.black45)));
                }

                DocumentSnapshot? currentUserDoc;
                for (var doc in snapshot.data!.docs) {
                  if (doc.id == currentUserId) {
                    currentUserDoc = doc;
                    break;
                  }
                }

                List<dynamic> followingList = [];
                List<dynamic> incomingRequests = [];
                List<dynamic> followersList = [];
                String currentUserName = 'Someone';

                if (currentUserDoc != null) {
                  final data = currentUserDoc.data() as Map<String, dynamic>;
                  followingList = data['following'] ?? [];
                  incomingRequests = data['incomingRequests'] ?? [];
                  followersList = data['followers'] ?? [];
                  currentUserName = data['name'] ?? data['displayName'] ?? 'Someone';
                }

                final users = snapshot.data!.docs.where((doc) {
                  if (doc.id == currentUserId) return false;
                  
                  final data = doc.data() as Map<String, dynamic>;
                  final String status = (data['status'] ?? '').toString().toLowerCase();
                  final bool isActive = data['isActive'] ?? false;
                  if (!(status == 'approved' || isActive == true)) return false;

                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();

                  if (_searchQuery.isEmpty) return true; 
                  return name.contains(_searchQuery) || email.contains(_searchQuery);
                }).toList();

                if (users.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 64, color: Colors.black.withOpacity(0.1)),
                        const SizedBox(height: 12),
                        const Text("No players match your search.", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = users[index];
                    final data = doc.data() as Map<String, dynamic>;
                    
                    final bool isFollowing = followingList.contains(doc.id);
                    final bool isTargetFollowingMe = incomingRequests.contains(doc.id) || followersList.contains(doc.id);
                    
                    return _UserCard(
                      userData: data,
                      targetUserId: doc.id,
                      currentUserId: currentUserId,
                      currentUserName: currentUserName,
                      isInitiallyFollowing: isFollowing,
                      isTargetFollowingMe: isTargetFollowingMe, 
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String targetUserId;
  final String? currentUserId;
  final String currentUserName;
  final bool isInitiallyFollowing;
  final bool isTargetFollowingMe;

  const _UserCard({
    required this.userData,
    required this.targetUserId,
    required this.currentUserId,
    required this.currentUserName,
    required this.isInitiallyFollowing,
    required this.isTargetFollowingMe,
  });

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  late bool isFollowing;

  @override
  void initState() {
    super.initState();
    isFollowing = widget.isInitiallyFollowing;
  }

  @override
  void didUpdateWidget(covariant _UserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isInitiallyFollowing != widget.isInitiallyFollowing) {
      isFollowing = widget.isInitiallyFollowing;
    }
  }

  Widget _buildUserAvatar(String? avatarData, {double size = 48}) {
    if (avatarData == null || avatarData.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: const Color(0xFFFFEFA7),
        child: Icon(Icons.person_rounded, size: size * 0.6, color: const Color(0xFFFFB800)),
      );
    }
    if (avatarData.startsWith('data:image')) {
      try {
        final bytes = base64Decode(avatarData.split(',').last);
        return CircleAvatar(radius: size / 2, backgroundImage: MemoryImage(bytes), backgroundColor: const Color(0xFFFFEFA7));
      } catch (e) {
        return CircleAvatar(radius: size / 2, backgroundColor: Colors.grey.shade200, child: Icon(Icons.broken_image_rounded, size: size * 0.5, color: Colors.grey));
      }
    } else {
      return CircleAvatar(radius: size / 2, backgroundImage: NetworkImage(avatarData), backgroundColor: const Color(0xFFFFEFA7));
    }
  }

  @override
  Widget build(BuildContext context) {
    String name = widget.userData['name'] ?? 'Student';
    String avatarUrl = widget.userData['avatar'] ?? '';
    int xp = widget.userData['xp'] ?? 0;
    
    // MLBB Logic: Mutuals = Friends
    bool isFriends = isFollowing && widget.isTargetFollowingMe;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          _buildUserAvatar(avatarUrl, size: 52),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFamily: 'Inter', color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.bolt_rounded, size: 14, color: Colors.blue.shade400),
                    const SizedBox(width: 2),
                    Text("$xp XP", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.blue.shade600)),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(width: 12),
          
          // --- DYNAMIC GAMIFIED BUTTON ---
          GestureDetector(
            onTap: () async {
              if (widget.currentUserId == null) return;
              
              final currentUserRef = FirebaseFirestore.instance.collection('users').doc(widget.currentUserId);
              final targetUserRef = FirebaseFirestore.instance.collection('users').doc(widget.targetUserId);
              
              setState(() => isFollowing = !isFollowing);
              
              try {
                if (isFollowing) {
                  final payload = {
                    'type': 'new_follower',
                    'title': 'New Follower',
                    'body': '${widget.currentUserName} started following you.',
                    'fromUserId': widget.currentUserId,
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                    'isRead': false,
                  };

                  await targetUserRef.update({
                    'incomingRequests': FieldValue.arrayUnion([widget.currentUserId]),
                    'followers': FieldValue.arrayUnion([widget.currentUserId]),
                    'notifications': FieldValue.arrayUnion([payload]), 
                  });
                  await currentUserRef.update({
                    'following': FieldValue.arrayUnion([widget.targetUserId])
                  });
                } else {
                  // Unfollow logic
                  await targetUserRef.update({
                    'followers': FieldValue.arrayRemove([widget.currentUserId])
                  });
                  await currentUserRef.update({
                    'following': FieldValue.arrayRemove([widget.targetUserId])
                  });
                }
              } catch (e) {
                setState(() => isFollowing = !isFollowing); // Revert on fail
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isFriends ? Colors.green.shade500 
                     : isFollowing ? Colors.grey.shade300 
                     : const Color(0xFFFFB800),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  if (isFriends) ...[
                    const Icon(Icons.people_alt_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    isFriends ? "Friends" 
                      : isFollowing ? "Following" 
                      : (widget.isTargetFollowingMe ? "Follow Back" : "Follow"),
                    style: TextStyle(
                      color: isFriends ? Colors.white : (isFollowing ? Colors.black54 : Colors.white),
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Inter',
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}