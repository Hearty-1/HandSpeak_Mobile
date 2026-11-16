/// Response latency of a camera check, for the System Testing measurements:
///
///   response latency = output time - gesture input time
///
/// * gesture input time: the moment the captured sign is submitted for
///   checking (CAPTURE & CHECK tapped, or the recording stopped). Screens
///   call [markInput]; when a screen does not, the first server request of
///   the check is used instead.
/// * output time: the moment the verdict is recorded, which is when the
///   result is shown to the student ([take], called by the attempt loggers).
///
/// The server round trip (request sent -> answer received) is measured
/// separately, so the network part can be told apart from the on-phone part.
/// Stored on every attempt in gesture_attempts and practice_sessions.
class LatencyProbe {
  LatencyProbe._();

  /// A mark older than this belongs to a check that was never recorded.
  static const Duration _stale = Duration(seconds: 30);

  static DateTime? _inputAt;
  static int _serverMs = 0;
  static int _serverCalls = 0;

  static bool _fresh(DateTime? t) => t != null && DateTime.now().difference(t) < _stale;

  static void _reset() {
    _inputAt = null;
    _serverMs = 0;
    _serverCalls = 0;
  }

  /// The student submitted the sign (capture / recording stopped).
  static void markInput() {
    _reset();
    _inputAt = DateTime.now();
  }

  /// A recognition request is being sent.
  static void requestStarted() {
    if (!_fresh(_inputAt)) {
      _reset();
      _inputAt = DateTime.now();
    }
  }

  /// A recognition request came back after [ms] milliseconds.
  static void requestDone(int ms) {
    _serverMs += ms;
    _serverCalls++;
  }

  /// The verdict is shown: returns the measurement and clears it, or null
  /// when there was no measured check (e.g. a skipped question).
  static Map<String, int>? take() {
    final at = _inputAt;
    if (!_fresh(at)) {
      _reset();
      return null;
    }
    final out = <String, int>{
      'responseLatencyMs': DateTime.now().difference(at!).inMilliseconds,
      'serverRoundTripMs': _serverMs,
      'serverCalls': _serverCalls,
    };
    _reset();
    return out;
  }
}
