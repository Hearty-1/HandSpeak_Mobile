import 'package:flutter/material.dart';

import 'civic_tutorial_interface.dart' show LupangLines;
import 'civic_tutorial_practice.dart';

/// Continuous practice for Civic Observances (Lupang Hinirang), like the
/// alphabet (practice.dart), numbers (numbers_practice.dart) and phrases
/// (phrase_practice.dart) continuous practice: the 21 lines come one after
/// another, each success gives XP and moves on to the next line, Skip moves
/// on without XP, and after the last line it starts again.
///
/// The lines are moving signs, so each one is recorded and evaluated by the
/// Lupang Hinirang model on the server, with the same capture as the civic
/// tutorial (CivicTutorialPractice in continuous mode, one camera session
/// for the whole run).
class CivicPractice extends StatelessWidget {
  const CivicPractice({super.key});

  @override
  Widget build(BuildContext context) {
    return const CivicTutorialPractice(
      category: LupangLines.category, // all lines of labels_lupang_hinirang.json
      continuous: true,
      continuousXp: 10,
    );
  }
}
