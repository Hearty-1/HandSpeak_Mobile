import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Camera-sign analytics, organised so each play session reads like a report.
///
/// gesture_attempts/{sessionId}            one document per play session
///   id:       2026-10-07_2125_alphabet_hard_2_mFPxzo   (date_time_level_user)
///   summary:  "3 of 5 correct (60%) · 2 low score · completed"
///   student   { userId, name }
///   level     { category, levelId, difficulty, passMark }
///   session   { startedAt, endedAt, durationSeconds, outcome, heartsLeft, starsEarned, questions }
///   results   { attempts, correct, wrong, accuracyPercent, averageScore, averageConfidencePercent }
///   mistakes  { noHands, wrongSign, nearMiss, lowScore }
///   signs     { L: { attempts, correct, accuracyPercent, averageScore, mistakes } , ... }
///   needsAttention [ "L — failed 2 times in this session (student needs practice)", ... ]
///
///   attempts/{01_Q1_L_try1}                every single attempt of that session
///     order, question, sign, try, result ("correct" | "wrong"), score, passMark,
///     mistake (plain words), mistakeCode, howJudged, handsDetected, time
///     model { confidencePercent, recognizedAs, framesRecorded }   dynamic signs only
///
/// gesture_level_stats/{levelId}           running totals over ALL students
///   level { ... }, attempts, correct, scoreSum, mistakes { ... },
///   signs { L: { attempts, correct, scoreSum, mistakes { ... } } }
///   A sign that most students fail -> likely a MODEL problem; a sign one
///   student fails while others pass -> that STUDENT needs practice. Each
///   session's `needsAttention` already applies this comparison.
class GestureAttemptTracker {
  final String category; // alphabet | numbers | ...
  final String levelId;
  final String difficulty;
  final double threshold; // pass mark, 0..100

  GestureAttemptTracker({
    required this.category,
    required this.levelId,
    required this.threshold,
    String? difficulty,
  }) : difficulty = difficulty ?? _difficultyOf(levelId);

  static String _difficultyOf(String levelId) {
    final l = levelId.toLowerCase();
    if (l.contains('hard')) return 'hard';
    if (l.contains('medium') || l.contains('average')) return 'medium';
    if (l.contains('easy')) return 'easy';
    return 'other';
  }

  // ------------------------------------------------------------- mistakes ---
  static const Map<String, String> mistakeText = {
    'noHands': 'No hands: no hand was in view',
    'wrongSign': 'Wrong sign: the model recognised a different sign',
    'nearMiss': 'Near miss: right sign, slightly off (within 15 points of passing)',
    'lowScore': 'Low score: handshape or movement clearly off',
  };
  static const Map<String, String> howJudgedText = {
    'check': 'Pressed CHECK',
    'auto_hold': 'Held the sign (auto)',
    'auto_recording': 'Motion recording (auto)',
  };
  static const double _nearMissBand = 15.0;
  static const int _repeatedErrorMin = 2;

  // -------------------------------------------------------------- session ---
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final DateTime _startedAt = DateTime.now();
  late final String sessionId = _makeSessionId();
  bool _finished = false;
  String _outcome = 'in progress';
  int? _heartsLeft, _starsEarned, _questions;
  DateTime _lastActivity = DateTime.now();

  int _order = 0, _correct = 0, _dynamicCount = 0;
  double _scoreSum = 0, _confidenceSum = 0;
  final Map<String, int> _triesPerQuestion = {};
  final Map<String, int> _mistakes = {'noHands': 0, 'wrongSign': 0, 'nearMiss': 0, 'lowScore': 0};
  final Map<String, _SignStats> _signs = {};

  User? get _user => FirebaseAuth.instance.currentUser;
  DocumentReference<Map<String, dynamic>> get _sessionRef => _db.collection('gesture_attempts').doc(sessionId);
  DocumentReference<Map<String, dynamic>> get _statsRef =>
      _db.collection('gesture_level_stats').doc(levelId.replaceAll('/', '_'));

  static String _two(int v) => v.toString().padLeft(2, '0');

  String _makeSessionId() {
    final d = _startedAt;
    final uid = _user?.uid ?? 'anon';
    return '${d.year}-${_two(d.month)}-${_two(d.day)}_${_two(d.hour)}${_two(d.minute)}${_two(d.second)}'
        '_${levelId}_${uid.substring(0, uid.length < 6 ? uid.length : 6)}';
  }

  static String _signKey(String sign) =>
      sign.toLowerCase().startsWith('http') ? sign : sign.trim().toUpperCase();

  /// Firestore map keys cannot contain '.', '/', '[', ']', '*', '`' or start with '__'.
  static String _fieldKey(String sign) =>
      _signKey(sign).replaceAll(RegExp(r'[./\[\]*`~]'), '_').replaceFirst(RegExp(r'^_+'), '');

  static double _round(double v, [int digits = 1]) => double.parse(v.toStringAsFixed(digits));

