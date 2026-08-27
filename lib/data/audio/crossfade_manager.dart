// lib/data/audio/crossfade_manager.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:just_audio/just_audio.dart';
import 'package:mutex/mutex.dart';
import '../../core/utils/error_logger.dart';

/// Supported crossfade curves.
enum CrossfadeCurve {
  linear('Linear', 'Equal slope linear volume ramp'),
  equalPower('Equal Power', 'Constant perceived acoustic loudness (sine/cosine)'),
  sCurve('S-Curve', 'Smooth ease-in ease-out transition'),
  exponential('Exponential', 'Natural logarithmic acoustic response'),
  djCutDrop('DJ Cut/Drop', 'Aggressive club DJ blend with quick drop-in');

  final String label;
  final String description;
  const CrossfadeCurve(this.label, this.description);
}

/// Manages crossfading between two [AudioPlayer] instances with atomic concurrency,
/// selectable DSP loudness curves, BPM beat alignment, and robust cancellation safety.
class CrossfadeManager {
  final Mutex _fadeMutex = Mutex();
  Timer? _fadeTimer;

  Duration duration = Duration.zero;
  CrossfadeCurve curve = CrossfadeCurve.equalPower;
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

  /// Calculates beat-aligned duration if BPM is provided.
  static Duration calculateBpmAlignedDuration(Duration baseDuration, double? bpm) {
    if (bpm == null || bpm <= 40.0 || bpm >= 240.0) return baseDuration;
    final secondsPerBeat = 60.0 / bpm;
    // Align to nearest 2, 4, 8, or 16 beats
    final baseSec = baseDuration.inMilliseconds / 1000.0;
    if (baseSec <= 0) return Duration.zero;

    final candidateBeats = [2.0, 4.0, 8.0, 16.0, 32.0];
    double bestBeats = 4.0;
    double bestDiff = double.infinity;

    for (final beats in candidateBeats) {
      final durationForBeats = beats * secondsPerBeat;
      final diff = (durationForBeats - baseSec).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestBeats = beats;
      }
    }

    final alignedSeconds = bestBeats * secondsPerBeat;
    return Duration(milliseconds: (alignedSeconds * 1000).round().clamp(1000, 20000));
  }

  /// Evaluates the curve fraction (0.0 to 1.0) based on active [curve].
  double evaluateCurve(double fraction, bool isFadeIn) {
    final f = fraction.clamp(0.0, 1.0);
    switch (curve) {
      case CrossfadeCurve.linear:
        return isFadeIn ? f : (1.0 - f);

      case CrossfadeCurve.equalPower:
        return isFadeIn
            ? math.sin(f * (math.pi / 2))
            : (1.0 - math.cos(f * (math.pi / 2)));

      case CrossfadeCurve.sCurve:
        // Smoothstep: 3f^2 - 2f^3
        final s = f * f * (3.0 - 2.0 * f);
        return isFadeIn ? s : (1.0 - s);

      case CrossfadeCurve.exponential:
        if (isFadeIn) {
          return f == 0.0 ? 0.0 : math.pow(2.0, 10.0 * (f - 1.0)).toDouble();
        } else {
          return f == 1.0 ? 1.0 : (1.0 - math.pow(2.0, -10.0 * f).toDouble());
        }

      case CrossfadeCurve.djCutDrop:
        if (isFadeIn) {
          // Sharp attack after midpoint
          return f < 0.2 ? f * 1.5 : (0.3 + 0.7 * math.sin((f - 0.2) / 0.8 * (math.pi / 2)));
        } else {
          // Drops quickly past midpoint
          return f > 0.6 ? (1.0 - f) * 2.5 : (1.0 - 0.4 * (f / 0.6));
        }
    }
  }

  /// Gradually transitions the volume of [player] from [from] to [to] over [fadeDuration]
  /// using the selected [curve] sampled at 16ms intervals (~60 FPS).
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
    final stopwatch = Stopwatch()..start();
    final isFadeIn = to > from;

    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_fadeId != fadeId) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }

      final elapsed = stopwatch.elapsedMilliseconds.toDouble();
      final fraction = (elapsed / totalMs).clamp(0.0, 1.0);

      final curveFraction = evaluateCurve(fraction, isFadeIn);
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
