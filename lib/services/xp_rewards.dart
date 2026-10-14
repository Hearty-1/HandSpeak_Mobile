/// XP plan: fixed XP per action type, the same in every category and not
/// changed when content is added (more content = more XP available).
///
///   tutorial sign, first mastery            20 XP
///   continuous practice sign, first success 10 XP
///   activity level, each NEW star           10 XP
///   any repeat (mastered sign / replayed
///   level without new stars)                 3 XP, at most 50 XP per
///                                            category per day
///
/// First completions give full XP; repeats still reward practice but cannot
/// be farmed (daily cap, ProgressService). XP feeds leaderboards, daily
/// quests, the overall level and the module XP shown in each category.
class XpRewards {
  XpRewards._();

  /// Module XP that completes a module and unlocks the next (module.dart).
  static const int moduleGoal = 1000;

  static const int tutorialSign = 20;
  static const int practiceSign = 10;
  static const int activityStar = 10;

  /// XP for repeating something already completed, and the daily cap of
  /// that repeat XP per category (per module XP field, e.g. 'alphabetXp').
  static const int repeat = 3;
  static const int repeatDailyCap = 50;

  // Names used by the screens (same values in every category).
  static const int alphabetTutorial = tutorialSign;
  static const int numbersTutorial = tutorialSign;
  static const int phraseTutorial = tutorialSign;
  static const int civicTutorial = tutorialSign;

  static const int alphabetPractice = practiceSign;
  static const int numbersPractice = practiceSign;
  static const int phrasePractice = practiceSign;
  static const int civicPractice = practiceSign;

  /// Mastery record keys (users.tutorialMastery.<key>).
  static String practiceKey(String category) => 'practice_$category';
}
