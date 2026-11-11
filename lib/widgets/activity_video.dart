import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

import '/providers/sound_provider.dart';

/// Sign video in an activity question / answer option (all categories):
/// shows the first frame, plays and loops after a tap on the centred play
/// button (hidden while playing; a tap on the video pauses it), only one at
/// a time, muted.
class ActivityVideo extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final Widget fallback;

  const ActivityVideo({super.key, required this.url, required this.fit, required this.fallback});

  /// Sign videos kept on the phone (30 days, up to 300 files).
  static final CacheManager _cache = CacheManager(Config('handspeak_sign_videos', stalePeriod: const Duration(days: 30), maxNrOfCacheObjects: 300));
  static final Set<String> _downloading = {};

  /// The saved copy of [url], if it was downloaded before.
  static Future<File?> cachedFile(String url) async {
    try {
      return (await _cache.getFileFromCache(url))?.file;
    } catch (_) {
      return null;
    }
  }

  /// Downloads [url] in the background (e.g. the next questions' videos), so
  /// it plays at once when it is shown.
  static void prefetch(String url) {
    if (!url.startsWith('http') || !_downloading.add(url)) return;
    _cache.downloadFile(url).then((_) {}, onError: (Object e) => debugPrint('Video not saved ($url): $e')).whenComplete(() => _downloading.remove(url));
  }

  @override
  State<ActivityVideo> createState() => _ActivityVideoState();
}

class _ActivityVideoState extends State<ActivityVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final url = widget.url;
    // mixWithOthers: each player otherwise takes the audio focus when it
    // starts, which pauses the others, so only one of several option
    // videos kept playing. These videos are muted anyway.
    final options = VideoPlayerOptions(mixWithOthers: true);
    // A video seen before plays from the phone (no download); a new one
    // streams now and is saved in the background for next time.
    final cached = url.startsWith('http') ? await ActivityVideo.cachedFile(url) : null;
    if (!mounted || url != widget.url) return;
    final c = url.startsWith('assets/')
        ? VideoPlayerController.asset(url, videoPlayerOptions: options)
        : cached != null
            ? VideoPlayerController.file(cached, videoPlayerOptions: options)
            : VideoPlayerController.networkUrl(Uri.parse(url), videoPlayerOptions: options);
    if (cached == null && url.startsWith('http')) ActivityVideo.prefetch(url);
    _controller = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      // Not played until tapped (several looping videos at once are heavy);
      // the first frame shows meanwhile.
      c.addListener(_onTick);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Activity video unavailable ($url): $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant ActivityVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Same slot, next question: load the new video.
    if (oldWidget.url != widget.url) {
      if (_playing == this) _playing = null;
      _controller?.removeListener(_onTick);
      _controller?.dispose();
      _controller = null;
      _failed = false;
      _wasPlaying = false;
      _open();
    }
  }

  /// The video playing now: starting one pauses the other.
  static _ActivityVideoState? _playing;

  bool _wasPlaying = false;

  void _onTick() {
    final p = _controller?.value.isPlaying ?? false;
    if (p != _wasPlaying) {
      SoundProvider.videoPlaybackChanged(this, p); // music dips while it plays
      if (mounted) setState(() => _wasPlaying = p);
    }
  }

  void _toggle() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
      if (_playing == this) _playing = null;
    } else {
      if (_playing != this) _playing?._controller?.pause();
      _playing = this;
      c.play();
    }
  }

  @override
  void dispose() {
    SoundProvider.videoPlaybackChanged(this, false);
    if (_playing == this) _playing = null;
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed) return widget.fallback;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final playing = c.value.isPlaying;
    // ▶ in the middle starts it and hides while playing, so it does not
    // cover the sign; a tap on the playing video pauses it (a Listener, so
    // the tap still reaches an answer option too).
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: (_) {
        if (playing) _toggle();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: FittedBox(
              fit: widget.fit,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
            ),
          ),
          Center(
            child: IgnorePointer(
              ignoring: playing,
              child: AnimatedOpacity(
                opacity: playing ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: _toggle,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plays the question's audio clip (audioStoragePath in the doc).
