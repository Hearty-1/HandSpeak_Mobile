import 'dart:math';
import 'package:flutter/material.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:provider/provider.dart'; 
import '/providers/sound_provider.dart'; 
import '/services/progress_service.dart'; 
import 'easyAct_mc.dart'; 

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
    
    // ENHANCED DEFAULT THEME: Kid-Friendly Playground Palette
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

// ==========================================
// 2. BACKEND-CONNECTED ACTIVITY INTERFACE
// ==========================================
class ActivityInterface extends StatefulWidget {
  final String difficulty;

  const ActivityInterface({super.key, required this.difficulty});

  @override
  State<ActivityInterface> createState() => _ActivityInterfaceState();
}

class _ActivityInterfaceState extends State<ActivityInterface> {
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

    if (bgColor == 0xFF080928) { // Space Theme
      const nodeColor = Color(0xFFB9A6FF);
      return {
        'primary': const Color(0xFF7C4DFF), 
        'text': const Color(0xFFB9A6FF),
        'line': nodeColor.withOpacity(0.6),
        'dividerText': const Color(0xFFB9A6FF).withOpacity(0.7),
        'appBarIcon': const Color(0xFFB9A6FF),
        'cardBg': const Color(0xFF1B1A4B),
        'nodeColor': nodeColor,
        'nodeLightColor': const Color(0xFFC3B1E1),
      };
    }
    if (bgColor == 0xFF1D3D3A) { // Forest Theme
      const nodeColor = Color(0xFFB8D4CF);
      return {
        'primary': const Color(0xFFD7B3A1), 
        'text': const Color(0xFFF2F5F4),
        'line': nodeColor.withOpacity(0.6),
        'dividerText': const Color(0xFFF2F5F4).withOpacity(0.7),
        'appBarIcon': const Color(0xFFF2F5F4),
        'cardBg': const Color(0xFF4D7C73),
        'nodeColor': nodeColor,
        'nodeLightColor': const Color(0xFFE2F1ED),
      };
    }
    if (bgColor == 0xFF001B3A) { // Ocean Theme
      const nodeColor = Color(0xFF00E5FF);
      return {
        'primary': const Color(0xFF00E5FF), 
        'text': Colors.white,
        'line': nodeColor.withOpacity(0.6),
        'dividerText': Colors.white70,
        'appBarIcon': Colors.white,
        'cardBg': Colors.black54,
        'nodeColor': nodeColor,
        'nodeLightColor': const Color(0xFF80F3FF),
      };
    }
    if (bgColor == 0xFFE0EAFC) { // Sky Theme
      const nodeColor = Color(0xFF5C7CFA);
      return {
        'primary': const Color(0xFF5C7CFA), 
        'text': const Color(0xFF1E1E1E),
        'line': nodeColor.withOpacity(0.6),
        'dividerText': Colors.black54,
        'appBarIcon': const Color(0xFF322144),
        'cardBg': Colors.white.withOpacity(0.9),
        'nodeColor': nodeColor,
        'nodeLightColor': const Color(0xFF91A7FF),
      };
    }
    
