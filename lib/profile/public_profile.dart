import '/services/presence_service.dart';
import '/widgets/guide_tour.dart';
import '/services/live.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '/profile/achievements.dart';
import '/providers/language_provider.dart';
import '/services/app_haptics.dart';
import '/services/progress_service.dart';
import '/widgets/button_3d.dart';

/// Another student's public profile, opened from the leaderboard, the group
/// challenge and the friends list.
///
/// Privacy (school children): only what classmates already see in games is
/// shown: the display name (never the full name), the avatar, level, XP,
/// streak, stars, badges and category progress. Never the email, section,
/// student ID, birthday or when they were last online.
class PublicProfileScreen extends StatelessWidget {
  final String userId;
  const PublicProfileScreen({super.key, required this.userId});

  /// Opens [userId]'s profile; your own id opens nothing (use the Profile tab).
  static void open(BuildContext context, String? userId) {
    if (userId == null || userId.isEmpty || userId.startsWith('guest_')) return;
    AppHaptics.selection();
    Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: userId)));
  }

  /// The name others see: the chosen display name, else the first name only.
  static String publicName(Map<String, dynamic> d) {
    final display = (d['displayName'] ?? '').toString().trim();
    if (display.isNotEmpty) return display;
    final first = (d['firstName'] ?? '').toString().trim();
    if (first.isNotEmpty) return first;
    // Older, Google and dashboard-made accounts only have the full `name`:
    // show its first word (the first name), never the full name.
    final full = (d['name'] ?? '').toString().trim();
    if (full.isNotEmpty && !full.contains('@')) return full.split(RegExp(r'\s+')).first;
    return 'Student';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      floatingActionButtonLocation: PetAssistant.location,
      floatingActionButton: const PetAssistant(),
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(L.t('Player Profile', 'Profile ng Manlalaro'),
            style: TextStyle(fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: Live.doc(FirebaseFirestore.instance.collection('users').doc(userId)),
        builder: (context, snap) {
          if (snap.hasError) {
            return _Message(icon: Icons.lock_outline_rounded, text: L.t('This profile is private.', 'Pribado ang profile na ito.'));
          }
          if (!snap.hasData) return Center(child: CircularProgressIndicator(color: theme.primaryColor));
          final d = snap.data!.data();
          if (d == null) return _Message(icon: Icons.person_off_rounded, text: L.t('Player not found.', 'Hindi makita ang manlalaro.'));
          return _ProfileBody(userId: userId, data: d, myId: me);
        },
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final String userId;
  final Map<String, dynamic> data;
  final String? myId;
  const _ProfileBody({required this.userId, required this.data, required this.myId});

  int _n(String k) => (data[k] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final name = PublicProfileScreen.publicName(data);
    final xp = _n('xp');
    final level = xp ~/ 1000 + 1;
    final inLevel = xp % 1000;
    final badges = buildAchievements(data);
    final earned = badges.where((b) => b.isUnlocked).toList()
      ..sort((a, b) => (b.unlockedAt ?? DateTime(2000)).compareTo(a.unlockedAt ?? DateTime(2000)));
    final followers = (data['followers'] as List?)?.length ?? 0;
    final following = (data['following'] as List?)?.length ?? 0;
    final isMe = myId == userId;

    final modules = <(String, String, IconData)>[
      (L.t('Alphabet', 'Alpabeto'), 'alphabetXp', Icons.abc_rounded),
      (L.t('Numbers', 'Mga Numero'), 'numbersXp', Icons.pin_rounded),
      (L.t('Greetings', 'Mga Pagbati'), 'phraseXp', Icons.waving_hand_rounded),
      (L.t('Civic Observances', 'Pagdiriwang Pansibiko'), 'civicXp', Icons.flag_rounded),
    ];

    Widget card({required Widget child}) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: child,
        );
    Widget title(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(t, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: onSurface)),
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            // ---- who
            Column(children: [
              OnlineBadge(
                online: PresenceService.isOnline(data),
                size: 104,
                child: _Avatar(source: (data['avatar'] ?? data['avatarUrl'] ?? data['photoUrl'] ?? '').toString(), name: name, size: 104),
              ),
              const SizedBox(height: 12),
              Text(name, textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: onSurface)),
              const SizedBox(height: 4),
              if (PresenceService.isOnline(data))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(L.t('● Online now', '● Online ngayon'),
                      style: const TextStyle(color: Color(0xFF22A06B), fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              Text(L.t('Level $level', 'Level $level'),
                  style: TextStyle(fontWeight: FontWeight.w800, color: theme.primaryColor, fontSize: 15)),
              const SizedBox(height: 8),
              Text(L.t('$followers followers · $following following', '$followers tagasunod · $following sinusundan'),
                  style: TextStyle(color: onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              if (!isMe && myId != null) _FollowButton(myId: myId!, targetId: userId, targetData: data),
            ]),
            const SizedBox(height: 20),

            // ---- level
            card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(L.t('Level $level', 'Level $level'), style: TextStyle(fontWeight: FontWeight.w900, color: onSurface, fontSize: 16))),
                  Text('$inLevel / 1000 XP', style: TextStyle(fontWeight: FontWeight.w700, color: onSurface.withValues(alpha: 0.6))),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: inLevel / 1000,
                    minHeight: 10,
                    backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(theme.primaryColor),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),

            // ---- stats
            Row(children: [
              _Stat(icon: Icons.local_fire_department_rounded, color: const Color(0xFFE8711C), value: '${_n('streak')}', label: L.t('Day streak', 'Sunod-sunod na araw')),
              const SizedBox(width: 10),
              _Stat(icon: Icons.bolt_rounded, color: const Color(0xFF2196F3), value: '$xp', label: L.t('Total XP', 'Kabuuang XP')),
              const SizedBox(width: 10),
              _Stat(icon: Icons.star_rounded, color: const Color(0xFFFFB300), value: '${_n('stars')}', label: L.t('Stars', 'Bituin')),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _Stat(icon: Icons.emoji_events_rounded, color: const Color(0xFF8E24AA), value: '${earned.length}', label: L.t('Badges', 'Badge')),
              const SizedBox(width: 10),
              _Stat(icon: Icons.calendar_today_rounded, color: const Color(0xFF2E9E4F), value: '${ProgressService.weekXpOf(data)}', label: L.t('XP this week', 'XP ngayong linggo')),
            ]),
            const SizedBox(height: 14),

            // ---- badges
            card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                title(L.t('Badges earned', 'Mga nakuhang badge')),
                if (earned.isEmpty)
                  Text(L.t('No badges yet.', 'Wala pang badge.'), style: TextStyle(color: onSurface.withValues(alpha: 0.6)))
                else
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final b in earned.take(12))
                        Tooltip(
                          message: '${b.title}: ${b.description}',
                          triggerMode: TooltipTriggerMode.tap,
                          child: SizedBox(
                            width: 72,
                            child: Column(children: [
                              BadgeMedallion(badge: b, size: 56),
                              const SizedBox(height: 6),
                              Text(b.title,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: onSurface)),
                            ]),
                          ),
                        ),
                    ],
                  ),
                if (earned.length > 12) ...[
                  const SizedBox(height: 10),
                  Text(L.t('+${earned.length - 12} more', '+${earned.length - 12} pa'),
                      style: TextStyle(fontWeight: FontWeight.w700, color: onSurface.withValues(alpha: 0.6))),
                ],
              ]),
            ),
            const SizedBox(height: 14),

            // ---- categories
            card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                title(L.t('Category progress', 'Progreso sa mga kategorya')),
                for (final (label, field, icon) in modules) ...[
                  Row(children: [
                    Icon(icon, color: theme.primaryColor, size: 22),
                    const SizedBox(width: 10),
                    Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: onSurface))),
                    Text('${_n(field)} XP', style: TextStyle(fontWeight: FontWeight.w800, color: onSurface.withValues(alpha: 0.7))),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (_n(field) / 1000).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(theme.primaryColor),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Follow / Following / Friends, the same rules as Add Friend.
