import 'package:cloud_firestore/cloud_firestore.dart';

import '/module/custom_category_screen.dart' show CloudCategory;

/// Categories a solo / group challenge can be played in: the four built-in
/// modules plus every active category made on the web app
/// (activity_categories). [value] is stored in the room / passed to the game
/// (matched against activity_questions.category), [label] is shown.
class ChallengeCategories {
  static const List<({String value, String label})> builtIn = [
    (value: 'Alphabet', label: 'Alphabet'),
    (value: 'Numbers', label: 'Numbers'),
    (value: 'Common Phrases', label: 'Greetings'),
    (value: 'Civic Observances', label: 'Civic Observances'),
  ];

  /// Built-in first, then the web app's categories (by their order / name).
  static Future<List<({String value, String label})>> load() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('activity_categories').get();
      final cloud = [for (final d in snap.docs) CloudCategory.fromDoc(d)].whereType<CloudCategory>().toList()
        ..sort((a, b) => a.order != b.order ? a.order.compareTo(b.order) : a.title.compareTo(b.title));
      return [...builtIn, for (final c in cloud) (value: c.id, label: c.title)];
    } catch (_) {
      return builtIn;
    }
  }

  /// Whether a question's `category` belongs to the challenge [target].
  /// A question without a category never matches.
  static bool matches(String? questionCategory, String target) {
    final cat = (questionCategory ?? '').trim().toLowerCase();
    final t = target.trim().toLowerCase();
    if (cat.isEmpty || t.isEmpty) return false;
    return cat == t || cat.contains(t) || t.contains(cat);
  }
}

/// Points of one challenge answer, the same in solo and group challenges and
/// every category: a correct answer earns 50, plus a speed bonus of up to
/// 100 (the share of the round's time left), plus a streak bonus of 15 per
/// answer in the current streak from the 2nd in a row. A wrong or timed-out
/// answer earns 0 and resets the streak.
class ChallengeScoring {
  static const int base = 50;
  static const int maxSpeedBonus = 100;
  static const int streakStep = 15;

  /// [streak]: correct answers in a row including this one.
  static int points({required bool correct, required int timeLeft, required int maxTime, required int streak}) {
    if (!correct) return 0;
    final speed = maxTime > 0 ? (maxSpeedBonus * (timeLeft / maxTime)).round().clamp(0, maxSpeedBonus) : 0;
    final streakBonus = streak > 1 ? streak * streakStep : 0;
    return base + speed + streakBonus;
  }
}
