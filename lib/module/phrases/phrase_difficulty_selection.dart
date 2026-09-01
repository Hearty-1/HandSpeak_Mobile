import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '/providers/sound_provider.dart';
import '/services/progress_service.dart';


// This imports your interface and the ThemedBackground widget you have inside it
import 'phraseAct.dart'; 

class PhraseDifficultySelectionScreen extends StatefulWidget {
  const PhraseDifficultySelectionScreen({super.key});

  @override
  State<PhraseDifficultySelectionScreen> createState() => _PhraseDifficultySelectionScreenState();
}

class _PhraseDifficultySelectionScreenState extends State<PhraseDifficultySelectionScreen> {
  late SoundProvider _soundProvider;

  @override
  void initState() {
    super.initState(); 
    Provider.of<SoundProvider>(context, listen: false).playBgm(); 
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _soundProvider = Provider.of<SoundProvider>(context, listen: false);
  }

  @override
  void dispose() {
    _soundProvider.stopBgm();
    super.dispose(); 
  }

  // Exact theme style logic mirrored from your provided alphabet code
  Map<String, dynamic> _getThemeStyles(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor.value;

    if (bgColor == 0xFF0F0C29) { // Galaxy
      return {
        'primary': const Color(0xFFFF2A85), 
        'text': Colors.white,
        'appBarIcon': Colors.white,
        'cardBg': Colors.black54,
      };
    }
    if (bgColor == 0xFF132A13) { // Enchanted Forest
      return {
        'primary': const Color(0xFFFFD700), 
        'text': Colors.white,
        'appBarIcon': Colors.white,
        'cardBg': Colors.black54,
      };
    }
    if (bgColor == 0xFF001B3A) { // Ocean
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
        'cardBg': Colors.white.withOpacity(0.9),
      };
    }
    
