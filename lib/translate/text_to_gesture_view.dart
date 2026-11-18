import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '/widgets/activity_video.dart';

import '/providers/language_provider.dart';
import '/services/app_haptics.dart';

/// One sign of a translation: a word / phrase, a fingerspelled letter or a
/// number, with its lesson video (null when no video is uploaded yet).
class SignClip {
  final String label;
  final String? source; // URL or Firebase Storage path of the lesson video
  final bool spelled; // a letter of a fingerspelled word
  const SignClip(this.label, this.source, {this.spelled = false});
  bool get missing => source == null;
}

/// The lesson videos uploaded from the web app (tutorial_lessons.videoUrl),
/// indexed for translation. Only cloud videos: lessons with only a picture, a
/// bundled asset or nothing are left out. Read once per app session.
class SignVideoDictionary {
  final Map<String, String> phrases; // normalised title / key -> video
  final Map<String, String> letters; // "A" -> video
  final Map<String, String> numbers; // "7" -> video
  final int maxPhraseWords;
  bool get isEmpty => phrases.isEmpty && letters.isEmpty && numbers.isEmpty;
  const SignVideoDictionary(
    this.phrases,
    this.letters,
    this.numbers,
    this.maxPhraseWords,
  );

  static Future<SignVideoDictionary>? _loading;

  /// Cost saving: the lesson list is kept on the phone for a day, so opening
  /// Text to Sign does not read every lesson document from Firestore again.
  static const String _cacheKey = 'text_to_sign_dictionary_v1';
  static const Duration _cacheFor = Duration(hours: 24);

  Map<String, dynamic> _toJson() =>
      {'p': phrases, 'l': letters, 'n': numbers, 'm': maxPhraseWords, 't': DateTime.now().millisecondsSinceEpoch};

  static SignVideoDictionary? _fromJson(Map<String, dynamic> j) {
    final t = DateTime.fromMillisecondsSinceEpoch((j['t'] as num?)?.toInt() ?? 0);
    if (DateTime.now().difference(t) > _cacheFor) return null;
    Map<String, String> m(String k) => Map<String, String>.from(j[k] as Map? ?? const {});
    final d = SignVideoDictionary(m('p'), m('l'), m('n'), (j['m'] as num?)?.toInt() ?? 1);
    return d.isEmpty ? null : d;
  }

