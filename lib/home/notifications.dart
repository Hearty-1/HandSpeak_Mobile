import 'package:flutter/material.dart';
import '/services/offline_sync.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../profile/friend_requests_screen.dart';

// Import your arena screen to access RoomLobbyScreen
import '../leaderboard/arena.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Only the newest notifications are kept (they live in an array on the
  /// user doc, which must stay small).
  static const int _maxNotifications = 50;

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(currentUserId);

  @override
  void initState() {
    super.initState();
    _pruneOld();
  }

  // ---------------------------------------------------------------------------
  // Notification data
  // ---------------------------------------------------------------------------

  static int _timeMs(Map<String, dynamic> n) {
    final t = n['timestamp'];
    if (t is int) return t;
    if (t is num) return t.toInt();
    if (t is Timestamp) return t.millisecondsSinceEpoch;
    return 0;
  }

  /// Identity of a notification (no ids are stored in the array).
  static String _keyOf(Map<String, dynamic> n) => '${_timeMs(n)}_${n['type']}_${n['fromUserId']}_${n['roomCode']}';

  /// Reads the latest array, changes it and writes it back in a transaction,
  /// so a notification arriving at the same moment is not lost.
  Future<void> _updateNotifications(List<Map<String, dynamic>> Function(List<Map<String, dynamic>> current) change) async {
    if (currentUserId.isEmpty) return;
    try {
      await OfflineSync.run((tx) async {
        final snap = await tx.get(_userRef);
        final raw = (snap.data()?['notifications'] as List?) ?? const [];
        final current = [for (final n in raw) if (n is Map) Map<String, dynamic>.from(n)];
        tx.update(_userRef, {'notifications': change(current)});
      });
    } catch (e) {
      debugPrint('Could not update notifications: $e');
    }
  }

  Future<void> _pruneOld() async {
    if (currentUserId.isEmpty) return;
    final snap = await _userRef.get();
    final raw = (snap.data()?['notifications'] as List?) ?? const [];
    if (raw.length <= _maxNotifications) return;
    await _updateNotifications((current) {
      current.sort((a, b) => _timeMs(b).compareTo(_timeMs(a)));
      return current.take(_maxNotifications).toList();
    });
  }

  Future<void> _markRead(Map<String, dynamic> notification) {
    final key = _keyOf(notification);
    return _updateNotifications((current) => [
          for (final n in current) _keyOf(n) == key ? {...n, 'isRead': true} : n,
        ]);
  }

  Future<void> _markAllRead() => _updateNotifications((current) => [
        for (final n in current) {...n, 'isRead': true},
      ]);

  /// Swiped away and being deleted: hidden at once (a transaction updates the
  /// stream only after the server answers; a dismissed tile must not return).
  final Set<String> _hidden = {};

  Future<void> _delete(Map<String, dynamic> notification) async {
    final key = _keyOf(notification);
    setState(() => _hidden.add(key));
    await _updateNotifications((current) => current.where((n) => _keyOf(n) != key).toList());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Notification removed'),
        // A SnackBar with an action stays until tapped unless persist is
        // false (Flutter default); close it by itself after a few seconds.
        persist: false,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            await _updateNotifications((current) => [
                  ...current.where((n) => _keyOf(n) != key),
                  notification,
                ]);
            if (mounted) setState(() => _hidden.remove(key));
          },
        ),
      ));
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text("This removes every notification. It can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _updateNotifications((_) => []);
  }

  // ---------------------------------------------------------------------------
  // Tap
  // ---------------------------------------------------------------------------

  Future<void> _handleNotificationTap(Map<String, dynamic> notification) async {
    if (currentUserId.isEmpty) return;

    // 1. Mark as read (in the background; navigation doesn't wait for it).
    if (notification['isRead'] == false) _markRead(notification);

    // 2. Navigate based on notification types
    if ((notification['type'] == 'new_follower' || notification['type'] == 'follow_back') && mounted) {
      // Opens the followers page on that user: under "Friends" when you
      // already follow each other, else under "New Followers" (Follow Back).
      final fromUserId = notification['fromUserId']?.toString();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => FriendRequestsScreen(highlightUid: fromUserId)),
      );
    }
    // Handle Challenge Invite Routing -> Send to Lobby first
    else if (notification['type'] == 'challenge_invite' && mounted) {
      final String roomCode = notification['roomCode'] ?? '';

      if (roomCode.isNotEmpty) {
        // Show loading indicator while joining room
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );

        try {
          final roomRef = FirebaseFirestore.instance.collection('rooms').doc(roomCode);
          final roomSnapshot = await roomRef.get();

          if (roomSnapshot.exists) {
            // Safely add the invited user to the room's player list
            await roomRef.update({
              'playerUids': FieldValue.arrayUnion([currentUserId]),
            });

            final data = roomSnapshot.data() as Map<String, dynamic>;

            if (mounted) {
              Navigator.pop(context); // Remove loading dialog
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => RoomLobbyScreen(
                    roomCode: roomCode,
                    challengeTitle: data['title'] ?? 'Group Challenge',
                    isHost: false, // Invited user is a guest
                  ),
                ),
              );
            }
          } else {
            if (mounted) {
              Navigator.pop(context); // Remove loading dialog
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("This challenge room no longer exists.")),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            Navigator.pop(context); // Remove loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Failed to join room: $e")),
            );
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  /// "Today", "This Week" or "Earlier".
  static String _sectionOf(int ms, DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    final time = DateTime.fromMillisecondsSinceEpoch(ms);
    if (!time.isBefore(day)) return 'Today';
    if (!time.isBefore(day.subtract(const Duration(days: 6)))) return 'This Week';
    return 'Earlier';
  }

  static String _timeAgo(int ms, DateTime now) {
    if (ms <= 0) return '';
    final diff = now.difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[t.month - 1]} ${t.day}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userRef.snapshots(),
      builder: (context, snapshot) {
        final raw = (snapshot.data?.data()?['notifications'] as List?) ?? const [];
        final notifications = [
          for (final n in raw)
            if (n is Map && !_hidden.contains(_keyOf(Map<String, dynamic>.from(n)))) Map<String, dynamic>.from(n),
        ]..sort((a, b) => _timeMs(b).compareTo(_timeMs(a)));
        final hasUnread = notifications.any((n) => n['isRead'] == false);

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
            actions: [
              IconButton(
                tooltip: 'Mark all as read',
                icon: const Icon(Icons.done_all_rounded),
                color: textColor,
                onPressed: hasUnread ? _markAllRead : null,
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: textColor),
                enabled: notifications.isNotEmpty,
                onSelected: (value) {
                  if (value == 'clear') _clearAll();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'clear',
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                        SizedBox(width: 10),
                        Text('Clear all'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: _buildBody(theme, textColor, snapshot, notifications),
        );
      },
    );
  }

  Widget _buildBody(
    ThemeData theme,
    Color textColor,
    AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
    List<Map<String, dynamic>> notifications,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return Center(child: CircularProgressIndicator(color: theme.primaryColor));
    }

    if (!snapshot.hasData || !snapshot.data!.exists) {
      return Center(
        child: Text(
          "User not found.",
          style: TextStyle(color: textColor.withValues(alpha: 0.6)),
        ),
      );
    }

    if (notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_outlined, size: 64, color: textColor.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              "You're all caught up!",
              style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final children = <Widget>[];
    String? section;
    for (final notification in notifications) {
      final s = _sectionOf(_timeMs(notification), now);
      if (s != section) {
        section = s;
        children.add(Padding(
          padding: EdgeInsets.fromLTRB(4, children.isEmpty ? 0 : 12, 4, 10),
          child: Text(
            s,
            style: TextStyle(color: textColor.withValues(alpha: 0.6), fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ));
      }
      children.add(_buildNotificationTile(theme, textColor, notification, now));
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  Widget _buildNotificationTile(ThemeData theme, Color textColor, Map<String, dynamic> notification, DateTime now) {
    final bool isRead = notification['isRead'] ?? true;
    final String title = notification['title'] ?? 'Notification';
    final String body = notification['body'] ?? '';
    final String type = notification['type'] ?? 'general';
    final String time = _timeAgo(_timeMs(notification), now);

    // Icons and dynamic colors based on notification type
    IconData iconData = Icons.notifications_rounded;
    Color iconColor = theme.primaryColor;

    if (type == 'new_follower') {
      iconData = Icons.person_add_alt_1_rounded;
      iconColor = const Color(0xFF2196F3);
    } else if (type == 'follow_back') {
      iconData = Icons.people_alt_rounded;
      iconColor = const Color(0xFF4CAF50);
    } else if (type == 'challenge_invite') {
      iconData = Icons.videogame_asset_rounded;
      iconColor = const Color(0xFFFF9800);
    }

    // Swipe left to delete (Undo in the snackbar).
    return Dismissible(
      key: ValueKey(_keyOf(notification)),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _delete(notification),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () => _handleNotificationTap(notification),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isRead ? theme.cardColor : theme.primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRead ? theme.dividerColor.withValues(alpha: 0.2) : theme.primaryColor.withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
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
                  color: iconColor.withValues(alpha: 0.15),
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
                        color: isRead ? textColor.withValues(alpha: 0.6) : textColor,
                        height: 1.4,
                      ),
                    ),
                    if (time.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        time,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.45)),
                      ),
                    ],
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
      ),
    );
  }
}
