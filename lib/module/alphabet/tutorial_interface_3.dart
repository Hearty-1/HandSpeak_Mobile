import 'dart:ui'; // Required for ImageFilter (Glassmorphism)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tutorial_practice.dart';

class TutorialSign {
  final String label;
  final String imagePath;
  const TutorialSign({required this.label, required this.imagePath});
}

class TutorialInterface3 extends StatefulWidget {
  final int initialIndex; 
  
  const TutorialInterface3({super.key, this.initialIndex = 0});

  @override
  _TutorialInterface3State createState() => _TutorialInterface3State();
}

class _TutorialInterface3State extends State<TutorialInterface3> {
  final List<TutorialSign> _alphabetList = const [
    TutorialSign(label: 'Aa', imagePath: 'assets/pictures/A.jpg'),
    TutorialSign(label: 'Bb', imagePath: 'assets/pictures/B.jpg'),
    TutorialSign(label: 'Cc', imagePath: 'assets/pictures/C.jpg'),
    TutorialSign(label: 'Dd', imagePath: 'assets/pictures/D.jpg'),
    TutorialSign(label: 'Ee', imagePath: 'assets/pictures/E.jpg'),
    TutorialSign(label: 'Ff', imagePath: 'assets/pictures/F.jpg'),
    TutorialSign(label: 'Gg', imagePath: 'assets/pictures/G.jpg'),
    TutorialSign(label: 'Hh', imagePath: 'assets/pictures/H.jpg'),
    TutorialSign(label: 'Ii', imagePath: 'assets/pictures/I.jpg'),
    TutorialSign(label: 'Jj', imagePath: 'assets/pictures/J.jpg'),
    TutorialSign(label: 'Kk', imagePath: 'assets/pictures/K.jpg'),
    TutorialSign(label: 'Ll', imagePath: 'assets/pictures/L.jpg'),
    TutorialSign(label: 'Mm', imagePath: 'assets/pictures/M.jpg'),
    TutorialSign(label: 'Nn', imagePath: 'assets/pictures/N.jpg'),
    TutorialSign(label: 'Oo', imagePath: 'assets/pictures/O.jpg'),
    TutorialSign(label: 'Pp', imagePath: 'assets/pictures/P.jpg'),
    TutorialSign(label: 'Qq', imagePath: 'assets/pictures/Q.jpg'),
    TutorialSign(label: 'Rr', imagePath: 'assets/pictures/R.jpg'),
    TutorialSign(label: 'Ss', imagePath: 'assets/pictures/S.jpg'),
    TutorialSign(label: 'Tt', imagePath: 'assets/pictures/T.jpg'),
    TutorialSign(label: 'Uu', imagePath: 'assets/pictures/U.jpg'),
    TutorialSign(label: 'Vv', imagePath: 'assets/pictures/V.jpg'),
    TutorialSign(label: 'Ww', imagePath: 'assets/pictures/W.jpg'),
    TutorialSign(label: 'Xx', imagePath: 'assets/pictures/X.jpg'),
    TutorialSign(label: 'Yy', imagePath: 'assets/pictures/Y.jpg'),
    TutorialSign(label: 'Zz', imagePath: 'assets/pictures/Z.jpg'),
  ];

  int _currentIndex = 0;
  final int _currentStars = 3; 

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _goToNext() {
    if (_currentIndex < _alphabetList.length - 1) {
      if (_currentStars >= 3) {
        setState(() {
          _currentIndex++;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Earn 3 stars in Practice mode to unlock the next letter!'),
            backgroundColor: Color(0xCCF39C12),
          ),
        );
      }
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
    }
  }

  Stream<DocumentSnapshot>? _getUserDocStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final currentSign = _alphabetList[_currentIndex];
    
    const double baseWidth = 393;
    const double baseHeight = 693; 
    const double maxProgressWidth = 295.0;
    
    double progressPercentage = (_currentIndex + 1) / _alphabetList.length;

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: const Color(0xFFFFF9E5),
      
