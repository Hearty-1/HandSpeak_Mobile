import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// One sign of a published model: `classes[]` of the model document.
class PublishedGestureClass {
  final int index;
  final String key;
  final String label;

  /// Symbol of the tutorial lesson this class teaches (may be empty).
  final String lessonSymbol;

  /// Per-sign practice settings: the model's, with classes[].practice on top.
  final PracticeSettings practice;

  const PublishedGestureClass({
    required this.index,
    required this.key,
    required this.label,
    required this.lessonSymbol,
    this.practice = PracticeSettings.defaults,
  });

  PublishedGestureClass withPractice(PracticeSettings p) =>
      PublishedGestureClass(index: index, key: key, label: label, lessonSymbol: lessonSymbol, practice: p);

  /// Shown to the learner: label, else key.
  String get name => label.trim().isNotEmpty ? label.trim() : key.trim();
}

/// How a practice attempt is shaped and judged for a published model. Every
/// value can be set from the web app, so a newly trained model needs no app
/// update:
///
///   `published_gesture_models/{id}`.practice = { minConfidence, minSignShare,
///     minSignLead, minActiveS, minPoseCoverage, minHandCoverage,
///     maxOutOfFrame, marginMs, tightFirst }
///   `published_gesture_models/{id}`.classes[i].practice = { same keys }
///
/// The capture checks also read the training validation thresholds
/// (pipeline.thresholds: min_active_s, min_pose_coverage, ...), so a phone
/// clip is held to the same limits as the model's training videos.
class PracticeSettings {
  /// The top answer passes from this confidence.
  final double minConfidence;

  /// Or as the best SIGN (invalid class left out) with this share of the sign
  /// probability and this lead over the next sign.
  final double minSignShare;
  final double minSignLead;

  /// Capture checks (web validation thresholds).
  final double minActiveS;
  final double minPoseCoverage;
  final double minHandCoverage;
  final double maxOutOfFrame;

  /// Kept before / after the moving part of the capture.
  final int marginMs;

  /// Send the tight clip (the sign only, no margin) first: for signs whose
  /// training clips have no rest around the sign (activeS = durationS).
  final bool tightFirst;

  /// Length (s) of this sign's training clips, rest included (median of the
  /// uploaded samples, e.g. 1.8 s for Calendar, 4.05 s for Drinks). The
  /// practice capture is cut to the same length around the sign, so the sign
  /// fills the same share of the model's 32 time steps as in training.
  /// 0 = unknown: cut to the sign plus [marginMs].
  final double clipS;

  const PracticeSettings({
    this.minConfidence = 0.70,
    this.minSignShare = 0.20,
    this.minSignLead = 0.10,
    this.minActiveS = 0.75,
    this.minPoseCoverage = 0.8,
    this.minHandCoverage = 0.8,
    this.maxOutOfFrame = 0.2,
    this.marginMs = 400,
    this.tightFirst = false,
    this.clipS = 0,
  });

  static const PracticeSettings defaults = PracticeSettings();

  /// These settings with the values given in [m] (camelCase keys, or the
  /// snake_case names of the web's validation thresholds).
  PracticeSettings merge(Object? m) {
    if (m is! Map) return this;
    double d(List<String> keys, double v) {
      for (final k in keys) {
        final x = m[k];
        if (x is num && x.isFinite && x >= 0) return x.toDouble();
      }
      return v;
    }

    return PracticeSettings(
      minConfidence: d(['minConfidence', 'min_confidence'], minConfidence),
      minSignShare: d(['minSignShare', 'min_sign_share'], minSignShare),
      minSignLead: d(['minSignLead', 'min_sign_lead'], minSignLead),
      minActiveS: d(['minActiveS', 'min_active_s'], minActiveS),
      minPoseCoverage: d(['minPoseCoverage', 'min_pose_coverage'], minPoseCoverage),
      minHandCoverage: d(['minHandCoverage', 'min_hand_coverage'], minHandCoverage),
      maxOutOfFrame: d(['maxOutOfFrame', 'max_out_of_frame'], maxOutOfFrame),
      marginMs: d(['marginMs', 'margin_ms'], marginMs.toDouble()).round(),
      tightFirst: m['tightFirst'] is bool ? m['tightFirst'] as bool : tightFirst,
      clipS: d(['clipS', 'clip_s'], clipS),
    );
  }
}

/// A model an administrator published for a category from the web app
/// (Firestore `published_gesture_models/<modelId>`), served by Cloud Run at
/// `POST <serviceUrl>/v1/predict_raw/<modelId>`.
class PublishedGestureModel {
  final String modelId;
  final String serviceUrl;
  final String name;
  final String category;
  final int? invalidIndex;
  final String modelVersion;
  final List<PublishedGestureClass> classes;

  /// Model-wide practice settings (see [PracticeSettings]).
  final PracticeSettings practice;

