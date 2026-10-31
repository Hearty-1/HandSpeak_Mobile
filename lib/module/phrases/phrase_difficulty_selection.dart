import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/module/phrases/phraseAct.dart';
import 'package:provider/provider.dart';
import '../../providers/sound_provider.dart';
import '../../services/progress_service.dart';
import 'phrase_activity.dart'; 
import '/services/role_service.dart';
import '/providers/language_provider.dart';

class PhraseDifficultySelectionScreen extends StatefulWidget {
  final ActivityCategoryConfig config;
  const PhraseDifficultySelectionScreen({super.key, this.config = ActivityCategoryConfig.phrases});

  @override
  State<PhraseDifficultySelectionScreen> createState() => _PhraseDifficultySelectionScreenState();
}

class _PhraseDifficultySelectionScreenState extends State<PhraseDifficultySelectionScreen> {
  late dynamic _soundProvider;

  @override
  void initState() {
    super.initState(); 
    try {
      Provider.of<SoundProvider>(context, listen: false).claimBgm(this, BgmType.menu); // bgm.mp3 while open 
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _soundProvider = Provider.of<SoundProvider>(context, listen: false);
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _soundProvider.releaseBgm(this);
    } catch (_) {}
    super.dispose(); 
  }

  Map<String, dynamic> _getThemeStyles(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor.toARGB32();

    if (bgColor == 0xFF080928) { // Galaxy Explorer
      return {
        'primary': const Color(0xFF7C4DFF), 
        'text': const Color(0xFFB9A6FF),
        'appBarIcon': const Color(0xFFB9A6FF),
        'cardBg': const Color(0xFF1B1A4B),
      };
    }
    if (bgColor == 0xFF1D3D3A) { // Enchanted Forest
      return {
        'primary': const Color(0xFFD7B3A1), 
        'text': const Color(0xFFF2F5F4),
        'appBarIcon': const Color(0xFFF2F5F4),
        'cardBg': const Color(0xFF4D7C73),
      };
    }
    if (bgColor == 0xFF001B3A) { // Deep Ocean
      return {
        'primary': const Color(0xFF00E5FF), 
        'text': Colors.white,
        'appBarIcon': Colors.white,
        'cardBg': Colors.black54,
      };
    }
    if (bgColor == 0xFFE0EAFC) { // Cloudy Sky
      return {
        'primary': const Color(0xFF5C7CFA), 
        'text': const Color(0xFF1E1E1E),
        'appBarIcon': const Color(0xFF322144),
        'cardBg': Colors.white.withValues(alpha: 0.9),
      };
    }
    
    // Default Theme
    return {
      'primary': const Color(0xFFFF6B8B),
      'text': const Color(0xFF332050),
      'appBarIcon': const Color(0xFF332050),
      'cardBg': Colors.white.withValues(alpha: 0.92),
    };
  }

