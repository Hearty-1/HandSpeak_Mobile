import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as ja;

enum BgmType { none, menu, activity }

/// Provider handling continuous BGM looping, instant SFX mixing, audio ducking,
/// and concurrency-safe playback using just_audio[cite: 7].
class SoundProvider extends ChangeNotifier {
  final ja.AudioPlayer _bgmPlayer = ja.AudioPlayer();
  final ja.AudioPlayer _sfxPlayer = ja.AudioPlayer();

  BgmType _currentBgm = BgmType.none;
  bool _isBgmMuted = false;
  bool _isSfxMuted = false;
  bool _isDucked = false;
  bool _isDisposed = false;
  bool _isBgmLoading = false;

  double _bgmVolume = 0.4;
  double _sfxVolume = 1.0;

  // Percentage of normal BGM volume during SFX playback (30%)[cite: 7]
  static const double _duckingFactor = 0.30;

  // Background Music Asset Paths[cite: 7]
  static const String _menuBgmAsset = 'assets/sounds/bgm.mp3';
  static const String _activityBgmAsset = 'assets/sounds/gamebgm.mp3';

  // Sound Effects Asset Paths[cite: 7]
  static const String _correctSfxAsset = 'assets/sounds/correct.wav';
  static const String _incorrectSfxAsset = 'assets/sounds/incorrect.mp3';
  static const String _gameOverSfxAsset = 'assets/sounds/gameover.mp3';
  static const String _levelCompleteSfxAsset = 'assets/sounds/levelcomplete.wav';

  SoundProvider() {
    _safeExecute(() async {
      await _bgmPlayer.setLoopMode(ja.LoopMode.one);
    });
  }