  const PublishedGestureModel({
    required this.modelId,
    required this.serviceUrl,
    required this.name,
    required this.category,
    required this.invalidIndex,
    required this.modelVersion,
    required this.classes,
    this.practice = PracticeSettings.defaults,
  });

  /// Ids the web app gives published models: gs_<16 hex>.
  static final RegExp idPattern = RegExp(r'^gs_[0-9a-f]{16}$');

  /// Tuning for signs measured on phones, used until the web app sets
  /// classes[].practice for them. Setyembre (calendar, phone tests
  /// 2026-10-30): its training clips are the sign only (activeS = durationS
  /// = 2.08 s), and when the model is right it gives it only ~1/4 of the sign
  /// probability (24 % with a 12-point lead), less than the other months.
  static const Map<String, Map<String, Object>> _phoneTuning = {
    'setyembre': {'minSignShare': 0.15, 'tightFirst': true},
    'septyembre': {'minSignShare': 0.15, 'tightFirst': true},
    'setiyembre': {'minSignShare': 0.15, 'tightFirst': true},
    'september': {'minSignShare': 0.15, 'tightFirst': true},
  };

  static PublishedGestureModel? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null || d['active'] != true) return null;
    final id = (d['modelId'] ?? doc.id).toString().trim();
    if (!idPattern.hasMatch(id)) return null;
    // Model-wide: the training validation thresholds, then practice overrides.
    final pipeline = d['pipeline'];
    final practice = PracticeSettings.defaults
        .merge(pipeline is Map ? pipeline['thresholds'] : null)
        .merge(d['thresholds'])
        .merge(d['practice']);
    final classes = <PublishedGestureClass>[];
    final raw = d['classes'];
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final c = raw[i];
        if (c is! Map) continue;
        classes.add(PublishedGestureClass(
          index: (c['index'] as num?)?.toInt() ?? i,
          key: (c['key'] ?? '').toString(),
          label: (c['label'] ?? '').toString(),
          lessonSymbol: (c['lessonSymbol'] ?? '').toString(),
          practice: practice
              .merge(_phoneTuning[_norm('${c['label'] ?? ''}')] ?? _phoneTuning[_norm('${c['key'] ?? ''}')])
              .merge(c['practice']),
        ));
      }
    }
    if (classes.isEmpty) return null;
    return PublishedGestureModel(
      modelId: id,
      serviceUrl: (d['serviceUrl'] ?? '').toString().trim(),
      name: (d['name'] ?? id).toString(),
      category: (d['category'] ?? '').toString(),
      invalidIndex: (d['invalidIndex'] as num?)?.toInt(),
      modelVersion: (d['modelVersion'] ?? '').toString(),
      classes: classes,
      practice: practice,
    );
  }

  PublishedGestureModel withClasses(List<PublishedGestureClass> c) => PublishedGestureModel(
        modelId: modelId,
        serviceUrl: serviceUrl,
        name: name,
        category: category,
        invalidIndex: invalidIndex,
        modelVersion: modelVersion,
        classes: c,
        practice: practice,
      );

  PublishedGestureClass? classAt(int index) {
    for (final c in classes) {
      if (c.index == index) return c;
    }
    return null;
  }

  static String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), ' ');

  /// The class a lesson teaches: by lessonSymbol, else (a class without a
  /// lessonSymbol) by its key or label. Null when the model has no such sign.
  PublishedGestureClass? classForLesson(Iterable<String> lessonNames) {
    final names = {for (final n in lessonNames) if (n.trim().isNotEmpty) _norm(n)};
    if (names.isEmpty) return null;
    for (final c in classes) {
      if (c.index == invalidIndex) continue;
      if (c.lessonSymbol.trim().isNotEmpty && names.contains(_norm(c.lessonSymbol))) return c;
    }
    for (final c in classes) {
      if (c.index == invalidIndex || c.lessonSymbol.trim().isNotEmpty) continue;
      if (names.contains(_norm(c.key)) || names.contains(_norm(c.label))) return c;
    }
    return null;
  }
}

/// Published models by category, read once per app session.
class PublishedGestureModels {

  /// The active published model of [categoryId] (also tried in lower case),
  /// or null when there is none, it is inactive, or Firestore cannot be read
  /// (offline). A failed read is not cached, so it is tried again later.
  /// Categories whose published model is switched off in the app (testing):
  /// they practise without a model, as before one was published. Remove an
  /// entry to connect the model again.
  /// (activity_categories document ids, lower case: practice2final = Calendar.)
  static const Set<String> disconnected = {};

  static Future<PublishedGestureModel?> forCategory(String categoryId) {
    final id = categoryId.trim();
    if (id.isEmpty || disconnected.contains(id.toLowerCase())) return Future.value(null);
    _watch(id);
    final model = _latest.containsKey(id)
        ? Future.value(_latest[id])
        : _first[id]!.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
    return model.then((m) => m == null ? null : _withTrainingShape(m));
  }

