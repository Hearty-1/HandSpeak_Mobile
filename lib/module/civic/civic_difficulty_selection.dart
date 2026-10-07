import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '/providers/sound_provider.dart';
import '/services/progress_service.dart';
import 'civic_activity_interface.dart';
import 'dart:math';


class ThemedBackground extends StatelessWidget {
  final Color bgColor;

  const ThemedBackground({super.key, required this.bgColor});

  Widget _buildGlowingOrb(double size, Color color, double top, double left) {
    return Positioned(
      top: top,
      left: left,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.6), color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }

  Widget _buildJellyfish(double top, double left, Color color, double scale) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.scale(
        scale: scale,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 26,
              decoration: BoxDecoration(
                color: color.withOpacity(0.75),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(4, (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCuteFish(double top, double left, Color color, double scale, bool flip) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.scale(
        scaleX: flip ? -scale : scale,
        scaleY: scale,
        child: Icon(
          Icons.set_meal_rounded,
          color: color.withOpacity(0.8),
          size: 34,
        ),
      ),
    );
  }

  Widget _buildStarfish(double top, double left, Color color, double scale, double angle) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.rotate(
        angle: angle,
        child: Transform.scale(
          scale: scale,
          child: Icon(
            Icons.star_rounded,
            color: color.withOpacity(0.85),
            size: 38,
          ),
        ),
      ),
    );
  }

