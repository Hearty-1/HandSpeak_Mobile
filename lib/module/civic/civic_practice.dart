import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '/module/tutorial_session_practice.dart';
import 'civic_tutorial_interface.dart' show LupangLines;

/// Continuous practice for Civic Observances (the Lupang Hinirang lines),
/// checked like the Hard camera activities (RECORD SIGN -> the Lupang
/// Hinirang model), with ◀ / ▶, each line's tutorial video, and the session
/// stored in the Practice Sessions (tutorial_session_practice.dart).
class CivicPractice extends StatefulWidget {
  const CivicPractice({super.key});

  @override
  State<CivicPractice> createState() => _CivicPracticeState();
}

class _CivicPracticeState extends State<CivicPractice> {
  late final Future<List<PracticeSign>> _signs = _load();

  static bool _isVideoFile(String url) {
    if (url.isEmpty) return false;
    final path = Uri.decodeComponent(url.split('?').first).toLowerCase();
    return RegExp(r'\.(mp4|mov|webm|m4v|3gp)$').hasMatch(path);
  }

  /// Video of a lesson / question, as in the civic tutorial list.
  static String _video(Map m) {
    final v = (m['videoUrl'] ?? m['video_url'] ?? m['mediaUrl'] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
    final img = (m['imageUrl'] ?? m['image_url'] ?? '').toString().trim();
    return _isVideoFile(img) ? img : '';
  }

  /// The lines with the same videos as the civic tutorial: the line's own
  /// lesson / question video, else the whole-anthem video.
  static Future<List<PracticeSign>> _load() async {
    final phrases = await LupangLines.loadPhrases();
    final videoByLine = <String, String>{};
    var anthemVideo = '';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('tutorial_lessons')
          .where('category', whereIn: ['civic', 'Civic', 'civics'])
          .get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final key = LupangLines.compact((d['displayTitle'] ?? d['title'] ?? d['label'] ?? '').toString());
        if (_video(d).isNotEmpty) videoByLine.putIfAbsent(key, () => _video(d));
        final isAnthem = key.contains('lupang') && key.contains('hinirang') && key.length <= 'lupanghinirang'.length + 12;
        if (isAnthem && anthemVideo.isEmpty) anthemVideo = _video(d);
        for (final q in (d['questions'] as List?) ?? const []) {
          if (q is! Map || _video(q).isEmpty) continue;
          for (final f in ['folder_code', 'label', 'question', 'title', 'id']) {
            final k = LupangLines.compact('${q[f] ?? ''}');
            if (k.isNotEmpty) videoByLine.putIfAbsent(k, () => _video(q));
          }
        }
      }
    } catch (e) {
      debugPrint('Civic practice videos unavailable: $e');
    }
    return [
      for (final p in phrases)
        PracticeSign(
          (p['label'] ?? '').toString(),
          itemKey: LupangLines.lineKey(((p['index'] as num?) ?? 0).toInt()),
          media: videoByLine[LupangLines.compact('${p['label']}')] ??
              videoByLine[LupangLines.compact('${p['folder_code'] ?? ''}')] ??
              anthemVideo,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PracticeSign>>(
      future: _signs,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Scaffold(body: Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)));
        }
        return TutorialSessionPractice(
          title: 'Civic Practice',
          category: 'civic',
          categoryName: 'Civic Observances',
          xpField: LupangLines.xpField,
          signs: snap.data!,
        );
      },
    );
  }
}
