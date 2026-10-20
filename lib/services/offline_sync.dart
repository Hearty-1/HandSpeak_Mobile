import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

/// Online / offline state of the device (checked by reaching Firestore's
/// host every few seconds and whenever the app comes back to the
/// foreground).
class ConnectivityService with WidgetsBindingObserver {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  /// true while the internet is reachable.
  final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  /// Briefly true after coming back online once everything saved offline has
  /// reached the server ("All caught up").
  final ValueNotifier<bool> justSynced = ValueNotifier<bool>(false);

  Timer? _timer;
  bool _checking = false;
  bool _pending = false; // progress saved while offline, not yet on the server

  static bool get isOnline => instance.online.value;

  void start() {
    if (_timer != null) return;
    WidgetsBinding.instance.addObserver(this);
    unawaited(check());
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  /// Call after saving progress while offline.
  void markPending() => _pending = true;

  Future<bool> check() async {
    if (_checking) return online.value;
    _checking = true;
    bool ok;
    try {
      final r = await InternetAddress.lookup('firestore.googleapis.com').timeout(const Duration(seconds: 4));
      ok = r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      ok = false;
    }
    _checking = false;
    final wasOffline = !online.value;
    online.value = ok;
    if (ok && wasOffline) unawaited(_onBackOnline());
    return ok;
  }

  Future<void> _onBackOnline() async {
    final hadPending = _pending;
    try {
      // Firestore sends the writes queued while offline by itself; this
      // completes once they are all on the server.
      await FirebaseFirestore.instance.waitForPendingWrites().timeout(const Duration(seconds: 60));
      _pending = false;
      if (hadPending) {
        justSynced.value = true;
        await Future.delayed(const Duration(seconds: 4));
        justSynced.value = false;
      }
    } catch (e) {
      debugPrint('[Sync] pending writes not confirmed yet: $e');
    }
  }
}

/// Transaction-like access for [OfflineSync.run]: the same code runs inside a
/// real Firestore transaction when online, or against the phone's cached
/// copy (with writes queued for later) when offline.
abstract class SyncTx {
  Future<DocumentSnapshot<Map<String, dynamic>>> get(DocumentReference<Map<String, dynamic>> ref);
  void set(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data, [SetOptions? options]);
  void update(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data);
}

class _OnlineTx implements SyncTx {
  final Transaction tx;
  _OnlineTx(this.tx);

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(DocumentReference<Map<String, dynamic>> ref) => tx.get(ref);

  @override
  void set(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data, [SetOptions? options]) =>
      tx.set(ref, data, options);

  @override
  void update(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) => tx.update(ref, data);
}

class _OfflineTx implements SyncTx {
  final WriteBatch batch;
  _OfflineTx(this.batch);

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      // Not cached yet: read through the normal path (returns quickly offline).
      return ref.get();
    }
  }

  @override
  void set(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data, [SetOptions? options]) =>
      batch.set(ref, data, options);

  @override
  void update(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) =>
      batch.set(ref, data, SetOptions(merge: true));
}

/// Saves progress whether or not the phone is online.
///
/// Firestore keeps a copy of the user's data on the phone (persistence is on,
/// see main.dart), but transactions only work online, so XP / stars /
/// mastery earned offline used to be lost. [run] uses a transaction when
/// online and otherwise applies the same writes to the local copy at once
/// (the app shows them immediately) and queues them; Firestore sends them
/// when the internet is back.
class OfflineSync {
  static Future<T> run<T>(Future<T> Function(SyncTx tx) body, {FirebaseFirestore? db}) async {
    final fs = db ?? FirebaseFirestore.instance;
    if (ConnectivityService.isOnline) {
      try {
        return await fs.runTransaction<T>((t) => body(_OnlineTx(t))).timeout(const Duration(seconds: 12));
      } on FirebaseException catch (e) {
        if (e.code != 'unavailable' && e.code != 'deadline-exceeded') rethrow;
        unawaited(ConnectivityService.instance.check());
      } on TimeoutException {
        unawaited(ConnectivityService.instance.check());
      }
    }
    final batch = fs.batch();
    final result = await body(_OfflineTx(batch));
    // Applied locally right away; completes when it reaches the server, so
    // it is not awaited.
    unawaited(batch.commit().catchError((e) => debugPrint('[Sync] queued write failed: $e')));
    ConnectivityService.instance.markPending();
    debugPrint('[Sync] saved offline; will sync when back online');
    return result;
  }
}