  Widget _buildMushroom(double top, double left, double scale) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.scale(
        scale: scale,
        child: Column(
          children: [
            Container(
              width: 32,
              height: 20,
              decoration: const BoxDecoration(
                color: Color(0xFFD7B3A1),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CircleAvatar(radius: 2, backgroundColor: Colors.white),
                  CircleAvatar(radius: 3, backgroundColor: Colors.white),
                  CircleAvatar(radius: 2, backgroundColor: Colors.white),
                ],
              ),
            ),
            Container(
              width: 14,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F5F4),
                borderRadius: BorderRadius.circular(3),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCloud(double top, double left, double scale) {
    return Positioned(
      top: top, 
      left: left,
      child: Transform.scale(
        scale: scale,
        child: SizedBox(
          width: 140,
          height: 80,
          child: Stack(
            children: [
              Positioned(bottom: 0, left: 10, child: Container(width: 50, height: 50, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.65)))),
              Positioned(bottom: 12, left: 35, child: Container(width: 70, height: 70, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.8)))),
              Positioned(bottom: 0, left: 75, child: Container(width: 45, height: 45, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.65)))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHotAirBalloon(double top, double left, Color balloonColor, double scale) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.scale(
        scale: scale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 52,
              decoration: BoxDecoration(
                color: balloonColor,
                borderRadius: const BorderRadius.all(Radius.elliptical(44, 52)),
                boxShadow: [
                  BoxShadow(color: balloonColor.withOpacity(0.4), blurRadius: 8, spreadRadius: 1)
                ],
              ),
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: 16,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.35),
                        borderRadius: const BorderRadius.all(Radius.elliptical(16, 52)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 12,
              height: 8,
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.black26, width: 1.5),
                  right: BorderSide(color: Colors.black26, width: 1.5),
                ),
              ),
            ),
            Container(
              width: 14,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFFFFB74D),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (bgColor.value == 0xFF080928) { 
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF080928), Color(0xFF1B1A4B), Color(0xFF080928)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            _buildGlowingOrb(300, const Color(0xFF7C4DFF), -50, -100),
            _buildGlowingOrb(400, const Color(0xFF4C5FE6), 400, 200),
            _buildGlowingOrb(200, const Color(0xFFB9A6FF), 700, -50),
            Positioned(top: 120, right: 30, child: Transform.rotate(angle: -0.5, child: const Icon(Icons.rocket_launch_rounded, color: Color(0xFF7C4DFF), size: 48))),
            Positioned(top: 480, left: 25, child: Transform.rotate(angle: 0.3, child: const Icon(Icons.public_rounded, color: Color(0xFFB9A6FF), size: 54))),
            Positioned(top: 720, right: 40, child: const Icon(Icons.brightness_3_rounded, color: Color(0xFFB9A6FF), size: 40)),
            ...List.generate(20, (index) {
              final random = Random(index);
              return Positioned(
                top: random.nextDouble() * 900,
                left: random.nextDouble() * 380,
                child: Icon(
                  Icons.auto_awesome, 
                  color: const Color(0xFFB9A6FF).withOpacity(random.nextDouble() * 0.5 + 0.2),
                  size: random.nextDouble() * 18 + 10,
                ),
              );
            }),
          ],
        ),
      );
    }
    
    if (bgColor.value == 0xFF1D3D3A) { 
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1D3D3A), Color(0xFF4D7C73), Color(0xFF1D3D3A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            _buildGlowingOrb(350, const Color(0xFFD7B3A1), -100, 150), 
            _buildGlowingOrb(250, const Color(0xFFB8D4CF), 300, -100),
            _buildMushroom(220, 25, 1.2),
            _buildMushroom(540, 320, 1.1),
            _buildMushroom(780, 50, 1.3),
            Positioned(top: 140, right: 40, child: Icon(Icons.flutter_dash_rounded, color: const Color(0xFFD7B3A1).withOpacity(0.8), size: 36)),
            Positioned(top: 410, left: 30, child: Icon(Icons.eco_rounded, color: const Color(0xFFB8D4CF).withOpacity(0.7), size: 32)),
            ...List.generate(15, (index) {
              final random = Random(index + 50);
              return _buildGlowingOrb(
                random.nextDouble() * 20 + 10, 
                const Color(0xFFF2F5F4), 
                random.nextDouble() * 900, 
                random.nextDouble() * 380
              );
            }),
          ],
        ),
      );
    }
    
    if (bgColor.value == 0xFF001B3A) { 
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF005C97), Color(0xFF001B3A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            _buildGlowingOrb(400, const Color(0xFF00E5FF), -150, -50),
            _buildGlowingOrb(300, const Color(0xFF363795), 500, 150),
            _buildCuteFish(130, 40, const Color(0xFFFFD166), 1.2, false),
            _buildCuteFish(320, 280, const Color(0xFFFF6B6B), 1.1, true),
            _buildCuteFish(620, 50, const Color(0xFF00E5FF), 1.3, false),
            _buildJellyfish(230, 290, const Color(0xFFFF70A6), 1.1),
            _buildJellyfish(510, 30, const Color(0xFF70D6FF), 1.2),
            _buildStarfish(180, 310, const Color(0xFFFF9F1C), 1.0, 0.4),
            _buildStarfish(440, 20, const Color(0xFFFFD166), 1.1, -0.3),
            _buildStarfish(760, 300, const Color(0xFFFF6B6B), 1.2, 0.2),
            ...List.generate(18, (index) {
              final random = Random(index + 100);
              return Positioned(
                top: random.nextDouble() * 900,
                left: random.nextDouble() * 380,
                child: Icon(
                  Icons.bubble_chart_rounded,
                  color: Colors.white.withOpacity(random.nextDouble() * 0.35 + 0.15),
                  size: random.nextDouble() * 30 + 12,
                ),
              );
            }),
          ],
        ),
      );
    }
    
    if (bgColor.value == 0xFFE0EAFC) { 
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFA8C0FF), Color(0xFFE0EAFC), Color(0xFFFFFFFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 40, 
              right: 30, 
              child: Icon(Icons.wb_sunny_rounded, color: const Color(0xFFFFD700).withOpacity(0.85), size: 70)
            ),
            _buildCloud(80, -30, 1.2),
            _buildCloud(280, 200, 0.9),
            _buildCloud(520, -40, 1.4),
            _buildCloud(720, 160, 1.1),
            Positioned(top: 190, left: 60, child: Icon(Icons.flutter_dash_rounded, color: const Color(0xFF5C7CFA).withOpacity(0.5), size: 30)),
            Positioned(top: 430, right: 50, child: Icon(Icons.flutter_dash_rounded, color: const Color(0xFF5C7CFA).withOpacity(0.5), size: 26)),
          ],
        ),
      );
    }
    
    const confettiColors = [
      Color(0xFFFF6B8B),
      Color(0xFFFFB74D),
      Color(0xFF4DD0E1),
      Color(0xFFAED581),
      Color(0xFFBA68C8),
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFF5D6), Color(0xFFFFE3E8), Color(0xFFE0F7FA)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          _buildGlowingOrb(350, const Color(0xFFFFCA28).withOpacity(0.5), -100, -80),
          _buildGlowingOrb(300, const Color(0xFFFF80AB).withOpacity(0.35), 450, 180),
          _buildGlowingOrb(250, const Color(0xFF4DD0E1).withOpacity(0.35), 700, -60),

          Positioned(
            top: 45,
            right: 25,
            child: Icon(Icons.wb_sunny_rounded, color: const Color(0xFFFFB300).withOpacity(0.9), size: 72),
          ),

          _buildCloud(70, -30, 1.1),
          _buildCloud(380, 190, 1.0),
          _buildCloud(680, -20, 1.2),

          _buildHotAirBalloon(150, 260, const Color(0xFFFF6B8B), 1.2),
          _buildHotAirBalloon(450, 30, const Color(0xFF4DD0E1), 1.0),
          _buildHotAirBalloon(720, 270, const Color(0xFFFFB74D), 1.1),

          Positioned(
            top: 280,
            left: 45,
            child: Transform.rotate(
              angle: -0.2,
              child: Icon(Icons.extension_rounded, color: const Color(0xFFBA68C8).withOpacity(0.7), size: 36),
            ),
          ),
          Positioned(
            top: 590,
            right: 40,
            child: Transform.rotate(
              angle: 0.3,
              child: Icon(Icons.pets_rounded, color: const Color(0xFFFF6B8B).withOpacity(0.65), size: 38),
            ),
          ),
          Positioned(
            top: 190,
            left: 170,
            child: Icon(Icons.music_note_rounded, color: const Color(0xFF4DD0E1).withOpacity(0.7), size: 30),
          ),

          ...List.generate(24, (index) {
            final random = Random(index + 200);
            final color = confettiColors[random.nextInt(confettiColors.length)];
            return Positioned(
              top: random.nextDouble() * 900,
              left: random.nextDouble() * 380,
              child: Transform.rotate(
                angle: random.nextDouble() * 3.14,
                child: Icon(
                  random.nextBool() ? Icons.star_rounded : Icons.auto_awesome_rounded,
                  color: color.withOpacity(random.nextDouble() * 0.5 + 0.3),
                  size: random.nextDouble() * 18 + 10,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
class CivicDifficultySelectionScreen extends StatefulWidget {
  const CivicDifficultySelectionScreen({super.key});

  @override
  State<CivicDifficultySelectionScreen> createState() =>
      _CivicDifficultySelectionScreenState();
}

class _CivicDifficultySelectionScreenState
    extends State<CivicDifficultySelectionScreen> {
  late dynamic _soundProvider;

  @override
  void initState() {
    super.initState();
    try {
      Provider.of<SoundProvider>(context, listen: false).playBgm();
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
      _soundProvider.stopBgm();
    } catch (_) {}
    super.dispose();
  }

  Map<String, dynamic> _getThemeStyles(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor.value;

    if (bgColor == 0xFF080928) {
      return {
        'primary': const Color(0xFF7C4DFF),
        'text': const Color(0xFFB9A6FF),
        'appBarIcon': const Color(0xFFB9A6FF),
        'cardBg': const Color(0xFF1B1A4B),
      };
    }
    if (bgColor == 0xFF1D3D3A) {
      return {
        'primary': const Color(0xFFD7B3A1),
        'text': const Color(0xFFF2F5F4),
        'appBarIcon': const Color(0xFFF2F5F4),
        'cardBg': const Color(0xFF4D7C73),
      };
    }
    if (bgColor == 0xFF001B3A) {
      return {
        'primary': const Color(0xFF00E5FF),
        'text': Colors.white,
        'appBarIcon': Colors.white,
        'cardBg': Colors.black54,
      };
    }
    if (bgColor == 0xFFE0EAFC) {
      return {
        'primary': const Color(0xFF5C7CFA),
        'text': const Color(0xFF1E1E1E),
        'appBarIcon': const Color(0xFF322144),
        'cardBg': Colors.white.withOpacity(0.9),
      };
    }

    return {
      'primary': const Color(0xFFFF6B8B),
      'text': const Color(0xFF332050),
      'appBarIcon': const Color(0xFF332050),
      'cardBg': Colors.white.withOpacity(0.92),
    };
  }

  void _navigateToActivity(BuildContext context, String difficulty) {
    try {
      _soundProvider.stopBgm();
    } catch (_) {}

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CivicActivityInterface(
          difficulty: difficulty,
        ),
      ),
    ).then((_) {
      try {
        _soundProvider.playBgm();
      } catch (_) {}
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
          'Select Difficulty',
          style: TextStyle(
            color: themeStyles['appBarIcon'],
            fontSize: 24,
            fontWeight: FontWeight.w800,
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
                      .where('category', isEqualTo: 'civic')
                      .snapshots(),
                  builder: (context, questionsSnapshot) {
                    if (userProgressSnapshot.connectionState == ConnectionState.waiting ||
                        questionsSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Color(0xFFFFB300)),
                      );
                    }

                    int easyStars = 0;
                    int mediumStars = 0;
                    int hardStars = 0;

                    if (userProgressSnapshot.hasData && userProgressSnapshot.data!.exists) {
                      final data = userProgressSnapshot.data!.data() as Map<String, dynamic>?;
                      if (data != null && data['progress'] != null) {
                        final progressMap = Map<String, dynamic>.from(data['progress']);

                        progressMap.forEach((key, value) {
                          if (key.startsWith('civic_easy_')) easyStars += (value as num).toInt();
                          if (key.startsWith('civic_medium_')) mediumStars += (value as num).toInt();
                          if (key.startsWith('civic_hard_')) hardStars += (value as num).toInt();
                        });
                      }
                    }

                    final Set<String> easyLevels = {};
                    final Set<String> mediumLevels = {};
                    final Set<String> hardLevels = {};

                    if (questionsSnapshot.hasData) {
                      for (var doc in questionsSnapshot.data!.docs) {
                        final qData = doc.data() as Map<String, dynamic>;
                        final String? levelId = qData['level'];
                        if (levelId != null) {
                          if (levelId.startsWith('civic_easy_')) easyLevels.add(levelId);
                          if (levelId.startsWith('civic_medium_')) mediumLevels.add(levelId);
                          if (levelId.startsWith('civic_hard_')) hardLevels.add(levelId);
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

                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _buildDifficultyCard(
                          context,
                          themeStyles: themeStyles,
                          title: "EASY",
                          subtitle: "Learn civic basics",
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
                          subtitle: "Test your knowledge",
                          icon: Icons.bolt_rounded,
                          color: const Color(0xFFFFB800),
                          isUnlocked: isMediumUnlocked,
                          currentStars: mediumStars,
                          maxStars: maxMediumStars,
                          lockedMessage:
                              "Earn at least $starsToUnlockMedium ⭐ (50%) in Easy mode to unlock!",
                          onTap: () => _navigateToActivity(context, 'medium'),
                        ),
                        const SizedBox(height: 16),
                        _buildDifficultyCard(
                          context,
                          themeStyles: themeStyles,
                          title: "HARD",
                          subtitle: "Master civic concepts",
                          icon: Icons.local_fire_department_rounded,
                          color: const Color(0xFFFF2A85),
                          isUnlocked: isHardUnlocked,
                          currentStars: hardStars,
                          maxStars: maxHardStars,
                          lockedMessage:
                              "Earn at least $starsToUnlockHard ⭐ (50%) in Medium mode to unlock!",
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
    final double progressRatio =
        maxStars > 0 ? (currentStars / maxStars).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: isUnlocked
          ? onTap
          : () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(lockedMessage ?? "Locked!"),
                  backgroundColor: Colors.redAccent,
                ),
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
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(21)),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color:
                            isUnlocked ? themeStyles['text'] : Colors.grey.shade500,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isUnlocked ? subtitle : "Locked",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isUnlocked
                            ? themeStyles['text'].withOpacity(0.7)
                            : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: progressRatio,
                              minHeight: 10,
                              backgroundColor:
                                  Colors.grey.shade300.withOpacity(0.3),
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
                            color: isUnlocked
                                ? themeStyles['text']
                                : Colors.grey.shade500,
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