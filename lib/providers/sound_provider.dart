import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart' as ja;

enum BgmType { none, menu, activity }

/// Background music + sound effects (just_audio).
///
/// BGM is owned by a stack of claims: every screen that wants music claims it
/// ([claimBgm]) and releases it when it closes ([releaseBgm]); the top claim
/// decides what plays, and no claim means silence. So a child screen's own
/// music replaces its parent's, and returning to the parent resumes the
/// parent's music no matter in which order push / pop / dispose arrive.
/// All player changes are applied one at a time in order (no dropped or
/// overlapping requests), music pauses while the app is in the background,
/// and resuming the same track continues where it was paused.
class SoundProvider extends ChangeNotifier with WidgetsBindingObserver {
  final ja.AudioPlayer _bgmPlayer = ja.AudioPlayer();
  final ja.AudioPlayer _sfxPlayer = ja.AudioPlayer();

  /// (owner, music) claims; the last one wins.
  final List<MapEntry<Object, BgmType>> _claims = [];

  /// Owner used by the legacy [playBgm] / [stopBgm] calls.
  static final Object _legacyOwner = Object();

  BgmType _loaded = BgmType.none; // asset currently loaded in the player
  bool _playing = false;
  bool _applying = false;
  bool _dirty = false;
  bool _inBackground = false;

  bool _isBgmMuted = false;
  bool _isSfxMuted = false;
  bool _isDucked = false;
  bool _isDisposed = false;

  double _bgmVolume = 0.4;
  double _sfxVolume = 1.0;

  // Percentage of normal BGM volume during SFX playback (30%).
  static const double _duckingFactor = 0.30;

  static const String _menuBgmAsset = 'assets/sounds/bgm.mp3';
  static const String _activityBgmAsset = 'assets/sounds/gamebgm.mp3';

  static const String _correctSfxAsset = 'assets/sounds/correct.wav';
  static const String _incorrectSfxAsset = 'assets/sounds/incorrect.mp3';
  static const String _gameOverSfxAsset = 'assets/sounds/gameover.mp3';
  static const String _levelCompleteSfxAsset = 'assets/sounds/levelcomplete.wav';

  SoundProvider() {
    WidgetsBinding.instance.addObserver(this);
    _safeExecute(() => _bgmPlayer.setLoopMode(ja.LoopMode.one));
  }

