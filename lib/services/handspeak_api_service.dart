import 'dart:convert';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'performance_monitor.dart';

/// Feature dimensions batay sa sinanay na ONNX models (legacy /v1/predict).
class HandSpeakModels {
  static const String greetings = 'greetings';
  static const String lupangHinirang = 'lupang_hinirang';
  static const String calendar = 'calendar';

  static const Map<String, int> featureDimensions = {
    greetings: 3072, // 32 frames x 96 features (PhraseRecognizer.flatInputLength)
    lupangHinirang: 818, // 32 sampled frames
  };

  /// Mga model sa POST /v1/predict_raw/{model_id} (raw landmarks + server-side gates).
  static const List<String> rawModels = [lupangHinirang, calendar];
}

class Prediction {
  final int index;
  final String label;
  final String? labelEn;
  final String? code;
  final double confidence;

  Prediction({
    required this.index,
    required this.label,
    this.labelEn,
    this.code,
    required this.confidence,
  });

  factory Prediction.fromJson(Map<String, dynamic> json) {
    return Prediction(
      index: json['index'] as int? ?? 0,
      label: json['label'] as String? ?? '',
      labelEn: json['label_en'] as String?,
      code: json['code'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class PredictResponse {
  final String model;
  final Prediction prediction;
  final List<Prediction> topK;

  PredictResponse({
    required this.model,
    required this.prediction,
    required this.topK,
  });

  factory PredictResponse.fromJson(Map<String, dynamic> json) {
    final topKList = (json['top_k'] as List<dynamic>? ?? [])
        .map((item) => Prediction.fromJson(item as Map<String, dynamic>))
        .toList();

    return PredictResponse(
      model: json['model'] as String? ?? '',
      prediction: Prediction.fromJson(json['prediction'] as Map<String, dynamic>? ?? {}),
      topK: topKList,
    );
  }
}

// ---------------------------------------------------------------------------
// POST /v1/predict_raw/lupang_hinirang
// Contract: inference-service/app/main.py (RawFrame, RawPredictRequest)
//           inference-service/app/lupang_raw.py (LupangRawModel.predict)
// ---------------------------------------------------------------------------

/// Isang camera frame ng MediaPipe landmarks.
///
/// Mga patakaran ng server (kapag mali, 422 o maling resulta):
///  * Coordinates ay MediaPipe-normalised (0..1) sa UNMIRRORED na image, hindi
///    sa selfie preview. Kung galing sa mirrored na image ang landmarks, gamitin
///    ang [RawLandmarkFrame.unmirrored].
///  * [leftHand] / [rightHand] = kaliwa / kanang kamay ng SIGNER (MediaPipe
///    Holistic convention), hindi kung saang bahagi ng screen sila lumabas.
///  * [pose]: eksaktong 33 x [x, y, visibility]. Ang ikatlong value ay
///    VISIBILITY, hindi z. Ginagamit ng model ang nose, shoulders, elbows,
///    wrists (index 0, 11-16); puwedeng 0 ang iba.
///  * Hands: eksaktong 21 x [x, y, z].
///  * null = hindi na-detect sa frame na ito (huwag punuin ng zeros).
class RawLandmarkFrame {
  /// Oras ng capture sa SEGUNDO (double). Relative lang ang mahalaga: ibinabawas
  /// ng server ang unang timestamp. Dapat non-decreasing.
  final double t;
  final List<List<double>>? pose;
  final List<List<double>>? leftHand;
  final List<List<double>>? rightHand;

  RawLandmarkFrame({
    required this.t,
    this.pose,
    this.leftHand,
    this.rightHand,
  });

  /// Gumawa mula sa camera timestamp na microseconds (hal. Stopwatch o
  /// DateTime.microsecondsSinceEpoch).
  factory RawLandmarkFrame.fromMicros({
    required int timestampMicros,
    List<List<double>>? pose,
    List<List<double>>? leftHand,
    List<List<double>>? rightHand,
  }) {
    return RawLandmarkFrame(
      t: timestampMicros / 1e6,
      pose: pose,
      leftHand: leftHand,
      rightHand: rightHand,
    );
  }

  /// MediaPipe pose: magkapares na kaliwa/kanang landmark index (mata, tainga,
  /// bibig, balikat, siko, pulso, daliri, balakang, tuhod, bukung-bukong, sakong, paa).
  static const List<List<int>> _posePairs = [
    [1, 4], [2, 5], [3, 6], [7, 8], [9, 10], [11, 12], [13, 14], [15, 16], [17, 18],
    [19, 20], [21, 22], [23, 24], [25, 26], [27, 28], [29, 30], [31, 32],
  ];

  /// Pose mula sa MIRRORED na image -> UNMIRRORED: x -> 1 - x AT palitan ang
  /// bawat kaliwa/kanang pares (sa mirrored image, ang kanang balikat ng signer
  /// ay tinatawag ng pose model na "left").
  static List<List<double>>? unmirrorPose(List<List<double>>? pose) {
    if (pose == null) return null;
    final flipped = pose.map((p) => [1.0 - p[0], ...p.sublist(1)]).toList();
    for (final pair in _posePairs) {
      final tmp = flipped[pair[0]];
      flipped[pair[0]] = flipped[pair[1]];
      flipped[pair[1]] = tmp;
    }
    return flipped;
  }

  static List<double> _flipX(List<double> p) => [1.0 - p[0], ...p.sublist(1)];

  /// Para sa landmarks na kinuha sa MIRRORED na image (selfie preview).
  /// Inaayos ang pose (x flip + left/right swap) at itinatalaga ang mga kamay
  /// sa pinakamalapit na pose wrist, kaya HINDI kailangan ang handedness label.
  factory RawLandmarkFrame.unmirrored({
    required double t,
    List<List<double>>? pose,
    List<List<List<double>>> handsInMirroredImage = const [],
  }) {
    return RawLandmarkFrame.fromDetections(
      t: t,
      pose: unmirrorPose(pose),
      hands: handsInMirroredImage.map((h) => h.map(_flipX).toList()).toList(),
    );
  }

  /// Inirerekomendang paraan: [pose] (33 x [x, y, visibility]) at lahat ng
  /// na-detect na kamay (bawat isa 21 x [x, y, z]) mula sa UNMIRRORED na image,
  /// WALANG handedness. Bawat kamay ay itinatalaga sa pose wrist na pinakamalapit
  /// sa hand wrist (pose 15 = kaliwang pulso, 16 = kanang pulso ng signer), gaya
  /// ng MediaPipe Holistic na ginamit sa training. Gumagana sa hand_landmarker
  /// package (walang handedness). Kung walang pose: ang kamay na mas nasa KANAN
  /// ng image (mas malaking x) ang kaliwang kamay ng signer.
  factory RawLandmarkFrame.fromDetections({
    required double t,
    List<List<double>>? pose,
    List<List<List<double>>> hands = const [],
  }) {
    if (hands.length > 2) {
      throw ArgumentError("Hanggang 2 kamay lang ang tinatanggap, nakuha: ${hands.length}");
    }
    List<List<double>>? left;
    List<List<double>>? right;
    double d2(List<double> a, List<double> b) =>
        (a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]);
    if (hands.isNotEmpty && pose != null && pose.length == 33) {
      final lw = pose[15], rw = pose[16];
      if (hands.length == 1) {
        final w = hands[0][0];
        if (d2(w, lw) <= d2(w, rw)) {
          left = hands[0];
        } else {
          right = hands[0];
        }
      } else {
        final a = hands[0][0], b = hands[1][0];
        final straight = d2(a, lw) + d2(b, rw);
        final swapped = d2(a, rw) + d2(b, lw);
        left = straight <= swapped ? hands[0] : hands[1];
        right = straight <= swapped ? hands[1] : hands[0];
      }
    } else if (hands.isNotEmpty) {
      final sorted = [...hands]..sort((p, q) => p[0][0].compareTo(q[0][0]));
      if (sorted.length == 2) {
        right = sorted[0];
        left = sorted[1];
      } else {
        // Isang kamay na walang pose: hula batay sa panig ng image.
        if (sorted[0][0][0] >= 0.5) {
          left = sorted[0];
        } else {
          right = sorted[0];
        }
      }
    }
    return RawLandmarkFrame(t: t, pose: pose, leftHand: left, rightHand: right);
  }

  /// Pixel coordinates (hal. ML Kit pose: x, y sa pixels, likelihood) ->
  /// MediaPipe-normalised [x / width, y / height, third]. Para sa pose, ang
  /// ikatlong value ay dapat VISIBILITY / in-frame likelihood (0..1).
  static List<List<double>> normalizePixels(List<List<double>> points, int width, int height) {
    return points.map((p) => [p[0] / width, p[1] / height, p.length > 2 ? p[2] : 0.0]).toList();
  }

  static List<List<double>>? _points(List<List<double>>? pts, int n, String name) {
    if (pts == null) return null;
    if (pts.length != n || pts.any((p) => p.length < 3)) {
      throw ArgumentError("$name ay dapat $n landmarks na may tig-3 value [x, y, z|visibility]");
    }
    // 5 decimals (~0.01 px sa 1280px): sapat sa model, halos kalahati ng JSON size.
    return pts.map((p) {
      final v = p.sublist(0, 3);
      if (v.any((x) => !x.isFinite)) throw ArgumentError("$name ay may NaN o Infinity");
      return v.map((x) => double.parse(x.toStringAsFixed(5))).toList();
    }).toList();
  }

  /// Mula sa JSON map na kapareho ng request format
  /// ({'t', 'pose', 'left_hand', 'right_hand'}), hal. CaptureFrame.toJson(t0)
  /// o RawFrame.toJson(t0) ng mga practice screen.
  factory RawLandmarkFrame.fromJson(Map<String, dynamic> json) {
    List<List<double>>? pts(Object? v) => v == null
        ? null
        : [for (final p in v as List) [for (final c in p as List) (c as num).toDouble()]];
    final t = json['t'];
    if (t is! num) throw ArgumentError("Bawat frame ay kailangan ng numerong 't' (segundo)");
    return RawLandmarkFrame(
      t: t.toDouble(),
      pose: pts(json['pose']),
      leftHand: pts(json['left_hand']),
      rightHand: pts(json['right_hand']),
    );
  }

  /// Tumatanggap ng [RawLandmarkFrame] o JSON map ng frame.
  static RawLandmarkFrame coerce(Object frame) {
    if (frame is RawLandmarkFrame) return frame;
    if (frame is Map) return RawLandmarkFrame.fromJson(Map<String, dynamic>.from(frame));
    throw ArgumentError("Hindi frame: ${frame.runtimeType}");
  }

  Map<String, dynamic> toJson() => {
        't': t,
        'pose': _points(pose, 33, 'pose'),
        'left_hand': _points(leftHand, 21, 'left_hand'),
        'right_hand': _points(rightHand, 21, 'right_hand'),
      };
}

/// Isang gate/check na ginawa ng server (hal. NO_HANDS, LOW_CONFIDENCE, SMALL_MARGIN).
class RawGateCheck {
  final String code;
  final String label;
  final double value;
  final double? threshold;
  final bool passed;
  final String text;

  RawGateCheck({
    required this.code,
    required this.label,
    required this.value,
    required this.threshold,
    required this.passed,
    required this.text,
  });

  factory RawGateCheck.fromJson(Map<String, dynamic> json) {
    return RawGateCheck(
      code: json['code'] as String? ?? '',
      label: json['label'] as String? ?? '',
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
      threshold: (json['threshold'] as num?)?.toDouble(),
      passed: json['passed'] as bool? ?? false,
      text: json['text'] as String? ?? '',
    );
  }
}

class RawRejection {
  /// Hal. NO_HANDS, TOO_SHORT, FRAGMENT_DURATION, LOW_MOTION, PHASE_IMBALANCE,
  /// SINGLE_STROKE, INVALID_CLASS, LOW_CONFIDENCE, SMALL_MARGIN, HIGH_ENTROPY
  final String code;
  final String message;

  RawRejection({required this.code, required this.message});

  factory RawRejection.fromJson(Map<String, dynamic> json) {
    return RawRejection(
      code: json['code'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }
}

class RawCaptureInfo {
  final int frames;
  final int activeFrames;
  final double activeDurationS;
  final double fps;
  final String? restingHand;

  RawCaptureInfo({
    required this.frames,
    required this.activeFrames,
    required this.activeDurationS,
    required this.fps,
    this.restingHand,
  });

  factory RawCaptureInfo.fromJson(Map<String, dynamic> json) {
    return RawCaptureInfo(
      frames: json['frames'] as int? ?? 0,
      activeFrames: json['active_frames'] as int? ?? 0,
      activeDurationS: (json['active_duration_s'] as num?)?.toDouble() ?? 0.0,
      fps: (json['fps'] as num?)?.toDouble() ?? 0.0,
      restingHand: json['resting_hand']?.toString(),
    );
  }
}

class RawPredictResponse {
  final String model;
  final String modelVersion;
  final bool accepted;

  /// null kapag hindi accepted (tingnan ang [rejection]).
  final Prediction? prediction;
  final RawRejection? rejection;
  final List<String> failedChecks;
  final List<RawGateCheck> checks;

  /// Puno kapag may na-classify, kahit rejected (para sa debugging/UI).
  final List<Prediction> topK;
  final RawCaptureInfo capture;
  final double inferenceMs;

  /// Buong JSON reply ng server (para sa debug logs, hal. raw['checks']).
  final Map<String, dynamic> raw;

  RawPredictResponse({
    required this.model,
    required this.modelVersion,
    required this.accepted,
    required this.prediction,
    required this.rejection,
    required this.failedChecks,
    required this.checks,
    required this.topK,
    required this.capture,
    required this.inferenceMs,
    this.raw = const {},
  });

  /// Mga code ng hindi pumasang gate, ayon sa pagkakasunod (hal. ['FRAGMENT_DURATION']).
  List<String> get failed => failedChecks;

  /// Paliwanag ng server sa unang hindi pumasang gate (null kapag accepted).
  String? get message => rejection?.message;

  /// "accepted" o "rejected".
  String get decision => accepted ? 'accepted' : 'rejected';

  /// Top-1 na klase kahit rejected (null kung walang na-classify, hal. NO_HANDS).
  Prediction? get predictedClass => prediction ?? (topK.isNotEmpty ? topK.first : null);

  double? get confidence => predictedClass?.confidence;

  /// Margin na ginamit ng server gate (top-1 minus top-2). Galing sa
  /// SMALL_MARGIN check; kung wala ito, kinukuwenta mula sa topK.
  double? get margin {
    for (final c in checks) {
      if (c.code == 'SMALL_MARGIN') return c.value;
    }
    return topK.length >= 2 ? topK[0].confidence - topK[1].confidence : null;
  }

  /// Pass/fail bawat gate code. Puwedeng higit sa isang check ang isang code
  /// (hal. dalawang TOO_SHORT: raw frames at duration); pasado lang kung pasado lahat.
  /// Tingnan ang [checks] para sa value/threshold ng bawat isa.
  Map<String, bool> get gateResults {
    final out = <String, bool>{};
    for (final c in checks) {
      out[c.code] = (out[c.code] ?? true) && c.passed;
    }
    return out;
  }

  factory RawPredictResponse.fromJson(Map<String, dynamic> json) {
    List<dynamic> list(String k) => json[k] as List<dynamic>? ?? const [];
    return RawPredictResponse(
      model: json['model'] as String? ?? '',
      modelVersion: json['model_version'] as String? ?? '',
      accepted: json['accepted'] as bool? ?? false,
      prediction: json['prediction'] == null
          ? null
          : Prediction.fromJson(json['prediction'] as Map<String, dynamic>),
      rejection: json['rejection'] == null
          ? null
          : RawRejection.fromJson(json['rejection'] as Map<String, dynamic>),
      failedChecks: list('failed_checks').map((e) => e.toString()).toList(),
      checks: list('checks').map((e) => RawGateCheck.fromJson(e as Map<String, dynamic>)).toList(),
      topK: list('top_k').map((e) => Prediction.fromJson(e as Map<String, dynamic>)).toList(),
      capture: RawCaptureInfo.fromJson(json['capture'] as Map<String, dynamic>? ?? {}),
      inferenceMs: (json['inference_ms'] as num?)?.toDouble() ?? 0.0,
      raw: json,
    );
  }
}

// ---------------------------------------------------------------------------
// POST /v1/predict_raw/letter_j | letter_z  (dynamic letters, feature set jz-v2)
// Contract: inference-service/app/main.py (LetterStrokeRequest)
//           inference-service/app/letters_jz.py (LetterModel.predict)
// ---------------------------------------------------------------------------

/// Sagot ng server para sa Letter J / Z.
class LetterPredictResponse {
  final String model; // "letter_j" | "letter_z"
  final String letter; // "J" | "Z"
  final String featureVersion;

  /// true kapag confidence >= threshold (0.25).
  final bool accepted;

  /// P(letter) ng model, 0..1.
  final double confidence;
  final double threshold;
  final String label; // "Letter J" | "Not J"
  final String message;
  final String input; // "frames" | "features"
  final List<double> features;
  final double inferenceMs;
  final Map<String, dynamic> raw;

  LetterPredictResponse({
    required this.model,
    required this.letter,
    required this.featureVersion,
    required this.accepted,
    required this.confidence,
    required this.threshold,
    required this.label,
    required this.message,
    required this.input,
    required this.features,
    required this.inferenceMs,
    this.raw = const {},
  });

  factory LetterPredictResponse.fromJson(Map<String, dynamic> json) {
    return LetterPredictResponse(
      model: json['model'] as String? ?? '',
      letter: json['letter'] as String? ?? '',
      featureVersion: json['feature_version'] as String? ?? '',
      accepted: json['accepted'] as bool? ?? false,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      threshold: (json['threshold'] as num?)?.toDouble() ?? 0.25,
      label: json['label'] as String? ?? '',
      message: json['message'] as String? ?? '',
      input: json['input'] as String? ?? '',
      features: (json['features'] as List<dynamic>? ?? const []).map((e) => (e as num).toDouble()).toList(),
      inferenceMs: (json['inference_ms'] as num?)?.toDouble() ?? 0.0,
      raw: json,
    );
  }
}

// ---------------------------------------------------------------------------
// CaptureFixer: make a phone capture look like the desktop engine's
// ---------------------------------------------------------------------------

/// Result of [CaptureFixer.fix].
class FixedCapture {
  /// Frames in the /v1/predict_raw format ({'t', 'pose', 'left_hand', 'right_hand'}).
  final List<Map<String, dynamic>> frames;
  final int imageWidth;
  final int imageHeight;

  /// Clockwise rotation applied to the landmarks (0, 90, 180, 270).
  final int rotation;

  /// Frames whose left/right hands were swapped to match the pose wrists.
  final int handsReassigned;

  FixedCapture(this.frames, this.imageWidth, this.imageHeight, this.rotation, this.handsReassigned);

  String get report => 'rotation $rotation°, image ${imageWidth}x$imageHeight, '
      'hands reassigned in $handsReassigned/${frames.length} frames';
}

/// Brings a phone capture into the exact form the desktop engine
/// (live_lupang_engine.py: MediaPipe Holistic on the upright camera frame)
/// produces, independent of how the native detector reports it:
///
///  1. Orientation: a signer is upright, so the nose must be ABOVE the
///     mid-shoulder point. Across all frames with a pose, the clockwise
///     rotation (0/90/180/270) that makes this true is applied to every
///     landmark, and width/height are swapped for 90/270. (Phone frames often
///     arrive in the sensor's rotated frame while the size is reported upright,
///     or the other way round.)
///  2. Hands: each detected hand is assigned to the pose wrist it is closest to
///     (15 = signer's left, 16 = right), exactly like MediaPipe Holistic, so
///     front-camera handedness labels cannot swap the hands.
/// Mirroring is left as is: both server models are trained mirror-invariant.
class CaptureFixer {
  static List<List<double>>? _pts(Object? v) => v == null
      ? null
      : [for (final p in v as List) [for (final c in p as List) (c as num).toDouble()]];

  /// Clockwise rotation of normalised image coordinates.
  static List<double> _rot(List<double> p, int r) {
    final x = p[0], y = p[1];
    final rest = p.sublist(2);
    switch (r) {
      case 90:
        return [1.0 - y, x, ...rest];
      case 180:
        return [1.0 - x, 1.0 - y, ...rest];
      case 270:
        return [y, 1.0 - x, ...rest];
      default:
        return [x, y, ...rest];
    }
  }

  static double _median(List<double> v) {
    final s = [...v]..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2.0;
  }

  /// Rotation that puts the nose above the shoulders, or 0 if unclear.
  static int uprightRotation(List<Map> frames) {
    final dxs = <double>[], dys = <double>[];
    for (final f in frames) {
      final pose = _pts(f['pose']);
      if (pose == null || pose.length < 13) continue;
      dxs.add(pose[0][0] - (pose[11][0] + pose[12][0]) / 2);
      dys.add(pose[0][1] - (pose[11][1] + pose[12][1]) / 2);
    }
    if (dxs.length < 3) return 0;
    final dx = _median(dxs), dy = _median(dys);
    final len = (dx * dx + dy * dy);
    if (len <= 0) return 0;
    // y component of the nose offset after each clockwise rotation (negative = up).
    final up = {0: dy, 90: dx, 180: -dy, 270: -dx};
    final best = up.entries.reduce((a, b) => a.value <= b.value ? a : b);
    // Only rotate when the evidence is clear (nose well above the shoulders).
    return best.value < -0.5 * math.sqrt(len) ? best.key : 0;
  }

  /// [frames]: maps in the request format (e.g. CaptureFrame.toJson(t0) or
  /// RawFrame.toJson(t0)); any Map type is accepted.
  static FixedCapture fix(List<Map> frames, int imageWidth, int imageHeight) {
    final r = uprightRotation(frames);
    final swapSize = r == 90 || r == 270;
    int reassigned = 0;
    final out = <Map<String, dynamic>>[];
    for (final f in frames) {
      List<List<double>>? rot(Object? v) => _pts(v)?.map((p) => _rot(p, r)).toList();
      final pose = rot(f['pose']);
      var left = rot(f['left_hand']);
      var right = rot(f['right_hand']);
      if (pose != null && pose.length >= 17) {
        final hands = [if (left != null) left, if (right != null) right];
        final assigned = RawLandmarkFrame.fromDetections(t: 0, pose: pose, hands: hands);
        if (!identical(assigned.leftHand, left) || !identical(assigned.rightHand, right)) reassigned++;
        left = assigned.leftHand;
        right = assigned.rightHand;
      }
      out.add({...Map<String, dynamic>.from(f), 'pose': pose, 'left_hand': left, 'right_hand': right});
    }
    return FixedCapture(out, swapSize ? imageHeight : imageWidth, swapSize ? imageWidth : imageHeight, r, reassigned);
  }
}

class HandSpeakApiException implements Exception {
  final int statusCode;
  final String message;
  final String body;

  HandSpeakApiException(this.statusCode, this.message, this.body);

  bool get isAuthError => statusCode == 401 || statusCode == 403;

  @override
  String toString() => "HandSpeakApiException[$statusCode]: $message";
}

class HandSpeakApiService {
  static const String baseUrl =
      "https://handspeak-inference-xo2j6ffgta-as.a.run.app";

  // Mga limit ng server (inference-service/app/main.py). Sinusuri dito para
  // makakuha ng malinaw na error bago mag-upload.
  static const int maxRawFrames = 600;
  static const double maxRawDurationS = 30.0;
  static const int maxRawBodyBytes = 2 * 1024 * 1024;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final http.Client _client;

  HandSpeakApiService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> _getIdToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception("Kailangang naka-sign in ang user sa Firebase Auth.");
    }
    final token = await user.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) {
      throw Exception("Walang Firebase ID token.");
    }
    return token;
  }

  /// Nagpapadala ng authenticated request; kapag 401 (expired token), isang
  /// beses na nire-refresh ang token at inuulit.
  Future<http.Response> _authed(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    Future<http.Response> attempt(bool refresh) async => send({
          "Authorization": "Bearer ${await _getIdToken(forceRefresh: refresh)}",
          "Accept": "application/json",
          "Content-Type": "application/json",
        });
    // Server round trip time feeds the in-app slow-connection hint.
    final sw = Stopwatch()..start();
    var response = await attempt(false);
    if (response.statusCode == 401) response = await attempt(true);
    PerformanceMonitor.instance.reportNetwork(sw.elapsedMilliseconds);
    return response;
  }

  static HandSpeakApiException _error(http.Response r) {
    String message = r.reasonPhrase ?? 'Request failed';
    try {
      final detail = (jsonDecode(r.body) as Map<String, dynamic>)['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List) {
        // FastAPI 422: [{loc: [...], msg: "..."}]
        message = detail
            .map((e) => e is Map ? "${(e['loc'] as List?)?.join('.')}: ${e['msg']}" : e.toString())
            .join('; ');
      }
    } catch (_) {}
    return HandSpeakApiException(r.statusCode, message, r.body);
  }

  /// GET /health
  Future<bool> checkHealth() async {
    try {
      final response = await _client.get(Uri.parse("$baseUrl/health"));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// GET /v1/models -> {"models": [...], "raw_models": [...]}
  Future<Map<String, dynamic>> fetchModels() async {
    final response = await _authed((h) => _client.get(Uri.parse("$baseUrl/v1/models"), headers: h));
    if (response.statusCode != 200) throw _error(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// POST /v1/predict/{model_id} (legacy: client-built feature vector)
  Future<PredictResponse> predict({
    required String modelId,
    required List<double> features,
    int topK = 3,
  }) async {
    final expectedDim = HandSpeakModels.featureDimensions[modelId];
    if (expectedDim != null && features.length != expectedDim) {
      throw ArgumentError(
        "Invalid feature length para sa $modelId. Inaasahan: $expectedDim, nakuha: ${features.length}",
      );
    }

    final body = jsonEncode({"features": features, "top_k": topK});
    final response = await _authed(
        (h) => _client.post(Uri.parse("$baseUrl/v1/predict/$modelId"), headers: h, body: body));

    if (response.statusCode != 200) throw _error(response);
    return PredictResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// POST /v1/predict_raw/lupang_hinirang
  Future<RawPredictResponse> predictRawLupangHinirang({
    required List<Object> frames,
    required int imageWidth,
    required int imageHeight,
    int topK = 3,
  }) =>
      predictRaw(
        modelId: HandSpeakModels.lupangHinirang,
        frames: frames,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        topK: topK,
      );

  /// POST /v1/predict_raw/calendar (12 buwan + INVALID_GESTURE).
  /// Pareho ang request/response sa Lupang Hinirang; iba lang ang model at gate
  /// (strict: confidence >= 0.65, margin >= 0.20, entropy <= 0.50, duration floor
  /// bawat buwan; tinatanggal ng server ang nakapahingang kamay sa simula/dulo).
  Future<RawPredictResponse> predictRawCalendar({
    required List<Object> frames,
    required int imageWidth,
    required int imageHeight,
    int topK = 3,
  }) =>
      predictRaw(
        modelId: HandSpeakModels.calendar,
        frames: frames,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        topK: topK,
      );

  /// Minimum na bahagi ng frames na may pose. Ang pose (ilong, balikat, siko,
  /// pulso) ang reference frame ng LAHAT ng position features; kung wala ito,
  /// walang saysay ang resulta ng model.
  static const double minPoseCoverage = 0.5;

  /// POST /v1/predict_raw/{modelId}
  ///
  /// Ipadala ang BUONG capture (lahat ng frames mula simula hanggang dulo ng
  /// pag-sign); ang server ang gumagawa ng feature pipeline at rejection gates.
  /// [imageWidth] / [imageHeight] = laki ng image na pinagkunan ng landmarks
  /// (pagkatapos ng rotation, i.e. kung paano ito nakikita ng detector).
  /// Ginagamit ito ng server para sa aspect-ratio correction.
  Future<RawPredictResponse> predictRaw({
    required String modelId,
    required List<Object> frames,
    required int imageWidth,
    required int imageHeight,
    int topK = 3,
  }) async {
    // RawLandmarkFrame o JSON map ({'t', 'pose', 'left_hand', 'right_hand'}).
    final fs = frames.map(RawLandmarkFrame.coerce).toList();
    if (!HandSpeakModels.rawModels.contains(modelId)) {
      throw ArgumentError("Hindi raw model ang '$modelId'. Pagpipilian: ${HandSpeakModels.rawModels}");
    }
    final withPose = fs.where((f) => f.pose != null).length;
    if (fs.isNotEmpty && withPose < fs.length * minPoseCoverage) {
      throw ArgumentError(
        "Pose landmarks sa $withPose/${fs.length} frames lang. Kailangan ang pose (hal. "
        "google_mlkit_pose_detection) sa karamihan ng frames, hindi lang hand landmarks.",
      );
    }
    if (fs.length < 2 || fs.length > maxRawFrames) {
      throw ArgumentError("Kailangan ng 2..$maxRawFrames frames, nakuha: ${fs.length}");
    }
    if (imageWidth <= 0 || imageHeight <= 0 || imageWidth > 10000 || imageHeight > 10000) {
      throw ArgumentError("Invalid image size: ${imageWidth}x$imageHeight");
    }
    if (topK < 1 || topK > 10) throw ArgumentError("topK ay dapat 1..10");
    for (var i = 0; i < fs.length; i++) {
      final t = fs[i].t;
      if (!t.isFinite || (i > 0 && t < fs[i - 1].t)) {
        throw ArgumentError("Ang frame times ay dapat finite at non-decreasing (frame $i)");
      }
    }
    if (fs.last.t - fs.first.t > maxRawDurationS) {
      throw ArgumentError("Mas mahaba sa ${maxRawDurationS.toInt()} s ang capture");
    }

    final body = utf8.encode(jsonEncode({
      "image_width": imageWidth,
      "image_height": imageHeight,
      "frames": fs.map((f) => f.toJson()).toList(),
      "top_k": topK,
    }));
    if (body.length > maxRawBodyBytes) {
      throw ArgumentError("Masyadong malaki ang request (${body.length} bytes)");
    }

    final response = await _authed((h) => _client.post(
          Uri.parse("$baseUrl/v1/predict_raw/$modelId"),
          headers: h,
          body: body,
        ));

    if (response.statusCode != 200) throw _error(response);
    return RawPredictResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Bilang ng features ng J/Z model (feature version jz-v2).
  static const int letterFeatureDim = 24;

  /// POST /v1/predict_raw/letter_j
  ///
  /// Ipadala ang ISA sa dalawa:
  ///  * [frames] = buong stroke ng kamay na gumuguhit: bawat frame ay 21 x
  ///    [x, y, (z)] MediaPipe-normalised (0..1) na coordinates, kasama ang
  ///    [imageWidth] / [imageHeight] ng image na pinagkunan (pagkatapos ng
  ///    rotation). Puwedeng mirrored o hindi ang image.
  ///  * [features] = 24 jz-v2 features (LetterStrokeFeatures.compute sa phone).
  /// Tinatanggap kapag confidence (P ng letter) >= 0.25.
  Future<LetterPredictResponse> predictRawLetterJ({
    List<List<List<double>>>? frames,
    List<double>? features,
    int? imageWidth,
    int? imageHeight,
  }) =>
      _predictLetter('letter_j', frames, features, imageWidth, imageHeight);

  /// POST /v1/predict_raw/letter_z (parehong input gaya ng [predictRawLetterJ]).
  Future<LetterPredictResponse> predictRawLetterZ({
    List<List<List<double>>>? frames,
    List<double>? features,
    int? imageWidth,
    int? imageHeight,
  }) =>
      _predictLetter('letter_z', frames, features, imageWidth, imageHeight);

  Future<LetterPredictResponse> _predictLetter(String modelId, List<List<List<double>>>? frames,
      List<double>? features, int? imageWidth, int? imageHeight) async {
    if ((frames == null) == (features == null)) {
      throw ArgumentError("Ipadala ang 'frames' (kasama ang imageWidth/imageHeight) O ang 'features', hindi pareho");
    }
    final Map<String, dynamic> payload;
    if (features != null) {
      if (features.length != letterFeatureDim || features.any((v) => !v.isFinite)) {
        throw ArgumentError("features ay dapat $letterFeatureDim finite na numero, nakuha: ${features.length}");
      }
      payload = {'features': features};
    } else {
      if (frames!.length < 2 || frames.length > maxRawFrames) {
        throw ArgumentError("Kailangan ng 2..$maxRawFrames frames, nakuha: ${frames.length}");
      }
      if (imageWidth == null || imageHeight == null || imageWidth <= 0 || imageHeight <= 0 ||
          imageWidth > 10000 || imageHeight > 10000) {
        throw ArgumentError("Kailangan ng tamang imageWidth / imageHeight kasama ng frames (para sa aspect ratio)");
      }
      final cleaned = <List<List<double>>>[];
      for (var i = 0; i < frames.length; i++) {
        final fr = frames[i];
        if (fr.length != 21 || fr.any((p) => p.length < 2 || p.take(2).any((v) => !v.isFinite))) {
          throw ArgumentError("Frame $i ay dapat 21 landmarks na may finite na [x, y, (z)]");
        }
        cleaned.add([
          for (final p in fr) [for (final v in p.take(3)) double.parse(v.toStringAsFixed(5))]
        ]);
      }
      payload = {'frames': cleaned, 'image_width': imageWidth, 'image_height': imageHeight};
    }
    final body = utf8.encode(jsonEncode(payload));
    if (body.length > maxRawBodyBytes) {
      throw ArgumentError("Masyadong malaki ang request (${body.length} bytes)");
    }
    final response = await _authed((h) => _client.post(
          Uri.parse("$baseUrl/v1/predict_raw/$modelId"),
          headers: h,
          body: body,
        ));
    if (response.statusCode != 200) throw _error(response);
    return LetterPredictResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
