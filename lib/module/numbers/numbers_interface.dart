import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/services/progress_service.dart';

import 'numbers_practice.dart'; 
import 'numbers_tutorial.dart';
import 'numbers_activity.dart';

class NumbersInterface extends StatelessWidget {
  final int currentXp;
  final int targetXp;

  const NumbersInterface({
    super.key,
    this.currentXp = 0,
    this.targetXp = 1000,
  });

  @override
  Widget build(BuildContext context) {
    const double baseWidth = 393;
    const double baseHeight = 693; // Reduced by 100 to account for standard AppBar

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(),
      builder: (context, snapshot) {
        
        int numbersXp = 0;
        int categoryStars = 0;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            numbersXp = data['numbersXp'] ?? 0;
            
            if (data['progress'] != null) {
              Map<String, dynamic> progressMap = Map<String, dynamic>.from(data['progress']);
              progressMap.forEach((key, value) {
                if (key.startsWith('numbers_')) {
                  categoryStars += (value as num).toInt();
                }
              });
            }
          }
        }

        int displayXp = numbersXp > targetXp ? targetXp : numbersXp;

        return Scaffold(
          backgroundColor: const Color(0xFFFFF9E5),
          appBar: AppBar(
            backgroundColor: const Color(0xFFFFB800),
            elevation: 0,
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.black),
            title: const Text(
              'Numbers',
              style: TextStyle(color: Colors.black, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Image.asset("assets/pictures/image 66.png", width: 45),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final double scale = constraints.maxWidth / baseWidth;

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  height: baseHeight * scale,
                  width: constraints.maxWidth,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 6 * scale, top: 12 * scale,
                        child: _buildMainProgressPanel(
                          scale: scale,
                          currentXp: displayXp,
                          targetXp: targetXp,
                        ),
                      ),

                      Positioned(
                        left: 24 * scale, top: 80 * scale,
                        child: Container(width: 130 * scale, height: 110 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/tutor.png"), fit: BoxFit.fill))),
                      ),
                      Positioned(
                        left: 165 * scale, top: 95 * scale,
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

                      Positioned(
                        left: 16 * scale, top: 200 * scale,
                        child: Container(width: 135 * scale, height: 135 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/practice.png"), fit: BoxFit.cover))),
                      ),
                      Positioned(
                        left: 165 * scale, top: 225 * scale,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Practice', style: TextStyle(color: Colors.black, fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5)),
                            SizedBox(height: 6 * scale),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB800), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale))),
                              icon: Icon(Icons.camera_alt, size: 16 * scale),
                              label: Text('Train Sign', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13 * scale)),
                              onPressed: () => Navigator.push(
                                context, 
                                MaterialPageRoute(builder: (context) => const NumbersPractice())
                              ),
                            ),
                          ],
                        ),
                      ),

                      Positioned(left: 56.75 * scale, top: 355 * scale, child: Text('Activity', style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44))),
                      Positioned(left: 233.75 * scale, top: 355 * scale, child: Text('Challenges', style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44))),
                      
                      Positioned(
                        left: 20.75 * scale, top: 392 * scale,
                        child: GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NumbersActivityInterface())),
                          child: Container(width: 164 * scale, height: 160 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/activity.png"), fit: BoxFit.cover))),
                        ),
                      ),
                      Positioned(
                        left: 215.75 * scale, top: 392 * scale,
                        child: GestureDetector(
                          onTap: () {},
                          child: Container(width: 159 * scale, height: 159 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/challenge.png"), fit: BoxFit.cover))),
                        ),
                      ),

                      Positioned(
                        left: 13.75 * scale, 
                        top: 565 * scale, 
                        child: _buildSubMetricPanel(scale: scale, valueDisplay: "$categoryStars Stars", progress: (categoryStars / 27).clamp(0.0, 1.0))
                      ),
                      Positioned(
                        left: 203.75 * scale, 
                        top: 565 * scale, 
                        child: _buildSubMetricPanel(scale: scale, valueDisplay: "0 XP", progress: 0.0)
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMainProgressPanel({required double scale, required int currentXp, required int targetXp}) {
    final double progressRatio = (currentXp / targetXp).clamp(0.0, 1.0);
    const double maxTrackWidth = 235.0;

    return Container(
      width: 381 * scale, height: 55 * scale,
      decoration: ShapeDecoration(color: Colors.white.withOpacity(0.18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale))),
      child: Stack(
        children: [
          Positioned(left: 56 * scale, top: 5 * scale, child: Text('Progress', style: TextStyle(color: const Color(0xFF322144), fontSize: 14 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.w600, letterSpacing: -0.90))),
          Positioned(left: 56 * scale, top: 24 * scale, child: Text('$currentXp / $targetXp XP', style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 16 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.0))),
          
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

  Widget _buildSubMetricPanel({required double scale, required String valueDisplay, required double progress}) {
    return Container(
      width: 178 * scale, height: 37 * scale,
      decoration: ShapeDecoration(color: Colors.white.withOpacity(0.18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * scale))),
      child: Stack(
        children: [
          Positioned(
            left: 45 * scale, 
            top: 3 * scale, 
            child: Text(valueDisplay, style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 15 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.20))
          ),
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