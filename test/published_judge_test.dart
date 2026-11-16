// The one pass rule for published (web-trained) models, checked against real
// server answers from phone tests (2026-11-14) and the cases that must fail.
import 'package:flutter_application_1/module/custom_category_screen.dart';
import 'package:flutter_application_1/services/handspeak_api_service.dart';
import 'package:flutter_application_1/services/published_gesture_models.dart';
import 'package:flutter_test/flutter_test.dart';

// The strict thresholds the web published for Drinks (from the phone log).
const strict = PracticeSettings(minConfidence: 0.70, minSignShare: 1.01, minSignLead: 0.05, maxInvalid: 0.40);

PublishedGestureModel model(List<String> labels, {int invalid = 99, String version = 'v1'}) => PublishedGestureModel(
      modelId: 'gs_0000000000000000',
      serviceUrl: '',
      name: 'test',
      category: 'test',
      invalidIndex: invalid,
      modelVersion: version,
      classes: [
        for (var i = 0; i < labels.length; i++)
          PublishedGestureClass(index: i, key: labels[i].toLowerCase(), label: labels[i], lessonSymbol: '', practice: strict),
        PublishedGestureClass(index: invalid, key: 'not_recognised', label: 'Not recognised', lessonSymbol: '', practice: strict),
      ],
    );

RawPredictResponse answer(List<(int, String, double)> top, {bool accepted = false, List<String> failed = const [], String version = 'v1'}) =>
    RawPredictResponse.fromJson({
      'model': 'gs_0000000000000000',
      'model_version': version,
      'accepted': accepted,
      'failed_checks': failed,
      'top_k': [for (final (i, l, c) in top) {'index': i, 'label': l, 'confidence': c}],
    });

void main() {
  final drinks = model(['Coffee', 'Juice', 'Tea', 'Milk', 'Wine']);
  PublishedGestureClass cls(PublishedGestureModel m, String label) => m.classes.firstWhere((c) => c.label == label);

  test('Tea: server accepted at 62 % -> pass (was "Almost")', () {
    final v = judgePublishedSign(
        answer([(2, 'Tea', 0.62), (1, 'Juice', 0.22), (99, 'Not recognised', 0.05)], accepted: true), drinks, cls(drinks, 'Tea'));
    expect(v.passed, isTrue);
  });

  test('Milk: server accepted at 59 % -> pass', () {
    final v = judgePublishedSign(
        answer([(3, 'Milk', 0.59), (99, 'Not recognised', 0.32), (0, 'Coffee', 0.02)], accepted: true), drinks, cls(drinks, 'Milk'));
    expect(v.passed, isTrue);
  });

  test('refused only on model scores, sign clearly ahead -> pass (lead rule)', () {
    final v = judgePublishedSign(
        answer([(99, 'Not recognised', 0.50), (3, 'Milk', 0.40), (0, 'Coffee', 0.05)], failed: ['INVALID_CLASS']),
        drinks, cls(drinks, 'Milk'));
    expect(v.passed, isTrue);
    expect(v.why, contains('lead rule'));
  });

  test('Cousin: "not recognised" 93 %, sign at 1 % -> fail, and no "Almost"', () {
    final family = model(['Cousin', 'Grandfather', 'Grandmother']);
    final v = judgePublishedSign(
        answer([(99, 'Not recognised', 0.93), (0, 'Cousin', 0.01), (1, 'Grandfather', 0.01), (2, 'Grandmother', 0.01)],
            failed: ['INVALID_CLASS']),
        family, cls(family, 'Cousin'));
    expect(v.passed, isFalse);
    expect(v.bestConfidence < 0.10, isTrue); // below the "Almost" floor
  });

  test('wrong sign accepted by the server (Coffee for Wine) -> fail', () {
    final v = judgePublishedSign(
        answer([(0, 'Coffee', 0.80), (4, 'Wine', 0.10)], accepted: true), drinks, cls(drinks, 'Wine'));
    expect(v.passed, isFalse);
  });

  test('refused on motion / framing -> fail even when the sign leads', () {
    final v = judgePublishedSign(
        answer([(99, 'Not recognised', 0.40), (3, 'Milk', 0.55)], failed: ['LOW_MOTION']), drinks, cls(drinks, 'Milk'));
    expect(v.passed, isFalse);
  });

  test('no model answer (gate refusal) -> fail', () {
    final v = judgePublishedSign(answer([], failed: ['OUT_OF_FRAME']), drinks, cls(drinks, 'Milk'));
    expect(v.passed, isFalse);
  });

  test('model retrained with signs reordered: matched by label, not index', () {
    // The server now has Tea at index 0 and Coffee at index 2; the app still has the old list.
    final v = judgePublishedSign(
        answer([(0, 'Tea', 0.75), (2, 'Coffee', 0.10)], accepted: true, version: 'v2'), drinks, cls(drinks, 'Tea'));
    expect(v.passed, isTrue);
    final wrong = judgePublishedSign(
        answer([(0, 'Tea', 0.75), (2, 'Coffee', 0.10)], accepted: true, version: 'v2'), drinks, cls(drinks, 'Coffee'));
    expect(wrong.passed, isFalse);
  });
}
