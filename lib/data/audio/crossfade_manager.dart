// lib/data/audio/crossfade_manager.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:just_audio/just_audio.dart';
import 'package:mutex/mutex.dart';
import '../../core/utils/error_logger.dart';

/// Supported crossfade curves.
enum CrossfadeCurve {
  linear('Linear', 'Equal slope linear volume ramp'),
  equalPower(
      'Equal Power', 'Constant perceived acoustic loudness (sine/cosine)'),
  sCurve('S-Curve', 'Smooth ease-in ease-out transition'),
  exponential('Exponential', 'Natural logarithmic acoustic response'),
  djCutDrop('DJ Cut/Drop', 'Aggressive club DJ blend with quick drop-in');

  final String label;
  final String description;
  const CrossfadeCurve(this.label, this.description);
}

/// Transition type determined by crossfade arbitration authority.
enum TransitionType { gapless, crossfade }

/// Outcome of transition arbitration.
class TransitionDecision {
  final TransitionType type;
  final Duration effectiveDuration;
  final String reason;

  const TransitionDecision({
    required this.type,
    required this.effectiveDuration,
    required this.reason,
  });

  bool get isCrossfade => type == TransitionType.crossfade;
  bool get isGapless => type == TransitionType.gapless;
}

/// Manages crossfading between two [AudioPlayer] instances with atomic concurrency,
/// selectable DSP loudness curves, BPM beat alignment, and robust cancellation safety.
class CrossfadeManager {
  final Mutex _fadeMutex = Mutex();
  final List<Timer> _activeTimers = [];
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
  Future<T> protect<T>(Future<T> Function() action) =>
      _fadeMutex.protect(action);

  /// Calculates beat-aligned duration if BPM is provided.
  static Duration calculateBpmAlignedDuration(
      Duration baseDuration, double? bpm) {
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
    return Duration(
        milliseconds: (alignedSeconds * 1000).round().clamp(1000, 20000));
  }

  /// Returns the effective crossfade duration, optionally aligned to song [bpm].
  Duration getEffectiveDuration({double? bpm}) =>
      bpm != null ? calculateBpmAlignedDuration(duration, bpm) : duration;

  /// Evaluates the curve fraction (0.0 to 1.0) based on active [curve].
  /// Always returns 0→1; the caller controls direction via [from]/[to].
  double evaluateCurve(double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    switch (curve) {
      case CrossfadeCurve.linear:
        return f;

      case CrossfadeCurve.equalPower:
        return math.sin(f * (math.pi / 2));

      case CrossfadeCurve.sCurve:
        // Smoothstep: 3f^2 - 2f^3
        return f * f * (3.0 - 2.0 * f);

      case CrossfadeCurve.exponential:
        return f == 0.0 ? 0.0 : math.pow(2.0, 10.0 * (f - 1.0)).toDouble();

      case CrossfadeCurve.djCutDrop:
        // Sharp attack after midpoint
        return f < 0.2
            ? f * 1.5
            : (0.3 + 0.7 * math.sin((f - 0.2) / 0.8 * (math.pi / 2)));
    }
  }

