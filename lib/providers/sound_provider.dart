import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class SoundProvider with ChangeNotifier {
  final AudioPlayer _bgmPlayer = AudioPlayer();
  final AudioPlayer _sfxPlayer = AudioPlayer();

  bool _isSoundEnabled = true;

  bool get isSoundEnabled => _isSoundEnabled;

  SoundProvider() {
    // Set background music to loop continuously
    _bgmPlayer.setReleaseMode(ReleaseMode.loop);
  }

  // Toggle sound ON/OFF globally
  void toggleSound() {
    _isSoundEnabled = !_isSoundEnabled;
    if (!_isSoundEnabled) {
      _bgmPlayer.pause();
    } else {
      _bgmPlayer.resume();
    }
    notifyListeners();
  }

  // ==========================================
  // BACKGROUND MUSIC CONTROLS
  // ==========================================
  Future<void> playBgm() async {
    if (_isSoundEnabled) {
      try {
        await _bgmPlayer.play(AssetSource('sounds/bgm.mp3'));
      } catch (e) {
        debugPrint('Error playing BGM: $e');
      }
    }
  }

  Future<void> stopBgm() async {
    try {
      await _bgmPlayer.stop();
    } catch (e) {
      debugPrint('Error stopping BGM: $e');
    }
  }

  // ==========================================
  // SOUND EFFECTS CONTROLS
  // ==========================================
  Future<void> _playSfx(String fileName) async {
    if (_isSoundEnabled) {
      try {
        await _sfxPlayer.stop(); // Stop any currently playing SFX first
        await _sfxPlayer.play(AssetSource('sounds/$fileName'));
      } catch (e) {
        debugPrint('Error playing SFX ($fileName): $e');
      }
    }
  }

  Future<void> playCorrect() async => _playSfx('correct.wav');

  Future<void> playIncorrect() async => _playSfx('incorrect.mp3');

  Future<void> playGameOver() async => _playSfx('gameover.mp3');

  Future<void> playLevelComplete() async => _playSfx('levelcomplete.wav');

  @override
  void dispose() {
    _bgmPlayer.dispose();
    _sfxPlayer.dispose();
    super.dispose();
  }
}