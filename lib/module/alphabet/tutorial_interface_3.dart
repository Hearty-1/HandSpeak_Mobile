import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'tutorial_practice.dart';

import '/services/performance_monitor.dart';

class TutorialSign {
  final String label;
  final String gestureKey;
  final String imageUrl;
  const TutorialSign({required this.label, required this.gestureKey, required this.imageUrl});
}

class TutorialInterface3 extends StatefulWidget {
  final int initialIndex;
  final List<Map<String, dynamic>> dynamicLessons;

  const TutorialInterface3({
    super.key,
    this.initialIndex = 0,
    required this.dynamicLessons,
  });

  @override
  State<TutorialInterface3> createState() => _TutorialInterface3State();
}

class _TutorialInterface3State extends State<TutorialInterface3> {
  late List<TutorialSign> _alphabetList;
  int _currentIndex = 0;
  final int _currentStars = 3;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    _alphabetList = widget.dynamicLessons.map((lesson) => TutorialSign(
      label: lesson['title'] ?? '',
      gestureKey: lesson['gestureKey'] ?? '',
      imageUrl: lesson['imageUrl'] ?? lesson['imagePath'] ?? '',
    )).toList();
  }

  void _goToNext() {
    if (_currentIndex < _alphabetList.length - 1) {
      if (_currentStars >= 3) {
        setState(() {
          _currentIndex++;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Earn 3 stars in Practice mode to unlock the next letter!'),
            backgroundColor: Theme.of(context).primaryColor,
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

  Future<String> _resolveImageUrl(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';

    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('data:image') ||
        trimmed.startsWith('assets/')) {
      return trimmed;
    }

    try {
      final ref = trimmed.startsWith('gs://')
          ? FirebaseStorage.instance.refFromURL(trimmed)
          : FirebaseStorage.instance.ref(trimmed);
      return await ref.getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  Widget _buildDynamicImage(String path, double width, double height) {
    return FutureBuilder<String>(
      future: _resolveImageUrl(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: width,
            height: height,
            color: Colors.black12,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final resolvedUrl = snapshot.data ?? '';

        if (resolvedUrl.startsWith('data:image')) {
          try {
            final base64String = resolvedUrl.split(',').last;
            return Image.memory(base64Decode(base64String), width: width, height: height, fit: BoxFit.cover);
          } catch (_) {}
        } else if (resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://')) {
          return Image.network(
            resolvedUrl,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (c, o, s) => _buildFallback(width, height),
          );
        } else if (resolvedUrl.startsWith('assets/')) {
          return Image.asset(
            resolvedUrl,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (c, o, s) => _buildFallback(width, height),
          );
        }

        return _buildFallback(width, height);
      },
    );
  }

  Widget _buildFallback(double width, double height) {
    return Image.asset(
      'assets/pictures/A.jpg',
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (c, o, s) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade300,
        child: const Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_alphabetList.isEmpty) {
      return const Scaffold(
        body: Center(child: Text("No tutorials loaded.")),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentSign = _alphabetList[_currentIndex];

    const double baseWidth = 393;
    const double baseHeight = 693;
    const double maxProgressWidth = 295.0;

    double progressPercentage = (_currentIndex + 1) / _alphabetList.length;

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
        backgroundColor: theme.cardColor.withOpacity(0.4),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        flexibleSpace: ClipRRect(
          child: SmartBlur(
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
                totalXp = data['alphabetXp'] ?? data['xp'] ?? 0;
              }
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SmartBlur(
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
            },
          )
        ],
      ),
      body: Stack(
        children: [
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.primaryColor.withOpacity(0.2),
              ),
            ),
          ),
          Positioned(
            bottom: 150,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary.withOpacity(0.15),
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
                            left: 0,
                            right: 0,
                            top: 20 * scale,
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
                            top: 105 * scale,
                            child: Container(
                              width: 299 * scale,
                              height: 276 * scale,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16 * scale),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 15,
                                    offset: const Offset(0, 8),
                                  )
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16 * scale),
                                child: _buildDynamicImage(currentSign.imageUrl, 299 * scale, 276 * scale),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 49 * scale,
                            top: 415 * scale,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(25 * scale),
                              child: SmartBlur(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Container(
                                  width: maxProgressWidth * scale,
                                  height: 14 * scale,
                                  decoration: BoxDecoration(
                                    color: theme.cardColor.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(25 * scale),
                                    border: Border.all(color: theme.colorScheme.surface.withOpacity(0.5), width: 1.0),
                                  ),
                                  child: Stack(
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        width: calculatedProgressWidth * scale,
                                        height: 14 * scale,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.secondary,
                                          borderRadius: BorderRadius.circular(25 * scale),
                                          boxShadow: [
                                            BoxShadow(
                                              color: theme.colorScheme.secondary.withOpacity(0.4),
                                              blurRadius: 4,
                                            )
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 36 * scale,
                            top: 455 * scale,
                            child: TextButton.icon(
                              onPressed: _goToPrevious,
                              icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface, size: 18 * scale),
                              label: Text('Previous', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          Positioned(
                            right: 36 * scale,
                            top: 455 * scale,
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
                            left: 47 * scale,
                            top: 530 * scale,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(25 * scale),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.primaryColor.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  )
                                ],
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
                                  String letterToPractice = currentSign.gestureKey;
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