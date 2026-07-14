import 'package:flutter/material.dart';
import 'easyNumAct_mc.dart';

class NumbersActivityInterface extends StatelessWidget {
  final int level1Xp;
  final int level2Xp;
  final int level3Xp;
  final int targetXp;

  const NumbersActivityInterface({
    super.key,
    this.level1Xp = 0,
    this.level2Xp = 0,
    this.level3Xp = 0,
    this.targetXp = 1000,
  });

  @override
  Widget build(BuildContext context) {
    const double baseWidth = 393;
    const double baseHeight = 852;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double scale = constraints.maxWidth / baseWidth;

        return Scaffold(
          body: SafeArea(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: const Color(0xFFFFF9E5),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  height: baseHeight * scale,
                  width: constraints.maxWidth,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // --- TOP BANNERS ---
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Container(
                          width: 393 * scale,
                          height: 50 * scale,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFB800),
                            boxShadow: [BoxShadow(color: Color(0x0C132C4A), blurRadius: 16)],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 50 * scale,
                        child: Container(
                          width: 393 * scale,
                          height: 50 * scale,
                          decoration: const BoxDecoration(
                            color: Color(0xCCF39C12),
                            boxShadow: [BoxShadow(color: Color(0x0C132C4A), blurRadius: 16)],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 142 * scale, // Slightly adjusted for "Numbers" title
                        top: 61 * scale,
                        child: Text(
                          'Numbers',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 20 * scale,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.96,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16 * scale,
                        top: 51 * scale,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 46 * scale,
                            height: 46 * scale,
                            decoration: ShapeDecoration(
                              color: const Color(0x33FFF8E7),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14 * scale),
                              ),
                            ),
                            child: Icon(Icons.arrow_back, color: Colors.black87, size: 22 * scale),
                          ),
                        ),
                      ),

                      // --- ACTIVITY LEVELS ---
                      // Easy
                      ..._buildLevelBlock(
                        scale: scale,
                        startY: 204.0,
                        title: 'Easy',
                        currentXp: level1Xp,
                        targetXp: targetXp,
                        onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const NumbersQuizScreen()),
                        );
                      }
                      ),

                      // Medium
                      ..._buildLevelBlock(
                        scale: scale,
                        startY: 406.0,
                        title: 'Medium',
                        currentXp: level2Xp,
                        targetXp: targetXp,
                      ),

                      // Hard
                      ..._buildLevelBlock(
                        scale: scale,
                        startY: 608.0,
                        title: 'Hard',
                        currentXp: level3Xp,
                        targetXp: targetXp,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildLevelBlock({
    required double scale,
    required double startY,
    required String title,
    required int currentXp,
    required int targetXp,
    VoidCallback? onTap,
  }) {
    final double progressRatio = (currentXp / targetXp).clamp(0.0, 1.0);
    const double trackWidth = 312.64;

    return [
      // Base Container
      Positioned(
        left: 21.50 * scale,
        top: startY * scale,
        child: Container(
          width: 350 * scale,
          height: 85.82 * scale,
          decoration: ShapeDecoration(
            color: const Color(0xFFFFB800),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale)),
          ),
        ),
      ),
      
      // Title
      Positioned(
        left: 36 * scale,
        top: (startY + 16.08) * scale,
        child: SizedBox(
          width: 250 * scale,
          child: Text(
            title,
            style: TextStyle(
              color: Colors.black,
              fontSize: 54 * scale,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w800,
              letterSpacing: -3.84 * scale,
            ),
          ),
        ),
      ),

      // ARROW BUTTON
      Positioned(
        right: 40 * scale,
        top: (startY + 20) * scale,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12 * scale),
          ),
          child: IconButton(
            onPressed: onTap, 
            icon: Icon(Icons.arrow_forward_ios, size: 20 * scale),
            color: const Color(0xFFFFB800),
          ),
        ),
      ),

      // XP Sub-Container
      Positioned(
        left: 21.50 * scale,
        top: (startY + 93.5) * scale,
        child: Container(
          width: 350 * scale,
          height: 66.50 * scale,
          decoration: ShapeDecoration(
            color: Colors.white.withOpacity(0.18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale)),
          ),
        ),
      ),

      // Star Icon
      Positioned(
        left: 42.88 * scale,
        top: (startY + 102.93) * scale,
        child: Icon(Icons.star, color: const Color(0xFFFFB800), size: 36 * scale),
      ),

      // XP Text
      Positioned(
        left: 88.47 * scale,
        top: (startY + 105.4) * scale,
        child: Text(
          '$currentXp XP',
          style: TextStyle(
            color: const Color(0xFFBA8E23),
            fontSize: 20 * scale,
            fontFamily: 'Holtwood One SC',
            fontWeight: FontWeight.w400,
            letterSpacing: -1.20 * scale,
          ),
        ),
      ),

      // Background Progress Track (Grey)
      Positioned(
        left: 43.13 * scale,
        top: (startY + 143.82) * scale,
        child: Container(
          width: trackWidth * scale,
          height: 8.99 * scale,
          decoration: ShapeDecoration(
            color: const Color(0xFFF1F1FA),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)),
          ),
        ),
      ),

      // Active Progress Track
      Positioned(
        left: 43.13 * scale,
        top: (startY + 143.82) * scale,
        child: Container(
          width: (trackWidth * progressRatio) * scale,
          height: 8.99 * scale,
          decoration: ShapeDecoration(
            color: const Color(0xFF7DC579),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)),
          ),
        ),
      ),
    ];
  }
}