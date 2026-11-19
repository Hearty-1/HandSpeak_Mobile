import '/services/presence_service.dart';
import '/profile/public_profile.dart';
import '/widgets/guide_tour.dart';
import '/providers/language_provider.dart';
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
  // Hoot's "how to add friends" guide.
  final GlobalKey _fgSearch = GlobalKey();
  final GlobalKey _fgList = GlobalKey();
  final GlobalKey _fgRequests = GlobalKey();

  void _startFriendsGuide() {
    GuideTour.start(context, [
      GuideStep(
        target: _fgSearch,
        icon: Icons.search_rounded,
        title: L.t('1. Find', '1. Hanapin'),
        body: L.t("Type your classmate's name.", 'I-type ang pangalan ng kaklase.'),
      ),
      GuideStep(
        target: _fgList,
        icon: Icons.person_add_alt_1_rounded,
        title: L.t('2. Add', '2. Idagdag'),
        body: L.t('Tap Follow next to their name.', 'Pindutin ang Follow sa tabi ng pangalan.'),
      ),
      GuideStep(
        target: _fgRequests,
        icon: Icons.notifications_rounded,
        title: L.t('3. Requests', '3. Mga request'),
        body: L.t('See who wants to be your friend.', 'Tingnan kung sino ang gustong makipagkaibigan.'),
      ),
    ]);
  }

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  // ---- Loading players (thrifty on Firestore reads) -------------------------
  // Was: a live stream of every student (all of them read, and every change
  // of any student re-sent while the screen was open). Now:
  //  * suggested players: the 30 most recently active students, read once;
  //  * search: the student list is read only when something is typed, and
  //    kept for 10 minutes (more typing costs nothing);
  //  * this student's own follow lists: a stream of their own document only.
  static const int _suggestedCount = 30;
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _allStudents;
  static DateTime _allStudentsAt = DateTime(2000);
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _suggested;

  Query<Map<String, dynamic>> get _students =>
      FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'student');

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _suggestedFuture() => _suggested ??= () async {
        try {
          final snap = await _students.orderBy('lastActive', descending: true).limit(_suggestedCount).get();
          return snap.docs;
        } on FirebaseException catch (e) {
          // The role + lastActive index is not there: a small plain page.
          debugPrint('Suggested players (role + lastActive) failed: ${e.code}');
          return (await _students.limit(_suggestedCount).get()).docs;
        }
      }();

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _searchFuture() {
    if (_allStudents == null || DateTime.now().difference(_allStudentsAt) > const Duration(minutes: 10)) {
      _allStudentsAt = DateTime.now();
      _allStudents = _students.limit(2000).get().then((s) => s.docs).catchError((Object e) {
        _allStudents = null; // try again on the next search
        throw e;
      });
    }
    return _allStudents!;
  }

  Future<void> _refresh() async {
    setState(() {
      _suggested = null;
      if (_searchQuery.isNotEmpty) _allStudents = null;
    });
    await (_searchQuery.isEmpty ? _suggestedFuture() : _searchFuture());
  }

  /// The requests bell's stream of the same document, made once (not per build).
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _bellStream = FirebaseAuth.instance.currentUser == null
      ? null
      : FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).snapshots();

  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _meStream = FirebaseAuth.instance.currentUser == null
      ? null
      : FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).snapshots();


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold( 
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButtonLocation: PetAssistant.location,
      floatingActionButton: PetAssistant(onGuide: _startFriendsGuide),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Find Players",
          style: TextStyle(
            color: textColor, 
            fontWeight: FontWeight.w800, 
            fontFamily: 'Inter', 
            fontSize: 22, 
            letterSpacing: -0.5
          ),
        ),
        actions: [
          if (currentUserId != null)
            StreamBuilder<DocumentSnapshot>(
              stream: _bellStream,
              builder: (context, snapshot) {
                int requestCount = 0;
                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  // Only followers you don't follow back yet (friends aren't requests).
                  final following = (data?['following'] as List?) ?? const [];
                  requestCount = ((data?['incomingRequests'] as List?) ?? const [])
                      .where((u) => !following.contains(u))
                      .toSet()
                      .length;
                }

                return Padding(
                  key: _fgRequests,
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon: Icon(Icons.notifications_rounded, color: textColor, size: 28),
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
              key: _fgSearch,
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))
                ]
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                decoration: InputDecoration(
                  hintText: "Search by username...",
                  hintStyle: TextStyle(color: textColor.withValues(alpha: 0.4), fontWeight: FontWeight.w500, fontFamily: 'Inter'),
                  prefixIcon: Icon(CupertinoIcons.search, color: theme.primaryColor),
                  suffixIcon: _searchQuery.isNotEmpty 
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, color: textColor.withValues(alpha: 0.4)),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = "");
                          },
                        ) 
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(left: 24.0, top: 16.0, bottom: 8.0),
            child: Text(
              _searchQuery.isEmpty ? "Suggested Players" : "Search Results",
              style: TextStyle(
                color: textColor.withValues(alpha: 0.6), 
                fontWeight: FontWeight.w800, 
                fontFamily: 'Inter', 
                fontSize: 14, 
                letterSpacing: 0.5
              ),
            ),
          ),

          Expanded(
            key: _fgList,
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _meStream,
              builder: (context, meSnap) {
              return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              future: _searchQuery.isEmpty ? _suggestedFuture() : _searchFuture(),
              builder: (context, snapshot) {
                if ((snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)) {
                  return Center(child: CircularProgressIndicator(color: theme.primaryColor));
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text("No users found.", style: TextStyle(color: textColor.withValues(alpha: 0.5))));
                }

                List<dynamic> followingList = [];
                List<dynamic> incomingRequests = [];
                List<dynamic> followersList = [];
                String currentUserName = 'Someone';

                final me = meSnap.data?.data();
                if (me != null) {
                  followingList = me['following'] ?? [];
                  incomingRequests = me['incomingRequests'] ?? [];
                  followersList = me['followers'] ?? [];
                  currentUserName = PublicProfileScreen.publicName(me);
                }

                final users = snapshot.data!.where((doc) {
                  if (doc.id == currentUserId) return false;
                  
                  final data = doc.data();
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
                        Icon(Icons.search_off_rounded, size: 64, color: textColor.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        Text("No players match your search.", style: TextStyle(color: textColor.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  itemCount: users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = users[index];
                    final data = doc.data();
                    
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
                ),
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

  Widget _buildUserAvatar(BuildContext context, String? avatarData, {double size = 48}) {
    final theme = Theme.of(context);
    if (avatarData == null || avatarData.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: theme.primaryColor.withValues(alpha: 0.2),
        child: Icon(Icons.person_rounded, size: size * 0.6, color: theme.primaryColor),
      );
    }
    if (avatarData.startsWith('data:image')) {
      try {
        final bytes = base64Decode(avatarData.split(',').last);
        return CircleAvatar(radius: size / 2, backgroundImage: MemoryImage(bytes), backgroundColor: theme.primaryColor.withValues(alpha: 0.2));
      } catch (e) {
        return CircleAvatar(radius: size / 2, backgroundColor: theme.disabledColor.withValues(alpha: 0.2), child: Icon(Icons.broken_image_rounded, size: size * 0.5, color: theme.disabledColor));
      }
    } else {
      return CircleAvatar(radius: size / 2, backgroundImage: NetworkImage(avatarData), backgroundColor: theme.primaryColor.withValues(alpha: 0.2));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    String name = PublicProfileScreen.publicName(widget.userData);
    String avatarUrl = widget.userData['avatar'] ?? '';
    int xp = widget.userData['xp'] ?? 0;
    
    bool isFriends = isFollowing && widget.isTargetFollowingMe;

    return GestureDetector(
      onTap: () => PublicProfileScreen.open(context, widget.targetUserId),
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          OnlineBadge(online: PresenceService.isOnline(widget.userData), size: 52, child: _buildUserAvatar(context, avatarUrl, size: 52)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFamily: 'Inter', color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF2196F3)),
                    const SizedBox(width: 2),
                    Text(
                      "$xp XP", 
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2196F3)),
                    ),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(width: 12),
          
          GestureDetector(
            onTap: () async {
              if (widget.currentUserId == null) return;
              
              final currentUserRef = FirebaseFirestore.instance.collection('users').doc(widget.currentUserId);
              final targetUserRef = FirebaseFirestore.instance.collection('users').doc(widget.targetUserId);
              
              setState(() => isFollowing = !isFollowing);
              
              try {
                final batch = FirebaseFirestore.instance.batch();
                if (isFollowing) {
                  // Following someone who already follows you = follow back:
                  // you become friends, and they are not asked to follow back.
                  final bool followBack = widget.isTargetFollowingMe;
                  final payload = {
                    'type': followBack ? 'follow_back' : 'new_follower',
                    'title': followBack ? 'New Friend!' : 'New Follower',
                    'body': followBack
                        ? '${widget.currentUserName} followed you back. You are now friends!'
                        : '${widget.currentUserName} started following you.',
                    'fromUserId': widget.currentUserId,
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                    'isRead': false,
                  };

                  batch.update(targetUserRef, {
                    'incomingRequests': followBack
                        ? FieldValue.arrayRemove([widget.currentUserId])
                        : FieldValue.arrayUnion([widget.currentUserId]),
                    'followers': FieldValue.arrayUnion([widget.currentUserId]),
                    'notifications': FieldValue.arrayUnion([payload]),
                  });
                  batch.update(currentUserRef, {
                    'following': FieldValue.arrayUnion([widget.targetUserId]),
                    // Their follow request is answered.
                    'incomingRequests': FieldValue.arrayRemove([widget.targetUserId]),
                  });
                } else {
                  batch.update(targetUserRef, {
                    'followers': FieldValue.arrayRemove([widget.currentUserId]),
                    'incomingRequests': FieldValue.arrayRemove([widget.currentUserId]),
                  });
                  batch.update(currentUserRef, {
                    'following': FieldValue.arrayRemove([widget.targetUserId])
                  });
                }
                await batch.commit();
              } catch (e) {
                setState(() => isFollowing = !isFollowing);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isFriends ? Colors.green.shade600 
                     : isFollowing ? theme.disabledColor.withValues(alpha: 0.2) 
                     : theme.primaryColor,
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
                      color: isFriends ? Colors.white : (isFollowing ? textColor.withValues(alpha: 0.6) : theme.colorScheme.onPrimary),
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
    ));
  }
}