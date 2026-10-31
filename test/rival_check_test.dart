import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:flutter_application_1/services/dynamic_sign_judge.dart';

List<dynamic> tpl(String l) => jsonDecode(File('test/fixtures/$l.json').readAsStringSync()) as List;

/// Template points placed in the image like a hand would be.
Hand handOf(String l) => Hand([
      for (final p in tpl(l))
        Landmark(0.5 + (p['x'] as num).toDouble() * 0.12, 0.6 + (p['y'] as num).toDouble() * 0.12,
            ((p['z'] ?? 0) as num).toDouble() * 0.12)
    ]);

/// Verdict of the shared letter checks after holding [shown] in the
/// [target] practice for 2 s of frames (null = passes the checks).
Future<String?> judge(String target, String shown) async {
  final c = StaticLetterChecker();
  String? last;
  for (var i = 0; i < 60; i++) {
    last = c.check(handOf(shown), target, imageWidth: 640, imageHeight: 640, rotation: 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return last;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    for (final l in 'ABCDEFGHIKLMNOPQRSTUVWXY'.split('')) {
      TemplateStore.debugPut('alphabet', l, tpl(l));
    }
  });

  for (final (target, shown, shouldPass) in [
    ('M', 'M', true), ('M', 'N', false), ('N', 'N', true), ('N', 'M', false),
    ('T', 'T', true), ('T', 'X', false), ('X', 'X', true), ('K', 'K', true),
    ('X', 'T', false), ('U', 'V', false), ('V', 'U', false), ('K', 'V', false), ('K', 'L', false),
    ('P', 'Q', false), ('Q', 'P', false), ('B', 'C', false), ('C', 'B', false), ('C', 'O', false),
    ('L', 'I', false), ('Y', 'I', false), ('A', 'S', false), ('A', 'N', false), ('S', 'A', false),
    ('E', 'F', false), ('F', 'E', false), ('D', 'L', false),
  ]) {
    test('$shown shown in $target practice -> ${shouldPass ? 'passes' : 'rejected'}', () async {
      final v = await judge(target, shown);
      if (shouldPass) {
        expect(v, isNull, reason: 'rejected: $v');
      } else {
        expect(v, isNotNull, reason: '$shown passed the $target checks');
      }
    });
  }

  // Every letter's own template must pass its own checks (no false negative
  // built into a rule).
  for (final l in 'ABCDEFGHIKLMNOPQRSTUVWXY'.split('')) {
    test('$l template passes the $l checks', () async {
      final v = await judge(l, l);
      expect(v, isNull, reason: 'rejected: $v');
    });
  }

  // The real loading path (no Firebase in tests: Storage fails, no bundled
  // copy) must finish, not hang.
  test('TemplateStore.load finishes for a template that does not exist', () async {
    final t = await TemplateStore.load('alphabet', 'ZZ').timeout(const Duration(seconds: 20));
    expect(t, isNull);
  });
}