    return {
      'primary': const Color(0xFFFFB800),
      'text': const Color(0xFF322144),
      'appBarIcon': const Color(0xFF322144),
      'cardBg': Colors.white.withOpacity(0.9),
    };
  }

  void _navigateToActivity(BuildContext context, String difficulty) {
    _soundProvider.stopBgm();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhraseActivityInterface(difficulty: difficulty),
      ),
    ).then((_) {
      _soundProvider.playBgm();
    });
  }

  @override
  Widget build(BuildContext context) {
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
          'Phrases Difficulty',
          style: TextStyle(
            color: themeStyles['appBarIcon'], 
            fontSize: 24, 
            fontWeight: FontWeight.w800
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
                      .where('category', isEqualTo: 'phrase') // Changed to phrase
                      .snapshots(),
                  builder: (context, questionsSnapshot) {
                    if (userProgressSnapshot.connectionState == ConnectionState.waiting ||
                        questionsSnapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator(color: themeStyles['primary']));
                    }

                    // 1. Calculate earned stars per difficulty
                    int easyStars = 0;
                    int mediumStars = 0;
                    int hardStars = 0;

                    if (userProgressSnapshot.hasData && userProgressSnapshot.data!.exists) {
                      final data = userProgressSnapshot.data!.data() as Map<String, dynamic>?;
                      if (data != null && data['progress'] != null) {
                        final progressMap = Map<String, dynamic>.from(data['progress']);
                        
                        progressMap.forEach((key, value) {
                          // Updated to match phrase keys
                          if (key.startsWith('phrase_easy_')) easyStars += (value as num).toInt();
                          if (key.startsWith('phrase_medium_')) mediumStars += (value as num).toInt();
                          if (key.startsWith('phrase_hard_')) hardStars += (value as num).toInt();
                        });
                      }
                    }

                    // 2. Dynamically calculate total available max stars per difficulty tier
                    final Set<String> easyLevels = {};
                    final Set<String> mediumLevels = {};
                    final Set<String> hardLevels = {};

                    if (questionsSnapshot.hasData) {
                      for (var doc in questionsSnapshot.data!.docs) {
                        final qData = doc.data() as Map<String, dynamic>;
                        final String? levelId = qData['level'];
                        if (levelId != null) {
                          // Updated to match phrase keys
                          if (levelId.startsWith('phrase_easy_')) easyLevels.add(levelId);
                          if (levelId.startsWith('phrase_medium_')) mediumLevels.add(levelId);
                          if (levelId.startsWith('phrase_hard_')) hardLevels.add(levelId);
                        }
                      }
                    }

                    // Each level offers up to 3 stars (default to 9 stars if collection is empty)
                    final int maxEasyStars = easyLevels.isNotEmpty ? easyLevels.length * 3 : 9;
                    final int maxMediumStars = mediumLevels.isNotEmpty ? mediumLevels.length * 3 : 9;
                    final int maxHardStars = hardLevels.isNotEmpty ? hardLevels.length * 3 : 9;

                    // Required stars to unlock next tier (50% of available stars)
                    final int starsToUnlockMedium = (maxEasyStars * 0.5).ceil();
                    final int starsToUnlockHard = (maxMediumStars * 0.5).ceil();

                    final bool isMediumUnlocked = easyStars >= starsToUnlockMedium;
                    final bool isHardUnlocked = mediumStars >= starsToUnlockHard;

                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _buildDifficultyCard(
                          context,
                          themeStyles: themeStyles,
                          title: "EASY",
                          subtitle: "Common greetings & words", // Adjusted subtitle for phrases
                          icon: Icons.star_rounded,
                          color: const Color(0xFF58CC02),
                          isUnlocked: true,
                          currentStars: easyStars,
                          maxStars: maxEasyStars,
                          onTap: () => _navigateToActivity(context, 'easy'),
                        ),
                        const SizedBox(height: 16),
                        _buildDifficultyCard(
                          context,
                          themeStyles: themeStyles,
                          title: "MEDIUM",
                          subtitle: "Full expressions & questions", // Adjusted subtitle for phrases
                          icon: Icons.bolt_rounded,
                          color: const Color(0xFFFFB800),
                          isUnlocked: isMediumUnlocked,
                          currentStars: mediumStars,
                          maxStars: maxMediumStars,
                          lockedMessage: "Earn at least $starsToUnlockMedium ⭐ (50%) in Easy mode to unlock!",
                          onTap: () => _navigateToActivity(context, 'medium'),
                        ),
                        const SizedBox(height: 16),
                        _buildDifficultyCard(
                          context,
                          themeStyles: themeStyles,
                          title: "HARD",
                          subtitle: "Complex phrase signing", // Adjusted subtitle for phrases
                          icon: Icons.local_fire_department_rounded,
                          color: const Color(0xFFFF2A85),
                          isUnlocked: isHardUnlocked,
                          currentStars: hardStars,
                          maxStars: maxHardStars,
                          lockedMessage: "Earn at least $starsToUnlockHard ⭐ (50%) in Medium mode to unlock!",
                          onTap: () => _navigateToActivity(context, 'hard'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultyCard(
    BuildContext context, {
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
    final double progressRatio = maxStars > 0 
        ? (currentStars / maxStars).clamp(0.0, 1.0) 
        : 0.0;

    return GestureDetector(
      onTap: isUnlocked
          ? () {
              onTap();
            }
          : () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(lockedMessage ?? "Locked!"), backgroundColor: Colors.redAccent),
              );
            },
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: isUnlocked ? themeStyles['cardBg'] : Colors.black45,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isUnlocked ? color : Colors.grey.shade600,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: (isUnlocked ? color : Colors.black).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 100,
              decoration: BoxDecoration(
                color: isUnlocked ? color.withOpacity(0.2) : Colors.black26,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(21)),
              ),
              child: Center(
                child: Icon(
                  isUnlocked ? icon : Icons.lock_rounded,
                  size: 48,
                  color: isUnlocked ? color : Colors.grey.shade500,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: isUnlocked ? themeStyles['text'] : Colors.grey.shade500,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isUnlocked ? subtitle : "Locked",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isUnlocked ? themeStyles['text'].withOpacity(0.7) : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Progress Bar & Star Counter
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: progressRatio,
                              minHeight: 10,
                              backgroundColor: Colors.grey.shade300.withOpacity(0.3),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isUnlocked ? color : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "$currentStars/$maxStars ⭐",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isUnlocked ? themeStyles['text'] : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}