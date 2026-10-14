import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// New followers (follow back / ignore) and friends (mutual follows).
class FriendRequestsScreen extends StatefulWidget {
  /// User to highlight (the one a tapped notification is about).
  final String? highlightUid;

  const FriendRequestsScreen({Key? key, this.highlightUid}) : super(key: key);

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  // MLBB-Style Follow Back Logic
  Future<void> _acceptRequest(String requesterUid) async {
    if (currentUserId.isEmpty) return;

    final currentRef = FirebaseFirestore.instance.collection('users').doc(currentUserId);
    final requesterRef = FirebaseFirestore.instance.collection('users').doc(requesterUid);

    final currentUserDoc = await currentRef.get();
    final currentUserData = currentUserDoc.data() ?? {};
    final String currentUserName = currentUserData['name'] ?? currentUserData['displayName'] ?? 'A player';

    final batch = FirebaseFirestore.instance.batch();

    // 1. Current User: Add them to your following list, clear the notification.
    batch.update(currentRef, {
      'following': FieldValue.arrayUnion([requesterUid]),
      'incomingRequests': FieldValue.arrayRemove([requesterUid]),
    });

    final notificationPayload = {
      'type': 'follow_back',
      'title': 'New Friend!',
      'body': '$currentUserName followed you back. You are now friends!',
      'fromUserId': currentUserId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'isRead': false,
    };

    // 2. Requester: Add you to their followers. You are now mutuals (Friends).
    // Not into their incomingRequests: they already follow you, so they
    // must not be asked to follow back.
    batch.update(requesterRef, {
      'followers': FieldValue.arrayUnion([currentUserId]),
      'incomingRequests': FieldValue.arrayRemove([currentUserId]),
      'notifications': FieldValue.arrayUnion([notificationPayload]),
    });

    await batch.commit();
  }

  /// Requests left over from users you already follow (old follow-back bug):
  /// removed once so they stop showing as "Follow Back".
  bool _cleaning = false;
  void _cleanUpStaleRequests(List<String> stale) {
    if (stale.isEmpty || _cleaning || currentUserId.isEmpty) return;
    _cleaning = true;
    FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .update({'incomingRequests': FieldValue.arrayRemove(stale)})
        .catchError((e) => debugPrint("Could not clean follow requests: $e"))
        .whenComplete(() => _cleaning = false);
  }

  Future<void> _declineRequest(String requesterUid) async {
    if (currentUserId.isEmpty) return;

    final currentRef = FirebaseFirestore.instance.collection('users').doc(currentUserId);

    // Remove from incomingRequests to clear the notification UI.
    await currentRef.update({
      'incomingRequests': FieldValue.arrayRemove([requesterUid]),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "Followers",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: theme.primaryColor));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Text(
                "User not found.", 
                style: TextStyle(color: textColor.withOpacity(0.5))
              ),
            );
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final following = {for (final u in (userData?['following'] as List?) ?? const []) u.toString()};
          final followers = {for (final u in (userData?['followers'] as List?) ?? const []) u.toString()};
          final incoming = [for (final u in (userData?['incomingRequests'] as List?) ?? const []) u.toString()];

          // Someone you already follow back is a friend, not a request.
          final pending = incoming.where((u) => !following.contains(u)).toSet().toList();
          final friends = following.where(followers.contains).toList();
          _cleanUpStaleRequests(incoming.where(following.contains).toList());

          if (pending.isEmpty && friends.isEmpty) {
            return Center(
              child: Text(
                "No new followers.",
                style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 16, fontWeight: FontWeight.w600),
              ),
            );
          }

          Widget header(String text) => Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                child: Text(
                  text,
                  style: TextStyle(color: textColor.withOpacity(0.6), fontWeight: FontWeight.w800, fontSize: 14),
                ),
              );

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (pending.isNotEmpty) ...[
                header("New Followers"),
                for (final uid in pending)
                  _RequestTile(
                    key: ValueKey('req_$uid'),
                    requesterUid: uid,
                    highlighted: uid == widget.highlightUid,
                    onAccept: () => _acceptRequest(uid),
                    onDecline: () => _declineRequest(uid),
                  ),
              ],
              if (friends.isNotEmpty) ...[
                header("Friends"),
                for (final uid in friends)
                  _RequestTile(
                    key: ValueKey('friend_$uid'),
                    requesterUid: uid,
                    isFriend: true,
                    highlighted: uid == widget.highlightUid,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final String requesterUid;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  /// Mutual follow: shows a "Friends" label instead of the buttons.
  final bool isFriend;
  final bool highlighted;

  const _RequestTile({
    Key? key,
    required this.requesterUid,
    this.onAccept,
    this.onDecline,
    this.isFriend = false,
    this.highlighted = false,
  }) : super(key: key);

  Widget _buildAvatarImage(BuildContext context, String? avatarData, {double size = 48}) {
    final theme = Theme.of(context);
    if (avatarData == null || avatarData.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: theme.primaryColor.withOpacity(0.2),
        child: Icon(Icons.person_rounded, color: theme.primaryColor, size: size * 0.5),
      );
    }
    if (avatarData.startsWith('data:image')) {
      try {
        final bytes = base64Decode(avatarData.split(',').last);
        return CircleAvatar(
          radius: size / 2,
          backgroundImage: MemoryImage(bytes),
          backgroundColor: theme.primaryColor.withOpacity(0.2),
        );
      } catch (e) {
        return CircleAvatar(
          radius: size / 2,
          backgroundColor: theme.disabledColor.withOpacity(0.2),
          child: Icon(Icons.broken_image_rounded, color: theme.disabledColor, size: size * 0.5),
        );
      }
    } else {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(avatarData),
        backgroundColor: theme.primaryColor.withOpacity(0.2),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(requesterUid).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final name = data?['name'] ?? data?['displayName'] ?? 'Player';
        final avatar = data?['avatar'] ?? data?['photoURL'];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: highlighted ? Border.all(color: theme.primaryColor, width: 2) : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              _buildAvatarImage(context, avatar, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              if (isFriend)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_alt_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        "Friends",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ],
                  ),
                )
              else ...[
              // --- FOLLOW BACK BUTTON ---
              GestureDetector(
                onTap: onAccept,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "Follow Back",
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // --- IGNORE BUTTON ---
              GestureDetector(
                onTap: onDecline,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: textColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "Ignore",
                    style: TextStyle(
                      color: textColor.withOpacity(0.6),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              ],
            ],
          ),
        );
      },
    );
  }
}