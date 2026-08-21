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
    final startTime = DateTime.now();
    final totalMs = fadeDuration.inMilliseconds.toDouble();
    if (totalMs <= 0) {
      await player.setVolume(to);
      return;
    }

    await player.setVolume(from);
    while (_fadeId == fadeId) {
      await Future.delayed(const Duration(milliseconds: 20));
      if (_fadeId != fadeId) break;
      final elapsed = DateTime.now().difference(startTime).inMilliseconds.toDouble();
      final fraction = (elapsed / totalMs).clamp(0.0, 1.0);
      final currentVol = from + (to - from) * fraction;
      await player.setVolume(currentVol.clamp(0.0, 1.0));
      if (fraction >= 1.0) break;
    }
  }

  Future<void> cancel(AudioPlayer inactivePlayer, AudioPlayer activePlayer, {double restoreVolume = 1.0}) async {
    if (isCrossfading) {
      _fadeId++;
      isCrossfading = false;
      pendingIndex = null;
      try {
        await inactivePlayer.stop();
        await inactivePlayer.setVolume(restoreVolume);
        await activePlayer.setVolume(restoreVolume);
      } catch (_) {}
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