      // --- GLASSMORPHISM APPBAR ---
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.4), 
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: const Text(
          'Tutorial',
          style: TextStyle(
            color: Colors.black87, 
            fontSize: 22, 
            fontFamily: 'Inter', 
            fontWeight: FontWeight.w800, 
            letterSpacing: -0.96
          ),
        ),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: _getUserDocStream(),
            builder: (context, snapshot) {
              int totalXp = 0;
              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                totalXp = data['alphabetXp'] ?? 0; 
              }
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.5), width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt, color: Color(0xFFBA8E23), size: 16),
                            const SizedBox(width: 4),
                            Text(
                              "$totalXp XP",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFBA8E23)),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
          )
        ],
      ),
      body: Stack(
        children: [
          // Ambient backgrounds
          Positioned(
            top: -50, left: -50,
            child: Container(width: 250, height: 250, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFB800).withOpacity(0.2))),
          ),
          Positioned(
            bottom: 150, right: -100,
            child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7DC579).withOpacity(0.15))),
          ),
          
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double scale = constraints.maxWidth / baseWidth;
                final double calculatedProgressWidth = maxProgressWidth * progressPercentage;

                return SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      height: baseHeight * scale,
                      width: constraints.maxWidth,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0, right: 0, top: 20 * scale,
                            child: Center(
                              child: Text(
                                currentSign.label,
                                style: TextStyle(
                                  color: Colors.black87, 
                                  fontSize: 52 * scale, 
                                  fontFamily: 'Inter', 
                                  fontWeight: FontWeight.w800, 
                                  letterSpacing: -1.5
                                ),
                              ),
                            ),
                          ),

                          // Media Card Showcase Envelope
                          Positioned(
                            left: 47 * scale, top: 105 * scale,
                            child: Container(
                              width: 299 * scale, height: 276 * scale,
                              decoration: ShapeDecoration(
                                image: DecorationImage(
                                  image: AssetImage(currentSign.imagePath), 
                                  fit: BoxFit.cover
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16 * scale)),
                                shadows: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 15, offset: const Offset(0, 8))],
                              ),
                            ),
                          ),

                          // Glassmorphism Progress Metric Indicator Track
                          Positioned(
                            left: 49 * scale, top: 415 * scale,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(25 * scale),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Container(
                                  width: maxProgressWidth * scale, height: 14 * scale,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.4), 
                                    borderRadius: BorderRadius.circular(25 * scale),
                                    border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.0)
                                  ),
                                  child: Stack(
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        width: calculatedProgressWidth * scale, height: 14 * scale,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF7DC579), 
                                          borderRadius: BorderRadius.circular(25 * scale),
                                          boxShadow: [BoxShadow(color: const Color(0xFF7DC579).withOpacity(0.4), blurRadius: 4)]
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          Positioned(
                            left: 36 * scale, top: 455 * scale,
                            child: TextButton.icon(
                              onPressed: _goToPrevious,
                              icon: Icon(Icons.arrow_back, color: Colors.black87, size: 18 * scale),
                              label: Text('Previous', style: TextStyle(color: Colors.black87, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          Positioned(
                            right: 36 * scale, top: 455 * scale,
                            child: TextButton(
                              onPressed: _goToNext,
                              child: Row(
                                children: [
                                  Text('Next', style: TextStyle(color: Colors.black87, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                                  SizedBox(width: 8 * scale),
                                  Icon(Icons.arrow_forward, color: Colors.black87, size: 18 * scale),
                                ],
                              ),
                            ),
                          ),

                          Positioned(
                            left: 47 * scale, top: 530 * scale,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(25 * scale),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFFB800).withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  )
                                ],
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFB800),
                                  foregroundColor: Colors.white,
                                  minimumSize: Size(299 * scale, 50 * scale),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)),
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  String letterToPractice = currentSign.label[0]; 
                                  Navigator.push(
                                    context, 
                                    MaterialPageRoute(
                                      builder: (context) => TutorialPractice(
                                        targetLetter: letterToPractice,
                                      ),
                                    ),
                                  );
                                },
                                child: Text('Practice', style: TextStyle(fontSize: 22 * scale, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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