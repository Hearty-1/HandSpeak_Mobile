import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '/providers/sound_provider.dart';
import '/services/progress_service.dart';
import 'easyNumAct_mc.dart';

// ==========================================
// 1. KIDDIE PROCEDURAL BACKGROUND WIDGET
// ==========================================
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

  // --- OCEAN CREATURE HELPERS ---
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

  // --- FOREST MUSHROOM HELPER ---
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
                color: Color(0xFFFF5252),
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
                color: const Color(0xFFFFF8E7),
                borderRadius: BorderRadius.circular(3),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- SKY CLOUD & SUN HELPERS ---
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
              Positioned(bottom: 0, left: 10, child: Container(width: 50, height: 50, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.5)))),
              Positioned(bottom: 12, left: 35, child: Container(width: 70, height: 70, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.6)))),
              Positioned(bottom: 0, left: 75, child: Container(width: 45, height: 45, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.5)))),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. GALAXY THEME (Rockets, Stars, & Planets)
    if (bgColor.value == 0xFF0F0C29) { 
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            _buildGlowingOrb(300, const Color(0xFFFF2A85), -50, -100),
            _buildGlowingOrb(400, const Color(0xFF4A00E0), 400, 200),
            _buildGlowingOrb(200, const Color(0xFF00E5FF), 700, -50),
            
            // Kiddie Rocket & Space Visuals
            Positioned(top: 120, right: 30, child: Transform.rotate(angle: -0.5, child: const Icon(Icons.rocket_launch_rounded, color: Color(0xFFFF2A85), size: 48))),
            Positioned(top: 480, left: 25, child: Transform.rotate(angle: 0.3, child: const Icon(Icons.public_rounded, color: Color(0xFF00E5FF), size: 54))),
            Positioned(top: 720, right: 40, child: const Icon(Icons.brightness_3_rounded, color: Color(0xFFFFD700), size: 40)),

            ...List.generate(20, (index) {
              final random = Random(index);
              return Positioned(
                top: random.nextDouble() * 900,
                left: random.nextDouble() * 380,
                child: Icon(
                  Icons.auto_awesome, 
                  color: Colors.white.withOpacity(random.nextDouble() * 0.5 + 0.2),
                  size: random.nextDouble() * 18 + 10,
                ),
              );
            }),
          ],
        ),
      );
    }
    
    // 2. ENCHANTED FOREST THEME (Mushrooms, Leaves, & Fireflies)
    if (bgColor.value == 0xFF132A13) { 
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF132A13), Color(0xFF31572C), Color(0xFF4F772D)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            _buildGlowingOrb(350, const Color(0xFFFFD700), -100, 150), 
            _buildGlowingOrb(250, const Color(0xFF90BE6D), 300, -100),
            
            // Cute Mushrooms
            _buildMushroom(220, 25, 1.2),
            _buildMushroom(540, 320, 1.1),
            _buildMushroom(780, 50, 1.3),

            // Butterflies & Leaves
            Positioned(top: 140, right: 40, child: Icon(Icons.flutter_dash_rounded, color: const Color(0xFFFFD700).withOpacity(0.6), size: 36)),
            Positioned(top: 410, left: 30, child: Icon(Icons.eco_rounded, color: const Color(0xFF90BE6D).withOpacity(0.5), size: 32)),

            // Fireflies
            ...List.generate(15, (index) {
              final random = Random(index + 50);
              return _buildGlowingOrb(
                random.nextDouble() * 20 + 10, 
                const Color(0xFFFFFF99), 
                random.nextDouble() * 900, 
                random.nextDouble() * 380
              );
            }),
          ],
        ),
      );
    }
    
    // 3. DEEP OCEAN THEME (Sea Creatures, Starfish, & Bubbles)
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

            // Kiddie Sea Creatures
            _buildCuteFish(130, 40, const Color(0xFFFFD166), 1.2, false),
            _buildCuteFish(320, 280, const Color(0xFFFF6B6B), 1.1, true),
            _buildCuteFish(620, 50, const Color(0xFF00E5FF), 1.3, false),

            _buildJellyfish(230, 290, const Color(0xFFFF70A6), 1.1),
            _buildJellyfish(510, 30, const Color(0xFF70D6FF), 1.2),

            _buildStarfish(180, 310, const Color(0xFFFF9F1C), 1.0, 0.4),
            _buildStarfish(440, 20, const Color(0xFFFFD166), 1.1, -0.3),
            _buildStarfish(760, 300, const Color(0xFFFF6B6B), 1.2, 0.2),

            // Rising Bubbles
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
    
    // 4. CLOUDY SKY THEME (Sun, Rainbow, & Layered Clouds)
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
            // Smiling Sun
            Positioned(
              top: 40, 
              right: 30, 
              child: Icon(Icons.wb_sunny_rounded, color: const Color(0xFFFFD700).withOpacity(0.85), size: 70)
            ),

            // Fluffy Clouds
            _buildCloud(80, -30, 1.2),
            _buildCloud(280, 200, 0.9),
            _buildCloud(520, -40, 1.4),
            _buildCloud(720, 160, 1.1),

            // Flying Birds
            Positioned(top: 190, left: 60, child: Icon(Icons.flutter_dash_rounded, color: const Color(0xFF5C7CFA).withOpacity(0.5), size: 30)),
            Positioned(top: 430, right: 50, child: Icon(Icons.flutter_dash_rounded, color: const Color(0xFF5C7CFA).withOpacity(0.5), size: 26)),
          ],
        ),
      );
    }
    
    // 5. DEFAULT FALLBACK THEME
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFF9E5), Color(0xFFFFE0B2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          _buildGlowingOrb(400, const Color(0xFFFFB800).withOpacity(0.4), -100, -100),
          _buildGlowingOrb(300, const Color(0xFFFFCC80).withOpacity(0.5), 500, 200),
        ],
      ),
    );
  }
}