  static String _mistakeCode({
    required bool isCorrect,
    required bool handsDetected,
    required double score,
    required double threshold,
    String? predictedLabel,
    required String sign,
  }) {
    if (isCorrect) return '';
    if (!handsDetected) return 'noHands';
    if (predictedLabel != null && predictedLabel.isNotEmpty && predictedLabel.trim().toUpperCase() != _signKey(sign)) {
      return 'wrongSign';
    }
    if (score >= threshold - _nearMissBand) return 'nearMiss';
    return 'lowScore';
  }

  /// Records one attempt and refreshes the session report.
  /// [score] is 0..100; [confidence] (0..1 or 0..100) is the model's
  /// confidence for its own prediction (dynamic signs).
  Future<void> recordAttempt({
    required String sign,
    required String questionId,
    required bool isCorrect,
    required double score,
    int? questionIndex,
    bool isDynamic = false,
    double? confidence,
    String? predictedLabel,
    bool handsDetected = true,
    int? framesRecorded,
    String trigger = 'check',
  }) async {
    final user = _user;
    if (user == null) return;
    _lastActivity = DateTime.now();

    final s = score.isFinite ? score.clamp(0.0, 100.0).toDouble() : 0.0;
    final conf = confidence == null || !confidence.isFinite
        ? null
        : (confidence > 1.0 ? confidence / 100.0 : confidence).clamp(0.0, 1.0).toDouble();
    final tryNo = (_triesPerQuestion[questionId] ?? 0) + 1;
    _triesPerQuestion[questionId] = tryNo;
    final code = _mistakeCode(
        isCorrect: isCorrect, handsDetected: handsDetected, score: s, threshold: threshold,
        predictedLabel: predictedLabel, sign: sign);

    _order++;
    if (isCorrect) _correct++;
    _scoreSum += s;
    if (isDynamic && conf != null) {
      _dynamicCount++;
      _confidenceSum += conf;
    }
    if (code.isNotEmpty) _mistakes[code] = (_mistakes[code] ?? 0) + 1;
    _signs.putIfAbsent(_signKey(sign), () => _SignStats()).add(isCorrect: isCorrect, score: s, mistake: code);

    final q = (questionIndex ?? 0) + 1;
    final attemptId = '${_two(_order)}_Q${q}_${_fieldKey(sign)}_try$tryNo';
    final attempt = <String, dynamic>{
      'order': _order,
      'question': q,
      'sign': _signKey(sign),
      'try': tryNo,
      'result': isCorrect ? 'correct' : 'wrong',
      'score': _round(s),
      'passMark': threshold,
      if (!isCorrect) 'mistake': mistakeText[code],
      if (!isCorrect) 'mistakeCode': code,
      'howJudged': howJudgedText[trigger] ?? trigger,
      'handsDetected': handsDetected,
      'time': FieldValue.serverTimestamp(),
      if (isDynamic)
        'model': {
          if (conf != null) 'confidencePercent': _round(conf * 100),
          if (predictedLabel != null && predictedLabel.isNotEmpty) 'recognizedAs': predictedLabel,
          if (framesRecorded != null) 'framesRecorded': framesRecorded,
        },
    };

    try {
      await _sessionRef.collection('attempts').doc(attemptId).set(attempt);
      await _sessionRef.set(_sessionDoc(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('gesture_attempts: attempt not saved: $e');
    }
    unawaited(_bumpLevelStats(sign: sign, isCorrect: isCorrect, score: s, mistake: code));
  }

  /// The session report (rewritten after every attempt, final on [finish]).
  Map<String, dynamic> _sessionDoc({List<String>? needsAttention}) {
    final user = _user;
    final wrong = _order - _correct;
    final acc = _order == 0 ? 0.0 : _correct / _order * 100;
    final mistakeParts = [
      for (final e in _mistakes.entries)
        if (e.value > 0) '${e.value} ${const {'noHands': 'no hands', 'wrongSign': 'wrong sign', 'nearMiss': 'near miss', 'lowScore': 'low score'}[e.key]}'
    ];
    final now = DateTime.now();
    return {
      'summary': '$_correct of $_order correct (${acc.round()}%)'
          '${mistakeParts.isEmpty ? '' : ' · ${mistakeParts.join(', ')}'} · $_outcome',
      'student': {
        'userId': user?.uid,
        'name': user?.displayName?.isNotEmpty == true ? user!.displayName : (user?.email ?? ''),
      },
      'level': {'category': category, 'levelId': levelId, 'difficulty': difficulty, 'passMark': threshold},
      'session': {
        'startedAt': Timestamp.fromDate(_startedAt),
        'endedAt': Timestamp.fromDate(now),
        'durationSeconds': now.difference(_startedAt).inSeconds,
        'outcome': _outcome,
        if (_heartsLeft != null) 'heartsLeft': _heartsLeft,
        if (_starsEarned != null) 'starsEarned': _starsEarned,
        if (_questions != null) 'questions': _questions,
      },
      'results': {
        'attempts': _order,
        'correct': _correct,
        'wrong': wrong,
        'accuracyPercent': _round(acc),
        'averageScore': _round(_order == 0 ? 0 : _scoreSum / _order),
        if (_dynamicCount > 0) 'averageConfidencePercent': _round(_confidenceSum / _dynamicCount * 100),
      },
      'mistakes': Map<String, int>.from(_mistakes),
      'signs': {for (final e in _signs.entries) _fieldKey(e.key): e.value.toMap()},
      if (needsAttention != null) 'needsAttention': needsAttention,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Running totals for the level over all students (best-effort: skipped
  /// silently if the Firestore rules do not allow it).
  Future<void> _bumpLevelStats({required String sign, required bool isCorrect, required double score, required String mistake}) async {
    final k = _fieldKey(sign);
    final inc = FieldValue.increment;
    try {
      await _statsRef.set({
        'level': {'category': category, 'levelId': levelId, 'difficulty': difficulty},
        'attempts': inc(1),
        'correct': inc(isCorrect ? 1 : 0),
        'scoreSum': inc(score),
        if (mistake.isNotEmpty) 'mistakes': {mistake: inc(1)},
        'signs': {
          k: {
            'attempts': inc(1),
            'correct': inc(isCorrect ? 1 : 0),
            'scoreSum': inc(score),
            if (mistake.isNotEmpty) 'mistakes': {mistake: inc(1)},
          }
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('gesture_level_stats not updated (rules?): $e');
    }
  }

  /// Final report. [outcome]: completed | game_over | exited.
  Future<void> finish({required String outcome, int? heartsLeft, int? starsEarned, int? totalQuestions}) async {
    if (_finished) return;
    _finished = true;
    if (_user == null || _order == 0) return;
    _outcome = const {'completed': 'completed', 'game_over': 'out of hearts', 'exited': 'left early'}[outcome] ?? outcome;
    _heartsLeft = heartsLeft;
    _starsEarned = starsEarned;
    _questions = totalQuestions;

    // Compare this student with all students on the same level (if readable).
    Map<String, dynamic> global = {};
    try {
      global = Map<String, dynamic>.from(((await _statsRef.get()).data()?['signs'] as Map?) ?? {});
    } catch (_) {}
    final notes = <String>[];
    _signs.forEach((sign, st) {
      final misses = st.attempts - st.correct;
      final g = global[_fieldKey(sign)];
      final ga = g is Map ? (g['attempts'] as num?)?.toDouble() ?? 0 : 0.0;
      final gc = g is Map ? (g['correct'] as num?)?.toDouble() ?? 0 : 0.0;
      final globalAcc = ga > 0 ? gc / ga : null;
      if (globalAcc != null && ga >= 20 && globalAcc < 0.5) {
        notes.add('$sign — only ${(globalAcc * 100).round()}% of all attempts pass (${ga.round()} attempts): check the model');
      } else if (misses >= _repeatedErrorMin) {
        final cmp = globalAcc != null && ga >= 20 ? ', others pass ${(globalAcc * 100).round()}%' : '';
        notes.add('$sign — failed $misses times in this session$cmp: student needs practice');
      }
    });
    try {
      await _sessionRef.set(_sessionDoc(needsAttention: notes), SetOptions(merge: true));
    } catch (e) {
      debugPrint('gesture_attempts: session report not saved: $e');
    }
  }

  // ------------------------------------------- game / challenge screens ---
  static final Map<String, GestureAttemptTracker> _open = {};

  /// Session tracker for screens without a level start / end (games,
  /// challenges): one session per level, closed after 20 idle minutes.
  static GestureAttemptTracker forScreen({required String category, required String levelId, double threshold = 70}) {
    final key = '$category|$levelId';
    final t = _open[key];
    if (t != null && !t._finished && DateTime.now().difference(t._lastActivity) < const Duration(minutes: 20)) return t;
    final fresh = GestureAttemptTracker(category: category, levelId: levelId, threshold: threshold)
      .._outcome = 'played';
    _open[key] = fresh;
    return fresh;
  }
}

class _SignStats {
  int attempts = 0, correct = 0;
  double scoreSum = 0;
  final Map<String, int> mistakes = {};

  void add({required bool isCorrect, required double score, required String mistake}) {
    attempts++;
    if (isCorrect) correct++;
    scoreSum += score;
    if (mistake.isNotEmpty) mistakes[mistake] = (mistakes[mistake] ?? 0) + 1;
  }

  Map<String, dynamic> toMap() => {
        'attempts': attempts,
        'correct': correct,
        'accuracyPercent': double.parse((correct / attempts * 100).toStringAsFixed(1)),
        'averageScore': double.parse((scoreSum / attempts).toStringAsFixed(1)),
        if (mistakes.isNotEmpty) 'mistakes': mistakes,
      };
}
