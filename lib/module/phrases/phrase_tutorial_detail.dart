import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'phrase_tutorial_practice.dart'; 

class PhraseSign {
  final String label;
  final String imagePath;
  const PhraseSign({required this.label, required this.imagePath});
}

class PhraseTutorialDetail extends StatefulWidget {
  final int initialIndex; 
  
  const PhraseTutorialDetail({super.key, this.initialIndex = 0});

  @override
  _PhraseTutorialDetailState createState() => _PhraseTutorialDetailState();
}

class _PhraseTutorialDetailState extends State<PhraseTutorialDetail> {
  final List<PhraseSign> _phraseList = const [
    PhraseSign(label: 'Hello', imagePath: 'assets/pictures/hello.jpg'),
    PhraseSign(label: 'Thank You', imagePath: 'assets/pictures/thank_you.jpg'),
    PhraseSign(label: 'Sorry', imagePath: 'assets/pictures/sorry.jpg'),
    PhraseSign(label: 'Please', imagePath: 'assets/pictures/please.jpg'),
    PhraseSign(label: 'Yes', imagePath: 'assets/pictures/yes.jpg'),
    PhraseSign(label: 'No', imagePath: 'assets/pictures/no.jpg'),
  ];

  int _currentIndex = 0;
  final int _currentStars = 3; 

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _goToNext() {
    if (_currentIndex < _phraseList.length - 1) {
      if (_currentStars >= 3) {
        setState(() {
          _currentIndex++;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Earn 3 stars in Practice mode to unlock the next phrase!'),
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
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    final currentSign = _phraseList[_currentIndex];
    
    const double baseWidth = 393;
    const double baseHeight = 693; 
    const double maxProgressWidth = 295.0;
    
    double progressPercentage = (_currentIndex + 1) / _phraseList.length;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: theme.scaffoldBackgroundColor,
      
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.6), 
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withOpacity(0.1),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'Tutorial',
          style: TextStyle(
            color: textColor, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96
          ),
        ),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: _getUserDocStream(),
            builder: (context, snapshot) {
              int totalXp = 0;
              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                totalXp = data['phraseXp'] ?? 0; 
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
                          color: theme.cardColor.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.primaryColor.withOpacity(0.5), width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt, color: theme.primaryColor, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              "$totalXp XP",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.primaryColor),
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
          Positioned(
            top: -50, left: -50,
            child: Container(
              width: 250, height: 250, 
              decoration: BoxDecoration(
                shape: BoxShape.circle, 
                color: theme.primaryColor.withOpacity(0.2),
              ),
            ),
          ),
          Positioned(
            bottom: 150, right: -100,
            child: Container(
              width: 300, height: 300, 
              decoration: BoxDecoration(
                shape: BoxShape.circle, 
                color: const Color(0xFF4CAF50).withOpacity(0.15),
              ),
            ),
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
                                  color: textColor, fontSize: 42 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -1.0
                                ),
                              ),
                            ),
                          ),

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
                                shadows: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.06), 
                                    blurRadius: 15, 
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          Positioned(
                            left: 49 * scale, top: 415 * scale,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(25 * scale),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Container(
                                  width: maxProgressWidth * scale, height: 14 * scale,
                                  decoration: BoxDecoration(
                                    color: theme.cardColor.withOpacity(0.5), 
                                    borderRadius: BorderRadius.circular(25 * scale),
                                    border: Border.all(color: theme.dividerColor.withOpacity(0.2), width: 1.0)
                                  ),
                                  child: Stack(
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        width: calculatedProgressWidth * scale, height: 14 * scale,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF4CAF50), 
                                          borderRadius: BorderRadius.circular(25 * scale),
                                          boxShadow: [BoxShadow(color: const Color(0xFF4CAF50).withOpacity(0.4), blurRadius: 4)]
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
                              icon: Icon(Icons.arrow_back, color: textColor, size: 18 * scale),
                              label: Text('Previous', style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          Positioned(
                            right: 36 * scale, top: 455 * scale,
                            child: TextButton(
                              onPressed: _goToNext,
                              child: Row(
                                children: [
                                  Text('Next', style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                                  SizedBox(width: 8 * scale),
                                  Icon(Icons.arrow_forward, color: textColor, size: 18 * scale),
                                ],
                              ),
                            ),
                          ),

                          Positioned(
                            left: 47 * scale, top: 530 * scale,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(25 * scale),
                                boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 5))],
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.primaryColor,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                  minimumSize: Size(299 * scale, 50 * scale),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25 * scale)),
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context, 
                                    MaterialPageRoute(
                                      builder: (context) => PhraseTutorialPractice(
                                        targetPhrase: currentSign.label,
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