  // ---- training clip shape ----------------------------------------------------

  static final Map<String, Future<PublishedGestureModel>> _shaped = {};

  /// [m] with each sign's training clip length (PracticeSettings.clipS), the
  /// median durationS of the category's validated training samples
  /// (gesture_training_samples.validation.metrics). Every gesture set records
  /// its clips differently (Calendar: ~1.8 s, the sign with a short rest;
  /// Drinks: 4 s, ~1.5 s of signing in the middle), and the server resamples
  /// the whole clip to 32 steps, so the phone's clip must have the same length
  /// around the sign. A clipS set on the web (practice / classes[].practice)
  /// wins. Read once per model version; on failure the model is used as is.
  static Future<PublishedGestureModel> _withTrainingShape(PublishedGestureModel m) {
    final key = '${m.modelId}|${m.modelVersion}';
    return _shaped[key] ??= _readTrainingShape(m).catchError((Object e) {
      debugPrint('Training clip shape for ${m.modelId} not read: $e');
      _shaped.remove(key);
      return m;
    });
  }

  static Future<PublishedGestureModel> _readTrainingShape(PublishedGestureModel m) async {
    if (m.category.isEmpty || m.classes.every((c) => c.practice.clipS > 0)) return m;
    final snap = await FirebaseFirestore.instance
        .collection('gesture_training_samples')
        .where('category', isEqualTo: m.category)
        .limit(2000)
        .get();
    final byClass = <String, List<double>>{};
    final all = <double>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['status'] != 'valid') continue;
      final v = d['validation'];
      final metrics = v is Map ? v['metrics'] : null;
      final dur = metrics is Map ? metrics['durationS'] : null;
      if (dur is! num || dur <= 0) continue;
      all.add(dur.toDouble());
      for (final k in [d['classKey'], d['classLabel']]) {
        if (k != null && '$k'.trim().isNotEmpty) (byClass['$k'.trim()] ??= []).add(dur.toDouble());
      }
    }
    if (all.isEmpty) return m;
    double median(List<double> xs) => (List.of(xs)..sort())[xs.length ~/ 2];
    final overall = median(all);
    final classes = [
      for (final c in m.classes)
        c.practice.clipS > 0
            ? c
            : c.withPractice(c.practice.merge({'clipS': median(byClass[c.key] ?? byClass[c.label] ?? all)})),
    ];
    debugPrint('Training clip length for ${m.modelId}: median ${overall.toStringAsFixed(2)} s '
        '(${all.length} samples; ${[for (final c in classes) '${c.name} ${c.practice.clipS.toStringAsFixed(2)}'].join(', ')})');
    return m.withClasses(classes);
  }

  // A live Firestore listener per category: a model published, replaced or
  // switched off on the web reaches the app within seconds, without a restart.
  static final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs = {};
  static final Map<String, PublishedGestureModel?> _latest = {};
  static final Map<String, Completer<PublishedGestureModel?>> _first = {};

  static void _watch(String id) {
    if (_subs.containsKey(id)) return;
    final first = _first[id] = Completer<PublishedGestureModel?>();
    void done(PublishedGestureModel? m) {
      if (!first.isCompleted) first.complete(m);
    }

    _subs[id] = FirebaseFirestore.instance
        .collection('published_gesture_models')
        .where('category', whereIn: {id, id.toLowerCase()}.toList())
        .where('active', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      final docs = [...snap.docs]..sort((a, b) => _time(b.data()).compareTo(_time(a.data())));
      final models = [for (final d in docs) PublishedGestureModel.fromDoc(d)].whereType<PublishedGestureModel>().toList();
      // Offline with nothing cached: no answer yet, wait for the server.
      if (models.isEmpty && snap.metadata.isFromCache) {
        done(null);
        return;
      }
      final model = models.isEmpty ? null : models.first;
      if (models.length > 1) {
        debugPrint('Several active published models for $id: ${models.map((m) => m.modelId)}; using the newest, ${model!.modelId}');
      }
      if (_latest[id]?.modelId != model?.modelId) debugPrint('Published model for $id: ${model?.modelId ?? 'none'}');
      _latest[id] = model;
      done(model);
    }, onError: (Object e) {
      debugPrint('Published model lookup failed for $id: $e');
      done(null);
      // Tried again on the next lookup.
      _subs.remove(id)?.cancel();
      _first.remove(id);
      _latest.remove(id);
    });
  }

  /// Newest first when several models are active.
  static int _time(Map<String, dynamic> d) {
    for (final k in ['publishedAt', 'updatedAt', 'createdAt']) {
      final v = d[k];
      if (v is Timestamp) return v.millisecondsSinceEpoch;
    }
    return 0;
  }
}
