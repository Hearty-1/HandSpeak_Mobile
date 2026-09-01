import 'dart:convert'; // Required to decode Base64 images[cite: 15]
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'numbers_tutorial_practice.dart';

class TutorialSign {
  final String label;
  final String gestureKey;
  final String imageUrl;
  const TutorialSign({required this.label, required this.gestureKey, required this.imageUrl});
}

class NumbersTutorialDetail extends StatefulWidget {
  final int initialIndex; 
  final List<Map<String, dynamic>> dynamicLessons; // Accepts dynamic data from Firestore[cite: 15]
  
  const NumbersTutorialDetail({
    super.key, 
    this.initialIndex = 0,
    required this.dynamicLessons,
  });

  @override
  _NumbersTutorialDetailState createState() => _NumbersTutorialDetailState();
}

class _NumbersTutorialDetailState extends State<NumbersTutorialDetail> {
  late List<TutorialSign> _numbersList;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    
    // Map the incoming dynamic lessons into our strongly-typed list[cite: 15]
    _numbersList = widget.dynamicLessons.map((lesson) => TutorialSign(
      label: lesson['title'] ?? '',
      gestureKey: lesson['gestureKey'] ?? '',
      imageUrl: lesson['imageUrl'] ?? '', 
    )).toList();
  }

  void _goToNext() {
    if (_currentIndex < _numbersList.length - 1) {
      // Unlocked freely: Navigate immediately without checking DB progression[cite: 15]
      setState(() => _currentIndex++);
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  Stream<DocumentSnapshot>? _getUserDocStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
  }

  // Helper method to handle Base64 images, Network images, or local Assets[cite: 15]
  ImageProvider _getImageProvider(String url) {
    if (url.startsWith('data:image')) {
      final base64String = url.split(',').last; // Extract the base64 part[cite: 15]
      return MemoryImage(base64Decode(base64String));
    } else if (url.startsWith('http')) {
      return NetworkImage(url);
    } else if (url.isNotEmpty) {
      return AssetImage(url);
    } else {
      return const AssetImage('assets/pictures/1.png'); 
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_numbersList.isEmpty) {
      return const Scaffold(body: Center(child: Text("No tutorials loaded.")));
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentSign = _numbersList[_currentIndex];
    
    const double baseWidth = 393;
    const double baseHeight = 693; 
    const double maxProgressWidth = 295.0;
    
    double progressPercentage = (_currentIndex + 1) / _numbersList.length;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: theme.scaffoldBackgroundColor,
      
      // --- GLASSMORPHISM APPBAR ---[cite: 15]
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
          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800),
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.cardColor.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.primaryColor.withOpacity(0.5), width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt, color: theme.primaryColor, size: 16),
                            const SizedBox(width: 4),
                            Text("$totalXp XP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.primaryColor))
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
          // Ambient backgrounds[cite: 15]
          Positioned(
            top: -50, left: -50,
            child: Container(width: 250, height: 250, decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primaryColor.withOpacity(0.2))),
          ),
          Positioned(
            bottom: 150, right: -100,
            child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.secondary.withOpacity(0.15))),
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
                                style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 52 * scale, fontFamily: 'Inter', fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),

                          // Media Card Showcase Envelope[cite: 15]
                          Positioned(
                            left: 47 * scale, top: 105 * scale,
                            child: Container(
                              width: 299 * scale, height: 276 * scale,
                              decoration: ShapeDecoration(
                                image: DecorationImage(
                                  image: _getImageProvider(currentSign.imageUrl), // Decodes base64[cite: 15]
                                  fit: BoxFit.cover
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16 * scale)),
                                shadows: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 15, offset: const Offset(0, 8))],
                              ),
                            ),
                          ),

                          // Glassmorphism Progress Indicator[cite: 15]
                          Positioned(
                            left: 49 * scale, top: 415 * scale,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(25 * scale),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Container(
                                  width: maxProgressWidth * scale, height: 14 * scale,
                                  decoration: BoxDecoration(
                                    color: theme.cardColor.withOpacity(0.4), 
                                    borderRadius: BorderRadius.circular(25 * scale),
                                    border: Border.all(color: theme.colorScheme.surface.withOpacity(0.5), width: 1.0)
                                  ),
                                  child: Stack(
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        width: calculatedProgressWidth * scale, height: 14 * scale,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.secondary, 
                                          borderRadius: BorderRadius.circular(25 * scale),
                                          boxShadow: [BoxShadow(color: theme.colorScheme.secondary.withOpacity(0.4), blurRadius: 4)]
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
                              icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface, size: 18 * scale),
                              label: Text('Previous', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          Positioned(
                            right: 36 * scale, top: 455 * scale,
                            child: TextButton(
                              onPressed: _goToNext,
                              child: Row(
                                children: [
                                  Text('Next', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                                  SizedBox(width: 8 * scale),
                                  Icon(Icons.arrow_forward, color: theme.colorScheme.onSurface, size: 18 * scale),
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
                                  // Pass the gestureKey to the practice screen[cite: 15]
                                  Navigator.push(
                                    context, 
                                    MaterialPageRoute(
                                      builder: (context) => NumbersTutorialPractice(
                                        targetNumber: currentSign.gestureKey,
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