// ==========================================
// 2. NUMBERS ACTIVITY INTERFACE
// ==========================================
class NumbersActivityInterface extends StatefulWidget {
  const NumbersActivityInterface({super.key});

  @override
  State<NumbersActivityInterface> createState() => _NumbersActivityInterfaceState();
}

class _NumbersActivityInterfaceState extends State<NumbersActivityInterface> {
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

  Map<String, dynamic> _getThemeStyles(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor.value;

    if (bgColor == 0xFF0F0C29) { // Galaxy
      return {
        'primary': const Color(0xFFFF2A85), 
        'text': Colors.white,
        'line': Colors.white54,
        'dividerText': Colors.white70,
        'appBarIcon': Colors.white,
        'cardBg': Colors.black54,
      };
    }
    if (bgColor == 0xFF132A13) { // Enchanted Forest
      return {
        'primary': const Color(0xFFFFD700), 
        'text': Colors.white,
        'line': Colors.white54,
        'dividerText': Colors.white70,
        'appBarIcon': Colors.white,
        'cardBg': Colors.black54,
      };
    }
    if (bgColor == 0xFF001B3A) { // Ocean
      return {
        'primary': const Color(0xFF00E5FF), 
        'text': Colors.white,
        'line': Colors.white54,
        'dividerText': Colors.white70,
        'appBarIcon': Colors.white,
        'cardBg': Colors.black54,
      };
    }
    if (bgColor == 0xFFE0EAFC) { // Cloudy Sky
      return {
        'primary': const Color(0xFF5C7CFA), 
        'text': const Color(0xFF1E1E1E),
        'line': Colors.black38,
        'dividerText': Colors.black54,
        'appBarIcon': const Color(0xFF322144),
        'cardBg': Colors.white.withOpacity(0.9),
      };
    }
    
    // Default Fallback
    return {
      'primary': const Color(0xFFFFB800),
      'text': const Color(0xFF322144),
      'line': Colors.grey.shade500,
      'dividerText': Colors.grey.shade700,
      'appBarIcon': const Color(0xFF322144),
      'cardBg': Colors.white.withOpacity(0.9),
    };
  }

