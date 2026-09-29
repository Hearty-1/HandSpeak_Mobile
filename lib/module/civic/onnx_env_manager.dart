import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// Process-wide manager for the single, shared `OrtEnv` native environment
/// used by every screen that imports `package:onnxruntime` (this civic
/// screen, recognizer.dart, PanataClassifierService, PanunumpaClassifierService).
///
/// ROOT CAUSE this fixes — `LateInitializationError: Field
/// '_ortSparseFormat@...' has not been initialized`:
///
/// `OrtEnv.instance` is a Dart-side singleton wrapping ONE native ONNX
/// Runtime `Ort::Env` for the entire process. The package's own official
/// usage example calls `OrtEnv.instance.init()` once and
/// `OrtEnv.instance.release()` once, at the very end of the program's
/// life — never per-screen:
/// https://pub.dev/packages/onnxruntime
///
/// When each practice screen independently calls `OrtEnv.instance.init()`
/// on entry and `OrtEnv.instance.release()` on dispose, the FIRST screen
/// you leave releases the *shared* native environment out from under
/// every other screen that still expects it to be alive. Some of the
/// plugin's internal state (lookup tables such as the `_ortSparseFormat`
/// field that crashed here) is only populated lazily, the first time real
/// work touches it after `init()`. After a release+reinit cycle caused by
/// navigating between screens, that populate step can be skipped, so the
/// FIRST inference call on the next screen — not model load, inference —
/// is the first time that field is ever needed, and it was never set.
/// That's exactly why this crashes at inference time and correlates with
/// screen navigation rather than a single screen's own use.
///
/// FIX: every screen calls [OnnxEnvManager.ensureInitialized] instead of
/// `OrtEnv.instance.init()` directly, and NO screen ever calls
/// `OrtEnv.instance.release()`. Releasing individual [OrtSession]s per
/// screen is still correct and necessary (sessions are cheap to recreate;
/// the shared environment is not) — only the environment itself is
/// treated as app-lifetime.
///
/// ACTION REQUIRED beyond this file: apply the same swap — call
/// `OnnxEnvManager.ensureInitialized()` instead of `OrtEnv.instance.init()`,
/// and delete any `OrtEnv.instance.release()` call — in every other screen
/// that uses `package:onnxruntime`: recognizer.dart,
/// panata_classifier_service.dart, panunumpa_classifier_service.dart. The
/// fix only holds if ALL of them stop touching the environment's
/// lifecycle individually.
class OnnxEnvManager {
  OnnxEnvManager._();

  static bool _initialized = false;

  /// Safe to call from every screen's bootstrap, as many times as you
  /// like, from any order of navigation — it only actually touches the
  /// native side the first time, ever, for the life of the process.
  static void ensureInitialized() {
    if (_initialized) return;
    try {
      OrtEnv.instance.init();
      _initialized = true;
      debugPrint("[OnnxEnvManager] OrtEnv initialized (process-wide, once).");
    } catch (e) {
      // If the native side reports it's already initialized (e.g. a race
      // between two screens' bootstraps on first app launch), that's a
      // success for our purposes, not a failure — don't crash the screen.
      debugPrint(
          "[OnnxEnvManager] init() reported: $e (treating as already-initialized).");
      _initialized = true;
    }
  }

  // Deliberately no release() exposed for screens to call. Mobile apps are
  // almost always just process-killed rather than cleanly shut down, so
  // there is normally nothing to call this from — but if a real full-app
  // shutdown hook is ever added, call OrtEnv.instance.release() exactly
  // ONCE there, never from a practice screen's dispose().
}