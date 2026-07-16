import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --- CHANGED THIS IMPORT SO IT LINKS TO THE RIGHT FILE ---
import 'numbers_tutorial_practice.dart'; 

class NumberSign {
  final String label;
  final String imagePath;
  const NumberSign({required this.label, required this.imagePath});
}

class NumbersTutorialDetail extends StatefulWidget {
  final int initialIndex;
  const NumbersTutorialDetail({super.key, this.initialIndex = 0});

  @override
  _NumbersTutorialDetailState createState() => _NumbersTutorialDetailState();
}

class _NumbersTutorialDetailState extends State<NumbersTutorialDetail> {
  final List<NumberSign> _numbersList = const [
    NumberSign(label: '1', imagePath: 'assets/pictures/1.png'),
    NumberSign(label: '2', imagePath: 'assets/pictures/2.png'),
    NumberSign(label: '3', imagePath: 'assets/pictures/3.png'),
    NumberSign(label: '4', imagePath: 'assets/pictures/4.png'),
    NumberSign(label: '5', imagePath: 'assets/pictures/5.png'),
    NumberSign(label: '6', imagePath: 'assets/pictures/6.png'),
    NumberSign(label: '7', imagePath: 'assets/pictures/7.png'),
    NumberSign(label: '8', imagePath: 'assets/pictures/8.png'),
    NumberSign(label: '9', imagePath: 'assets/pictures/9.png'),
    NumberSign(label: '10', imagePath: 'assets/pictures/10.png'),
  ];

  int _currentIndex = 0;
  final int _currentStars = 3;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _goToNext() {
    if (_currentIndex < _numbersList.length - 1) {
      if (_currentStars >= 3) {
        setState(() => _currentIndex++);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Earn 3 stars in Practice mode to unlock the next number!'),
          backgroundColor: Color(0xCCF39C12),
        ));
      }
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) setState(() => _currentIndex--);
  }

  Stream<DocumentSnapshot>? _getUserDocStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final currentSign = _numbersList[_currentIndex];
    
    const double baseWidth = 393;
    const double baseHeight = 793;
    const double maxProgressWidth = 295.0;
    
    double progressPercentage = (_currentIndex + 1) / _numbersList.length;

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
                      Positioned(
                        left: 0, top: 0,
                        child: Container(
                          width: 393 * scale, height: 50 * scale,
                          decoration: const BoxDecoration(color: Color(0xFFFFB800)),
                        ),
                      ),

                      Positioned(
                        right: 70 * scale, top: 10 * scale,
                        child: StreamBuilder<DocumentSnapshot>(
                          stream: _getUserDocStream(),
                          builder: (context, snapshot) {
                            int totalXp = 0;
                            if (snapshot.hasData && snapshot.data!.exists) {
                              final data = snapshot.data!.data() as Map<String, dynamic>;
                              totalXp = data['numbersXp'] ?? 0; 
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
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14 * scale, color: const Color(0xFFBA8E23)),
                                  )
                                ],
                              ),
                            );
                          }
                        )
                      ),

                      Positioned(
                        left: 0, top: 50 * scale,
                        child: Container(
                          width: 393 * scale, height: 50 * scale,
                          decoration: const BoxDecoration(color: Color(0xCCF39C12)),
                        ),
                      ),

                      Positioned(
                        left: 0, right: 0, top: 61 * scale,
                        child: Center(
                          child: Text(
                            'Tutorial',
                            style: TextStyle(color: Colors.black, fontSize: 18 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),

                      Positioned(
                        left: 16 * scale, top: 51 * scale,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 46 * scale, height: 46 * scale,
                            decoration: BoxDecoration(color: const Color(0x33FFF8E7), borderRadius: BorderRadius.circular(14 * scale)),
                            child: Icon(Icons.arrow_back, color: Colors.black, size: 20 * scale),
                          ),
                        ),
                      ),

                      Positioned(
                        left: 0, right: 0, top: 139 * scale,
                        child: Center(
                          child: Text(
                            currentSign.label,
                            style: TextStyle(color: Colors.black, fontSize: 52 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.5),
                          ),
                        ),
                      ),

                      Positioned(
                        left: 47 * scale, top: 225 * scale,
                        child: Container(
                          width: 299 * scale, height: 276 * scale,
                          decoration: ShapeDecoration(
                            image: DecorationImage(image: AssetImage(currentSign.imagePath), fit: BoxFit.cover),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16 * scale)),
                            shadows: const [BoxShadow(color: Color(0x0C132C4A), blurRadius: 12, offset: Offset(0, 4))],
                          ),
                        ),
                      ),

                      Positioned(
                        left: 49 * scale, top: 531 * scale,
                        child: SizedBox(
                          width: maxProgressWidth * scale, height: 14 * scale,
                          child: Stack(
                            children: [
                              Container(
                                width: maxProgressWidth * scale, height: 14 * scale,
                                decoration: BoxDecoration(color: const Color(0xFFF1F1FA), borderRadius: BorderRadius.circular(25 * scale)),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                width: calculatedProgressWidth * scale, height: 14 * scale,
                                decoration: BoxDecoration(color: const Color(0xFF7DC579), borderRadius: BorderRadius.circular(25 * scale)),
                              ),
                            ],
                          ),
                        ),
                      ),

                      Positioned(
                        left: 36 * scale, top: 565 * scale,
                        child: TextButton.icon(
                          onPressed: _goToPrevious,
                          icon: Icon(Icons.arrow_back, color: Colors.black, size: 18 * scale),
                          label: Text('Previous', style: TextStyle(color: Colors.black, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      Positioned(
                        right: 36 * scale, top: 565 * scale,
                        child: TextButton(
                          onPressed: _goToNext,
                          child: Row(
                            children: [
                              Text('Next', style: TextStyle(color: Colors.black, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                              SizedBox(width: 8 * scale),
                              Icon(Icons.arrow_forward, color: Colors.black, size: 18 * scale),
                            ],
                          ),
                        ),
                      ),

                      Positioned(
                        left: 47 * scale, top: 640 * scale,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFB800),
                            foregroundColor: Colors.white,
                            minimumSize: Size(299 * scale, 50 * scale),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)),
                          ),
                          onPressed: () {
                            // --- CHANGED THIS NAVIGATOR PUSH TO THE NEW CLASS ---
                            Navigator.push(
                              context, 
                              MaterialPageRoute(
                                builder: (context) => NumbersTutorialPractice(
                                  targetNumber: _numbersList[_currentIndex].label,
                                ),
                              ),
                            );
                          },
                          child: Text('Practice', style: TextStyle(fontSize: 22 * scale, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
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