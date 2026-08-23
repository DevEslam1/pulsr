import 'dart:async';
import 'dart:math' as math;
import 'package:just_audio/just_audio.dart';
import '../../core/utils/error_logger.dart';

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
      await Future.delayed(const Duration(milliseconds: 50));
      if (_fadeId != fadeId) break;
      final elapsed = DateTime.now().difference(startTime).inMilliseconds.toDouble();
      final fraction = (elapsed / totalMs).clamp(0.0, 1.0);

      // Equal-power crossfade curve: constant perceived acoustic energy
      final double curveFraction;
      if (to > from) {
        // Fade in
        curveFraction = math.sin(fraction * (math.pi / 2));
      } else {
        // Fade out
        curveFraction = 1.0 - math.cos((1.0 - fraction) * (math.pi / 2));
      }

      final currentVol = from + (to - from) * curveFraction;
      try {
        await player.setVolume(currentVol.clamp(0.0, 1.0));
      } catch (e, st) {
        ErrorLogger.log('Error adjusting volume during fade', error: e, stackTrace: st, category: 'CrossfadeManager');
        break;
      }
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
      } catch (e, st) {
        ErrorLogger.log('Error canceling crossfade players', error: e, stackTrace: st, category: 'CrossfadeManager');
      }
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
      } catch (e, st) {
        ErrorLogger.log('Timeout waiting for active crossfade to finish', error: e, stackTrace: st, category: 'CrossfadeManager');
      }
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
