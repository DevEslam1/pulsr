import 'dart:async';
import 'dart:math' as math;
import 'package:just_audio/just_audio.dart';
import 'package:mutex/mutex.dart';
import '../../core/utils/error_logger.dart';

/// Manages crossfading between two [AudioPlayer] instances with atomic concurrency,
/// equal-power loudness curves, and robust cancellation safety.
class CrossfadeManager {
  final Mutex _fadeMutex = Mutex();
  Timer? _fadeTimer;

  Duration duration = Duration.zero;
  bool isCrossfading = false;
  int? pendingIndex;
  int _fadeId = 0;
  Completer<void>? _crossfadeCompleter;

  Mutex get mutex => _fadeMutex;

  /// Returns the next fade identifier.
  int nextFadeId() => ++_fadeId;
  int get currentFadeId => _fadeId;

  /// Executes [action] with exclusive access to the crossfade pipeline.
  Future<T> protect<T>(Future<T> Function() action) => _fadeMutex.protect(action);

  /// Gradually transitions the volume of [player] from [from] to [to] over [fadeDuration]
  /// using an equal-power crossfade curve sampled at 16ms intervals (~60 FPS).
  Future<void> fadeVolume(
    AudioPlayer player,
    double from,
    double to,
    Duration fadeDuration,
    int fadeId,
  ) async {
    if (fadeDuration == Duration.zero) {
      await player.setVolume(to.clamp(0.0, 1.0));
      return;
    }

    final totalMs = fadeDuration.inMilliseconds.toDouble();
    if (totalMs <= 0) {
      await player.setVolume(to.clamp(0.0, 1.0));
      return;
    }

    final completer = Completer<void>();
    final startTime = DateTime.now();

    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_fadeId != fadeId) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }

      final elapsed = DateTime.now().difference(startTime).inMilliseconds.toDouble();
      final fraction = (elapsed / totalMs).clamp(0.0, 1.0);

      // Equal-power crossfade curve: maintains perceived constant acoustic volume
      final double curveFraction;
      if (to > from) {
        // Fade in: sin(fraction * pi / 2)
        curveFraction = math.sin(fraction * (math.pi / 2));
      } else {
        // Fade out: 1 - cos(fraction * pi / 2) -> fraction 0 -> curve 0 (vol=from), fraction 1 -> curve 1 (vol=to)
        curveFraction = 1.0 - math.cos(fraction * (math.pi / 2));
      }

      final currentVol = from + (to - from) * curveFraction;
      try {
        player.setVolume(currentVol.clamp(0.0, 1.0));
      } catch (e, st) {
        ErrorLogger.log(
          'Error adjusting volume during fade',
          error: e,
          stackTrace: st,
          category: 'CrossfadeManager',
        );
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }

      if (fraction >= 1.0) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });

    return completer.future;
  }

  /// Cancels any active crossfade safely and resets player states.
  Future<void> cancel(
    AudioPlayer inactivePlayer,
    AudioPlayer activePlayer, {
    double restoreVolume = 1.0,
  }) async {
    final hadActiveFade = isCrossfading || _fadeTimer != null;
    if (!hadActiveFade) return;

    _fadeId++; // Invalidate any in-progress fade timers
    _fadeTimer?.cancel();
    _fadeTimer = null;
    isCrossfading = false; // Set BEFORE stopping players
    pendingIndex = null;

    try {
      await inactivePlayer.stop();
      try {
        await inactivePlayer
            .setAudioSource(AudioSource.uri(Uri.parse('about:blank')));
      } catch (_) {}
      await inactivePlayer.setVolume(restoreVolume.clamp(0.0, 1.0));
      await activePlayer.setVolume(restoreVolume.clamp(0.0, 1.0));
    } catch (e, st) {
      ErrorLogger.log(
        'Error canceling crossfade players',
        error: e,
        stackTrace: st,
        category: 'CrossfadeManager',
      );
    }

    // Complete the completer exactly once
    final completer = _crossfadeCompleter;
    _crossfadeCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Awaits the completion of an active crossfade with a 2-second timeout guard.
  Future<void> waitForActiveCrossfade() async {
    if (isCrossfading && _crossfadeCompleter != null) {
      try {
        await _crossfadeCompleter!.future.timeout(const Duration(seconds: 2));
      } catch (e, st) {
        ErrorLogger.log(
          'Timeout waiting for active crossfade to finish',
          error: e,
          stackTrace: st,
          category: 'CrossfadeManager',
        );
      }
    }
  }

  /// Marks the start of a crossfade operation targeting [targetIndex].
  void beginCrossfade(int targetIndex) {
    isCrossfading = true;
    pendingIndex = targetIndex;
    _crossfadeCompleter = Completer<void>();
  }

  /// Concludes the active crossfade state.
  void finishCrossfade() {
    isCrossfading = false;
    pendingIndex = null;
    if (_crossfadeCompleter != null && !_crossfadeCompleter!.isCompleted) {
      _crossfadeCompleter!.complete();
    }
    _crossfadeCompleter = null;
  }

  /// Disposes active timers and resources.
  void dispose() {
    _fadeId++;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    if (_crossfadeCompleter != null && !_crossfadeCompleter!.isCompleted) {
      _crossfadeCompleter!.complete();
    }
    _crossfadeCompleter = null;
  }
}
