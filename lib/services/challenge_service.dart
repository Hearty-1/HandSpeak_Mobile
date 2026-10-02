import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class ChallengeService {
  /// Sends a game invite notification to a specific friend's Firestore document
  static Future<bool> sendChallengeInvite({
    required String recipientUid,
    required String roomCode,
    required String challengeTitle,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;
      
      // Fallback to email prefix if displayName is null
      final senderName = currentUser.displayName ?? 
                         currentUser.email?.split('@')[0] ?? 
                         'A friend';

      // Build the notification object matching what NotificationsScreen expects
      final notificationEntry = {
        'title': 'New Challenge Invite! 🎮',
        'body': '$senderName invited you to join: $challengeTitle',
        'type': 'challenge_invite',
        'roomCode': roomCode,
        'fromUserId': currentUser.uid, 
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isRead': false,
      };

      // Append the notification to the recipient's Firestore document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(recipientUid)
          .update({
        'notifications': FieldValue.arrayUnion([notificationEntry]),
      });
      
      return true; // Successfully sent
    } catch (e) {
      debugPrint('Error sending challenge invite: $e');
      return false; // Failed to send
    }
  }
}