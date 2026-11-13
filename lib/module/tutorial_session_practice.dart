import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '/module/custom_category_screen.dart' show PublishedCameraSign;
import '/providers/language_provider.dart';
import '/providers/sound_provider.dart';
import '/services/progress_service.dart';
import '/services/tutorial_session_recorder.dart';
import '/services/xp_rewards.dart';
import '/module/civic/civic_tutorial_detail.dart' show CustomVideoPlayer;
import '/widgets/lesson_demo_media.dart';
import '/widgets/button_3d.dart';
import '/widgets/challenge_camera_sign.dart';

/// One sign of a continuous practice run.
class PracticeSign {
  /// The sign checked by the camera (letter, number, phrase, line, lesson).
  final String sign;

  /// Shown above the camera (defaults to [sign]).
  final String label;

  /// Optional demo picture / video of the sign.
  final String media;

  /// XP item key (first pass only); defaults to the sign's mastery key.
  final String? itemKey;

  const PracticeSign(this.sign, {String? label, this.media = '', this.itemKey}) : label = label ?? sign;
}

/// Continuous practice for every category, checked like the Hard camera
/// activities: still signs (letters, numbers 1-10) with CAPTURE & CHECK,
/// moving signs (J / Z, numbers 11-100, Greetings, Civic, web categories)
/// with RECORD SIGN -> 3-2-1 -> recording -> check. ◀ / ▶ move between
/// signs; a passed sign gives practice XP (first time) and moves on; a wrong
/// one can be tried again. Every attempt is stored in the "Practice
/// Sessions" (TutorialSessionRecorder, Firestore `practice_sessions`).
class TutorialSessionPractice extends StatefulWidget {
  /// Screen title, e.g. "Alphabet Practice".
  final String title;

  /// Category id: 'alphabet' / 'numbers' use the Alphabet / Numbers checks;
  /// any other ('phrases', 'civic', a web category id) its published model.
  final String category;

  /// Category name for the session record (level.levelId "practice_NAME").
  final String categoryName;

  final List<PracticeSign> signs;
  final int startIndex;

  /// Practice XP: module key (XpRewards.practiceKey) and the user XP field.
  final String xpField;

  const TutorialSessionPractice({
    super.key,
    required this.title,
    required this.category,
    required this.categoryName,
    required this.signs,
    required this.xpField,
    this.startIndex = 0,
  });

  @override
  State<TutorialSessionPractice> createState() => _TutorialSessionPracticeState();
}

class _TutorialSessionPracticeState extends State<TutorialSessionPractice> {
  late int _i = widget.signs.isEmpty ? 0 : widget.startIndex.clamp(0, widget.signs.length - 1);
  int _attempt = 0; // new camera check per try
  ChallengeSignResult? _result;
  int _xp = 0;
  DateTime _shownAt = DateTime.now();
  Timer? _advance;

  late final TutorialSessionRecorder _session = TutorialSessionRecorder(
    category: widget.category,
    levelId: 'practice_${widget.categoryName}',
  );

  bool get _builtInChecks => widget.category == 'alphabet' || widget.category == 'numbers';
  PracticeSign get _sign => widget.signs[_i];

  @override
  void dispose() {
    _advance?.cancel();
    unawaited(_session.finish());
    super.dispose();
  }

  void _go(int step) {
    if (widget.signs.isEmpty) return;
    _advance?.cancel();
    setState(() {
      _i = (_i + step) % widget.signs.length;
      if (_i < 0) _i += widget.signs.length;
      _attempt++;
      _result = null;
      _xp = 0;
      _shownAt = DateTime.now();
    });
  }

  void _retry() {
    _advance?.cancel();
    setState(() {
      _attempt++;
      _result = null;
      _xp = 0;
      _shownAt = DateTime.now();
    });
  }

