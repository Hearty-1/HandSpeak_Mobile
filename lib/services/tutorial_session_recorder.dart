import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '/services/activity_log.dart';
import 'package:flutter/foundation.dart';

/// "Practice Sessions": one Firestore document per continuous-practice run
/// (collection `practice_sessions`), for the web dashboard.
///
///   {
///     source: "practice", sessionId, userId, student, sectionId,
///     level: { levelId, category, difficulty, passMark },
///     modelVersion, modelVersions,
///     session: { startedAt, endedAt, durationSeconds, outcome },
///     results: { attempts, correct, wrong, accuracyPercent, averageScore },
///     mistakes: { noHands, wrongSign, nearMiss, lowScore },
///     signs: { "SIGN": { attempts, correct, accuracyPercent, averageScore,
///              handsDetected, totalDurationMs,
///              scoreBuckets: { low, borderline, good, strong },
///              confusedWith: { "PREDICTED": n }, mistakes: {...} } },
///     needsAttention, summary,
///     expireAt (endedAt + 90 days, Firestore TTL), updatedAt
///   }
///
/// The document is rewritten after every attempt ("in_progress") and closed
/// by [finish] ("completed"). Students only: guests and runs without an
/// attempt write nothing.
class TutorialSessionRecorder {
  TutorialSessionRecorder({required this.category, required this.levelId, this.difficulty = 'other', this.passMark = 70});

  static const String collection = 'practice_sessions';
  static const Duration keepFor = Duration(days: 90);

  final String category;
  final String levelId;
  final String difficulty;
  final double passMark;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final DateTime _startedAt = DateTime.now();
  late final String sessionId = _makeSessionId();
  late final Future<String?> _section = _loadSection();

  int _attempts = 0;
  int _correct = 0;
  double _scoreSum = 0;
  final Map<String, int> _mistakes = {'noHands': 0, 'wrongSign': 0, 'nearMiss': 0, 'lowScore': 0};
  final Map<String, _SignStats> _signs = {};
  final Set<String> _models = {};
  bool _finished = false;

  User? get _user {
    final u = FirebaseAuth.instance.currentUser;
    return u == null || u.isAnonymous ? null : u;
  }

  DocumentReference<Map<String, dynamic>> get _ref => _db.collection(collection).doc(sessionId);

  static String _two(int v) => v.toString().padLeft(2, '0');

  String _makeSessionId() {
    final d = _startedAt;
    final uid = _user?.uid ?? 'anon';
    final level = levelId.replaceAll(RegExp(r'[/\s]+'), '_');
    return 'practice_${d.year}-${_two(d.month)}-${_two(d.day)}_${_two(d.hour)}${_two(d.minute)}${_two(d.second)}'
        '_${level}_${uid.substring(0, uid.length < 6 ? uid.length : 6)}';
  }

