import 'package:flutter/material.dart';
// --- NEW IMPORTS FOR XP ---
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

  // --- STREAM FOR LIVE XP ---
  Stream<DocumentSnapshot>? _getUserDocStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final currentSign = _alphabetList[_currentIndex];
    
    const double baseWidth = 393;
    const double baseHeight = 793;
    const double maxProgressWidth = 295.0;
    
    double progressPercentage = (_currentIndex + 1) / _alphabetList.length;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double scale = constraints.maxWidth / baseWidth;
            final double calculatedProgressWidth = maxProgressWidth * progressPercentage;

            return Container(
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
                      // --- Yellow Top Decorative Banner ---
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Container(
                          width: 393 * scale,
                          height: 50 * scale,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFB800),
                          ),
                        ),
                      ),

                      // --- XP DISPLAY TAG ---
                      Positioned(
                        right: 70 * scale,
                        top: 10 * scale,
                        child: StreamBuilder<DocumentSnapshot>(
                          stream: _getUserDocStream(),
                          builder: (context, snapshot) {
                            int totalXp = 0;
                            if (snapshot.hasData && snapshot.data!.exists) {
                              final data = snapshot.data!.data() as Map<String, dynamic>;
                              // FETCH ALPHABET XP SPECIFICALLY
                              totalXp = data['alphabetXp'] ?? 0; 
                            }
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(16 * scale),
                                border: Border.all(color: const Color(0xFFBA8E23), width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.bolt, color: const Color(0xFFBA8E23), size: 16 * scale),
                                  SizedBox(width: 4 * scale),
                                  Text(
                                    "$totalXp XP",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14 * scale,
                                      color: const Color(0xFFBA8E23)
                                    ),
                                  )
                                ],
                              ),
                            );
                          }
                        )
                      ),

                      // --- Consistent Avatar Widget ---
                      Positioned(
                        left: 346.46 * scale,
                        top: 0,
                        child: SizedBox(
                          width: 45.39 * scale,
                          height: 50.11 * scale,
                          child: Image.asset(
                            "assets/pictures/image 66.png",
                            fit: BoxFit.fill,
                            errorBuilder: (context, error, stackTrace) => Container(
                              margin: EdgeInsets.all(4 * scale),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.3),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.person,
                                size: 22 * scale,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // --- Orange Subtitle Base Accent Bar ---
                      Positioned(
                        left: 0,
                        top: 50 * scale,
                        child: Container(
                          width: 393 * scale,
                          height: 50 * scale,
                          decoration: const BoxDecoration(
                            color: Color(0xCCF39C12),
                          ),
                        ),
                      ),

                      // --- Tutorial Header Text Label ---
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 61 * scale,
                        child: Center(
                          child: Text(
                            'Tutorial',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 18 * scale,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),

                      // --- Dynamic Back Navigation Button ---
                      Positioned(
                        left: 16 * scale,
                        top: 51 * scale,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 46 * scale,
                            height: 46 * scale,
                            decoration: BoxDecoration(
                              color: const Color(0x33FFF8E7),
                              borderRadius: BorderRadius.circular(14 * scale),
                            ),
                            child: Icon(
                              Icons.arrow_back,
                              color: Colors.black,
                              size: 20 * scale,
                            ),
                          ),
                        ),
                      ),

                      // --- Character Display Value Label Banner ---
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 139 * scale,
                        child: Center(
                          child: Text(
                            currentSign.label,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 52 * scale,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.5,
                            ),
                          ),
                        ),
                      ),

                      // --- Sign Image Workspace Display Window Canvas ---
                      Positioned(
                        left: 47 * scale,
                        top: 225 * scale,
                        child: Container(
                          width: 299 * scale,
                          height: 276 * scale,
                          decoration: ShapeDecoration(
                            image: DecorationImage(
                              image: AssetImage(currentSign.imagePath),
                              fit: BoxFit.cover,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16 * scale),
                            ),
                            shadows: const [
                              BoxShadow(
                                color: Color(0x0C132C4A),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              )
                            ],
                          ),
                        ),
                      ),

                      // --- Linear Dynamic Progress Step Tracker Indicator Bar ---
                      Positioned(
                        left: 49 * scale,
                        top: 531 * scale,
                        child: SizedBox(
                          width: maxProgressWidth * scale,
                          height: 14 * scale,
                          child: Stack(
                            children: [
                              Container(
                                width: maxProgressWidth * scale,
                                height: 14 * scale,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F1FA),
                                  borderRadius: BorderRadius.circular(25 * scale),
                                ),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                width: calculatedProgressWidth * scale,
                                height: 14 * scale,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7DC579),
                                  borderRadius: BorderRadius.circular(25 * scale),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // --- Controller Component Navigation: Previous ---
                      Positioned(
                        left: 36 * scale,
                        top: 565 * scale,
                        child: TextButton.icon(
                          onPressed: _goToPrevious,
                          icon: Icon(Icons.arrow_back, color: Colors.black, size: 18 * scale),
                          label: Text(
                            'Previous',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      // --- Controller Component Navigation: Next ---
                      Positioned(
                        right: 36 * scale,
                        top: 565 * scale,
                        child: TextButton(
                          onPressed: _goToNext,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Next',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 8 * scale),
                              Icon(
                                Icons.arrow_forward,
                                color: Colors.black,
                                size: 18 * scale,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // --- Interface Practice Dynamic Routing Action Button ---
                      Positioned(
                        left: 47 * scale,
                        top: 640 * scale,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFB800),
                            foregroundColor: Colors.white,
                            minimumSize: Size(299 * scale, 50 * scale),
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25 * scale),
                            ),
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
                          child: Text(
                            'Practice',
                            style: TextStyle(
                              fontSize: 22 * scale,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Inter',
                              letterSpacing: -0.5,
                            ),
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
    );
  }
}