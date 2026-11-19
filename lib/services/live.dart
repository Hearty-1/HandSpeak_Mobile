import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared Firestore live data for the screens.
///
/// A `StreamBuilder(stream: ref.snapshots())` inside build() opened a new
/// Firestore listener on every rebuild (XP change, presence heartbeat, theme
/// or language change): the screen flashed its spinner, and every reconnect
/// could be read again. [Live.doc] / [Live.query] instead give every screen
/// that asks for the same document or query ONE shared listener:
///  * a rebuilt screen gets the last value at once (no reconnect, no flicker);
///  * the listener stays open 30 s after the last screen leaves, so going
///    back and forth between screens costs nothing extra;
///  * then it closes (no listener left running in the background).
///
///   StreamBuilder(stream: Live.doc(db.collection('users').doc(uid)), ...)
///   StreamBuilder(stream: Live.query(db.collection('rooms').where(...)), ...)
class Live {
  Live._();

  static const Duration _keepOpen = Duration(seconds: 30);
  static final Map<String, _Shared<Object?>> _shared = {};

  /// A document, shared by its path.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> doc(DocumentReference<Map<String, dynamic>> ref) =>
      _stream<DocumentSnapshot<Map<String, dynamic>>>('doc:${ref.path}', ref.snapshots);

  /// A query, shared by its collection and filters.
  static Stream<QuerySnapshot<Map<String, dynamic>>> query(Query<Map<String, dynamic>> q) =>
      _stream<QuerySnapshot<Map<String, dynamic>>>('query:${_queryKey(q)}', q.snapshots);

  static String _queryKey(Query q) {
    final path = q is CollectionReference ? q.path : '';
    return '$path|${q.parameters}|${q.hashCode}';
  }

  static Stream<T> _stream<T>(String key, Stream<T> Function() open) {
    return Stream<T>.multi((listener) {
      final s = (_shared[key] ??= _Shared<T>()) as _Shared<T>;
      s.closeTimer?.cancel();
      s.listeners++;
      // The last value at once: a rebuilt screen keeps showing its data.
      final last = s.last;
      if (last != null) listener.add(last);
      final sub = s.out.stream.listen(listener.add, onError: listener.addError);
      s.source ??= open().listen(
        (v) {
          s.last = v;
          s.out.add(v);
        },
        onError: s.out.addError,
      );
      listener.onCancel = () {
        sub.cancel();
        if (--s.listeners > 0) return;
        s.closeTimer = Timer(_keepOpen, () {
          if (s.listeners > 0) return;
          s.source?.cancel();
          s.out.close();
          _shared.remove(key);
        });
      };
    });
  }
}

class _Shared<T> {
  final StreamController<T> out = StreamController<T>.broadcast();
  StreamSubscription<T>? source;
  T? last;
  int listeners = 0;
  Timer? closeTimer;
}
