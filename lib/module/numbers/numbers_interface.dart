import 'dart:ui'; // Required for ImageFilter (Glassmorphism)
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/services/progress_service.dart';

import 'numbers_practice.dart'; 
import 'numbers_tutorial.dart';
import 'numbers_activity.dart';

class NumbersInterface extends StatelessWidget {
  final int currentXp; //[cite: 13]
  final int targetXp; //[cite: 13]

  const NumbersInterface({
    super.key,
    this.currentXp = 0, //[cite: 13]
    this.targetXp = 1000, //[cite: 13]
  });

  @override
  Widget build(BuildContext context) {
    const double baseWidth = 393; //[cite: 13]
    const double baseHeight = 693; //[cite: 13]

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(), //[cite: 13]
      builder: (context, snapshot) {
        
        int numbersXp = 0; //[cite: 13]
        int categoryStars = 0; //[cite: 13]

        if (snapshot.hasData && snapshot.data!.exists) { //[cite: 13]
          final data = snapshot.data!.data() as Map<String, dynamic>?; //[cite: 13]
          if (data != null) { //[cite: 13]
            numbersXp = data['numbersXp'] ?? 0; //[cite: 13]
            
            if (data['progress'] != null) { //[cite: 13]
              Map<String, dynamic> progressMap = Map<String, dynamic>.from(data['progress']); //[cite: 13]
              progressMap.forEach((key, value) { //[cite: 13]
                if (key.startsWith('numbers_')) { //[cite: 13]
                  categoryStars += (value as num).toInt(); //[cite: 13]
                }
              });
            }
          }
        }

        int displayXp = numbersXp > targetXp ? targetXp : numbersXp; //[cite: 13]

        return Scaffold(
          extendBodyBehindAppBar: true, 
          backgroundColor: const Color(0xFFFFF9E5), //[cite: 13]
          
          appBar: AppBar(
            backgroundColor: Colors.white.withOpacity(0.35),
            elevation: 0, //[cite: 13]
            centerTitle: true, //[cite: 13]
            iconTheme: const IconThemeData(color: Color(0xFF322144)), 
            flexibleSpace: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(color: Colors.transparent),
              ),
            ),
            title: const Text(
              'Numbers',
              style: TextStyle(color: Color(0xFF322144), fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96), //[cite: 13]
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16.0), //[cite: 13]
                child: Image.asset("assets/pictures/image 66.png", width: 45), //[cite: 13]
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final double scale = constraints.maxWidth / baseWidth; //[cite: 13]

              return Stack(
                children: [
                  Positioned(
                    top: 180 * scale, left: -50 * scale,
                    child: Container(width: 200 * scale, height: 200 * scale, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFB800).withOpacity(0.2))),
                  ),
                  Positioned(
                    bottom: 100 * scale, right: -60 * scale,
                    child: Container(width: 250 * scale, height: 250 * scale, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7DC579).withOpacity(0.18))),
                  ),

