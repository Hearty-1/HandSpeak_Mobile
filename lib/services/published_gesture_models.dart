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
  static final Map<String, Future<PublishedGestureModel?>> _cache = {};

  /// The active published model of [categoryId] (also tried in lower case),
  /// or null when there is none, it is inactive, or Firestore cannot be read
  /// (offline). A failed read is not cached, so it is tried again later.
  static Future<PublishedGestureModel?> forCategory(String categoryId) {
    final id = categoryId.trim();
    if (id.isEmpty) return Future.value(null);
    return _cache[id] ??= _fetch(id).then((m) => m, onError: (Object e) {
      debugPrint('Published model lookup failed for $id: $e');
      _cache.remove(id);
      return null;
    });
  }

  static Future<PublishedGestureModel?> _fetch(String id) async {
    final snap = await FirebaseFirestore.instance
        .collection('published_gesture_models')
        .where('category', whereIn: {id, id.toLowerCase()}.toList())
        .where('active', isEqualTo: true)
        .get();
    final models = [for (final d in snap.docs) PublishedGestureModel.fromDoc(d)].whereType<PublishedGestureModel>().toList();
    // Offline with nothing cached: do not remember "no model" for the session.
    if (models.isEmpty && snap.metadata.isFromCache) throw StateError('offline');
    if (models.isEmpty) return null;
    if (models.length > 1) {
      debugPrint('Several active published models for $id: ${models.map((m) => m.modelId)}; using ${models.first.modelId}');
    }
    return models.first;
  }
}
