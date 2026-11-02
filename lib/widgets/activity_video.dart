import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Sign video in an activity question / answer option (all categories):
/// shows the first frame, plays and loops after a tap on the centred play
/// button (hidden while playing; a tap on the video pauses it), only one at
/// a time, muted.
class ActivityVideo extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final Widget fallback;

  const ActivityVideo({super.key, required this.url, required this.fit, required this.fallback});

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
    final c = url.startsWith('assets/')
        ? VideoPlayerController.asset(url, videoPlayerOptions: options)
        : VideoPlayerController.networkUrl(Uri.parse(url), videoPlayerOptions: options);
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
    if (p != _wasPlaying && mounted) setState(() => _wasPlaying = p);
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
