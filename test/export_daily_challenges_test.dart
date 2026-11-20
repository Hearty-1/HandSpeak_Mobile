// Writes the app's built-in daily quests to tools/daily_challenges.json, the
// file tools/seed_daily_challenges.py uploads to Firestore `daily_challenges`
// (the web dashboard reads the conditions from there, like the badges).
//
//   flutter test test/export_daily_challenges_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_application_1/services/daily_challenge_service.dart';
import 'package:flutter_application_1/services/quest_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export the daily quest conditions', () {
    final rows = [
      for (var i = 0; i < builtInQuests.length; i++)
        {
          'id': builtInQuests[i].id,
          'title': builtInQuests[i].title,
          'description': builtInQuests[i].description,
          'track': builtInQuests[i].track.name,
          'trackName': builtInQuests[i].info.name,
          'metric': builtInQuests[i].metric.name,
          'metricDescription': QuestCatalog.metrics[builtInQuests[i].metric.name],
          'target': builtInQuests[i].target,
          'reward': builtInQuests[i].reward,
          if (builtInQuests[i].category != null) 'category': builtInQuests[i].category,
          'order': i + 1,
          'active': true,
        },
    ];
    // Every metric the app counts has a description for the web form.
    for (final m in QuestMetric.values) {
      expect(QuestCatalog.metrics.containsKey(m.name), isTrue, reason: 'no description for ${m.name}');
    }
    final ids = rows.map((r) => r['id']).toSet();
    expect(ids.length, rows.length, reason: 'quest ids must be unique');
    File('tools/daily_challenges.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
    // ignore: avoid_print
    print('Wrote ${rows.length} quests to tools/daily_challenges.json');
  });
}