                  SafeArea(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(), //[cite: 13]
                      child: SizedBox(
                        height: baseHeight * scale, //[cite: 13]
                        width: constraints.maxWidth, //[cite: 13]
                        child: Stack(
                          clipBehavior: Clip.none, //[cite: 13]
                          children: [
                            Positioned(
                              left: 6 * scale, top: 12 * scale, //[cite: 13]
                              child: _buildMainProgressPanel(
                                scale: scale,
                                currentXp: displayXp,
                                targetXp: targetXp,
                              ),
                            ),

                            Positioned(
                              left: 24 * scale, top: 80 * scale, //[cite: 13]
                              child: Container(width: 130 * scale, height: 110 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/tutor.png"), fit: BoxFit.fill))), //[cite: 13]
                            ),
                            Positioned(
                              left: 165 * scale, top: 95 * scale, //[cite: 13]
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, //[cite: 13]
                                children: [
                                  Text('Tutorial', style: TextStyle(color: const Color(0xFF322144), fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5)), //[cite: 13]
                                  SizedBox(height: 6 * scale), //[cite: 13]
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFFB800), 
                                      foregroundColor: Colors.white, 
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale))
                                    ), //[cite: 13]
                                    icon: Icon(Icons.play_arrow, size: 16 * scale), //[cite: 13]
                                    label: Text('Start Learn', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13 * scale)), //[cite: 13]
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => NumbersTutorialInterface())), //[cite: 13]
                                  ),
                                ],
                              ),
                            ),

                            Positioned(
                              left: 16 * scale, top: 200 * scale, //[cite: 13]
                              child: Container(width: 135 * scale, height: 135 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/practice.png"), fit: BoxFit.cover))), //[cite: 13]
                            ),
                            Positioned(
                              left: 165 * scale, top: 225 * scale, //[cite: 13]
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, //[cite: 13]
                                children: [
                                  Text('Practice', style: TextStyle(color: const Color(0xFF322144), fontSize: 28 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5)), //[cite: 13]
                                  SizedBox(height: 6 * scale), //[cite: 13]
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFFB800), 
                                      foregroundColor: Colors.white, 
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale))
                                    ), //[cite: 13]
                                    icon: Icon(Icons.camera_alt, size: 16 * scale), //[cite: 13]
                                    label: Text('Train Sign', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13 * scale)), //[cite: 13]
                                    onPressed: () => Navigator.push(
                                      context, 
                                      MaterialPageRoute(builder: (context) => const NumbersPractice()) //[cite: 13]
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Positioned(left: 56.75 * scale, top: 355 * scale, child: Text('Activity', style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44))), //[cite: 13]
                            Positioned(left: 233.75 * scale, top: 355 * scale, child: Text('Challenges', style: TextStyle(color: const Color(0xFF312244), fontSize: 24 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.44))), //[cite: 13]
                            
                            Positioned(
                              left: 20.75 * scale, top: 392 * scale, //[cite: 13]
                              child: GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NumbersActivityInterface())), //[cite: 13]
                                child: Container(width: 164 * scale, height: 160 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/activity.png"), fit: BoxFit.cover))), //[cite: 13]
                              ),
                            ),
                            Positioned(
                              left: 215.75 * scale, top: 392 * scale, //[cite: 13]
                              child: GestureDetector(
                                onTap: () {}, //[cite: 13]
                                child: Container(width: 159 * scale, height: 159 * scale, decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/pictures/challenge.png"), fit: BoxFit.cover))), //[cite: 13]
                              ),
                            ),

                            Positioned(
                              left: 13.75 * scale, 
                              top: 565 * scale, //[cite: 13]
                              child: _buildSubMetricPanel(scale: scale, valueDisplay: "$categoryStars Stars", progress: (categoryStars / 27).clamp(0.0, 1.0)) //[cite: 13]
                            ),
                            Positioned(
                              left: 203.75 * scale, 
                              top: 565 * scale, //[cite: 13]
                              child: _buildSubMetricPanel(scale: scale, valueDisplay: "0 XP", progress: 0.0) //[cite: 13]
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMainProgressPanel({required double scale, required int currentXp, required int targetXp}) {
    final double progressRatio = (currentXp / targetXp).clamp(0.0, 1.0); //[cite: 13]
    const double maxTrackWidth = 235.0; //[cite: 13]

    return ClipRRect(
      borderRadius: BorderRadius.circular(14 * scale),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 381 * scale, height: 55 * scale, //[cite: 13]
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.45), 
            borderRadius: BorderRadius.circular(14 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5 * scale),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ]
          ),
          child: Stack(
            children: [
              Positioned(left: 56 * scale, top: 5 * scale, child: Text('Progress', style: TextStyle(color: const Color(0xFF322144), fontSize: 14 * scale, fontFamily: 'Google Sans Flex', fontWeight: FontWeight.w600, letterSpacing: -0.90))), //[cite: 13]
              Positioned(left: 56 * scale, top: 24 * scale, child: Text('$currentXp / $targetXp XP', style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 16 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.0))), //[cite: 13]
              
              Positioned(
                left: 130 * scale, top: 26 * scale, //[cite: 13]
                child: Container(width: maxTrackWidth * scale, height: 6 * scale, decoration: ShapeDecoration(color: Colors.black.withOpacity(0.06), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)))), //[cite: 13]
              ),
              Positioned(
                left: 130 * scale, top: 26 * scale, //[cite: 13]
                child: Container(width: (maxTrackWidth * progressRatio) * scale, height: 6 * scale, decoration: ShapeDecoration(color: const Color(0xFF7DC579), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)))), //[cite: 13]
              ),
              Positioned(left: 20 * scale, top: 16 * scale, child: Image.asset("assets/pictures/star.png", width: 22 * scale, height: 21 * scale, errorBuilder: (c, o, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 20 * scale))), //[cite: 13]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubMetricPanel({required double scale, required String valueDisplay, required double progress}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14 * scale),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: 178 * scale, height: 37 * scale, //[cite: 13]
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.45), 
            borderRadius: BorderRadius.circular(14 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5 * scale),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ]
          ),
          child: Stack(
            children: [
              Positioned(
                left: 45 * scale, 
                top: 3 * scale, //[cite: 13]
                child: Text(valueDisplay, style: TextStyle(color: const Color(0xFFBA8E23), fontSize: 15 * scale, fontFamily: 'Holtwood One SC', fontWeight: FontWeight.w400, letterSpacing: -1.20)) //[cite: 13]
              ),
              Positioned(
                left: 12 * scale, top: 24 * scale, //[cite: 13]
                child: Container(width: 154 * scale, height: 4 * scale, decoration: ShapeDecoration(color: Colors.black.withOpacity(0.06), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)))), //[cite: 13]
              ),
              Positioned(
                left: 12 * scale, top: 24 * scale, //[cite: 13]
                child: Container(width: (154 * progress) * scale, height: 4 * scale, decoration: ShapeDecoration(color: const Color(0xFF7DC579), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)))), //[cite: 13]
              ),
              Positioned(left: 12 * scale, top: 3 * scale, child: Image.asset("assets/pictures/star.png", width: 18 * scale, height: 17 * scale, errorBuilder: (c, o, s) => Icon(Icons.star, color: const Color(0xFFFFB800), size: 14 * scale))), //[cite: 13]
            ],
          ),
        ),
      ),
    );
  }
}