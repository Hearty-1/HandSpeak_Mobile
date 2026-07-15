import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/services/progress_service.dart';
import '../alphabet/practice.dart'; 
import 'numbers_tutorial.dart';
import 'numbers_activity.dart';

class NumbersInterface extends StatelessWidget {
  final int currentLevel;
  final int currentXp;
  final int targetXp;

  const NumbersInterface({
    super.key,
    this.currentLevel = 1,
    this.currentXp = 0,
    this.targetXp = 1000,
  });

  @override
  Widget build(BuildContext context) {
    const double baseWidth = 393;
    const double baseHeight = 793;

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(),
      builder: (context, snapshot) {
        int liveEasyXp = 0;
        int liveMediumXp = 0;
        int liveHardXp = 0;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            liveEasyXp = (data['numEasyXp'] ?? 0).clamp(0, targetXp);
            liveMediumXp = (data['numMediumXp'] ?? 0).clamp(0, targetXp);
            liveHardXp = (data['numHardXp'] ?? 0).clamp(0, targetXp);
          }
        }

        // Active numbers levels calculations
        int activeLevel = 1;
        int activeXp = liveEasyXp;
        if (liveEasyXp >= targetXp) {
          activeLevel = 2;
          activeXp = liveMediumXp;
        }
        if (liveMediumXp >= targetXp) {
          activeLevel = 3;
          activeXp = liveHardXp;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final double scale = constraints.maxWidth / baseWidth;

            return Container(
              width: double.infinity,
              height: double.infinity,
              color: const Color(0xFFFFF9E5),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: SizedBox(
                        height: baseHeight * scale,
                        width: constraints.maxWidth,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Header Components
                            Positioned(
                              left: 0, top: 0,
                              child: Container(
                                width: 393 * scale, height: 50 * scale,
                                decoration: const BoxDecoration(color: Color(0xFFFFB800), boxShadow: [BoxShadow(color: Color(0x0C132C4A), blurRadius: 16)]),
                              ),
                            ),
                            Positioned(
                              left: 0, top: 50 * scale,
                              child: Container(
                                width: 393 * scale, height: 50 * scale,
                                decoration: const BoxDecoration(color: Color(0xCCF39C12), boxShadow: [BoxShadow(color: Color(0x0C132C4A), blurRadius: 16)]),
                              ),
                            ),
                            Positioned(
                              left: 150 * scale, top: 61 * scale,
                              child: Text('Numbers', style: TextStyle(color: Colors.black, fontSize: 20 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96)),
                            ),
                            Positioned(
                              left: 16 * scale, top: 51 * scale,
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  width: 46 * scale, height: 46 * scale,
                                  decoration: ShapeDecoration(color: const Color(0x33FFF8E7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale))),
                                  child: Icon(Icons.arrow_back, color: Colors.black87, size: 22 * scale),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 346.46 * scale, top: 0,
                              child: Container(
                                width: 45.39 * scale, height: 50.11 * scale,
                                decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/image 66.png"), fit: BoxFit.fill)),
                              ),
                            ),

                            // Dynamic Live Progress Tracker
                            Positioned(
                              left: 6 * scale, top: 112 * scale,
                              child: _buildMainProgressPanel(
                                scale: scale,
                                level: activeLevel,
                                currentXp: activeXp,
                                targetXp: targetXp,
                              ),
                            ),

                            // Tutorial Container Row
                            Positioned(
                              left: 24 * scale, top: 180 * scale,
                              child: Container(width: 130 * scale, height: 110 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/tutor.png"), fit: BoxFit.fill))),
                            ),
                            Positioned(
                              left: 165 * scale, top: 195 * scale,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Tutorial', style: TextStyle(color: Colors.black, fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5)),
                                  SizedBox(height: 6 * scale),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB800), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale))),
                                    icon: Icon(Icons.play_arrow, size: 16 * scale),
                                    label: Text('Start Learn', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13 * scale)),
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => NumbersTutorialInterface())),
                                  ),
                                ],
                              ),
                            ),

                            // Practice Container Row
                            Positioned(
                              left: 16 * scale, top: 300 * scale,
                              child: Container(width: 135 * scale, height: 135 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/practice.png"), fit: BoxFit.cover))),
                            ),
                            Positioned(
                              left: 165 * scale, top: 325 * scale,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Practice', style: TextStyle(color: Colors.black, fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5)),
                                  SizedBox(height: 6 * scale),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB800), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale))),
                                    icon: Icon(Icons.camera_alt, size: 16 * scale),
                                    label: Text('Train Sign', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13 * scale)),
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PracticeInterface())),
                                  ),
                                ],
                              ),
                            ),

                            // Sub Activity Metrics Section
                            Positioned(left: 56.75 * scale, top: 455 * scale, child: Text('Activity', style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44))),
                            Positioned(left: 233.75 * scale, top: 455 * scale, child: Text('Challenges', style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44))),
                            
                            Positioned(
                              left: 20.75 * scale, top: 492 * scale,
                              child: GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NumbersActivityInterface())),
                                child: Container(width: 164 * scale, height: 160 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/activity.png"), fit: BoxFit.cover))),
                              ),
                            ),
                            Positioned(
                              left: 215.75 * scale, top: 492 * scale,
                              child: GestureDetector(
                                onTap: () {},
                                child: Container(width: 159 * scale, height: 159 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/challenge.png"), fit: BoxFit.cover))),
                              ),
                            ),

                            Positioned(left: 13.75 * scale, top: 665 * scale, child: _buildSubMetricPanel(scale: scale, xpDisplay: "$activeXp XP", progress: activeXp / targetXp)),
                            Positioned(left: 203.75 * scale, top: 665 * scale, child: _buildSubMetricPanel(scale: scale, xpDisplay: "0 XP", progress: 0.0)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMainProgressPanel({required double scale, required int level, required int currentXp, required int targetXp}) {
    final double progressRatio = (currentXp / targetXp).clamp(0.0, 1.0);
    const double maxTrackWidth = 235.0;

    return Container(
      width: 381 * scale, height: 55 * scale,
      decoration: ShapeDecoration(color: Colors.white.withOpacity(0.18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale))),
      child: Stack(
        children: [
          Positioned(left: 56 * scale, top: 5 * scale, child: Text('Level $level', style: TextStyle(color: const Color(0xFF322144), fontSize: 14 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.w600, letterSpacing: -0.90))),
          Positioned(left: 56 * scale, top: 24 * scale, child: Text('$currentXp XP', style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 17 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.20))),
          
          Positioned(
            left: 130 * scale, top: 26 * scale,
            child: Container(width: maxTrackWidth * scale, height: 6 * scale, decoration: ShapeDecoration(color: const Color(0xFFF1F1FA), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)))),
          ),
          Positioned(
            left: 130 * scale, top: 26 * scale,
            child: Container(width: (maxTrackWidth * progressRatio) * scale, height: 6 * scale, decoration: ShapeDecoration(color: const Color(0xFF7DC579), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)))),
          ),
          Positioned(left: 20 * scale, top: 16 * scale, child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, o, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale))),
        ],
      ),
    );
  }

  Widget _buildSubMetricPanel({required double scale, required String xpDisplay, required double progress}) {
    return Container(
      width: 178 * scale, height: 37 * scale,
      decoration: ShapeDecoration(color: Colors.white.withOpacity(0.18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale))),
      child: Stack(
        children: [
          Positioned(left: 45 * scale, top: 3 * scale, child: Text(xpDisplay, style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 16 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.20))),
          Positioned(
            left: 12 * scale, top: 24 * scale,
            child: Container(width: 154 * scale, height: 4 * scale, decoration: ShapeDecoration(color: const Color(0xFFF1F1FA), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)))),
          ),
          Positioned(
            left: 12 * scale, top: 24 * scale,
            child: Container(width: (154 * progress) * scale, height: 4 * scale, decoration: ShapeDecoration(color: const Color(0xFF7DC579), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)))),
          ),
          Positioned(left: 12 * scale, top: 3 * scale, child: Image.asset("assets/pictures/star.png", width: 18 * scale, height: 17 * scale, errorBuilder: (c, o, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 14 * scale))),
        ],
      ),
    );
  }
}