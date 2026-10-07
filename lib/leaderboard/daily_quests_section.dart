import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/services/daily_challenge_service.dart';

/// "Daily Quests" in the Arena: three quests picked for this learner's pace
/// and weak spots, live progress, a claim button, and the history of every
/// completed quest with badge progress per track.
class DailyQuestsSection extends StatefulWidget {
  final double scale;
  const DailyQuestsSection({super.key, required this.scale});

  @override
  State<DailyQuestsSection> createState() => _DailyQuestsSectionState();
}

class _DailyQuestsSectionState extends State<DailyQuestsSection> {
  final DailyChallengeService _service = DailyChallengeService();
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  Map<String, dynamic> _user = {};
  Map<QuestMetric, int>? _metrics;
  bool _loading = true;
  final Set<String> _claiming = {};
  Timer? _debounce;

  double get s => widget.scale;

  @override
  void initState() {
    super.initState();
    if (_uid.isEmpty) return;
    _service.ensureTodayQuests().catchError((e) => debugPrint('Daily quests: $e'));
    _sub = FirebaseFirestore.instance.collection('users').doc(_uid).snapshots().listen((snap) {
      _user = snap.data() ?? {};
      if (mounted) setState(() {});
      // Progress depends on attempts written elsewhere; refresh (debounced)
      // whenever the user document changes (XP, lessons, streak...).
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), _refreshProgress);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _refreshProgress() async {
    try {
      final m = await _service.todayProgress(_user);
      if (mounted) setState(() {
        _metrics = m;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Daily quest progress: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  LearnerProfile? get _profile {
    final p = _user['learnerProfile'];
    return p is Map ? LearnerProfile.fromMap(Map<String, dynamic>.from(p)) : null;
  }

  List<QuestDef> get _todayQuests => [
        for (final e in (_user['dailyChallenges'] as List? ?? const []))
          if (e is Map && questById('${e['id']}') != null) questById('${e['id']}')!
      ];

  Set<String> get _completedIds => Set<String>.from(_user['completedDailyChallenges'] ?? const []);

  Future<void> _claim(QuestDef q) async {
    if (_claiming.contains(q.id)) return;
    setState(() => _claiming.add(q.id));
    HapticFeedback.mediumImpact();
    final ok = await _service.claim(q, profile: _profile);
    if (!mounted) return;
    setState(() => _claiming.remove(q.id));
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: q.info.color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(children: [
          const Icon(Icons.celebration_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Quest complete: ${q.title}  +${q.reward} XP',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ]),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final profile = _profile;
    final quests = _todayQuests;
    final completed = _completedIds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Daily Quests',
                style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w900, fontFamily: 'Inter', color: textColor)),
            const Spacer(),
            if (profile != null) _PaceChip(profile: profile, scale: s, onTap: () => _showProfileSheet(profile)),
          ],
        ),
        SizedBox(height: 4 * s),
        Text(
          'Picked for you today · new quests at midnight',
          style: TextStyle(fontSize: 12 * s, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.55)),
        ),
        SizedBox(height: 14 * s),
        if (quests.isEmpty && !_loading)
          _emptyState(theme, completed.length >= questCatalog.length)
        else if (quests.isEmpty)
          Padding(
            padding: EdgeInsets.all(20 * s),
            child: Center(child: CircularProgressIndicator(color: theme.primaryColor)),
          )
        else
          ...quests.map((q) {
            final value = _metrics == null ? null : _service.progressFor(q, _metrics!);
            return _QuestCard(
              quest: q,
              value: value,
              claimed: completed.contains(q.id),
              claiming: _claiming.contains(q.id),
              scale: s,
              onClaim: () => _claim(q),
            );
          }),
        SizedBox(height: 4 * s),
        _historyTile(theme, completed),
      ],
    );
  }

  Widget _emptyState(ThemeData theme, bool allDone) {
    final textColor = theme.colorScheme.onSurface;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20 * s),
      margin: EdgeInsets.only(bottom: 12 * s),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20 * s),
        border: Border.all(color: textColor.withValues(alpha: 0.08)),
      ),
      child: Column(children: [
        Icon(allDone ? Icons.emoji_events_rounded : Icons.hourglass_empty_rounded,
            color: theme.primaryColor, size: 36 * s),
        SizedBox(height: 8 * s),
        Text(
          allDone ? 'You have completed every daily quest. Legendary!' : 'Check back tomorrow for new quests!',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, color: textColor.withValues(alpha: 0.7)),
        ),
      ]),
    );
  }

  Widget _historyTile(ThemeData theme, Set<String> completed) {
    final textColor = theme.colorScheme.onSurface;
    final tracks = DailyChallengeService.trackProgress(completed, unexplored: _profile?.unexplored);
    final badges = tracks.values.where((v) => v.$1 >= v.$2).length;
    return GestureDetector(
      onTap: _showHistorySheet,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 14 * s),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            theme.primaryColor.withValues(alpha: 0.16),
            theme.primaryColor.withValues(alpha: 0.06),
          ]),
          borderRadius: BorderRadius.circular(18 * s),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            padding: EdgeInsets.all(8 * s),
            decoration: BoxDecoration(color: theme.cardColor, shape: BoxShape.circle),
            child: Icon(Icons.history_edu_rounded, color: theme.primaryColor, size: 22 * s),
          ),
          SizedBox(width: 12 * s),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Quest History',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5 * s, color: textColor)),
              Text('${completed.length} completed · $badges/${QuestTrack.values.length} quest badges',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12 * s, color: textColor.withValues(alpha: 0.6))),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: textColor.withValues(alpha: 0.5)),
        ]),
      ),
    );
  }

  void _showProfileSheet(LearnerProfile p) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final color = _paceColor(p.pace);
    String pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24 * s, 12 * s, 24 * s, 24 * s),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: _grabber(textColor)),
            SizedBox(height: 16 * s),
            Row(children: [
              Icon(_paceIcon(p.pace), color: color, size: 30 * s),
              SizedBox(width: 10 * s),
              Text(p.paceLabel,
                  style: TextStyle(fontSize: 22 * s, fontWeight: FontWeight.w900, color: textColor, fontFamily: 'Inter')),
            ]),
            SizedBox(height: 8 * s),
            Text(p.paceReason, style: TextStyle(color: textColor.withValues(alpha: 0.7), height: 1.4)),
            SizedBox(height: 18 * s),
            Text('Based on your last 14 days',
                style: TextStyle(fontWeight: FontWeight.w800, color: textColor.withValues(alpha: 0.6), fontSize: 12 * s)),
            SizedBox(height: 10 * s),
            Wrap(spacing: 10 * s, runSpacing: 10 * s, children: [
              _stat('Active days', '${p.activeDays}/14', Icons.event_available_rounded, color),
              _stat('Levels / day', p.levelsPerActiveDay.toStringAsFixed(1), Icons.today_rounded, color),
              _stat('Levels / hour', p.levelsPerHour.toStringAsFixed(1), Icons.speed_rounded, color),
              _stat('Completion', pct(p.completionRate), Icons.task_alt_rounded, color),
              _stat('Sign accuracy', pct(p.signAccuracy), Icons.gps_fixed_rounded, color),
              _stat('Streak', '${p.streak} days', Icons.local_fire_department_rounded, color),
            ]),
            if (p.weakestCategory != null || p.unexplored.isNotEmpty) ...[
              SizedBox(height: 16 * s),
              if (p.weakestCategory != null)
                _note(Icons.fitness_center_rounded, 'Focus area: ${questCategoryNames[p.weakestCategory] ?? p.weakestCategory}'),
              if (p.unexplored.isNotEmpty)
                _note(Icons.explore_rounded,
                    'Not tried yet: ${p.unexplored.map((c) => questCategoryNames[c] ?? c).join(', ')}'),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _grabber(Color c) => Container(
      width: 40, height: 4, decoration: BoxDecoration(color: c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)));

  Widget _stat(String label, String value, IconData icon, Color color) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: 100 * s,
      padding: EdgeInsets.all(10 * s),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14 * s)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18 * s, color: color),
        SizedBox(height: 6 * s),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16 * s, color: textColor)),
        Text(label, style: TextStyle(fontSize: 11 * s, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.6))),
      ]),
    );
  }

  Widget _note(IconData icon, String text) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.only(bottom: 6 * s),
      child: Row(children: [
        Icon(icon, size: 16 * s, color: textColor.withValues(alpha: 0.6)),
        SizedBox(width: 8 * s),
        Expanded(child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: textColor.withValues(alpha: 0.75)))),
      ]),
    );
  }

  void _showHistorySheet() {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        builder: (context, controller) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _service.historyStream(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const [];
            final ids = {for (final d in docs) d.id, ..._completedIds};
            final tracks = DailyChallengeService.trackProgress(ids, unexplored: _profile?.unexplored);
            return ListView(
              controller: controller,
              padding: EdgeInsets.fromLTRB(20 * s, 12 * s, 20 * s, 32 * s),
              children: [
                Center(child: _grabber(textColor)),
                SizedBox(height: 16 * s),
                Text('Quest History',
                    style: TextStyle(fontSize: 22 * s, fontWeight: FontWeight.w900, color: textColor, fontFamily: 'Inter')),
                SizedBox(height: 4 * s),
                Text('Finish every quest in a track to earn its badge.',
                    style: TextStyle(color: textColor.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
                SizedBox(height: 16 * s),
                ...QuestTrack.values.map((t) {
                  final (done, total) = tracks[t]!;
                  final info = questTracks[t]!;
                  final complete = done >= total;
                  return Padding(
                    padding: EdgeInsets.only(bottom: 10 * s),
                    child: Row(children: [
                      Container(
                        padding: EdgeInsets.all(8 * s),
                        decoration: BoxDecoration(color: info.color.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: Icon(complete ? Icons.verified_rounded : info.icon, color: info.color, size: 18 * s),
                      ),
                      SizedBox(width: 12 * s),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Text(info.name,
                                  style: TextStyle(fontWeight: FontWeight.w800, color: textColor, fontSize: 13.5 * s)),
                            ),
                            Text('$done / $total',
                                style: TextStyle(fontWeight: FontWeight.w800, color: info.color, fontSize: 12.5 * s)),
                          ]),
                          SizedBox(height: 6 * s),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: total == 0 ? 0 : done / total,
                              minHeight: 6 * s,
                              backgroundColor: textColor.withValues(alpha: 0.08),
                              valueColor: AlwaysStoppedAnimation(info.color),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  );
                }),
                SizedBox(height: 16 * s),
                Text('Completed quests',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16 * s, color: textColor)),
                SizedBox(height: 10 * s),
                if (docs.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 24 * s),
                    child: Column(children: [
                      Icon(Icons.emoji_events_outlined, size: 40 * s, color: textColor.withValues(alpha: 0.3)),
                      SizedBox(height: 8 * s),
                      Text('No completed quests yet. Your first one is waiting!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textColor.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
                    ]),
                  )
                else
                  ...docs.map((d) {
                    final m = d.data();
                    final q = questById(d.id);
                    final info = q?.info ?? questTracks[QuestTrack.consistency]!;
                    final ts = m['completedAt'];
                    final when = ts is Timestamp ? _formatDate(ts.toDate()) : 'Just now';
                    return Container(
                      margin: EdgeInsets.only(bottom: 10 * s),
                      padding: EdgeInsets.all(12 * s),
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16 * s),
                      ),
                      child: Row(children: [
                        Container(
                          width: 40 * s,
                          height: 40 * s,
                          decoration: BoxDecoration(color: info.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12 * s)),
                          child: Icon(q?.icon ?? Icons.flag_rounded, color: info.color, size: 20 * s),
                        ),
                        SizedBox(width: 12 * s),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${m['title'] ?? q?.title ?? d.id}',
                                style: TextStyle(fontWeight: FontWeight.w800, color: textColor, fontSize: 13.5 * s)),
                            Text('${info.name} · $when',
                                style: TextStyle(color: textColor.withValues(alpha: 0.55), fontSize: 11.5 * s, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                        Text('+${m['reward'] ?? q?.reward ?? 0} XP',
                            style: TextStyle(fontWeight: FontWeight.w900, color: theme.primaryColor, fontSize: 12.5 * s)),
                      ]),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${months[d.month - 1]} ${d.day}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

Color _paceColor(LearnerPace p) => switch (p) {
      LearnerPace.starter => questTracks[QuestTrack.starter]!.color,
      LearnerPace.steady => questTracks[QuestTrack.steady]!.color,
      LearnerPace.fast => questTracks[QuestTrack.fast]!.color,
      LearnerPace.balanced => const Color(0xFF5C6BC0),
    };

IconData _paceIcon(LearnerPace p) => switch (p) {
      LearnerPace.starter => Icons.rocket_launch_rounded,
      LearnerPace.steady => Icons.spa_rounded,
      LearnerPace.fast => Icons.bolt_rounded,
      LearnerPace.balanced => Icons.balance_rounded,
    };

class _PaceChip extends StatelessWidget {
  final LearnerProfile profile;
  final double scale;
  final VoidCallback onTap;
  const _PaceChip({required this.profile, required this.scale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _paceColor(profile.pace);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_paceIcon(profile.pace), size: 15 * scale, color: color),
          SizedBox(width: 5 * scale),
          Text(profile.paceLabel, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12 * scale, color: color)),
          SizedBox(width: 2 * scale),
          Icon(Icons.info_outline_rounded, size: 13 * scale, color: color.withValues(alpha: 0.8)),
        ]),
      ),
    );
  }
}

class _QuestCard extends StatelessWidget {
  final QuestDef quest;
  final int? value; // null while loading
  final bool claimed;
  final bool claiming;
  final double scale;
  final VoidCallback onClaim;
  const _QuestCard({
    required this.quest,
    required this.value,
    required this.claimed,
    required this.claiming,
    required this.scale,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final info = quest.info;
    final v = value ?? 0;
    final ready = !claimed && v >= quest.target;
    final progress = claimed ? 1.0 : (v / quest.target).clamp(0.0, 1.0);
    final isPercent = quest.metric == QuestMetric.signAccuracy;
    final progressText = claimed
        ? 'Done'
        : value == null
            ? '…'
            : isPercent
                ? '$v% / ${quest.target}%'
                : '${v.clamp(0, quest.target)} / ${quest.target}';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: EdgeInsets.only(bottom: 12 * s),
      padding: EdgeInsets.all(16 * s),
      decoration: BoxDecoration(
        color: claimed ? info.color.withValues(alpha: 0.08) : theme.cardColor.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20 * s),
        border: Border.all(
          color: ready ? info.color.withValues(alpha: 0.7) : textColor.withValues(alpha: 0.08),
          width: ready ? 1.6 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: ready ? info.color.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.03),
            blurRadius: ready ? 18 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 46 * s,
          height: 46 * s,
          decoration: BoxDecoration(
            color: info.color.withValues(alpha: claimed ? 0.25 : 0.14),
            borderRadius: BorderRadius.circular(14 * s),
          ),
          child: Icon(claimed ? Icons.check_rounded : quest.icon, color: info.color, size: 24 * s),
        ),
        SizedBox(width: 14 * s),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(quest.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5 * s,
                      color: textColor,
                      decoration: claimed ? TextDecoration.lineThrough : null,
                      decorationColor: textColor.withValues(alpha: 0.4),
                    )),
              ),
              Text('+${quest.reward} XP',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13 * s, color: theme.primaryColor)),
            ]),
            SizedBox(height: 2 * s),
            Text(quest.description,
                style: TextStyle(fontSize: 12 * s, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.6))),
            SizedBox(height: 6 * s),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 2 * s),
              decoration: BoxDecoration(color: info.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(info.name,
                  style: TextStyle(fontSize: 10.5 * s, fontWeight: FontWeight.w800, color: info.color)),
            ),
            SizedBox(height: 10 * s),
            if (ready)
              SizedBox(
                width: double.infinity,
                height: 38 * s,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: info.color,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * s)),
                  ),
                  onPressed: claiming ? null : onClaim,
                  icon: claiming
                      ? SizedBox(width: 16 * s, height: 16 * s, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(Icons.card_giftcard_rounded, size: 18 * s),
                  label: Text('Claim +${quest.reward} XP', style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              )
            else
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10 * s),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (_, p, __) => LinearProgressIndicator(
                        value: p,
                        minHeight: 8 * s,
                        backgroundColor: textColor.withValues(alpha: 0.08),
                        valueColor: AlwaysStoppedAnimation(claimed ? const Color(0xFF4CAF50) : info.color),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10 * s),
                Text(progressText,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12 * s,
                        color: claimed ? const Color(0xFF4CAF50) : textColor.withValues(alpha: 0.6))),
              ]),
          ]),
        ),
      ]),
    );
  }
}