  /// Centralized exception wrapper preventing unhandled platform channel crashes
  Future<void> _safeExecute(Future<void> Function() action) async {
    if (_isDisposed) return;
    try {
      await action();
    } on ja.PlayerInterruptedException catch (e) {
      debugPrint("Audio load interrupted: ${e.message}");
    } on ja.PlayerException catch (e) {
      debugPrint("just_audio exception: ${e.message}");
    } catch (e) {
      debugPrint("Audio Exception in SoundProvider: $e");
    }
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  // Getters[cite: 7]
  BgmType get currentBgm => _currentBgm;
  bool get isBgmMuted => _isBgmMuted;
  bool get isSfxMuted => _isSfxMuted;
  bool get isSoundEnabled => !_isSfxMuted;
  double get bgmVolume => _bgmVolume;
  double get sfxVolume => _sfxVolume;

  /// Custom NavigatorObserver instance bound to this SoundProvider[cite: 7]
  NavigatorObserver get navigatorObserver => AppSoundObserver(this);

  /// Evaluates screen identity automatically via route name or closure representation[cite: 7]
  void handleRouteTransition({String? routeName}) {
    if (_isDisposed) return;
    final identifier = (routeName ?? '').toLowerCase();

    // Keywords matching activity, practice, and quiz screens[cite: 7]
    final isActivityScreen = identifier.contains('act') ||
        identifier.contains('quiz') ||
        identifier.contains('exercise') ||
        identifier.contains('practice') ||
        identifier.contains('game') ||
        identifier.contains('arena') ||
        identifier.contains('easy') ||
        identifier.contains('solo') ||
        identifier.contains('challenge') ||
        identifier.contains('recognizer');

    if (isActivityScreen) {
      playBgm(BgmType.activity);
    } else {
      stopBgm();
    }
  }

  /// Plays background music continuously without restarting or colliding during concurrent calls
  Future<void> playBgm([BgmType type = BgmType.menu]) async {
    if (_isDisposed || _currentBgm == type || _isBgmLoading) return;

    _isBgmLoading = true;
    final previousBgm = _currentBgm;
    _currentBgm = type;
    _isDucked = false;

    if (_isBgmMuted || type == BgmType.none) {
      await _safeExecute(() => _bgmPlayer.stop());
      _isBgmLoading = false;
      notifyListeners();
      return;
    }

    await _safeExecute(() async {
      final String assetPath =
          type == BgmType.menu ? _menuBgmAsset : _activityBgmAsset;

      try {
        await _bgmPlayer.stop();
        await _bgmPlayer.setAsset(assetPath);
        await _bgmPlayer.setVolume(_bgmVolume);
        await _bgmPlayer.play();
      } catch (e) {
        debugPrint("BGM playback error: $e");
        if (_currentBgm == type) {
          _currentBgm = previousBgm;
        }
      }
    });

    _isBgmLoading = false;
    notifyListeners();
  }

  /// Stops background music when exiting screens or activities[cite: 7]
  Future<void> stopBgm() async {
    if (_isDisposed) return;
    _currentBgm = BgmType.none;
    _isDucked = false;
    await _safeExecute(() => _bgmPlayer.stop());
    notifyListeners();
  }

  /// Audio controls & toggles[cite: 7]
  void toggleBgmMute() {
    if (_isDisposed) return;
    _isBgmMuted = !_isBgmMuted;
    if (_isBgmMuted) {
      _safeExecute(() => _bgmPlayer.pause());
    } else {
      if (_currentBgm != BgmType.none) {
        final previousBgm = _currentBgm;
        _currentBgm = BgmType.none;
        playBgm(previousBgm);
      }
    }
    notifyListeners();
  }

  void toggleSfxMute() {
    if (_isDisposed) return;
    _isSfxMuted = !_isSfxMuted;
    notifyListeners();
  }

  void toggleSound() => toggleSfxMute();

  void setBgmVolume(double volume) {
    if (_isDisposed) return;
    _bgmVolume = volume.clamp(0.0, 1.0);
    _safeExecute(() => _bgmPlayer.setVolume(_isDucked ? _bgmVolume * _duckingFactor : _bgmVolume));
    notifyListeners();
  }

  void setSfxVolume(double volume) {
    if (_isDisposed) return;
    _sfxVolume = volume.clamp(0.0, 1.0);
    notifyListeners();
  }

  // Sound Effects Triggers[cite: 7]
  Future<void> playCorrect() async => _playSfx(_correctSfxAsset);
  Future<void> playIncorrect() async => _playSfx(_incorrectSfxAsset);

  Future<void> playGameOver() async {
    await _playSfx(_gameOverSfxAsset, stopBgmOnFinish: true);
  }

  Future<void> playLevelComplete() async {
    await _playSfx(_levelCompleteSfxAsset, stopBgmOnFinish: true);
  }

  /// Lowers background music volume slightly during feedback SFX[cite: 7]
  Future<void> _duckBgm() async {
    if (_isBgmMuted || _currentBgm == BgmType.none || _isDisposed) return;
    _isDucked = true;
    await _safeExecute(() => _bgmPlayer.setVolume(_bgmVolume * _duckingFactor));
  }

  /// Restores background music volume to normal level[cite: 7]
  Future<void> _restoreBgm() async {
    if (!_isDucked || _isDisposed) return;
    _isDucked = false;
    if (_isBgmMuted || _currentBgm == BgmType.none) return;
    await _safeExecute(() => _bgmPlayer.setVolume(_bgmVolume));
  }

  /// Plays feedback SFX over BGM without interrupting the background track[cite: 7]
  Future<void> _playSfx(String assetPath, {bool stopBgmOnFinish = false}) async {
    if (_isSfxMuted || _isDisposed) return;

    await _safeExecute(() async {
      await _duckBgm();

      await _sfxPlayer.stop();
      await _sfxPlayer.setAsset(assetPath);
      await _sfxPlayer.setVolume(_sfxVolume);
      await _sfxPlayer.play();

      _sfxPlayer.playerStateStream
          .firstWhere((state) => state.processingState == ja.ProcessingState.completed)
          .then((_) async {
        if (_isDisposed) return;
        if (stopBgmOnFinish) {
          await stopBgm();
        } else {
          await _restoreBgm();
        }
      }).catchError((e) {
        debugPrint("SFX stream completion exception handled: $e");
      });
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _safeExecute(() async {
      await _bgmPlayer.dispose();
      await _sfxPlayer.dispose();
    });
    super.dispose();
  }
}

/// Custom NavigatorObserver that intercepts route transitions globally[cite: 7]
class AppSoundObserver extends NavigatorObserver {
  final SoundProvider soundProvider;

  AppSoundObserver(this.soundProvider);

  void _updateRouteBgm(Route<dynamic>? route) {
    if (route == null) return;

    String routeIdentifier = route.settings.name ?? '';

    if (routeIdentifier.isEmpty) {
      try {
        final dynamic dynamicRoute = route;
        if (dynamicRoute.builder != null) {
          routeIdentifier = dynamicRoute.builder.toString();
        }
      } catch (_) {}
    }

    if (routeIdentifier.isEmpty) {
      routeIdentifier = route.toString();
    }

    soundProvider.handleRouteTransition(routeName: routeIdentifier);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _updateRouteBgm(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _updateRouteBgm(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _updateRouteBgm(newRoute);
  }
}