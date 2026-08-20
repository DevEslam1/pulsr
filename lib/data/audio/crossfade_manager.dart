// lib/data/audio/crossfade_manager.dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';

class CrossfadeManager {
  Duration duration = Duration.zero;
  bool isCrossfading = false;
  int? pendingIndex;
  int _fadeId = 0;
  Completer<void>? _crossfadeCompleter;

  int nextFadeId() => ++_fadeId;
  int get currentFadeId => _fadeId;

  Future<void> fadeVolume(
    AudioPlayer player,
    double from,
    double to,
    Duration fadeDuration,
    int fadeId,
  ) async {
    if (fadeDuration == Duration.zero) {
      await player.setVolume(to);
      return;
    }
    const steps = 20;
    final stepDuration = Duration(milliseconds: (fadeDuration.inMilliseconds / steps).round());
    final volumeDelta = (to - from) / steps;

    await player.setVolume(from);
    for (int i = 1; i <= steps; i++) {
      if (_fadeId != fadeId) break;
      await Future.delayed(stepDuration);
      if (_fadeId != fadeId) break;
      final nextVolume = (from + volumeDelta * i).clamp(0.0, 1.0);
      await player.setVolume(nextVolume);
    }
  }

  void cancel(AudioPlayer inactivePlayer, AudioPlayer activePlayer) {
    if (isCrossfading) {
      _fadeId++;
      isCrossfading = false;
      pendingIndex = null;
      inactivePlayer.stop();
      inactivePlayer.setVolume(1.0);
      activePlayer.setVolume(1.0);
      if (_crossfadeCompleter != null && !_crossfadeCompleter!.isCompleted) {
        _crossfadeCompleter!.complete();
      }
      _crossfadeCompleter = null;
    }
  }

  Future<void> waitForActiveCrossfade() async {
    if (isCrossfading && _crossfadeCompleter != null) {
      try {
        await _crossfadeCompleter!.future.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  void beginCrossfade(int targetIndex) {
    isCrossfading = true;
    pendingIndex = targetIndex;
    _crossfadeCompleter = Completer<void>();
  }

  void finishCrossfade() {
    isCrossfading = false;
    pendingIndex = null;
    if (_crossfadeCompleter != null && !_crossfadeCompleter!.isCompleted) {
      _crossfadeCompleter!.complete();
    }
    _crossfadeCompleter = null;
  }
}