  /// Evaluates both old (fade-out) and new (fade-in) gains for a given [fraction] (0.0 to 1.0)
  /// ensuring constant acoustic power for equal-power curves ($cos^2 + sin^2 = 1.0$).
  (double oldGain, double newGain) evaluateGainPair(double fraction,
      {bool isRepeatOne = false}) {
    final f = fraction.clamp(0.0, 1.0);
    if (isRepeatOne) {
      // Linear equal-gain for identical correlated signals
      return (1.0 - f, f);
    }
    switch (curve) {
      case CrossfadeCurve.linear:
        return (1.0 - f, f);
      case CrossfadeCurve.equalPower:
        final theta = f * (math.pi / 2.0);
        return (math.cos(theta), math.sin(theta));
      case CrossfadeCurve.sCurve:
        final s = f * f * (3.0 - 2.0 * f);
        return (1.0 - s, s);
      case CrossfadeCurve.exponential:
        final inGain =
            f == 0.0 ? 0.0 : math.pow(2.0, 10.0 * (f - 1.0)).toDouble();
        final outGain = (1.0 - f) == 0.0
            ? 0.0
            : math.pow(2.0, 10.0 * ((1.0 - f) - 1.0)).toDouble();
        return (outGain, inGain);
      case CrossfadeCurve.djCutDrop:
        final inGain = f < 0.2
            ? f * 1.5
            : (0.3 + 0.7 * math.sin((f - 0.2) / 0.8 * (math.pi / 2)));
        final outGain = (1.0 - f) < 0.2
            ? (1.0 - f) * 1.5
            : (0.3 + 0.7 * math.sin(((1.0 - f) - 0.2) / 0.8 * (math.pi / 2)));
        return (outGain, inGain);
    }
  }

  /// Arbitrates the transition between outgoing track and incoming track.
  /// Returns [TransitionType.gapless] or [TransitionType.crossfade].
  static TransitionDecision arbitrateTransition({
    required Duration configuredCrossfade,
    required Duration remainingTrackDuration,
    required bool isSameDecoderConfig,
    required bool isRepeatOne,
  }) {
    if (configuredCrossfade == Duration.zero ||
        configuredCrossfade.inMilliseconds < 100) {
      return const TransitionDecision(
        type: TransitionType.gapless,
        effectiveDuration: Duration.zero,
        reason: 'Crossfade disabled (0s)',
      );
    }

    if (remainingTrackDuration < const Duration(seconds: 1)) {
      return const TransitionDecision(
        type: TransitionType.gapless,
        effectiveDuration: Duration.zero,
        reason: 'Remaining track duration < 1s; skipping crossfade for safety',
      );
    }

    // Clamp duration to min(configured, remaining - 500ms)
    final maxAllowedFade =
        remainingTrackDuration - const Duration(milliseconds: 500);
    final clampedDuration = configuredCrossfade > maxAllowedFade
        ? maxAllowedFade
        : configuredCrossfade;
    final effectiveFade = clampedDuration < const Duration(milliseconds: 500)
        ? const Duration(milliseconds: 500)
        : clampedDuration;

    return TransitionDecision(
      type: TransitionType.crossfade,
      effectiveDuration: effectiveFade,
      reason:
          'Crossfade active (${effectiveFade.inMilliseconds}ms, ${isRepeatOne ? "linear" : "equalPower"})',
    );
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

    late final Timer timer;
    timer = Timer.periodic(const Duration(milliseconds: 33), (t) {
      if (_fadeId != fadeId) {
        t.cancel();
        _activeTimers.remove(t);
        if (!completer.isCompleted) completer.complete();
        return;
      }

      final elapsed = stopwatch.elapsedMilliseconds.toDouble();
      final fraction = (elapsed / totalMs).clamp(0.0, 1.0);

      final curveFraction = evaluateCurve(fraction);
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
        t.cancel();
        _activeTimers.remove(t);
        if (!completer.isCompleted) completer.complete();
        return;
      }

      if (fraction >= 1.0) {
        t.cancel();
        _activeTimers.remove(t);
        if (!completer.isCompleted) completer.complete();
      }
    });

    _activeTimers.add(timer);
    return completer.future;
  }

  /// Cancels any active crossfade safely and resets player states.
  Future<void> cancel(
    AudioPlayer inactivePlayer,
    AudioPlayer activePlayer, {
    double restoreVolume = 1.0,
  }) async {
    final hadActiveFade =
        isCrossfading || _activeTimers.isNotEmpty || _fadeTimer != null;
    if (!hadActiveFade) return;

    _fadeId++; // Invalidate any in-progress fade timers
    for (final t in _activeTimers) {
      t.cancel();
    }
    _activeTimers.clear();
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