  static Future<SignVideoDictionary> _readCached() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_cacheKey);
      if (saved != null) {
        final d = _fromJson(jsonDecode(saved) as Map<String, dynamic>);
        if (d != null) return d;
      }
    } catch (_) {}
    final d = await _read();
    if (!d.isEmpty) {
      try {
        await prefs?.setString(_cacheKey, jsonEncode(d._toJson()));
      } catch (_) {}
    }
    return d;
  }

  static Future<SignVideoDictionary> load() =>
      _loading ??= _readCached().then((d) {
        // Nothing found (e.g. read before the rules allowed it): ask again
        // next time instead of keeping an empty dictionary for the session.
        if (d.isEmpty) _loading = null;
        return d;
      }).catchError((Object e) {
        _loading = null; // offline / denied: try again next time
        debugPrint('Text to Gesture: videos not loaded: $e');
        throw e;
      });

  static const Set<String> _letterCats = {'alphabet', 'alphabets', 'letters'};
  static const Set<String> _numberCats = {'numbers', 'number'};

  static String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r"[^a-z0-9ñ\s]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _cloudVideo(String url) {
    if (url.isEmpty || url.startsWith('assets/') || url.startsWith('data:')) {
      return false;
    }
    final path = Uri.decodeComponent(url.split('?').first).toLowerCase();
    if (RegExp(r'\.(mp4|mov|webm|m4v|3gp|mkv)$').hasMatch(path)) return true;
    // An upload saved without a file extension: a video unless it is clearly
    // a picture.
    return !RegExp(r'\.(png|jpe?g|gif|webp|bmp|svg|heic)$').hasMatch(path);
  }

  static Future<SignVideoDictionary> _read() async {
    final snap = await FirebaseFirestore.instance
        .collection('tutorial_lessons')
        .get();
    final phrases = <String, String>{},
        letters = <String, String>{},
        numbers = <String, String>{};
    var maxWords = 1;
    var inactive = 0, noVideo = 0;
    final samples = <String>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      if (samples.length < 3) {
        // Diagnostics: which fields hold media in this project's lessons.
        samples.add('${doc.id}: category=${d['category']} keys=${d.keys.where((k) => RegExp('video|media|image|url|path|active|status', caseSensitive: false).hasMatch(k)).map((k) => '$k=${Uri.decodeComponent(d[k].toString().split('?').first).split('/').last}').join(', ')}');
      }
      if (d['isActive'] == false) {
        inactive++;
        continue;
      }
      // The web app saves a lesson's upload (picture OR video) in imageUrl;
      // only uploads that are videos are used here.
      final video = [
        d['videoUrl'], d['video_url'], d['videoStoragePath'], d['mediaUrl'],
        d['imageUrl'], d['image_url'], d['imageStoragePath'],
      ].map((v) => (v ?? '').toString().trim()).firstWhere(_cloudVideo, orElse: () => '');
      if (video.isEmpty) {
        noVideo++;
        continue;
      }
      final cat = (d['category'] ?? '').toString().trim().toLowerCase();
      final key = (d['gestureKey'] ?? d['symbol'] ?? '').toString().trim();
      final title = (d['title'] ?? d['name'] ?? '').toString().trim();
      if (_letterCats.contains(cat)) {
        final k = (key.isNotEmpty ? key : title.split(' ').last).toUpperCase();
        if (k.isNotEmpty) letters.putIfAbsent(k, () => video);
        continue;
      }
      if (_numberCats.contains(cat)) {
        final k = (key.isNotEmpty ? key : title).replaceAll(
          RegExp(r'[^0-9]'),
          '',
        );
        if (k.isNotEmpty) {
          numbers.putIfAbsent(int.parse(k).toString(), () => video);
        }
        continue;
      }
      for (final name in [title, key, (d['symbol'] ?? '').toString()]) {
        final n = norm(name.replaceAll('_', ' '));
        if (n.isEmpty) continue;
        phrases.putIfAbsent(n, () => video);
        final words = n.split(' ').length;
        if (words > maxWords) maxWords = words;
      }
    }
    debugPrint('Text to Gesture: ${snap.docs.length} lessons read, $inactive inactive, $noVideo without a usable video');
    for (final s in samples) {
      debugPrint('Text to Gesture: lesson $s');
    }
    debugPrint(
      'Text to Gesture: ${phrases.length} words/phrases, ${letters.length} letters, ${numbers.length} numbers with videos',
    );
    return SignVideoDictionary(phrases, letters, numbers, maxWords.clamp(1, 8));
  }

  /// [text] as signs: the longest uploaded phrase first, then a whole
  /// number, then each letter / digit fingerspelled.
  List<SignClip> translate(String text) {
    final words = norm(text).split(' ').where((w) => w.isNotEmpty).toList();
    final out = <SignClip>[];
    var i = 0;
    while (i < words.length) {
      var matched = false;
      for (var n = maxPhraseWords.clamp(1, words.length - i); n >= 1; n--) {
        final phrase = words.sublist(i, i + n).join(' ');
        final v = phrases[phrase];
        if (v != null) {
          out.add(SignClip(_pretty(phrase), v));
          i += n;
          matched = true;
          break;
        }
      }
      if (matched) continue;
      final w = words[i++];
      if (RegExp(r'^\d+$').hasMatch(w)) {
        final v = numbers[int.parse(w).toString()];
        if (v != null) {
          out.add(SignClip(w, v));
          continue;
        }
      }
      for (final ch in w.toUpperCase().split('')) {
        final isDigit = RegExp(r'\d').hasMatch(ch);
        out.add(
          SignClip(ch, isDigit ? numbers[ch] : letters[ch], spelled: true),
        );
      }
    }
    return out;
  }

  static String _pretty(String s) => s
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Text to Gesture: type a word or sentence and watch it signed with the
/// lesson videos uploaded to the cloud, one after another.
class TextToGestureView extends StatefulWidget {
  final String initialText;
  const TextToGestureView({super.key, this.initialText = ''});