  Future<void> _onResult(ChallengeSignResult r) async {
    if (!mounted) return;
    setState(() => _result = r);
    if (r.skipped) return; // no model can check this sign: not an attempt
    final sign = _sign;
    final handsSeen = r.correct || r.score > 0 || (r.predicted ?? '').isNotEmpty || (r.frames ?? 0) > 0;
    unawaited(_session.recordAttempt(
      sign: sign.sign,
      correct: r.correct,
      score: r.score,
      handsDetected: handsSeen,
      predicted: r.predicted,
      model: r.model,
      durationMs: DateTime.now().difference(_shownAt).inMilliseconds,
    ));
    if (!r.correct) {
      HapticFeedback.heavyImpact();
      Provider.of<SoundProvider>(context, listen: false).playIncorrect();
      return;
    }
    HapticFeedback.mediumImpact();
    Provider.of<SoundProvider>(context, listen: false).playCorrect();
    final xp = await ProgressService().awardFirstMastery(
      moduleKey: XpRewards.practiceKey(widget.category),
      itemKey: sign.itemKey ?? ProgressService.masteryKey(sign.sign),
      xp: XpRewards.practiceSign,
      xpField: widget.xpField,
      countsAsLesson: false,
    );
    if (!mounted) return;
    setState(() => _xp = xp);
    // A pass moves on by itself, as the old continuous practice did.
    _advance = Timer(_advanceAfter, () {
      if (mounted) _go(1);
    });
  }