  /// Centralized exception wrapper preventing unhandled platform channel crashes.
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
    if (_isDisposed) return;
    // Screens claim music from initState / dispose, i.e. while the tree is
    // building; listeners must not be marked dirty during that phase.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks || phase == SchedulerPhase.midFrameMicrotasks) {
      if (_notifyScheduled) return;
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (!_isDisposed) super.notifyListeners();
      });
      return;
    }
    super.notifyListeners();
  }

  bool _notifyScheduled = false;

  // Getters
  /// The music the screens currently ask for (even while muted / paused).
  BgmType get currentBgm => _claims.isEmpty ? BgmType.none : _claims.last.value;
  bool get isBgmMuted => _isBgmMuted;
  bool get isBgmPlaying => _playing;
  bool get isSfxMuted => _isSfxMuted;
  bool get isSoundEnabled => !_isSfxMuted;
  double get bgmVolume => _bgmVolume;
  double get sfxVolume => _sfxVolume;

  /// NavigatorObserver that gives quiz / game screens the activity music.
  NavigatorObserver get navigatorObserver => AppSoundObserver(this);

  // ---------------------------------------------------------------------------
  // Claims
  // ---------------------------------------------------------------------------

  /// [owner] (usually a State or a Route) wants [type] while it is on top.
  void claimBgm(Object owner, [BgmType type = BgmType.menu]) {
    if (_isDisposed) return;
    _claims.removeWhere((c) => identical(c.key, owner));
    _claims.add(MapEntry(owner, type));
    _sync();
  }

  /// [owner] no longer needs music (screen closed).
  void releaseBgm(Object owner) {
    if (_isDisposed) return;
    final before = _claims.length;
    _claims.removeWhere((c) => identical(c.key, owner));
    if (_claims.length != before) _sync();
  }

  /// Legacy API: plays [type] until [stopBgm]. Prefer [claimBgm].
  Future<void> playBgm([BgmType type = BgmType.menu]) async => claimBgm(_legacyOwner, type);

  /// Legacy API: drops the [playBgm] request (screen claims are kept).
  Future<void> stopBgm() async => releaseBgm(_legacyOwner);

  /// Kept for older call sites: route-name based music is now decided by
  /// [AppSoundObserver] claims.
  void handleRouteTransition({String? routeName}) {}

  // ---------------------------------------------------------------------------
  // Player
  // ---------------------------------------------------------------------------

  /// Brings the player in line with the claims, one change at a time.
  /// Runs after the current frame's synchronous work (claims arrive from
  /// initState / dispose / navigator callbacks).
  Future<void> _sync() async {
    if (_isDisposed) return;
    if (_applying) {
      _dirty = true;
      return;
    }
    _applying = true;
    await Future<void>.delayed(Duration.zero); // claims made meanwhile set _dirty / are read below
    if (_isDisposed) return;
    try {
      do {
        _dirty = false;
        final want = (_isBgmMuted || _inBackground) ? BgmType.none : currentBgm;
        if (want == BgmType.none) {
          if (_playing) await _safeExecute(() => _bgmPlayer.pause());
          _playing = false;
          // Nobody wants this track any more: start it from the top next time.
          if (currentBgm == BgmType.none && _loaded != BgmType.none) {
            await _safeExecute(() => _bgmPlayer.stop());
            _loaded = BgmType.none;
          }
        } else {
          if (_loaded != want) {
            // Switching tracks (bgm.mp3 <-> gamebgm.mp3): stop() ends the old
            // track, so the new one must be started below.
            _playing = false;
            await _safeExecute(() async {
              await _bgmPlayer.stop();
              _loaded = BgmType.none;
              await _bgmPlayer.setAsset(want == BgmType.menu ? _menuBgmAsset : _activityBgmAsset);
              _loaded = want;
            });
          }
          if (_loaded == want && !_playing) {
            await _safeExecute(() => _bgmPlayer.setVolume(_isDucked ? _bgmVolume * _duckingFactor : _bgmVolume));
            // play() completes only when playback stops, so it is not awaited.
            _bgmPlayer.play().catchError((e) => debugPrint("BGM playback error: $e"));
            _playing = true;
          }
        }
      } while (_dirty && !_isDisposed);
    } finally {
      _applying = false;
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final background = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (state == AppLifecycleState.resumed || background) {
      if (_inBackground == background) return;
      _inBackground = background;
      _sync();
    }
  }

  /// Audio controls & toggles
  void toggleBgmMute() {
    if (_isDisposed) return;
    _isBgmMuted = !_isBgmMuted;
    notifyListeners();
    _sync();
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

  // ---------------------------------------------------------------------------
  // Sound effects
  // ---------------------------------------------------------------------------

  Future<void> playCorrect() async => _playSfx(_correctSfxAsset);
  Future<void> playIncorrect() async => _playSfx(_incorrectSfxAsset);

  /// Name-based effect ("correct", "wrong" / "incorrect", "gameover", "levelcomplete").
  Future<void> playSound(String effect) async {
    final e = effect.toLowerCase();
    if (e.contains('incorrect') || e.contains('wrong')) return playIncorrect();
    if (e.contains('correct')) return playCorrect();
    if (e.contains('over')) return playGameOver();
    if (e.contains('complete')) return playLevelComplete();
  }

  Future<void> playSoundEffect(String effect) => playSound(effect);

  Future<void> playGameOver() async => _playSfx(_gameOverSfxAsset);
  Future<void> playLevelComplete() async => _playSfx(_levelCompleteSfxAsset);

  /// Lowers background music volume slightly during feedback SFX.
  Future<void> _duckBgm() async {
    if (!_playing || _isDisposed) return;
    _isDucked = true;
    await _safeExecute(() => _bgmPlayer.setVolume(_bgmVolume * _duckingFactor));
  }

  /// Restores background music volume to normal level.
  Future<void> _restoreBgm() async {
    if (!_isDucked || _isDisposed) return;
    _isDucked = false;
    await _safeExecute(() => _bgmPlayer.setVolume(_bgmVolume));
  }

  /// Plays feedback SFX over BGM without interrupting the background track.
  Future<void> _playSfx(String assetPath) async {
    if (_isSfxMuted || _isDisposed) return;

    await _safeExecute(() async {
      await _duckBgm();
      await _sfxPlayer.stop();
      await _sfxPlayer.setAsset(assetPath);
      await _sfxPlayer.setVolume(_sfxVolume);
      _sfxPlayer.play().catchError((e) => debugPrint("SFX playback error: $e"));

      _sfxPlayer.playerStateStream
          .firstWhere((state) => state.processingState == ja.ProcessingState.completed)
          .then((_) => _restoreBgm())
          .catchError((e) => debugPrint("SFX stream completion exception handled: $e"));
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _bgmPlayer.dispose();
    _sfxPlayer.dispose();
    super.dispose();
  }
}

/// Gives quiz / game screens (recognised by their widget name) the activity
/// music while they are open. Other routes do not touch the music: screens
/// that want menu music claim it themselves ([SoundProvider.claimBgm]).
class AppSoundObserver extends NavigatorObserver {
  final SoundProvider soundProvider;

  AppSoundObserver(this.soundProvider);

  // Fallback for screens that do not claim music themselves (the activity
  // levels claim it in their State).
  static const List<String> _gameKeywords = ['solochallenge', 'quiz', 'exercise', 'minigame'];

  static bool _isGameRoute(Route<dynamic> route) {
    String id = route.settings.name ?? '';
    if (id.isEmpty) {
      try {
        final dynamic r = route;
        if (r.builder != null) id = r.builder.toString();
      } catch (_) {}
    }
    final key = id.toLowerCase();
    return _gameKeywords.any(key.contains);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (_isGameRoute(route)) soundProvider.claimBgm(route, BgmType.activity);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    soundProvider.releaseBgm(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    soundProvider.releaseBgm(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null) soundProvider.releaseBgm(oldRoute);
    if (newRoute != null && _isGameRoute(newRoute)) soundProvider.claimBgm(newRoute, BgmType.activity);
  }
}
