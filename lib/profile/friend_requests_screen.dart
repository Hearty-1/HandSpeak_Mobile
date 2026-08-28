import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({Key? key}) : super(key: key);

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
    batch.update(requesterRef, {
      'followers': FieldValue.arrayUnion([currentUserId]),
      'incomingRequests': FieldValue.arrayUnion([currentUserId]), 
      'notifications': FieldValue.arrayUnion([notificationPayload]),
    });

    await batch.commit();
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
          final List<dynamic> incomingRequests = userData?['incomingRequests'] ?? [];

          if (incomingRequests.isEmpty) {
            return Center(
              child: Text(
                "No new followers.",
                style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 16, fontWeight: FontWeight.w600),
              ),
            );
          }

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: incomingRequests.length,
            itemBuilder: (context, index) {
              final requesterUid = incomingRequests[index].toString();
              return _RequestTile(
                requesterUid: requesterUid,
                onAccept: () => _acceptRequest(requesterUid),
                onDecline: () => _declineRequest(requesterUid),
              );
            },
          );
        },
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final String requesterUid;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _RequestTile({
    Key? key,
    required this.requesterUid,
    required this.onAccept,
    required this.onDecline,
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
          ),
        );
      },
    );
  }
}