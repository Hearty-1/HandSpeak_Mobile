import '/widgets/button_3d.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'civic_tutorial_practice.dart';
import 'civic_tutorial_interface.dart';

import '/services/performance_monitor.dart';
import '/services/role_service.dart';

class CivicTutorialDetail extends StatefulWidget {
  final List<CivicLesson> civicList;
  final int initialIndex;

  const CivicTutorialDetail({super.key, required this.civicList, this.initialIndex = 0});

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
      SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,

      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor.withValues(alpha: 0.6),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        flexibleSpace: ClipRRect(
          child: SmartBlur(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1), width: 0.5)),
              ),
            ),
          ),
        ),
        title: Text(
          'Video Tutorial',
          style: TextStyle(color: textColor, fontSize: 22, fontFamily: 'Inter', fontWeight: FontWeight.w800, letterSpacing: -0.96),
        ),
        actions: [
          // XP badge: students only (Faculty / Parent earn no XP).
          if (context.roles.can(AppFeature.progress))
            StreamBuilder<DocumentSnapshot>(
              stream: _getUserDocStream(),
              builder: (context, snapshot) {
                int totalXp = 0;
                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  totalXp = data['civicXp'] ?? data['xp'] ?? 0;
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
                            color: theme.cardColor.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: theme.primaryColor.withValues(alpha: 0.5), width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt, color: theme.primaryColor, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                "$totalXp XP",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.primaryColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
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
              decoration: BoxDecoration(shape: BoxShape.circle, color: theme.primaryColor.withValues(alpha: 0.2)),
            ),
          ),
          Positioned(
            bottom: 150,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF4CAF50).withValues(alpha: 0.15)),
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
                            left: 20 * scale,
                            right: 20 * scale,
                            top: 15 * scale,
                            child: Center(
                              child: Text(
                                currentLesson.title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 26 * scale,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ),

                          Positioned(
                            left: 47 * scale,
                            top: 75 * scale,
                            child: Container(
                              width: 299 * scale,
                              height: 299 * scale,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(16 * scale),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                                    blurRadius: 15,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16 * scale),
                                child: CustomVideoPlayer(key: ValueKey(currentLesson.videoUrl), videoUrl: currentLesson.videoUrl),
                              ),
                            ),
                          ),

                          if (currentLesson.description.isNotEmpty)
                            Positioned(
                              left: 47 * scale,
                              top: 350 * scale,
                              child: Container(
                                width: 299 * scale,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.cardColor.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  currentLesson.description,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13 * scale, color: textColor.withValues(alpha: 0.8)),
                                ),
                              ),
                            ),

                          Positioned(
                            left: 49 * scale,
                            top: 430 * scale,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(25 * scale),
                              child: SmartBlur(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Container(
                                  width: maxProgressWidth * scale,
                                  height: 14 * scale,
                                  decoration: BoxDecoration(
                                    color: theme.cardColor.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(25 * scale),
                                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2), width: 1.0),
                                  ),
                                  child: Stack(
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        width: calculatedProgressWidth * scale,
                                        height: 14 * scale,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF4CAF50),
                                          borderRadius: BorderRadius.circular(25 * scale),
                                          boxShadow: [BoxShadow(color: const Color(0xFF4CAF50).withValues(alpha: 0.4), blurRadius: 4)],
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
                            top: 460 * scale,
                            child: TextButton.icon(
                              onPressed: _goToPrevious,
                              icon: Icon(Icons.arrow_back, color: textColor, size: 18 * scale),
                              label: Text(
                                'Previous',
                                style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 36 * scale,
                            top: 460 * scale,
                            child: TextButton(
                              onPressed: _goToNext,
                              child: Row(
                                children: [
                                  Text(
                                    'Next',
                                    style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.bold),
                                  ),
                                  SizedBox(width: 8 * scale),
                                  Icon(Icons.arrow_forward, color: textColor, size: 18 * scale),
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
                                  BoxShadow(color: theme.primaryColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 5)),
                                ],
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.primaryColor,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                  minimumSize: Size(299 * scale, 50 * scale),
                                  shape: Button3DBorder(borderRadius: BorderRadius.circular(25 * scale)),
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CivicTutorialPractice(
                                        // A Lupang Hinirang line lesson has the line as its
                                        // title; the practice screen needs the category.
                                        category: currentLesson.category.isNotEmpty ? currentLesson.category : currentLesson.title,
                                        questions: currentLesson.questions,
                                      ),
                                    ),
                                  );
                                },
                                child: Text(
                                  'Practice',
                                  style: TextStyle(fontSize: 22 * scale, fontWeight: FontWeight.w800, fontFamily: 'Inter'),
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
  /// Playback speeds offered for the sign demos (slow motion helps with
  /// dynamic signs). The chosen speed is remembered across videos and launches.
  static const List<double> _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5];
  static const String _speedPrefKey = 'tutorial_video_speed';
  static double _speed = 1.0;
  static bool _speedLoaded = false;

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final rawUrl = widget.videoUrl.trim();
    if (rawUrl.isEmpty) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    try {
      String resolvedUrl = rawUrl;

      // Handle Firebase Storage paths or standard URLs
      if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://') && !rawUrl.startsWith('assets/')) {
        try {
          resolvedUrl = await FirebaseStorage.instance.ref(rawUrl).getDownloadURL();
        } catch (e) {
          debugPrint("Firebase Storage video resolution error: $e");
        }
      }

      if (resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://')) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(resolvedUrl));
      } else {
        _controller = VideoPlayerController.asset(resolvedUrl);
      }

      await _controller!.initialize();
      if (!_speedLoaded) {
        try {
          final saved = (await SharedPreferences.getInstance()).getDouble(_speedPrefKey);
          if (saved != null && _speeds.contains(saved)) _speed = saved;
        } catch (_) {}
        _speedLoaded = true;
      }
      await _controller!.setPlaybackSpeed(_speed);
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (error) {
      debugPrint("Video initialization error: $error");
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await _controller?.setPlaybackSpeed(speed);
    try {
      await (await SharedPreferences.getInstance()).setDouble(_speedPrefKey, speed);
    } catch (_) {}
  }

  static String _speedLabel(double s) => '${s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toString()}x';

  Widget _buildSpeedButton(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: _speed,
      onSelected: _setSpeed,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (context) => [
        for (final s in _speeds)
          PopupMenuItem<double>(
            value: s,
            height: 40,
            child: Row(
              children: [
                SizedBox(width: 22, child: s == _speed ? Icon(Icons.check_rounded, size: 18, color: Theme.of(context).primaryColor) : null),
                const SizedBox(width: 6),
                Text(s == 1.0 ? 'Normal' : _speedLabel(s), style: TextStyle(fontWeight: s == _speed ? FontWeight.w800 : FontWeight.w500)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.speed_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(
              _speedLabel(_speed),
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
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
            Text("Video unavailable or invalid path", style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor));
    }

    // In its box the video is cropped to a centred 1:1 square that fills the
    // box (no black bars); the full-screen button shows the whole video.
    // Without a bounded box: the video's own size.
    // Display shape from aspectRatio (rotation already applied; a portrait
    // phone clip can report its size unrotated).
    final ar = _controller!.value.aspectRatio;
    final videoSize = Size(ar > 0 && ar.isFinite ? ar * 1000 : 1000, 1000);
    return LayoutBuilder(
      builder: (context, box) {
        final bounded = box.hasBoundedWidth && box.hasBoundedHeight;
        final content = Stack(
          alignment: Alignment.bottomCenter,
          children: [
            if (bounded && videoSize.width > 0 && videoSize.height > 0)
              Positioned.fill(
                child: ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    // The centred 1:1 square of the video...
                    child: SizedBox.square(
                      dimension: 1000,
                      child: ClipRect(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(width: videoSize.width, height: videoSize.height, child: VideoPlayer(_controller!)),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
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
                    child: Icon(_controller!.value.isPlaying ? Icons.pause_circle : Icons.play_circle_fill, size: 64, color: Colors.white),
                  ),
                ),
              ),
            ),
            VideoProgressIndicator(_controller!, allowScrubbing: true),
            Positioned(top: 8, right: 8, child: _buildSpeedButton(context)),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                tooltip: 'Full screen',
                icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 28, shadows: [Shadow(blurRadius: 6)]),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => _FullScreenVideo(controller: _controller!),
                  ));
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        );
        return bounded
            ? SizedBox(width: box.maxWidth, height: box.maxHeight, child: content)
            : AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: content);
      },
    );
  }
}

/// The whole video (not cropped) on a black full screen, sharing the
/// player's controller: playback, position and speed carry over.
class _FullScreenVideo extends StatefulWidget {
  final VideoPlayerController controller;
  const _FullScreenVideo({required this.controller});

  @override
  State<_FullScreenVideo> createState() => _FullScreenVideoState();
}

class _FullScreenVideoState extends State<_FullScreenVideo> {
  VideoPlayerController get _c => widget.controller;

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = _c.value.isPlaying;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _c.value.aspectRatio > 0 ? _c.value.aspectRatio : 1,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    VideoPlayer(_c),
                    GestureDetector(
                      onTap: () => playing ? _c.pause() : _c.play(),
                      child: AnimatedOpacity(
                        opacity: playing ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 250),
                        child: Container(
                          color: Colors.black38,
                          child: const Center(child: Icon(Icons.play_circle_fill, size: 72, color: Colors.white)),
                        ),
                      ),
                    ),
                    VideoProgressIndicator(_c, allowScrubbing: true),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                tooltip: 'Exit full screen',
                icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 32),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