    // Default Theme (Yellow Nodes)
    const defaultNodeYellow = Color(0xFFFFB300);
    return {
      'primary': const Color(0xFFFF6B8B),
      'text': const Color(0xFF332050),
      'line': defaultNodeYellow.withOpacity(0.6),
      'dividerText': const Color(0xFF6E5686),
      'appBarIcon': const Color(0xFF332050),
      'cardBg': Colors.white.withOpacity(0.92),
      'nodeColor': defaultNodeYellow,
      'nodeLightColor': const Color(0xFFFFD54F),
    };
  }

  Widget _buildVerticalPathLine(Map<String, dynamic> themeStyles) {
    final Color nodeColor = themeStyles['nodeColor'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(4, (index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: nodeColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: nodeColor.withOpacity(0.4), blurRadius: 4, spreadRadius: 1)
              ],
            ),
          ),
        )),
      ),
    );
  }

  String get _appBarTitle {
    if (widget.difficulty.isEmpty) return 'Alphabet Activity';
    return '${widget.difficulty[0].toUpperCase()}${widget.difficulty.substring(1)} Activity';
  }

  @override
  Widget build(BuildContext context) {
    final themeStyles = _getThemeStyles(context);
    final scaffoldBgColor = Theme.of(context).scaffoldBackgroundColor;
    final String currentDifficulty = widget.difficulty.isNotEmpty ? widget.difficulty.toLowerCase() : 'easy';
    final Color nodeColor = themeStyles['nodeColor'];
    final Color nodeLightColor = themeStyles['nodeLightColor'];

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
          _appBarTitle, 
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
              builder: (context, userProgressSnapshot) { 
                if (userProgressSnapshot.connectionState == ConnectionState.waiting) { 
                  return Center(child: CircularProgressIndicator(color: nodeColor)); 
                }

                int totalCategoryStars = 0; 
                int totalEasyStars = 0;
                int totalMediumStars = 0;
                Map<String, dynamic> progressMap = {}; 

                if (userProgressSnapshot.hasData && userProgressSnapshot.data!.exists) { 
                  final data = userProgressSnapshot.data!.data() as Map<String, dynamic>?; 
                  if (data != null && data['progress'] != null) { 
                    progressMap = Map<String, dynamic>.from(data['progress']); 
                    
                    final String prefix = 'alphabet_${currentDifficulty}_';
                    progressMap.forEach((key, value) { 
                      final int stars = (value as num).toInt();
                      if (key.startsWith(prefix)) totalCategoryStars += stars;
                      if (key.startsWith('alphabet_easy_')) totalEasyStars += stars;
                      if (key.startsWith('alphabet_medium_')) totalMediumStars += stars;
                    });
                  }
                }

                bool isTierUnlocked = true;
                if (currentDifficulty == 'medium') {
                  isTierUnlocked = totalEasyStars >= 5;
                } else if (currentDifficulty == 'hard') {
                  isTierUnlocked = totalMediumStars >= 5;
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('activity_questions')
                      .where('category', isEqualTo: 'alphabet')
                      .snapshots(),
                  builder: (context, questionsSnapshot) {
                    if (questionsSnapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator(color: nodeColor));
                    }

                    final docs = questionsSnapshot.data?.docs ?? [];

                    final Map<String, Map<String, dynamic>> levelsMap = {};
                    for (var doc in docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final String? levelId = data['level'];
                      if (levelId != null && levelId.startsWith('alphabet_${currentDifficulty}_')) {
                        if (!levelsMap.containsKey(levelId)) {
                          levelsMap[levelId] = {
                            'levelId': levelId,
                            'type': data['type'] ?? 'fill_in',
                            'title': 'Level ${levelId.split('_').last}',
                          };
                        }
                      }
                    }

                    final levelKeys = levelsMap.keys.toList()
                      ..sort((a, b) {
                        // Extract the numerical part at the end of the level ID string
                        final int numA = int.tryParse(a.split('_').last) ?? 0;
                        final int numB = int.tryParse(b.split('_').last) ?? 0;
                        
                        // Compare them as actual numbers
                        return numA.compareTo(numB);
                      });

                    if (levelKeys.isEmpty) {
                      return Center(
                        child: Text(
                          "No questions found for $currentDifficulty mode.",
                          style: TextStyle(color: themeStyles['text'], fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      );
                    }

                    final alignments = [
                      Alignment.center,
                      Alignment.centerRight,
                      Alignment.center,
                      Alignment.centerLeft,
                    ];

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          child: Align( 
                            alignment: Alignment.centerRight, 
                            child: Container( 
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), 
                              decoration: BoxDecoration( 
                                color: themeStyles['cardBg'], 
                                borderRadius: BorderRadius.circular(20), 
                                border: Border.all(color: nodeColor, width: 2), 
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))], 
                              ),
                              child: Row( 
                                mainAxisSize: MainAxisSize.min, 
                                children: [ 
                                  Icon(Icons.star_rounded, color: nodeColor, size: 24), 
                                  const SizedBox(width: 6), 
                                  Text( 
                                    "$totalCategoryStars / ${levelKeys.length * 3} Stars", 
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: themeStyles['text']), 
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        Expanded(
                          child: ListView.builder( 
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), 
                            physics: const BouncingScrollPhysics(), 
                            itemCount: levelKeys.length, 
                            itemBuilder: (context, index) { 
                              final levelId = levelKeys[index];
                              final levelData = levelsMap[levelId]!;
                              final String title = levelData['title'];
                              final String questionType = levelData['type'];

                              final int earnedStars = progressMap[levelId] ?? 0; 
                              final String prevLevelId = index > 0 ? levelKeys[index - 1] : '';
                              final int prevLevelStars = prevLevelId.isNotEmpty ? (progressMap[prevLevelId] ?? 0) : 0;

                              final bool isUnlocked = isTierUnlocked && (index == 0 || prevLevelStars >= 2);

                              final unlockMsg = !isTierUnlocked
                                  ? 'Earn at least 5 ⭐ in the previous difficulty to unlock!'
                                  : 'Earn 2 ⭐ in Level $index to unlock!';

                              return Column(
                                children: [
                                  Align( 
                                    alignment: alignments[index % alignments.length], 
                                    child: Column( 
                                      mainAxisSize: MainAxisSize.min, 
                                      children: [ 
                                        if (isUnlocked) 
                                          Row( 
                                            mainAxisSize: MainAxisSize.min, 
                                            children: List.generate(3, (starIdx) { 
                                              return Icon( 
                                                starIdx < earnedStars ? Icons.star_rounded : Icons.star_border_rounded, 
                                                color: nodeColor, 
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
                                                    MaterialPageRoute(
                                                      builder: (context) => EasyActMc(
                                                        levelId: levelId,
                                                        questionType: questionType,
                                                      ),
                                                    ),
                                                  ).then((_) {
                                                    _soundProvider.playBgm();
                                                  });
                                                }
                                              : () { 
                                                  ScaffoldMessenger.of(context).showSnackBar( 
                                                    SnackBar( 
                                                      content: Text(unlockMsg), 
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
                                                  color: isUnlocked ? nodeColor.withOpacity(0.3) : Colors.black12,
                                                ),
                                              ),
                                              Container( 
                                                width: 86, 
                                                height: 86, 
                                                decoration: BoxDecoration( 
                                                  shape: BoxShape.circle, 
                                                  gradient: LinearGradient(
                                                    colors: isUnlocked 
                                                      ? [nodeLightColor, nodeColor]
                                                      : [Colors.grey.shade400, Colors.grey.shade700],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  boxShadow: [ 
                                                    BoxShadow( 
                                                      color: (isUnlocked ? nodeColor : Colors.black).withOpacity(0.5), 
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
                                            title, 
                                            style: TextStyle( 
                                              color: isUnlocked ? themeStyles['text'] : themeStyles['dividerText'], 
                                              fontWeight: FontWeight.w800, 
                                              fontSize: 14, 
                                            ),
                                          ),
                                        )
                                      ],
                                    ),
                                  ),

                                  if (index < levelKeys.length - 1)
                                    _buildVerticalPathLine(themeStyles),
                                ],
                              );
                            },
                          ),
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
}