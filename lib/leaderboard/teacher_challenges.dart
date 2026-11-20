import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '/providers/language_provider.dart';
import '/services/daily_challenge_service.dart';

/// "2 from your teacher" on the Home screen's Daily Challenges card: open
/// teacher quests (users/{uid}/assigned_quests, status active, not expired,
/// a metric the app counts). Nothing when there are none.
class TeacherChallengeBadge extends StatelessWidget {
  final double scale;
  const TeacherChallengeBadge({super.key, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: DailyChallengeService().teacherQuests(),
      builder: (context, snap) {
        final open = (snap.data?.docs ?? const [])
            .where((d) => DailyChallengeService.teacherQuestOpen(d.data()))
            .take(DailyChallengeService.maxTeacherQuests)
            .length;
        if (open == 0) return const SizedBox.shrink();
        return Container(
          margin: EdgeInsets.only(top: 8 * scale),
          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.school_rounded, size: 14 * scale, color: const Color(0xFF7E57C2)),
            SizedBox(width: 4 * scale),
            Text(L.t('$open from your teacher', '$open mula sa guro'),
                style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w900, color: const Color(0xFF7E57C2))),
          ]),
        );
      },
    );
  }
}