  void _navigateToActivity(BuildContext context, String difficulty) {

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhrasesActivityInterface(difficulty: difficulty, config: widget.config),
      ),
    );
  }

  /// Role-based access: only roles with `AppFeature.activities` can open this screen.
  @override
  Widget build(BuildContext context) =>
      RoleGuard(feature: AppFeature.activities, child: _buildGuarded(context));

  Widget _buildGuarded(BuildContext context) {
    final themeStyles = _getThemeStyles(context);
    final scaffoldBgColor = Theme.of(context).scaffoldBackgroundColor;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scaffoldBgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: themeStyles['appBarIcon']),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          L.t('Select Difficulty', 'Pumili ng Antas'),
          style: TextStyle(
            color: themeStyles['appBarIcon'],
            fontSize: 22,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w800,
            letterSpacing: -0.96,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ThemedBackground(bgColor: scaffoldBgColor),
          ),
          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: ProgressService().getUserProgressStream(),
              builder: (context, userProgressSnapshot) {
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('activity_questions')
                      .where('category', whereIn: widget.config.aliases)
                      .snapshots(),
                  builder: (context, questionsSnapshot) {
                    if (userProgressSnapshot.connectionState == ConnectionState.waiting ||
                        questionsSnapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator(color: themeStyles['primary']));
                    }

                    int easyStars = 0;
                    int mediumStars = 0;
                    int hardStars = 0;

                    if (userProgressSnapshot.hasData && userProgressSnapshot.data!.exists) {
                      final data = userProgressSnapshot.data!.data() as Map<String, dynamic>?;
                      if (data != null) {
                        final progressMap = Map<String, dynamic>.from(data['progress'] ?? data['activityProgress'] ?? {});
                        
                        // Stars of this category's own levels (difficulty from the level id).
                        final levelIds = <String>{
                          for (final doc in questionsSnapshot.data?.docs ?? const [])
                            ((doc.data() as Map<String, dynamic>)['level'] ?? '').toString()
                        }..remove('');
                        for (final id in levelIds) {
                          final stars = ((progressMap[id] as num?) ?? 0).toInt();
                          switch (ActivityCategoryConfig.difficultyOf(id)) {
                            case 'easy':
                              easyStars += stars;
                            case 'medium':
                              mediumStars += stars;
                            default:
                              hardStars += stars;
                          }
                        }
                      }
                    }

                    final Set<String> easyLevels = {};
                    final Set<String> mediumLevels = {};
                    final Set<String> hardLevels = {};

                    if (questionsSnapshot.hasData) {
                      for (var doc in questionsSnapshot.data!.docs) {
                        final qData = doc.data() as Map<String, dynamic>;
                        final String? levelId = qData['level'];
                        final String cat = (qData['category'] ?? '').toString().trim().toLowerCase();
                        
                        if (cat.contains('alphabet')) continue;

                        if (levelId != null) {
                          switch (ActivityCategoryConfig.difficultyOf(levelId)) {
                            case 'easy':
                              easyLevels.add(levelId);
                            case 'medium':
                              mediumLevels.add(levelId);
                            default:
                              hardLevels.add(levelId);
                          }
                        }
                      }
                    }

                    final int maxEasyStars = easyLevels.isNotEmpty ? easyLevels.length * 3 : 9;
                    final int maxMediumStars = mediumLevels.isNotEmpty ? mediumLevels.length * 3 : 9;
                    final int maxHardStars = hardLevels.isNotEmpty ? hardLevels.length * 3 : 9;

                    final int starsToUnlockMedium = (maxEasyStars * 0.5).ceil();
                    final int starsToUnlockHard = (maxMediumStars * 0.5).ceil();

                    final bool isMediumUnlocked = easyStars >= starsToUnlockMedium;
                    final bool isHardUnlocked = mediumStars >= starsToUnlockHard;

                    // Cards of 140-168 px each, top-aligned; scrolls on very small screens.
                    return LayoutBuilder(builder: (context, box) {
                    final cardHeight = ((box.maxHeight - 40 - 32) / 3).clamp(140.0, 168.0);

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _buildDifficultyCard(
                          context,
                          height: cardHeight,
                          themeStyles: themeStyles,
                          title: "EASY",
                          subtitle: L.t('Common greetings & words', 'Karaniwang pagbati at salita'),
                          icon: Icons.signal_cellular_alt_1_bar_rounded,
                          color: const Color(0xFF58CC02),
                          isUnlocked: true,
                          currentStars: easyStars,
                          maxStars: maxEasyStars,
                          onTap: () => _navigateToActivity(context, 'easy'),
                        ),
                        const SizedBox(height: 16),
                        _buildDifficultyCard(
                          context,
                          height: cardHeight,
                          themeStyles: themeStyles,
                          title: "MEDIUM",
                          subtitle: L.t('Full expressions & questions', 'Buong pahayag at tanong'),
                          icon: Icons.signal_cellular_alt_2_bar_rounded,
                          color: const Color(0xFFFFB800),
                          isUnlocked: isMediumUnlocked,
                          currentStars: mediumStars,
                          maxStars: maxMediumStars,
                          lockedMessage: L.t('Earn at least $starsToUnlockMedium ⭐ (50%) in Easy mode to unlock!', 'Makakuha ng $starsToUnlockMedium ⭐ (50%) sa Easy para mabuksan!'),
                          onTap: () => _navigateToActivity(context, 'medium'),
                        ),
                        const SizedBox(height: 16),
                        _buildDifficultyCard(
                          context,
                          height: cardHeight,
                          themeStyles: themeStyles,
                          title: "HARD",
                          subtitle: L.t('Complex phrase signing', 'Mas mahirap na parirala'),
                          icon: Icons.signal_cellular_alt_rounded,
                          color: const Color(0xFFFF2A85),
                          isUnlocked: isHardUnlocked,
                          currentStars: hardStars,
                          maxStars: maxHardStars,
                          lockedMessage: L.t('Earn at least $starsToUnlockHard ⭐ (50%) in Medium mode to unlock!', 'Makakuha ng $starsToUnlockHard ⭐ (50%) sa Medium para mabuksan!'),
                          onTap: () => _navigateToActivity(context, 'hard'),
                        ),
                        const SizedBox(height: 20),
                        _buildProgressSummary(
                          themeStyles: themeStyles,
                          easyStars: easyStars, mediumStars: mediumStars, hardStars: hardStars,
                          maxEasy: maxEasyStars, maxMedium: maxMediumStars, maxHard: maxHardStars,
                          toUnlockMedium: starsToUnlockMedium, toUnlockHard: starsToUnlockHard,
                          mediumOpen: isMediumUnlocked, hardOpen: isHardUnlocked,
                        ),
                      ],
                    );
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Fills the space under the cards with something useful: total stars and
  /// the next goal in plain words (what to do to open the next level).
  Widget _buildProgressSummary({
    required Map<String, dynamic> themeStyles,
    required int easyStars, required int mediumStars, required int hardStars,
    required int maxEasy, required int maxMedium, required int maxHard,
    required int toUnlockMedium, required int toUnlockHard,
    required bool mediumOpen, required bool hardOpen,
  }) {
    final Color textColor = themeStyles['text'] as Color;
    final total = easyStars + mediumStars + hardStars;
    final maxTotal = maxEasy + maxMedium + maxHard;
    final String goal;
    final IconData goalIcon;
    if (!mediumOpen) {
      goal = L.t('${toUnlockMedium - easyStars} more ⭐ in Easy to unlock Medium.', '${toUnlockMedium - easyStars} ⭐ pa sa Easy para mabuksan ang Medium.');
      goalIcon = Icons.lock_open_rounded;
    } else if (!hardOpen) {
      goal = L.t('${toUnlockHard - mediumStars} more ⭐ in Medium to unlock Hard.', '${toUnlockHard - mediumStars} ⭐ pa sa Medium para mabuksan ang Hard.');
      goalIcon = Icons.lock_open_rounded;
    } else if (total < maxTotal) {
      goal = L.t('Everything is open! Get 3 ⭐ on every level.', 'Bukas na lahat! Kunin ang 3 ⭐ sa bawat level.');
      goalIcon = Icons.emoji_events_rounded;
    } else {
      goal = L.t('Complete! You earned every star.', 'Kumpleto! Nakuha mo ang lahat ng bituin.');
      goalIcon = Icons.workspace_premium_rounded;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (themeStyles['cardBg'] as Color).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: textColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 22),
              const SizedBox(width: 6),
              Text(L.t('Your progress', 'Iyong progreso'),
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 15, color: textColor)),
              const Spacer(),
              Text('$total/$maxTotal',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 15, color: textColor)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: maxTotal > 0 ? (total / maxTotal).clamp(0.0, 1.0) : 0.0,
              minHeight: 8,
              backgroundColor: textColor.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFC107)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(goalIcon, size: 20, color: textColor.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(goal,
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.3,
                        color: textColor.withValues(alpha: 0.8))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Difficulty card, same design in every category: a level badge with
  /// signal bars (1 / 2 / 3 = easy / medium / hard), title + subtitle, star
  /// progress, and a clear next step: a "go" arrow when open, or the unlock
  /// rule written on the card itself when locked (not only in a snackbar).
  Widget _buildDifficultyCard(
    BuildContext context, {
    double height = 150,
    required Map<String, dynamic> themeStyles,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isUnlocked,
    required int currentStars,
    required int maxStars,
    String? lockedMessage,
    required VoidCallback onTap,
  }) {
    final double progress = maxStars > 0 ? (currentStars / maxStars).clamp(0.0, 1.0) : 0.0;
    final int level = switch (title.toUpperCase()) { 'EASY' => 1, 'MEDIUM' => 2, _ => 3 };
    final IconData levelIcon = switch (level) {
      1 => Icons.signal_cellular_alt_1_bar_rounded,
      2 => Icons.signal_cellular_alt_2_bar_rounded,
      _ => Icons.signal_cellular_alt_rounded,
    };
    final Color textColor = themeStyles['text'] as Color;
    final Color accent = isUnlocked ? color : Colors.grey.shade500;
    final bool big = height >= 200;
    final bool done = isUnlocked && maxStars > 0 && currentStars >= maxStars;

    return Semantics(
      button: true,
      label: '$title. ${isUnlocked ? subtitle : (lockedMessage ?? L.t('Locked', 'Naka-lock'))}. $currentStars of $maxStars stars.',
      child: _PressableCard(
        onTap: isUnlocked
            ? onTap
            : () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(lockedMessage ?? L.t('Locked!', 'Naka-lock!')), backgroundColor: Colors.redAccent),
                ),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isUnlocked
                  ? [Color.alphaBlend(color.withValues(alpha: 0.16), themeStyles['cardBg'] as Color), themeStyles['cardBg'] as Color]
                  : [Colors.grey.shade800.withValues(alpha: 0.55), Colors.grey.shade900.withValues(alpha: 0.55)],
            ),
            border: Border.all(color: accent.withValues(alpha: isUnlocked ? 0.9 : 0.5), width: 2.5),
            boxShadow: [
              BoxShadow(
                color: (isUnlocked ? color : Colors.black).withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Soft watermark of the level icon.
              Positioned(
                right: -12,
                bottom: -18,
                child: Icon(levelIcon, size: height * 0.75, color: accent.withValues(alpha: 0.08)),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: big ? 18 : 12),
                child: Row(
                  children: [
                    // Level badge
                    Container(
                      width: big ? 92 : 72,
                      height: big ? 92 : 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isUnlocked
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color.lerp(color, Colors.white, 0.25)!, color],
                              )
                            : null,
                        color: isUnlocked ? null : Colors.grey.shade700,
                        boxShadow: [
                          if (isUnlocked) BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Icon(isUnlocked ? levelIcon : Icons.lock_rounded, size: big ? 46 : 36, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: big ? 28 : 22,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                    color: isUnlocked ? textColor : Colors.grey.shade400,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  done ? L.t('DONE', 'TAPOS NA') : L.t('LEVEL $level', 'LEVEL $level'),
                                  style: TextStyle(fontSize: 10.5, fontFamily: 'Inter', fontWeight: FontWeight.w800, color: accent),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isUnlocked ? subtitle : (lockedMessage ?? L.t('Locked', 'Naka-lock')),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: big ? 15 : 13,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                              color: isUnlocked ? textColor.withValues(alpha: 0.72) : Colors.grey.shade400,
                            ),
                          ),
                          SizedBox(height: big ? 14 : 10),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: big ? 12 : 10,
                                    backgroundColor: accent.withValues(alpha: 0.15),
                                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(Icons.star_rounded, size: big ? 20 : 17, color: isUnlocked ? const Color(0xFFFFC107) : Colors.grey.shade500),
                              const SizedBox(width: 2),
                              Text(
                                '$currentStars/$maxStars',
                                style: TextStyle(
                                  fontSize: big ? 14 : 12,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w800,
                                  color: isUnlocked ? textColor : Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Next step
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.18)),
                      child: Icon(
                        isUnlocked ? Icons.arrow_forward_ios_rounded : Icons.lock_outline_rounded,
                        size: 18,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shrinks a little while pressed, so a tap is felt even without sound.
class _PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _PressableCard({required this.child, required this.onTap});

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}
