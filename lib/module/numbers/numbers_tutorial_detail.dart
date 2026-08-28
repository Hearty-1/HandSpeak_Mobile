import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Earn 3 stars in Practice mode to unlock the next number!'),
          backgroundColor: Theme.of(context).colorScheme.error,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    const double baseWidth = 393;
    const double baseHeight = 693; 
    const double maxProgressWidth = 295.0;

    // Dynamically adjust status bar icon brightness according to active theme mode
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    final currentSign = _numbersList[_currentIndex];
    double progressPercentage = (_currentIndex + 1) / _numbersList.length;

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.cardColor.withOpacity(0.4),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text(
          'Tutorial',
          style: TextStyle(
            color: theme.colorScheme.onSurface, 
            fontSize: 22, 
            fontFamily: 'Inter', 
            fontWeight: FontWeight.w800, 
            letterSpacing: -0.96,
          ),
        ),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: _getUserDocStream(),
            builder: (context, snapshot) {
              int totalXp = 0;
              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                totalXp = data['numbersXp'] ?? 0; 
              }
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.cardColor.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.primaryColor, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt, color: theme.primaryColor, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          "$totalXp XP",
                          style: TextStyle(
                            fontWeight: FontWeight.bold, 
                            fontSize: 14, 
                            color: theme.primaryColor,
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              );
            },
          )
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double scale = constraints.maxWidth / baseWidth;
          final double calculatedProgressWidth = maxProgressWidth * progressPercentage;

          return Stack(
            children: [
              // Ambient background decorative glow circles matching AlphabetInterface
              Positioned(
                top: 180 * scale, 
                left: -50 * scale,
                child: Container(
                  width: 200 * scale, 
                  height: 200 * scale, 
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, 
                    color: theme.primaryColor.withOpacity(0.3),
                  ),
                ),
              ),
              Positioned(
                bottom: 100 * scale, 
                right: -60 * scale,
                child: Container(
                  width: 250 * scale, 
                  height: 250 * scale, 
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, 
                    color: theme.colorScheme.secondary.withOpacity(0.2),
                  ),
                ),
              ),

              // UI Control Layer
              SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    height: baseHeight * scale,
                    width: constraints.maxWidth,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0, 
                          right: 0, 
                          top: 39 * scale,
                          child: Center(
                            child: Text(
                              currentSign.label,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface, 
                                fontSize: 52 * scale, 
                                fontFamily: 'Inter', 
                                fontWeight: FontWeight.w800, 
                                letterSpacing: -1.5,
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          left: 47 * scale, 
                          top: 125 * scale,
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
                              shadows: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08), 
                                  blurRadius: 12, 
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                        ),

                        Positioned(
                          left: 49 * scale, 
                          top: 431 * scale,
                          child: SizedBox(
                            width: maxProgressWidth * scale, 
                            height: 14 * scale,
                            child: Stack(
                              children: [
                                Container(
                                  width: maxProgressWidth * scale, 
                                  height: 14 * scale,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onSurface.withOpacity(0.1), 
                                    borderRadius: BorderRadius.circular(25 * scale),
                                  ),
                                ),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  width: calculatedProgressWidth * scale, 
                                  height: 14 * scale,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondary, 
                                    borderRadius: BorderRadius.circular(25 * scale),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        Positioned(
                          left: 36 * scale, 
                          top: 465 * scale,
                          child: TextButton.icon(
                            onPressed: _goToPrevious,
                            icon: Icon(
                              Icons.arrow_back, 
                              color: theme.colorScheme.onSurface, 
                              size: 18 * scale,
                            ),
                            label: Text(
                              'Previous', 
                              style: TextStyle(
                                color: theme.colorScheme.onSurface, 
                                fontSize: 16 * scale, 
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 36 * scale, 
                          top: 465 * scale,
                          child: TextButton(
                            onPressed: _goToNext,
                            child: Row(
                              children: [
                                Text(
                                  'Next', 
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface, 
                                    fontSize: 16 * scale, 
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 8 * scale),
                                Icon(
                                  Icons.arrow_forward, 
                                  color: theme.colorScheme.onSurface, 
                                  size: 18 * scale,
                                ),
                              ],
                            ),
                          ),
                        ),

                        Positioned(
                          left: 47 * scale, 
                          top: 540 * scale,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(25 * scale),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.primaryColor.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primaryColor,
                                foregroundColor: theme.colorScheme.onPrimary,
                                minimumSize: Size(299 * scale, 50 * scale),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25 * scale),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context, 
                                  MaterialPageRoute(
                                    builder: (context) => NumbersTutorialPractice(
                                      targetNumber: _numbersList[_currentIndex].label,
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
                                ),
                              ),
                            ),
                          ),
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
  }
}