  @override
  State<TextToGestureView> createState() => _TextToGestureViewState();
}

class _TextToGestureViewState extends State<TextToGestureView> {
  late final TextEditingController _input = TextEditingController(
    text: widget.initialText,
  );
  SignVideoDictionary? _dict;
  String? _error;

  List<SignClip> _clips = [];
  int _index = -1; // playing clip
  bool _playing = false;
  double _speed = 1.0;

  VideoPlayerController? _video;
  final Map<int, Future<VideoPlayerController?>> _prepared = {};
  Timer? _missingTimer;
  int _session = 0; // a new translation cancels the old playback

  static final Map<String, Future<String>> _urls = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await SignVideoDictionary.load();
      if (!mounted) return;
      setState(() {
        _dict = d;
        _error = null;
      });
      if (_input.text.trim().isNotEmpty) _translate();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = L.t(
            'Could not load the sign videos. Check your internet connection.',
            'Hindi ma-load ang mga video. Tingnan ang koneksyon sa internet.',
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _stopAll();
    _input.dispose();
    super.dispose();
  }

  void _stopAll() {
    _session++;
    _missingTimer?.cancel();
    final v = _video;
    _video = null;
    v?.removeListener(_onTick);
    v?.dispose();
    for (final f in _prepared.values) {
      f.then((c) => c?.dispose());
    }
    _prepared.clear();
  }

