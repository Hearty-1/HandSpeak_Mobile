import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../profile/friend_requests_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _handleNotificationTap(Map<String, dynamic> notification, List<dynamic> allNotifications) async {
    if (currentUserId.isEmpty) return;

    // 1. Mark as read in Firestore
    if (notification['isRead'] == false) {
      final updatedNotifications = allNotifications.map((n) {
        if (n['timestamp'] == notification['timestamp'] && n['fromUserId'] == notification['fromUserId']) {
          return {...n as Map<String, dynamic>, 'isRead': true};
        }
        return n;
      }).toList();

      await FirebaseFirestore.instance.collection('users').doc(currentUserId).update({
        'notifications': updatedNotifications,
      });
    }

    // 2. Navigate based on notification types
    if ((notification['type'] == 'new_follower' || notification['type'] == 'follow_back') && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const FriendRequestsScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "Notifications",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: theme.iconTheme.copyWith(color: textColor),
        centerTitle: true,
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
                style: TextStyle(color: textColor.withOpacity(0.6)),
              ),
            );
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final List<dynamic> rawNotifications = userData?['notifications'] ?? [];

          if (rawNotifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 64, color: textColor.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text(
                    "You're all caught up!",
                    style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }

          // Sort notifications by timestamp (newest first)
          final List<Map<String, dynamic>> notifications = List<Map<String, dynamic>>.from(rawNotifications);
          notifications.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final bool isRead = notification['isRead'] ?? true;
              final String title = notification['title'] ?? 'Notification';
              final String body = notification['body'] ?? '';
              final String type = notification['type'] ?? 'general';

              // Icons and dynamic colors based on notification type
              IconData iconData = Icons.notifications_rounded;
              Color iconColor = theme.primaryColor;
              if (type == 'new_follower') {
                iconData = Icons.person_add_alt_1_rounded;
                iconColor = const Color(0xFF2196F3);
              } else if (type == 'follow_back') {
                iconData = Icons.people_alt_rounded; 
                iconColor = const Color(0xFF4CAF50);
              }

              return GestureDetector(
                onTap: () => _handleNotificationTap(notification, rawNotifications),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isRead ? theme.cardColor : theme.primaryColor.withOpacity(0.12), 
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isRead ? theme.dividerColor.withOpacity(0.2) : theme.primaryColor.withOpacity(0.5), 
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: iconColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(iconData, color: iconColor, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: isRead ? FontWeight.w700 : FontWeight.w900,
                                fontSize: 16,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              body,
                              style: TextStyle(
                                fontSize: 14,
                                color: isRead ? textColor.withOpacity(0.6) : textColor,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isRead)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF3B30),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}