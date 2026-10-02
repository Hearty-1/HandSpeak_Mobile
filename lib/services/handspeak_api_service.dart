import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Feature dimensions batay sa sinanay na ONNX models
class HandSpeakModels {
  static const String greetings = 'greetings';
  static const String lupangHinirang = 'lupang_hinirang';

  static const Map<String, int> featureDimensions = {
    greetings: 3072, // Pinalitan mula 336 upang tumugma sa bagong model
    lupangHinirang: 818, // (I-check din sa backend kung nagbago ito)
  };
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

class HandSpeakApiService {
  static const String baseUrl =
      "https://handspeak-inference-xo2j6ffgta-as.a.run.app";

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String?> _getIdToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception("Kailangang naka-sign in ang user sa Firebase Auth.");
    }
    return await user.getIdToken();
  }

  /// GET /health
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/health"));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// POST /v1/predict/{model_id}
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

    final token = await _getIdToken();

    final response = await http.post(
      Uri.parse("$baseUrl/v1/predict/$modelId"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "features": features,
        "top_k": topK,
      }),
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception("Nag-timeout ang server (Cloud Run cold start). Subukang muli."),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return PredictResponse.fromJson(data);
    } else {
      throw Exception("Prediction failed: [${response.statusCode}] ${response.body}");
    }
  }
}