  static Future<String> _resolve(String s) {
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return Future.value(s);
    }
    return _urls[s] ??=
        (s.startsWith('gs://')
                ? FirebaseStorage.instance.refFromURL(s)
                : FirebaseStorage.instance.ref(s))
            .getDownloadURL()
            .catchError((Object _) {
              _urls.remove(s);
              return '';
            });
  }

  Future<VideoPlayerController?> _prepare(int i) {
    return _prepared[i] ??= () async {
      if (i < 0 || i >= _clips.length || _clips[i].missing) return null;
      final url = await _resolve(_clips[i].source!);
      if (url.isEmpty) return null;
      // Cost saving: each video is downloaded once and then played from the
      // phone (shared with the activity videos' cache, 30 days).
      VideoPlayerController c;
      try {
        final file = await ActivityVideo.fetchFile(url).timeout(const Duration(seconds: 20));
        c = VideoPlayerController.file(file);
      } catch (_) {
        c = VideoPlayerController.networkUrl(Uri.parse(url));
      }
      try {
        await c.initialize();
        await c.setVolume(0);
        return c;
      } catch (e) {
        debugPrint('Text to Gesture: video ${_clips[i].label} failed: $e');
        await c.dispose();
        return null;
      }
    }();
  }

  void _translate() {
    final d = _dict;
    final text = _input.text.trim();
    FocusScope.of(context).unfocus();
    if (d == null || text.isEmpty) return;
    AppHaptics.selection();
    _stopAll();
    setState(() {
      _clips = d.translate(text);
      _index = -1;
      _playing = false;
    });
    if (_clips.isNotEmpty) _playFrom(0);
  }

  Future<void> _playFrom(int i) async {
    final session = _session;
    _missingTimer?.cancel();
    final old = _video;
    old?.removeListener(_onTick);
    if (i >= _clips.length) {
      setState(() => _playing = false);
      return;
    }
    setState(() {
      _index = i;
      _playing = true;
    });
    unawaited(_prepare(i + 1)); // the next sign loads while this one plays
    final c = await _prepare(i);
    if (!mounted || session != _session) return;
    _prepared.remove(i);
    if (old != null && old != c) unawaited(old.dispose());
    if (c == null) {
      // No video yet: show the letter / word for a moment, then go on.
      setState(() => _video = null);
      _missingTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted && session == _session) _playFrom(i + 1);
      });
      return;
    }
    await c.seekTo(Duration.zero);
    await c.setPlaybackSpeed(_speed);
    c.addListener(_onTick);
    setState(() => _video = c);
    await c.play();
  }

  void _onTick() {
    final c = _video;
    if (c == null || !_playing) return;
    final v = c.value;
    if (v.isInitialized &&
        !v.isPlaying &&
        v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 80)) {
      c.removeListener(_onTick);
      _playFrom(_index + 1);
    }
  }

  void _replay() {
    if (_clips.isEmpty) return;
    AppHaptics.selection();
    _stopAll();
    _playFrom(0);
  }

  void _jump(int i) {
    AppHaptics.selection();
    _stopAll();
    _playFrom(i);
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    _video?.setPlaybackSpeed(s);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight;
        final player = ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: _player(theme),
        );
        final controls = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _inputCard(theme),
            const SizedBox(height: 12),
            _chips(theme),
          ],
        );
        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: player),
                const SizedBox(width: 16),
                Expanded(child: SingleChildScrollView(child: controls)),
              ],
            ),
          );
        }
        final h = (c.maxHeight * 0.46).clamp(220.0, c.maxWidth);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            children: [
              SizedBox(height: h, width: double.infinity, child: player),
              const SizedBox(height: 14),
              controls,
            ],
          ),
        );
      },
    );
  }

  Widget _player(ThemeData theme) {
    final v = _video;
    final clip = _index >= 0 && _index < _clips.length ? _clips[_index] : null;
    Widget body;
    if (_error != null) {
      body = _centerText(_error!);
    } else if (_dict == null) {
      body = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else if (clip == null) {
      body = _centerText(
        L.t(
          'Type a word or sentence below, then tap Translate.',
          'Mag-type ng salita o pangungusap sa ibaba, saka pindutin ang Isalin.',
        ),
      );
    } else if (clip.missing) {
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            clip.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            L.t('No video uploaded yet', 'Wala pang na-upload na video'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
            ),
          ),
        ],
      );
    } else if (v == null || !v.value.isInitialized) {
      body = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else {
      body = Center(
        child: AspectRatio(
          aspectRatio: v.value.aspectRatio,
          child: VideoPlayer(v),
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          body,
          if (clip != null)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  clip.spelled
                      ? L.t(
                          'Spelling: ${clip.label}',
                          'Binabaybay: ${clip.label}',
                        )
                      : clip.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          if (_clips.isNotEmpty)
            Positioned(
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  _roundButton(
                    Icons.slow_motion_video_rounded,
                    _speed == 1.0 ? '1x' : '0.5x',
                    () => _setSpeed(_speed == 1.0 ? 0.5 : 1.0),
                  ),
                  const SizedBox(width: 8),
                  _roundButton(
                    _playing ? Icons.stop_rounded : Icons.replay_rounded,
                    null,
                    () {
                      if (_playing) {
                        _stopAll();
                        setState(() => _playing = false);
                      } else {
                        _replay();
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _roundButton(IconData icon, String? label, VoidCallback onTap) =>
      Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                if (label != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _centerText(String t) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        t,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
    ),
  );

  Widget _inputCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        // Glass, like the rest of the Translate page.
        color: theme.cardColor.withValues(alpha: theme.brightness == Brightness.dark ? 0.55 : 0.6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: theme.brightness == Brightness.dark ? 0.12 : 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L.t('Your text', 'Iyong teksto'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          TextField(
            controller: _input,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _translate(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: L.t('e.g. Magandang umaga', 'hal. Magandang umaga'),
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  L.t(
                    'Words without a video are fingerspelled.',
                    'Ang salitang walang video ay binabaybay.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _dict == null ? null : _translate,
                icon: const Icon(Icons.sign_language_rounded),
                label: Text(
                  L.t('Translate', 'Isalin'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chips(ThemeData theme) {
    if (_clips.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _clips.length; i++)
            ChoiceChip(
              label: Text(
                _clips[i].label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: _clips[i].missing
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              selected: i == _index,
              tooltip: _clips[i].missing
                  ? L.t('No video uploaded yet', 'Wala pang na-upload na video')
                  : null,
              onSelected: (_) => _jump(i),
            ),
        ],
      ),
    );
  }
}
