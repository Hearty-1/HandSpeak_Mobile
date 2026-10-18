import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'phrase_recognizer.dart';
import 'phrase_tutorial_practice.dart';

/// Continuous practice for the Words/Phrases category, like the alphabet
/// (practice.dart) and numbers (numbers_practice.dart) continuous practice:
/// the phrases come one after another, each success gives XP and moves on to
/// the next phrase, and the list loops.
///
/// Phrases are signs with movement, so each one is recorded and evaluated
/// by the same pipeline as the phrase tutorial (PhraseTutorialPractice in
/// continuous mode). Months (calendar) are left out: the calendar model
/// does not recognise new signers yet (2026-10-14 phone replay).
class PhrasePractice extends StatefulWidget {
  const PhrasePractice({super.key});

  @override
  State<PhrasePractice> createState() => _PhrasePracticeState();
}

class _PhrasePracticeState extends State<PhrasePractice> {
  /// Greetings the model recognises (PhraseRecognizer classes; "Walang
  /// anuman" is inactive in the model and the invalid class is not a sign).
  static const List<String> _phrases = [
    'Magandang Umaga',
    'Magandang Hapon',
    'Magandang Gabi',
    'Kumusta',
    'Kumusta Ka',
    'Mabuti',
    'Ikinagagalak Kong Makilala Ka',
    'Salamat',
    'Magkita Tayo Bukas',
  ];

  int _currentIdx = 0;

  /// Lesson demo (image / video) per phrase from Firestore tutorial_lessons.
  final Map<String, String> _media = {};

  @override
  void initState() {
    super.initState();
    _loadLessonMedia();
  }

  /// Key shared by a phrase and its Firestore lesson: greeting class index
  /// or the compacted text.
  static String _keyOf(String phrase) {
    final cls = PhraseRecognizer.classIndexFor(phrase);
    if (cls != -1) return 'greeting_$cls';
    return phrase.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Future<void> _loadLessonMedia() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tutorial_lessons')
          .where('category', whereIn: ['phrase', 'phrases', 'Phrase', 'Phrases'])
          .get();
      final media = <String, String>{};
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final title = (d['displayTitle'] ?? d['gestureKey'] ?? d['title'] ?? d['label'] ?? '').toString();
        final url = (d['videoUrl'] ?? d['video_url'] ?? d['image_url'] ?? d['imageUrl'] ??
                d['imageStoragePath'] ?? d['imagePath'] ?? '')
            .toString()
            .trim();
        if (title.isNotEmpty && url.isNotEmpty) media.putIfAbsent(_keyOf(title), () => url);
      }
      if (mounted) setState(() => _media.addAll(media));
    } catch (e) {
      debugPrint('Phrase lesson media unavailable: $e');
    }
  }

  void _next() {
    if (!mounted) return;
    setState(() => _currentIdx = (_currentIdx + 1) % _phrases.length);
  }

  @override
  Widget build(BuildContext context) {
    final phrase = _phrases[_currentIdx];
    return PhraseTutorialPractice(
      // A new key per phrase: each phrase gets a fresh capture pipeline
      // (greetings and months use different recognisers).
      key: ValueKey('phrase_practice_$_currentIdx'),
      targetPhrase: phrase,
      mediaUrl: _media[_keyOf(phrase)] ?? '',
      continuous: true,
      onMastered: _next,
      onSkip: _next,
      progressLabel: 'Phrase ${_currentIdx + 1} of ${_phrases.length}',
    );
  }
}
