import 'package:flutter/material.dart';

import '/module/tutorial_session_practice.dart';

/// Continuous practice for Numbers 1-100, checked like the Hard camera
/// activities (1-10 CAPTURE & CHECK, 11-100 RECORD SIGN), with ◀ / ▶ and
/// the session stored in the Practice Sessions (tutorial_session_practice.dart).
class NumbersPractice extends StatelessWidget {
  const NumbersPractice({super.key});

  @override
  Widget build(BuildContext context) => TutorialSessionPractice(
        title: 'Numbers Practice',
        category: 'numbers',
        categoryName: 'Numbers',
        xpField: 'numbersXp',
        signs: [for (var n = 1; n <= 100; n++) PracticeSign('$n')],
      );
}