class _FollowButton extends StatefulWidget {
  final String myId;
  final String targetId;
  final Map<String, dynamic> targetData;
  const _FollowButton({required this.myId, required this.targetId, required this.targetData});

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iFollow = ((widget.targetData['followers'] as List?) ?? const []).contains(widget.myId);
    final followsMe = ((widget.targetData['following'] as List?) ?? const []).contains(widget.myId);
    final friends = iFollow && followsMe;
    final label = friends
        ? L.t('Friends', 'Magkaibigan')
        : iFollow
            ? L.t('Following', 'Sinusundan')
            : (followsMe ? L.t('Follow back', 'Sundan pabalik') : L.t('Follow', 'Sundan'));
    final filled = !iFollow;
    return Pressable3D(
      child: ElevatedButton.icon(
        onPressed: _busy ? null : () => _toggle(iFollow, followsMe),
        style: ElevatedButton.styleFrom(
          backgroundColor: friends ? Colors.green.shade600 : (filled ? theme.primaryColor : theme.cardColor),
          foregroundColor: filled || friends ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: Button3DBorder(borderRadius: BorderRadius.circular(24)),
        ),
        icon: Icon(friends ? Icons.people_rounded : (iFollow ? Icons.check_rounded : Icons.person_add_rounded)),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }

  Future<void> _toggle(bool iFollow, bool followsMe) async {
    setState(() => _busy = true);
    final db = FirebaseFirestore.instance;
    final meRef = db.collection('users').doc(widget.myId);
    final themRef = db.collection('users').doc(widget.targetId);
    try {
      final batch = db.batch();
      if (!iFollow) {
        final meDoc = await meRef.get();
        final myName = PublicProfileScreen.publicName(meDoc.data() ?? const {});
        final payload = {
          'type': followsMe ? 'follow_back' : 'new_follower',
          'title': followsMe ? 'New Friend!' : 'New Follower',
          'body': followsMe ? '$myName followed you back. You are now friends!' : '$myName started following you.',
          'fromUserId': widget.myId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'isRead': false,
        };
        batch.update(themRef, {
          'incomingRequests': followsMe ? FieldValue.arrayRemove([widget.myId]) : FieldValue.arrayUnion([widget.myId]),
          'followers': FieldValue.arrayUnion([widget.myId]),
          'notifications': FieldValue.arrayUnion([payload]),
        });
        batch.update(meRef, {
          'following': FieldValue.arrayUnion([widget.targetId]),
          'incomingRequests': FieldValue.arrayRemove([widget.targetId]),
        });
      } else {
        batch.update(themRef, {
          'followers': FieldValue.arrayRemove([widget.myId]),
          'incomingRequests': FieldValue.arrayRemove([widget.myId]),
        });
        batch.update(meRef, {'following': FieldValue.arrayRemove([widget.targetId])});
      }
      await batch.commit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.t('Could not update. Try again.', 'Hindi ma-update. Subukang muli.'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _Stat({required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
          ),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String source;
  final String name;
  final double size;
  const _Avatar({required this.source, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = Container(
      color: theme.primaryColor.withValues(alpha: 0.18),
      alignment: Alignment.center,
      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w900, color: theme.primaryColor)),
    );
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    Widget child = initial;
    final s = source.trim();
    try {
      if (s.startsWith('data:image')) {
        child = Image(
          image: ResizeImage(MemoryImage(base64Decode(s.split(',').last)), width: px, height: px, allowUpscaling: false),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => initial,
        );
      } else if (s.startsWith('http')) {
        child = Image(
          image: ResizeImage(NetworkImage(s), width: px, height: px, allowUpscaling: false),
          fit: BoxFit.cover,
          frameBuilder: (context, img, frame, sync) => (sync || frame != null) ? img : initial,
          errorBuilder: (_, _, _) => initial,
        );
      }
    } catch (_) {}
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.primaryColor, width: 3)),
      child: ClipOval(child: child),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 56, color: c),
        const SizedBox(height: 12),
        Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: c, fontSize: 16)),
      ]),
    );
  }
}
