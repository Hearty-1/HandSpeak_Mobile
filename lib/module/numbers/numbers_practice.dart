import 'package:flutter/material.dart';

import 'numbers_tutorial_practice.dart';

/// Continuous practice for Numbers, like the phrases (phrase_practice.dart)
/// and civic (civic_practice.dart) continuous practice: the numbers 1-100
/// come one after another, each success gives practice XP and moves on, Skip
/// moves on without XP, and after 100 it starts again.
///
/// Every number is recognised and reported exactly as in the numbers
/// tutorial (NumbersTutorialPractice in continuous mode): templates for
/// 1-10, the decade models with the start / end handshape checks and
/// whole-sign capture for 11-100, and the shared feedback card.
class NumbersPractice extends StatefulWidget {
  const NumbersPractice({super.key});

  @override
  State<NumbersPractice> createState() => _NumbersPracticeState();
}

class _NumbersPracticeState extends State<NumbersPractice> {
  static const int _count = 100;
  int _currentIdx = 0;

  void _next() {
    if (!mounted) return;
    setState(() => _currentIdx = (_currentIdx + 1) % _count);
  }

  @override
  Widget build(BuildContext context) {
    final number = '${_currentIdx + 1}';
    return NumbersTutorialPractice(
      // A new key per number: each one gets a fresh capture pipeline and model.
      key: ValueKey('numbers_practice_$_currentIdx'),
      targetNumber: number,
      continuous: true,
      onMastered: _next,
      onSkip: _next,
      progressLabel: 'Number $number of $_count',
    );
  }
}
