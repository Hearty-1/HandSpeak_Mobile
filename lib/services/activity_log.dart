import 'dart:io' show Platform;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// What kind of thing happened (filters and icons in Settings > Activity Logs).
enum ActivityCategory { auth, learning, practice, activity, challenge, achievement, account }

/// The user's activity log: an audit-style record of what they do in the
/// app, shown live in Settings > Session & Activity Logs.
///
/// users/{uid}/activity_logs/{eventId}
///   schemaVersion  1
///   eventId        unique id (also the document id: retries never duplicate)
///   eventType      dotted name, e.g. "auth.login", "activity.completed"
///   category       auth | learning | practice | activity | challenge | achievement | account
///   title          short text shown in the log, e.g. "Completed Alphabet Easy 2"
///   details        small map of non-personal facts (level, stars, score...)
///   timestamp      server time (ordering, trustworthy)
///   clientTime     device time (when it happened, also offline)
///   sessionId      one id per app launch (groups a sitting)
///   platform       android | ios | web ...; device: model name
///   expireAt       timestamp + 365 days (Firestore TTL deletes old entries)
///
/// Data minimisation: no email, name, location, IP or device identifiers;
/// details carry only learning facts. Guests are not logged. Writing never
/// blocks or breaks the app (offline writes are queued by Firestore).
class ActivityLog {
  ActivityLog._();
  static final ActivityLog instance = ActivityLog._();

  static const String collection = 'activity_logs';
  static const int schemaVersion = 1;
  static const Duration keepFor = Duration(days: 365);

  /// The same event within this window is recorded once (double taps,
  /// screens rebuilt).
  static const Duration _dedupeWindow = Duration(seconds: 30);

  final String sessionId = _randomId();
  final Map<String, DateTime> _recent = {};
  Future<String>? _device;

  static String _randomId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }

  Future<String> _deviceModel() => _device ??= () async {
        try {
          if (kIsWeb) return 'browser';
          final info = DeviceInfoPlugin();
          if (Platform.isAndroid) {
            final a = await info.androidInfo;
            return '${a.manufacturer} ${a.model}'.trim();
          }
          if (Platform.isIOS) return (await info.iosInfo).utsname.machine;
        } catch (_) {}
        return 'unknown';
      }();

  /// Records one event for the signed-in student. [dedupeKey] distinguishes
  /// events of the same type (e.g. the module opened).
  Future<void> log(
    String eventType, {
    required ActivityCategory category,
    required String title,
    Map<String, Object?> details = const {},
    String? dedupeKey,
    String? uid,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final id = uid ?? (user == null || user.isAnonymous ? null : user.uid);
    if (id == null) return;
    final now = DateTime.now();
    final key = '$id|$eventType|${dedupeKey ?? title}';
    final last = _recent[key];
    if (last != null && now.difference(last) < _dedupeWindow) return;
    _recent[key] = now;
    if (_recent.length > 200) _recent.remove(_recent.keys.first);

    final eventId = '${now.millisecondsSinceEpoch}_${_randomId().substring(0, 8)}';
    try {
      await FirebaseFirestore.instance.collection('users').doc(id).collection(collection).doc(eventId).set({
        'schemaVersion': schemaVersion,
        'eventId': eventId,
        'eventType': eventType,
        'category': category.name,
        'title': title,
        'details': {
          for (final e in details.entries)
            if (e.value != null) e.key: e.value,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'clientTime': Timestamp.fromDate(now),
        'sessionId': sessionId,
        'platform': _platform,
        'device': await _deviceModel(),
        'expireAt': Timestamp.fromDate(now.add(keepFor)),
      });
    } catch (e) {
      debugPrint('activity log: not saved ($eventType): $e');
    }
  }

  /// Display name of a module / category key ("phrases" -> "Greetings").
  static String moduleName(String key) {
    final k = key.trim().toLowerCase();
    if (k.startsWith('practice_')) return moduleName(k.substring(9));
    if (k.startsWith('alphabet')) return 'Alphabet';
    if (k.startsWith('number')) return 'Numbers';
    if (k.startsWith('phrase') || k.startsWith('greeting')) return 'Greetings';
    if (k.startsWith('civic')) return 'Civic';
    if (k.isEmpty) return 'a module';
    return k.split(RegExp(r'[_\s]+')).where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  /// "alphabet_easy_2" -> "Alphabet Easy 2".
  static String levelName(String levelId) {
    final m = RegExp(r'^(.*?)_(easy|medium|hard)_(\d+)$').firstMatch(levelId.trim());
    if (m == null) return moduleName(levelId);
    final d = m.group(2)!;
    return '${moduleName(m.group(1)!)} ${d[0].toUpperCase()}${d.substring(1)} ${m.group(3)}';
  }

  /// Latest entries, newest first (Settings).
  static Stream<QuerySnapshot<Map<String, dynamic>>> stream(String uid, {int limit = 100}) => FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection(collection)
      .orderBy('clientTime', descending: true)
      .limit(limit)
      .snapshots();
}
