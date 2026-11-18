// publishedSignScores: a published model is judged on every output when the server sends the full probability
// vector (105-class models), and on top_k only from an older service.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/module/custom_category_screen.dart' show publishedSignScores;
import 'package:flutter_application_1/services/handspeak_api_service.dart';
import 'package:flutter_application_1/services/published_gesture_models.dart';

PublishedGestureModel _model(List<int> published, int invalid) => PublishedGestureModel(
      modelId: 'gs_0123456789abcdef',
      serviceUrl: 'https://example.invalid',
      name: 'Test',
      category: 'test',
      invalidIndex: invalid,
      modelVersion: 'v',
      classes: [
        for (final i in published)
          PublishedGestureClass(index: i, key: 'k$i', label: 'Sign $i', lessonSymbol: '', practice: PracticeSettings.defaults)
      ],
      practice: PracticeSettings.defaults,
    );

RawPredictResponse _response(Map<String, dynamic> extra) => RawPredictResponse.fromJson({
      'model': 'gs_0123456789abcdef',
      'accepted': false,
      'top_k': [
        {'index': 0, 'label': 'Sign 0', 'confidence': 0.30},
        {'index': 105, 'label': 'Not recognised', 'confidence': 0.20},
        {'index': 1, 'label': 'Sign 1', 'confidence': 0.10},
      ],
      ...extra,
    });

void main() {
  test('full vector: every output counts; held-back signs count as "not a sign"', () {
    final probs = List<double>.filled(106, 0.0);
    probs[0] = 0.30;
    probs[105] = 0.20;   // invalid
    probs[1] = 0.10;
    probs[50] = 0.05;    // the practised sign, 5th overall: outside top_k
    probs[7] = 0.15;     // held back (not published)
    probs[8] = 0.20;     // published, not in top_k
    final r = _response({'probabilities': probs, 'invalid_index': 105});
    final s = publishedSignScores(_model([0, 1, 8, 50], 105), r);
    expect(s.signs.map((p) => p.index).toList(), [0, 8, 1, 50]);
    expect(s.invalid, closeTo(0.35, 1e-9));   // invalid 0.20 + held-back 0.15
    expect(r.probabilityOf(50), 0.05);
  });

  test('older service without the vector: top_k only', () {
    final s = publishedSignScores(_model([0, 1, 8, 50], 105), _response({}));
    expect(s.signs.map((p) => p.index).toList(), [0, 1]);
    expect(s.invalid, closeTo(0.20, 1e-9));
  });
}