  Widget _buildSectionDivider(String title, Map<String, dynamic> themeStyles) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(child: Divider(color: themeStyles['line'].withOpacity(0.3), thickness: 2)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              title,
              style: TextStyle(
                color: themeStyles['dividerText'],
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(child: Divider(color: themeStyles['line'].withOpacity(0.3), thickness: 2)),
        ],
      ),
    );
  }

  Widget _buildVerticalPathLine(Map<String, dynamic> themeStyles) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5.0),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: themeStyles['line'],
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: themeStyles['primary'].withOpacity(0.3), blurRadius: 4, spreadRadius: 1)
            ]
          ),
        ),
      )),
    );
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
          'Numbers Activity',
          style: TextStyle(
            color: themeStyles['appBarIcon'],
            fontSize: 24,
            fontFamily: 'Inter',
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
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: themeStyles['primary']));
                }

                int categoryStars = 0; 
                Map<String, dynamic> progressMap = {};

                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  if (data != null) {
                    progressMap = data['progress'] != null 
                        ? Map<String, dynamic>.from(data['progress']) 
                        : {};
                    
                    progressMap.forEach((key, value) {
                      if (key.startsWith('numbers_')) {
                        categoryStars += (value as num).toInt();
                      }
                    });
                  }
                }

                final List<Map<String, dynamic>> pathNodes = [
                  {
                    'id': 'numbers_easy_1',
                    'title': 'Level 1: Sign to Text',
                    'isUnlocked': true, 
                    'unlockMessage': '',
                    'alignment': Alignment.center,
                    'destination': const EasyNumActMc(levelId: 'numbers_easy_1', questionType: 'sign_to_text'), 
                  },
                  {
                    'id': 'numbers_easy_2',
                    'title': 'Level 2: Text to Sign',
                    'isUnlocked': (progressMap['numbers_easy_1'] ?? 0) >= 2, 
                    'unlockMessage': 'Earn 2 ⭐ in Level 1 to unlock!',
                    'alignment': Alignment.centerRight,
                    'destination': const EasyNumActMc(levelId: 'numbers_easy_2', questionType: 'text_to_sign'), 
                  },
                  {
                    'id': 'numbers_easy_3',
                    'title': 'Level 3: Count & Sign', 
                    'isUnlocked': (progressMap['numbers_easy_2'] ?? 0) >= 2, 
                    'unlockMessage': 'Earn 2 ⭐ in Level 2 to unlock!',
                    'alignment': Alignment.centerRight, 
                    'destination': const EasyNumActMc(levelId: 'numbers_easy_3', questionType: 'mixed'), 
                  },
                  {
                    'id': 'numbers_medium_1',
                    'title': 'Level 4: Addition (+)',
                    'isUnlocked': (progressMap['numbers_easy_3'] ?? 0) >= 2,
                    'unlockMessage': 'Earn 2 ⭐ in Level 3 to unlock!',
                    'alignment': Alignment.center,
                    'destination': const EasyNumActMc(levelId: 'numbers_medium_1', questionType: 'addition'), 
                  },
                  {
                    'id': 'numbers_medium_2',
                    'title': 'Level 5: Subtraction (-)',
                    'isUnlocked': (progressMap['numbers_medium_1'] ?? 0) >= 2,
                    'unlockMessage': 'Earn 2 ⭐ in Level 4 to unlock!',
                    'alignment': Alignment.centerLeft,
                    'destination': const EasyNumActMc(levelId: 'numbers_medium_2', questionType: 'subtraction'),
                  },
                  {
                    'id': 'numbers_medium_3',
                    'title': 'Level 6: Mixed Math', 
                    'isUnlocked': (progressMap['numbers_medium_2'] ?? 0) >= 2,
                    'unlockMessage': 'Earn 2 ⭐ in Level 5 to unlock!',
                    'alignment': Alignment.centerLeft,
                    'destination': const EasyNumActMc(levelId: 'numbers_medium_3', questionType: 'mixed'),
                  },
                  {
                    'id': 'numbers_hard_1',
                    'title': 'Level 7: Sign to Text',
                    'isUnlocked': (progressMap['numbers_medium_3'] ?? 0) >= 2,
                    'unlockMessage': 'Earn 2 ⭐ in Level 6 to unlock!',
                    'alignment': Alignment.center,
                    'destination': const Placeholder(), 
                  },
                  {
                    'id': 'numbers_hard_2',
                    'title': 'Level 8: Text to Sign',
                    'isUnlocked': (progressMap['numbers_hard_1'] ?? 0) >= 2,
                    'unlockMessage': 'Earn 2 ⭐ in Level 7 to unlock!',
                    'alignment': Alignment.centerRight,
                    'destination': const Placeholder(),
                  },
                  {
                    'id': 'numbers_hard_3',
                    'title': 'Level 9: The Ultimate Test', 
                    'isUnlocked': (progressMap['numbers_hard_2'] ?? 0) >= 2,
                    'unlockMessage': 'Earn 2 ⭐ in Level 8 to unlock!',
                    'alignment': Alignment.center, 
                    'destination': const Placeholder(),
                  },
                ];

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: themeStyles['cardBg'],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: themeStyles['primary'], width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, color: themeStyles['primary'], size: 24),
                              const SizedBox(width: 6),
                              Text(
                                "$categoryStars Stars",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: themeStyles['text']),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      _buildSectionDivider("EASY", themeStyles),
                      const SizedBox(height: 10),

                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pathNodes.length,
                        separatorBuilder: (context, index) {
                          if (index == 2) { 
                            return Column(
                              children: [
                                _buildVerticalPathLine(themeStyles),
                                _buildSectionDivider("MEDIUM", themeStyles),
                                _buildVerticalPathLine(themeStyles),
                              ],
                            );
                          } else if (index == 5) { 
                            return Column(
                              children: [
                                _buildVerticalPathLine(themeStyles),
                                _buildSectionDivider("HARD", themeStyles),
                                _buildVerticalPathLine(themeStyles),
                              ],
                            );
                          }
                          return _buildVerticalPathLine(themeStyles);
                        },
                        itemBuilder: (context, index) {
                          final node = pathNodes[index];
                          final String nodeId = node['id'];
                          final int earnedStars = progressMap[nodeId] ?? 0;
                          final bool isUnlocked = node['isUnlocked'];

                          return Align(
                            alignment: node['alignment'],
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isUnlocked)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: List.generate(3, (starIdx) {
                                      return Icon(
                                        starIdx < earnedStars ? Icons.star_rounded : Icons.star_border_rounded,
                                        color: themeStyles['primary'],
                                        size: 20,
                                      );
                                    }),
                                  )
                                else
                                  Text(
                                    "🔒 Locked",
                                    style: TextStyle(color: themeStyles['dividerText'], fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                const SizedBox(height: 8),

                                GestureDetector(
                                  onTap: isUnlocked
                                      ? () {
                                          _soundProvider.stopBgm();
                                          Navigator.push(
                                            context, 
                                            MaterialPageRoute(builder: (context) => node['destination'])
                                          ).then((_) {
                                            _soundProvider.playBgm();
                                          });
                                        }
                                      : () {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(node['unlockMessage']),
                                              backgroundColor: Colors.redAccent,
                                            ),
                                          );
                                        },
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 104,
                                        height: 104,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isUnlocked ? themeStyles['primary'].withOpacity(0.25) : Colors.black12,
                                        ),
                                      ),
                                      Container(
                                        width: 86,
                                        height: 86,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: isUnlocked 
                                              ? [themeStyles['primary'].withOpacity(0.7), themeStyles['primary']]
                                              : [Colors.grey.shade400, Colors.grey.shade700],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (isUnlocked ? themeStyles['primary'] : Colors.black).withOpacity(0.5),
                                              blurRadius: 10,
                                              offset: const Offset(0, 6),
                                            )
                                          ],
                                          border: Border.all(
                                            color: isUnlocked ? Colors.white : Colors.grey.shade400,
                                            width: 4,
                                          ),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            isUnlocked ? Icons.play_arrow_rounded : Icons.lock_rounded,
                                            color: Colors.white,
                                            size: 46,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),

                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: themeStyles['cardBg'],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    node['title'],
                                    style: TextStyle(
                                      color: isUnlocked ? themeStyles['text'] : themeStyles['dividerText'],
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                )
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}