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

  // Mutual friendship connection logic
  Future<void> _acceptRequest(String requesterUid) async {
    if (currentUserId.isEmpty) return;

    final currentRef = FirebaseFirestore.instance.collection('users').doc(currentUserId);
    final requesterRef = FirebaseFirestore.instance.collection('users').doc(requesterUid);

    final currentUserDoc = await currentRef.get();
    final currentUserData = currentUserDoc.data() ?? {};
    final String currentUserName = currentUserData['name'] ?? currentUserData['displayName'] ?? 'A user';

    final batch = FirebaseFirestore.instance.batch();

    // 1. Current User: Add Requester to BOTH followers & following lists, remove from incoming
    batch.update(currentRef, {
      'followers': FieldValue.arrayUnion([requesterUid]),
      'following': FieldValue.arrayUnion([requesterUid]),
      'incomingRequests': FieldValue.arrayRemove([requesterUid]),
    });

    // Notification payload for Requester
    final notificationPayload = {
      'type': 'request_accepted',
      'title': 'Friend Request Accepted',
      'body': '$currentUserName accepted your friend request. You are now connected!',
      'fromUserId': currentUserId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'isRead': false,
    };

    // 2. Requester: Add Current User to BOTH followers & following lists, remove from outgoing
    batch.update(requesterRef, {
      'followers': FieldValue.arrayUnion([currentUserId]),
      'following': FieldValue.arrayUnion([currentUserId]),
      'outgoingRequests': FieldValue.arrayRemove([currentUserId]),
      'notifications': FieldValue.arrayUnion([notificationPayload]),
    });

    await batch.commit();
  }

  Future<void> _declineRequest(String requesterUid) async {
    if (currentUserId.isEmpty) return;

    final currentRef = FirebaseFirestore.instance.collection('users').doc(currentUserId);
    final requesterRef = FirebaseFirestore.instance.collection('users').doc(requesterUid);

    final batch = FirebaseFirestore.instance.batch();

    // Remove from current user's incoming requests
    batch.update(currentRef, {
      'incomingRequests': FieldValue.arrayRemove([requesterUid]),
    });

    // Remove from requester's outgoing requests
    batch.update(requesterRef, {
      'outgoingRequests': FieldValue.arrayRemove([currentUserId]),
    });

    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      appBar: AppBar(
        title: const Text(
          "Friend Requests",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("User not found."));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final List<dynamic> incomingRequests = userData?['incomingRequests'] ?? [];

          if (incomingRequests.isEmpty) {
            return const Center(
              child: Text(
                "No pending friend requests.",
                style: TextStyle(color: Colors.black54, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(requesterUid).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final name = data?['name'] ?? data?['displayName'] ?? 'User';
        final avatar = data?['avatar'] ?? data?['photoURL'];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
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
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFFFB800).withOpacity(0.2),
                backgroundImage: (avatar != null && avatar.isNotEmpty && !avatar.startsWith('data:image'))
                    ? NetworkImage(avatar)
                    : null,
                child: (avatar == null || avatar.isEmpty || avatar.startsWith('data:image'))
                    ? const Icon(Icons.person, color: Color(0xFFFFB800))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // --- ACCEPT BUTTON ---
              GestureDetector(
                onTap: onAccept,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB800),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "Accept",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // --- DECLINE BUTTON ---
              GestureDetector(
                onTap: onDecline,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "Decline",
                    style: TextStyle(
                      color: Colors.black54,
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