  /// The sign's demo, as in the tutorial practice screens: a square 60% of
  /// the screen wide (the camera's size), the uploaded tutorial video /
  /// picture, else the bundled picture (Alphabet, Numbers).
  Widget _media(ThemeData theme) {
    final side = MediaQuery.sizeOf(context).width * 0.60;
    final Widget? child;
    if (_builtInChecks) {
      final key = _sign.sign.trim().toUpperCase();
      child = LessonDemoMedia(
        key: ValueKey('demo_$key'),
        category: widget.category,
        gestureKey: key,
        fallbackAsset: widget.category == 'alphabet' ? 'assets/pictures/$key.jpg' : 'assets/pictures/$key.png',
      );
    } else {
      final src = _sign.media.trim();
      child = src.isEmpty ? null : _UploadedMedia(key: ValueKey('demo_$src'), source: src);
    }
    if (child == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: SizedBox(
        width: side,
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
          ),
        ),
      ),
    );
  }

  /// How long a correct sign stays on screen before the next one.
  static const Duration _advanceAfter = Duration(milliseconds: 1800);

  /// Result card in practice's own coaching style (not the activities' game
  /// look): a calm card in the app colours, green when right, soft amber (not
  /// red) when it needs another try. A pass shows the XP and a countdown bar
  /// to the next sign; a miss shows the match score, a hint and TRY AGAIN.
  Widget _feedback(ThemeData theme) {
    final r = _result;
    if (r == null) return const SizedBox.shrink();
    final onSurface = theme.colorScheme.onSurface;

    // No model for this sign yet: a neutral note.
    if (r.skipped) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.dividerColor, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: onSurface.withValues(alpha: 0.6), size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                L.t('This sign cannot be checked yet. Use ▶ for the next sign.', 'Hindi pa masusuri ang kumpas na ito. Pindutin ang ▶.'),
                style: TextStyle(fontWeight: FontWeight.w600, color: onSurface.withValues(alpha: 0.75)),
              ),
            ),
          ],
        ),
      );
    }

    // Practice colours: green = right, amber = try again (no red: mistakes
    // are part of practising).
    final badge = r.correct ? const Color(0xFF2E9E4F) : const Color(0xFFE59A1A);
    final sign = _sign.label;
    final title = r.correct
        ? L.t('Nice signing!', 'Magaling ang pagkumpas!')
        : L.t('Almost there, keep going', 'Malapit na, ituloy mo');
    final lookedLike = (r.predicted ?? '').trim().isNotEmpty && r.predicted!.trim().toUpperCase() != _sign.sign.trim().toUpperCase();
    final hint = r.correct
        ? L.t('"$sign" is correct.', 'Tama ang "$sign".')
        : lookedLike
            ? L.t('That looked like "${r.predicted}". Watch the example of "$sign" and try again.',
                'Mukhang "${r.predicted}" iyon. Panoorin ang halimbawa ng "$sign" at subukang muli.')
            : L.t('Watch the example of "$sign", then try again.', 'Panoorin ang halimbawa ng "$sign", saka subukang muli.');
    // A live match score only means something for still signs.
    final showScore = !r.correct && !r.isDynamic && r.score > 0;

    Widget pill(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: badge.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: badge, size: 15),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(color: badge, fontWeight: FontWeight.w900, fontSize: 13)),
          ]),
        );

    return TweenAnimationBuilder<double>(
      key: ValueKey('fb_${_i}_$_attempt'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, (1 - t) * 40),
        child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(badge.withValues(alpha: 0.07), theme.cardColor),
          borderRadius: BorderRadius.circular(18),
          border: Border(left: BorderSide(color: badge, width: 5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: badge.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(r.correct ? Icons.thumb_up_alt_rounded : Icons.lightbulb_rounded, color: badge, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: onSurface, fontWeight: FontWeight.w900, fontSize: 17)),
                      const SizedBox(height: 2),
                      Text(hint,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (r.correct) ...[
              Row(children: [
                if (_xp > 0) pill(Icons.bolt_rounded, '+$_xp XP') else pill(Icons.check_rounded, L.t('Correct!', 'Tama!')),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(L.t('Next sign coming up...', 'Susunod na kumpas...'),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 8),
              // Fills while the screen waits to show the next sign.
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('adv_${_i}_$_attempt'),
                  tween: Tween(begin: 0, end: 1),
                  duration: _advanceAfter,
                  builder: (context, p, _) => LinearProgressIndicator(
                    value: p,
                    minHeight: 6,
                    backgroundColor: badge.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(badge),
                  ),
                ),
              ),
            ] else ...[
              if (showScore) ...[
                Row(children: [
                  pill(Icons.speed_rounded, L.t('Match ${r.score.round()}%', 'Tugma ${r.score.round()}%')),
                  const SizedBox(width: 8),
                  Text(L.t('need 70%', 'kailangan 70%'),
                      style: TextStyle(color: onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
                const SizedBox(height: 10),
              ],
              SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _retry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: theme.colorScheme.onPrimary,
                    elevation: 0,
                    shape: Button3DBorder(borderRadius: BorderRadius.circular(23)),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(L.t('TRY AGAIN', 'ULITIN'), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _arrow(ThemeData theme, IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: SizedBox(
          width: 64,
          height: 56,
          child: ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              padding: EdgeInsets.zero,
              shape: Button3DBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: Icon(icon, color: theme.colorScheme.onPrimary, size: 30),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.signs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(child: Text(L.t('Nothing to practise yet.', 'Wala pang mapag-aaralan.'))),
      );
    }
    final sign = _sign;
    final camera = _builtInChecks
        ? ChallengeCameraSign(
            // One camera for the whole run: the sign / try changes in place
            // (restarting the camera per sign was slow and lost the hands).
            key: const ValueKey('practice_cam'),
            sign: sign.sign,
            attempt: _attempt,
            enabled: _result == null,
            onResult: _onResult,
          )
        : PublishedCameraSign(
            key: const ValueKey('practice_cam'),
            category: widget.category,
            sign: sign.sign,
            attempt: _attempt,
            enabled: _result == null,
            onResult: _onResult,
          );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(widget.title, style: TextStyle(fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  children: [
                    Text(sign.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: sign.label.length > 12 ? 24 : 40, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
                    const SizedBox(height: 16),
                    _media(theme),
                    camera,
                  ],
                ),
              ),
            ),
            // Feedback stays in view above the arrows (not scrolled away).
            Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: _feedback(theme)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _arrow(theme, Icons.arrow_back_rounded, L.t('Previous sign', 'Nakaraang kumpas'), () => _go(-1)),
                  Text('${_i + 1} / ${widget.signs.length}',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: theme.colorScheme.onSurface)),
                  _arrow(theme, Icons.arrow_forward_rounded, L.t('Next sign', 'Susunod na kumpas'), () => _go(1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tutorial video / picture uploaded from the web app (download link or
/// Firebase Storage path), shown whole, as in the tutorial practice screens.
class _UploadedMedia extends StatefulWidget {
  final String source;
  const _UploadedMedia({super.key, required this.source});

  @override
  State<_UploadedMedia> createState() => _UploadedMediaState();
}

class _UploadedMediaState extends State<_UploadedMedia> {
  late final Future<String> _url = _resolve(widget.source);

  static Future<String> _resolve(String src) async {
    if (src.startsWith('http://') || src.startsWith('https://')) return src;
    if (src.startsWith('assets/')) return src;
    try {
      final ref = src.startsWith('gs://') ? FirebaseStorage.instance.refFromURL(src) : FirebaseStorage.instance.ref(src);
      return await ref.getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        final url = snap.data ?? '';
        if (snap.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor));
        }
        if (url.isEmpty) return const SizedBox.shrink();
        if (LessonDemoMedia.isVideo(url)) {
          return ColoredBox(color: Colors.black, child: Center(child: CustomVideoPlayer(key: ValueKey(url), videoUrl: url)));
        }
        if (url.startsWith('assets/')) return Image.asset(url, fit: BoxFit.contain);
        return Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink());
      },
    );
  }
}
