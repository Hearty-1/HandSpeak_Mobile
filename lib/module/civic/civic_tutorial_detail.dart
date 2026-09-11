import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import 'civic_tutorial_practice.dart'; 
import 'civic_tutorial_interface.dart'; 

class CivicTutorialDetail extends StatefulWidget {
  final List<CivicLesson> civicList;
  final int initialIndex; 
  
  const CivicTutorialDetail({
    super.key, 
    required this.civicList, 
    this.initialIndex = 0,
  });

  @override
  State<CivicTutorialDetail> createState() => _CivicTutorialDetailState();
}

class _CivicTutorialDetailState extends State<CivicTutorialDetail> {
  int _currentIndex = 0;
  final int _currentStars = 3; 

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _goToNext() {
    if (_currentIndex < widget.civicList.length - 1) {
      if (_currentStars >= 3) {
        setState(() {
          _currentIndex++;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Earn 3 stars in Practice mode to unlock the next video lesson!'),
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
    if (widget.civicList.isEmpty) {
      return const Scaffold(body: Center(child: Text("No dynamic video lesson data available.")));
    }

    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    final currentLesson = widget.civicList[_currentIndex];
    
    const double baseWidth = 393;
    const double baseHeight = 693; 
    const double maxProgressWidth = 295.0;
    
    double progressPercentage = (_currentIndex + 1) / widget.civicList.length;

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
          'Video Tutorial',
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
                totalXp = data['civicXp'] ?? 0; 
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
                            left: 20 * scale, right: 20 * scale, top: 15 * scale,
                            child: Center(
                              child: Text(
                                currentLesson.title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: textColor, 
                                  fontSize: 26 * scale, 
                                  fontFamily: 'Inter', 
                                  fontWeight: FontWeight.w800, 
                                  letterSpacing: -0.5
                                ),
                              ),
                            ),
                          ),

                          Positioned(
                            left: 47 * scale, top: 75 * scale,
                            child: Container(
                              width: 299 * scale, height: 260 * scale,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(16 * scale),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.06), 
                                    blurRadius: 15, 
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16 * scale),
                                child: CustomVideoPlayer(
                                  key: ValueKey(currentLesson.videoUrl),
                                  videoUrl: currentLesson.videoUrl,
                                ),
                              ),
                            ),
                          ),

                          if (currentLesson.description.isNotEmpty)
                            Positioned(
                              left: 47 * scale, top: 350 * scale,
                              child: Container(
                                width: 299 * scale,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.cardColor.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  currentLesson.description,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13 * scale,
                                    color: textColor.withOpacity(0.8),
                                  ),
                                ),
                              ),
                            ),

                          Positioned(
                            left: 49 * scale, top: 430 * scale,
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
                            left: 36 * scale, top: 460 * scale,
                            child: TextButton.icon(
                              onPressed: _goToPrevious,
                              icon: Icon(Icons.arrow_back, color: textColor, size: 18 * scale),
                              label: Text('Previous', style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          Positioned(
                            right: 36 * scale, top: 460 * scale,
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
                                      builder: (context) => CivicTutorialPractice(
                                        category: currentLesson.title,
                                        questions: currentLesson.questions,
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

class CustomVideoPlayer extends StatefulWidget {
  final String videoUrl;
  const CustomVideoPlayer({super.key, required this.videoUrl});

  @override
  State<CustomVideoPlayer> createState() => _CustomVideoPlayerState();
}

class _CustomVideoPlayerState extends State<CustomVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    if (widget.videoUrl.isEmpty) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    try {
      if (widget.videoUrl.startsWith('http://') || widget.videoUrl.startsWith('https://')) {
        _controller = VideoPlayerController.network(widget.videoUrl);
      } else {
        _controller = VideoPlayerController.asset(widget.videoUrl);
      }

      _controller!.initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      }).catchError((error) {
        debugPrint("Video initialization error: $error");
        if (mounted) {
          setState(() {
            _hasError = true;
          });
        }
      });
    } catch (e) {
      debugPrint("Video player setup error: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie_rounded, color: Colors.white54, size: 48),
            SizedBox(height: 8),
            Text("Video unavailable or invalid URL", style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor));
    }

    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(_controller!),
          GestureDetector(
            onTap: () {
              setState(() {
                _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
              });
            },
            child: AnimatedOpacity(
              opacity: _controller!.value.isPlaying ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                color: Colors.black38,
                child: Center(
                  child: Icon(
                    _controller!.value.isPlaying ? Icons.pause_circle : Icons.play_circle_fill,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          VideoProgressIndicator(_controller!, allowScrubbing: true),
        ],
      ),
    );
  }
}