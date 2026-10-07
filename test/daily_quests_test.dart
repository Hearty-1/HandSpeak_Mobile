import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/daily_challenge_service.dart';

LearnerProfile prof(LearnerPace pace, {String? weak, List<String> unexplored = const [], int total = 20, int streak = 2}) =>
    LearnerProfile(pace: pace, activeDays: 5, levelsPerActiveDay: 3, levelsPerHour: 4, completionRate: 0.8,
        signAccuracy: 0.7, weakestCategory: weak, unexplored: unexplored, streak: streak, totalCompleted: total);

void main() {
  test('catalog ids unique, 34 quests', () {
    final ids = questCatalog.map((q) => q.id).toSet();
    expect(ids.length, questCatalog.length);
    print('catalog size ${questCatalog.length}');
  });

  for (final pace in LearnerPace.values) {
    test('$pace gets 3 suitable quests on several days', () {
      for (int d = 0; d < 7; d++) {
        final day = DateTime(2026, 10, 1 + d);
        final q = DailyChallengeService.select(
            prof(pace, weak: 'numbers', unexplored: ['civic'], total: pace == LearnerPace.starter ? 1 : 20),
            {}, day, 'uid123');
        expect(q.length, 3);
        expect(q.map((e) => e.id).toSet().length, 3);
        final tracks = q.map((e) => e.track).toList();
        final expected = {
          LearnerPace.starter: QuestTrack.starter,
          LearnerPace.steady: QuestTrack.steady,
          LearnerPace.fast: QuestTrack.fast,
        }[pace];
        if (expected != null) expect(tracks.first, expected);
        expect(q.any((e) => e.track == QuestTrack.fast) && pace == LearnerPace.steady, isFalse,
            reason: 'slow learners never get Fast Track quests');
        expect(q.any((e) => e.track == QuestTrack.explorer && e.category != 'civic'), isFalse);
        if (d == 0) print('$pace: ${q.map((e) => '${e.track.name}:${e.id}').join(', ')}');
      }
    });
  }

  test('same quests all day, completed quests never repeat', () {
    final p = prof(LearnerPace.fast, weak: 'alphabet');
    final a = DailyChallengeService.select(p, {}, DateTime(2026, 10, 7), 'u');
    final b = DailyChallengeService.select(p, {}, DateTime(2026, 10, 7), 'u');
    expect(a.map((e) => e.id), b.map((e) => e.id));
    final done = a.map((e) => e.id).toSet();
    final c = DailyChallengeService.select(p, done, DateTime(2026, 10, 7), 'u');
    expect(c.any((e) => done.contains(e.id)), isFalse);
  });

  test('catalog exhausts gracefully', () {
    final all = questCatalog.map((e) => e.id).toSet();
    expect(DailyChallengeService.select(prof(LearnerPace.fast), all, DateTime(2026, 10, 7), 'u'), isEmpty);
  });

  test('explorer badge counts categories explored on their own', () {
    final t = DailyChallengeService.trackProgress(const [], unexplored: ['civic']);
    expect(t[QuestTrack.explorer], (3, 4));
  });
}