  Future<String?> _loadSection() async {
    final uid = _user?.uid;
    if (uid == null) return null;
    try {
      final data = (await _db.collection('users').doc(uid).get()).data();
      final s = (data?['section'] ?? data?['sectionId'] ?? '').toString().trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  /// Sign names as map keys: upper case, without the characters Firestore
  /// field names cannot hold.
  static String signKey(String sign) =>
      sign.trim().toUpperCase().replaceAll(RegExp(r'[./\[\]*`~]'), '_').replaceFirst(RegExp(r'^_+'), '');

  static double _round(double v) => double.parse(v.toStringAsFixed(1));

  /// Records one checked attempt. [score] is 0-100; [predicted] is the sign
  /// the model recognised (if any); [durationMs] the time from the sign (or
  /// its retry) appearing to the result.
  Future<void> recordAttempt({
    required String sign,
    required bool correct,
    required double score,
    required bool handsDetected,
    String? predicted,
    String? model,
    int durationMs = 0,
  }) async {
    if (_user == null || _finished) return;
    final s = score.clamp(0.0, 100.0).toDouble();
    final key = signKey(sign);
    final guess = (predicted ?? '').trim().isEmpty ? null : signKey(predicted!);
    String code = '';
    if (!correct) {
      if (!handsDetected) {
        code = 'noHands';
      } else if (guess != null && guess != key) {
        code = 'wrongSign';
      } else if (s >= passMark - 20) {
        code = 'nearMiss';
      } else {
        code = 'lowScore';
      }
      _mistakes[code] = _mistakes[code]! + 1;
    }
    _attempts++;
    if (correct) _correct++;
    _scoreSum += s;
    if (model != null && model.trim().isNotEmpty) _models.add(model.trim());
    _signs.putIfAbsent(key, () => _SignStats()).add(
          correct: correct,
          score: s,
          handsDetected: handsDetected,
          durationMs: durationMs < 0 ? 0 : durationMs,
          mistake: code,
          confusedWith: !correct && guess != null && guess != key ? guess : null,
        );
    await _write(outcome: 'in_progress');
  }

  /// Closes the session (screen left). Nothing is written without attempts.
  Future<void> finish() async {
    if (_finished) return;
    if (_attempts > 0) {
      await _write(outcome: 'completed');
      await ActivityLog.instance.log('practice.session_completed',
          category: ActivityCategory.practice,
          title: 'Practised ${ActivityLog.moduleName(category)}: $_correct of $_attempts correct',
          details: {'category': category, 'attempts': _attempts, 'correct': _correct, 'sessionId': sessionId});
    }
    _finished = true;
  }

  Future<void> _write({required String outcome}) async {
    final user = _user;
    if (user == null) return;
    try {
      await _ref.set(await _doc(user, outcome));
    } catch (e) {
      debugPrint('practice_sessions: session not saved: $e');
    }
  }

  Future<Map<String, dynamic>> _doc(User user, String outcome) async {
    final section = await _section;
    final now = DateTime.now();
    final wrong = _attempts - _correct;
    final acc = _attempts == 0 ? 0.0 : _correct / _attempts * 100;
    final models = _models.toList()..sort();
    final weakSign = _signs.values.any((s) => s.accuracy < passMark);
    const names = {'noHands': 'no hands', 'wrongSign': 'wrong sign', 'nearMiss': 'near miss', 'lowScore': 'low score'};
    final mistakeParts = [
      for (final e in _mistakes.entries)
        if (e.value > 0) '${e.value} ${names[e.key]}'
    ];
    return {
      'source': 'practice',
      'sessionId': sessionId,
      'userId': user.uid,
      'student': {
        'userId': user.uid,
        'name': user.displayName?.isNotEmpty == true ? user.displayName : (user.email ?? ''),
        'sectionId': section,
      },
      'sectionId': section,
      'level': {'levelId': levelId, 'category': category, 'difficulty': difficulty, 'passMark': passMark},
      if (models.isNotEmpty) 'modelVersion': models.first,
      'modelVersions': models,
      'session': {
        'startedAt': Timestamp.fromDate(_startedAt),
        'endedAt': Timestamp.fromDate(now),
        'durationSeconds': now.difference(_startedAt).inSeconds,
        'outcome': outcome,
      },
      'results': {
        'attempts': _attempts,
        'correct': _correct,
        'wrong': wrong,
        'accuracyPercent': _round(acc),
        'averageScore': _attempts == 0 ? 0 : _round(_scoreSum / _attempts),
      },
      'mistakes': Map<String, int>.from(_mistakes),
      'signs': {for (final e in _signs.entries) e.key: e.value.toMap()},
      'needsAttention': _attempts > 0 && (acc < passMark || weakSign),
      'summary': '$_correct of $_attempts correct (${acc.round()}%)'
          '${mistakeParts.isEmpty ? '' : ' · ${mistakeParts.join(', ')}'} · $outcome',
      'expireAt': Timestamp.fromDate(now.add(keepFor)),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class _SignStats {
  int attempts = 0;
  int correct = 0;
  double scoreSum = 0;
  int handsDetected = 0;
  int totalDurationMs = 0;
  final Map<String, int> buckets = {'low': 0, 'borderline': 0, 'good': 0, 'strong': 0};
  final Map<String, int> confusedWith = {};
  final Map<String, int> mistakes = {};

  double get accuracy => attempts == 0 ? 0 : correct / attempts * 100;

  void add({
    required bool correct,
    required double score,
    required bool handsDetected,
    required int durationMs,
    required String mistake,
    String? confusedWith,
  }) {
    attempts++;
    if (correct) this.correct++;
    scoreSum += score;
    if (handsDetected) this.handsDetected++;
    totalDurationMs += durationMs;
    // <50 / 50-69 / 70-84 / 85+
    final b = score < 50 ? 'low' : (score < 70 ? 'borderline' : (score < 85 ? 'good' : 'strong'));
    buckets[b] = buckets[b]! + 1;
    if (confusedWith != null) this.confusedWith[confusedWith] = (this.confusedWith[confusedWith] ?? 0) + 1;
    if (mistake.isNotEmpty) mistakes[mistake] = (mistakes[mistake] ?? 0) + 1;
  }

  Map<String, dynamic> toMap() => {
        'attempts': attempts,
        'correct': correct,
        'accuracyPercent': TutorialSessionRecorder._round(accuracy),
        'averageScore': attempts == 0 ? 0 : TutorialSessionRecorder._round(scoreSum / attempts),
        'handsDetected': handsDetected,
        'totalDurationMs': totalDurationMs,
        'scoreBuckets': Map<String, int>.from(buckets),
        'confusedWith': Map<String, int>.from(confusedWith),
        'mistakes': Map<String, int>.from(mistakes),
      };
}
