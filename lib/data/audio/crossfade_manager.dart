// lib/data/audio/crossfade_manager.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:clock/clock.dart';
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
  /// BPM-synced crossfade: when true and a BPM value is available for the
  /// incoming track, the configured duration is aligned to the nearest
  /// 2/4/8/16/32 beats via [calculateBpmAlignedDuration].
  bool bpmSyncEnabled = false;
  /// Per-track BPM overrides (track id -> bpm). BPM sources: tag metadata or
  /// manual entry; tracks without an override fall back to the base duration.
  final Map<String, double> bpmOverrides = <String, double>{};
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
    if (bpm == null || !bpm.isFinite) return baseDuration;
    if (bpm <= 40.0 || bpm >= 240.0) {
      ErrorLogger.log(
        'BPM $bpm out of range (40-240) — using base duration',
        category: 'CrossfadeManager',
      );
      return baseDuration;
    }
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

  /// Effective fade duration for an incoming track, honouring BPM sync when
  /// enabled and a BPM override exists for [trackId].
  Duration effectiveFadeDuration({String? trackId}) {
    if (!bpmSyncEnabled || trackId == null) return duration;
    final bpm = bpmOverrides[trackId];
    if (bpm == null) return duration;
    return calculateBpmAlignedDuration(duration, bpm);
  }

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

  /// Sum-safe variant of [evaluateGainPair] for DUAL-PLAYER crossfades.
  ///
  /// The two players are mixed by Android AudioFlinger *after* each player's
  /// DSP chain, and the mixer saturates at full scale. Equal-power gains keep
  /// acoustic POWER constant (`cos²+sin²=1`), but their instantaneous sum
  /// peaks at √2 ≈ 1.41 at the midpoint — whenever both tracks carry
  /// coincident near-full-scale peaks (loud, dynamically compressed masters
  /// do this constantly), the summed sample exceeds 1.0 and hard-clips as
  /// crackle/distortion exactly during the overlap. HAL effects such as the
  /// volume boost ([LoudnessEnhancer], up to +10 dB) push this further.
  ///
  /// The fix scales both gains by `k = sumCeiling / (oldGain + newGain)`
  /// whenever the raw pair's sum exceeds [sumCeiling], guaranteeing
  /// `oldGain + newGain <= sumCeiling` and therefore a worst-case summed
  /// sample of exactly [sumCeiling] (1.0 = no clip even with all peaks
  /// aligned). For UNCORRELATED music the true loudness cost is far below the
  /// worst case: RMS of the sum is `k·sqrt(oldGain²+newGain²)`, so the dip is
  /// at most −3 dB at the very midpoint (0 dB near the endpoints, where the
  /// raw sum already fits under the ceiling), while eliminating the hard-clip
  /// crackle. Endpoints remain exact: f=0 → (1,0), f=1 → (0,1) because the
  /// raw sums there equal 1.0 and are never scaled.
  (double oldGain, double newGain) evaluateSumSafeGainPair(double fraction,
      {bool isRepeatOne = false, double sumCeiling = 1.0}) {
    final (oldGain, newGain) =
        evaluateGainPair(fraction, isRepeatOne: isRepeatOne);
    final sum = oldGain + newGain;
    if (sum > sumCeiling && sum > 0.0) {
      final k = sumCeiling / sum;
      return (oldGain * k, newGain * k);
    }
    return (oldGain, newGain);
  }

  /// Arbitrates the transition between outgoing track and incoming track.
  /// Returns [TransitionType.gapless] or [TransitionType.crossfade].
  static TransitionDecision arbitrateTransition({
    required Duration configuredCrossfade,
    required Duration remainingTrackDuration,
    required bool isSameDecoderConfig,
    required bool isRepeatOne,
    double? nextTrackBufferedFraction,
  }) {
    if (configuredCrossfade == Duration.zero ||
        configuredCrossfade.inMilliseconds < 100) {
      return const TransitionDecision(
        type: TransitionType.gapless,
        effectiveDuration: Duration.zero,
        reason: 'Crossfade disabled (0s)',
      );
    }

    if (nextTrackBufferedFraction != null && nextTrackBufferedFraction < 0.5) {
      return const TransitionDecision(
        type: TransitionType.gapless,
        effectiveDuration: Duration.zero,
        reason:
            'Next track insufficiently buffered (<50%); skipping crossfade for safety',
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
    final effectiveFade = clampedDuration < const Duration(milliseconds: 100)
        ? const Duration(milliseconds: 100)
        : clampedDuration;

    return TransitionDecision(
      type: TransitionType.crossfade,
      effectiveDuration: effectiveFade,
      reason:
          'Crossfade active (${effectiveFade.inMilliseconds}ms, ${isRepeatOne ? "linear" : "equalPower"})',
    );
  }

  /// True when the fade targets absolute silence (pure fade-out).
  static bool _isPureFadeOut(double to) => to <= 0.0;

  /// True when the fade starts from effective silence (pure fade-in).
  static bool _isPureFadeIn(double from) => from <= 0.001;

  /// Number of points used for native gain curves (~15 ms resolution, capped
  /// so the platform-channel payload stays small even for long fades).
  static int _curvePointCount(double totalMs) =>
      (totalMs / 15).ceil().clamp(2, 401);

  /// Arms a native sample-accurate gain curve if the platform (Pulsr Android
  /// fork) supports it. Returns false — without throwing — on any other
  /// platform or failure so callers can fall back to stepped ramps.
  Future<bool> _armNativeCurve(
      AudioPlayer player, List<double> gains, int segmentMs) async {
    try {
      return await player.dspSetGainCurve(gains, segmentMs: segmentMs) == true;
    } catch (_) {
      return false;
    }
  }

  /// Best-effort native curve clear (ignore failures — platform may not
  /// support it; a stale curve then still terminates at its last value).
  void _clearNativeCurve(AudioPlayer player) {
    player.dspClearGainCurve().catchError((_) => false);
  }

  /// Gradually transitions the volume of [player] from [from] to [to] over [fadeDuration]
  /// using the selected [curve] sampled at 10ms intervals (~100 FPS) for
  /// zipper-free ramp. 16ms was still audible as hiss during the overlap.
  ///
  /// Curve interpolation uses the COMPLEMENTARY pair from [evaluateGainPair]
  /// (`from·outGain + to·inGain`), which reduces to the plain curve shape for
  /// linear/s-curve fades and fixes equal-power fade-OUTs: interpolating the
  /// fade-in shape as `from + (to - from)·sin(f)` produced the mirrored
  /// `1 - sin` gain instead of `cos`, ducking ~10 dB below the intended
  /// midpoint and mismatching the matching fade-in.
  ///
  /// On the Pulsr Android fork the two "pure" fade directions (to silence /
  /// from silence) are applied as per-sample gain ramps inside the audio sink
  /// ([AudioPlayer.dspSetGainCurve]) instead of 10 ms stepped setVolume calls,
  /// eliminating mixer-granularity zipper noise; Dart stepping remains the
  /// fallback everywhere else. Mixed fades (both endpoints audible) keep the
  /// stepped path because the native ramp is a multiplier on the player
  /// volume and a mixed curve can exceed 1.0 mid-fade.
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
    final stopwatch = clock.stopwatch()..start();

    // --- Native sample-accurate path (Pulsr Android fork) ---
    // Fade-out: player volume stays at `from`, a 1→0 multiplier follows the
    // fade-out side of the curve. Fade-in: the 0→1 multiplier is armed BEFORE
    // the target volume is applied so the player can never leak through at
    // full gain, then volume is pinned at `to` in one step.
    final points = _curvePointCount(totalMs);
    final segmentMs = (totalMs / (points - 1)).ceil().clamp(1, 1000);
    var nativeArmed = false;
    if (_isPureFadeOut(to)) {
      final gains = List<double>.generate(
          points, (i) => evaluateGainPair(i / (points - 1)).$1);
      nativeArmed = await _armNativeCurve(player, gains, segmentMs);
    } else if (_isPureFadeIn(from)) {
      final gains = List<double>.generate(
          points, (i) => evaluateGainPair(i / (points - 1)).$2);
      nativeArmed = await _armNativeCurve(player, gains, segmentMs);
      if (nativeArmed) {
        try {
          await player.setVolume(to.clamp(0.0, 1.0));
        } catch (_) {
          nativeArmed = false;
        }
      }
    }
    if (nativeArmed) {
      Timer? singleTimer;
      singleTimer = Timer(Duration(milliseconds: totalMs.round()), () {
        _activeTimers.remove(singleTimer);
        if (_fadeId != fadeId) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        try {
          player.setVolume(to.clamp(0.0, 1.0));
        } catch (_) {}
        if (to > 0.0) {
          _clearNativeCurve(player);
        }
        if (!completer.isCompleted) completer.complete();
      });
      _activeTimers.add(singleTimer);
      return completer.future;
    }

    late final Timer timer;
    timer = Timer.periodic(const Duration(milliseconds: 10), (t) {
      if (_fadeId != fadeId) {
        t.cancel();
        _activeTimers.remove(t);
        if (!completer.isCompleted) completer.complete();
        return;
      }

      final elapsed = stopwatch.elapsedMilliseconds.toDouble();
      final fraction = (elapsed / totalMs).clamp(0.0, 1.0);

      if (nativeArmed) {
        // The sink applies the ramp per-sample; this timer only watches for
        // cancellation and fade end.
      } else {
        final (outGain, inGain) = evaluateGainPair(fraction);
        final currentVol = from * outGain + to * inGain;

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
      }

      if (fraction >= 1.0) {
        // Guarantee the exact endpoint volume (also silences a native
        // fade-out whose player volume still reads the pre-fade value).
        try {
          player.setVolume(to.clamp(0.0, 1.0));
        } catch (_) {}
        if (to > 0.0) {
          _clearNativeCurve(player);
        }
        t.cancel();
        _activeTimers.remove(t);
        if (!completer.isCompleted) completer.complete();
      }
    });

    _activeTimers.add(timer);
    return completer.future;
  }

  /// Phase-locked crossfade driving *both* players from a single timer using
  /// [evaluateSumSafeGainPair]. Running two independent [fadeVolume] timers causes
  /// inter-timer jitter (one fires before the other) and — for equal-power —
  /// uses `1 - sin` for the fade-out instead of `cos`, producing a ~3 dB dip
  /// and audible stepping/zipper noise at the midpoint. A single timer
  /// guarantees `cos²+sin²=1` at every tick and 10 ms (~100 fps) granularity
  /// to eliminate the hiss that lasted until the outgoing buffer drained.
  ///
  /// Gains are sum-safe ([evaluateSumSafeGainPair]): the players are summed
  /// and saturated by AudioFlinger AFTER each player's DSP chain, so equal-
  /// power pairs peaking at √2 hard-clip on coincident track peaks exactly
  /// during the overlap (user-audible crackle/distortion).
  ///
  /// On the Pulsr Android fork the OUTGOING player's 1→0 ramp is applied
  /// per-sample inside the audio sink ([AudioPlayer.dspSetGainCurve]); its base
  /// volume is kept and the sink multiplies it down, so there is no per-tick
  /// platform-channel traffic for it. The INCOMING player is always driven by
  /// the 10 ms stepped timer instead — see the inline note for why pinning its
  /// base volume to a native multiplier leaks a full-volume buffer. Every other
  /// platform steps both players.
  Future<void> crossfadeVolumes({
    required AudioPlayer active,
    required AudioPlayer inactive,
    required double fromActiveVol,
    required double toInactiveVol,
    required Duration duration,
    required int fadeId,
    bool isRepeatOne = false,
  }) async {
    if (duration == Duration.zero) {
      await active.setVolume(0.0);
      await inactive.setVolume(toInactiveVol.clamp(0.0, 1.0));
      return;
    }
    final totalMs = duration.inMilliseconds.toDouble();
    if (totalMs <= 0) {
      await active.setVolume(0.0);
      await inactive.setVolume(toInactiveVol.clamp(0.0, 1.0));
      return;
    }
    final completer = Completer<void>();
    final stopwatch = clock.stopwatch()..start();

    // Only the OUTGOING player may use the native per-sample gain ramp. The
    // INCOMING player is always ramped with stepped absolute setVolume calls.
    //
    // Why: the native curve is a *multiplier* on the player's base volume, so
    // fading in requires pinning the base at the target and arming a 0→1
    // multiplier. The platform applies that base-volume change on the main
    // thread while the sink still holds output buffers already rendered at the
    // pre-arm (unity) gain; raising the base exposes up to one buffer of full-
    // gain audio the instant the fade opens — heard as the next track starting
    // loud, then dropping and fading in. Stepping the incoming player's
    // ABSOLUTE volume never lets the base jump past the current fade gain, so
    // no such buffer can leak. The outgoing side is already audible, so its
    // one-buffer latency is inaudible and it keeps the smooth native ramp.
    final points = _curvePointCount(totalMs);
    final segmentMs = (totalMs / (points - 1)).ceil().clamp(1, 1000);
    final oldCurve = List<double>.generate(points, (i) {
      final (o, _) = evaluateSumSafeGainPair(i / (points - 1),
          isRepeatOne: isRepeatOne);
      return o;
    });
    final oldArmed = await _armNativeCurve(active, oldCurve, segmentMs);

    late final Timer timer;
    timer = Timer.periodic(const Duration(milliseconds: 10), (t) {
      if (_fadeId != fadeId) {
        t.cancel();
        _activeTimers.remove(t);
        if (!completer.isCompleted) completer.complete();
        return;
      }
      final elapsed = stopwatch.elapsedMilliseconds.toDouble();
      final fraction = (elapsed / totalMs).clamp(0.0, 1.0);
      final (oldGain, newGain) = evaluateSumSafeGainPair(fraction,
          isRepeatOne: isRepeatOne);
      try {
        // A native-armed outgoing keeps its base volume and ramps inside the
        // sink; only the non-armed side (and always the incoming side) is
        // stepped. Gains are 0→1 scaled by the ReplayGain-compensated peaks;
        // the sum-safe pair bounds oldGain+newGain <= 1 so the AudioFlinger
        // mix of both players cannot exceed full scale.
        if (!oldArmed) {
          active.setVolume((oldGain * fromActiveVol).clamp(0.0, 1.0));
        }
        inactive.setVolume((newGain * toInactiveVol).clamp(0.0, 1.0));
      } catch (e, st) {
        ErrorLogger.log(
          'Error adjusting volume during crossfade',
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
        // Guarantee exact endpoints — avoids leaving at 0.99 due to timing.
        try {
          active.setVolume(0.0);
          inactive.setVolume(toInactiveVol.clamp(0.0, 1.0));
        } catch (_) {}
        if (oldArmed) _clearNativeCurve(active);
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
      // Clear any armed native gain curves BEFORE restoring volumes: a
      // mid-fade curve would otherwise multiply the restored volume down to
      // its held gain and leave the player audibly quiet after a cancel.
      _clearNativeCurve(inactivePlayer);
      _clearNativeCurve(activePlayer);
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
    // FIX-B04: Guard against completing an already completed crossfade completer
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
    // FIX-B04: Complete previous crossfade completer before starting new crossfade
    if (_crossfadeCompleter != null && !_crossfadeCompleter!.isCompleted) {
      _crossfadeCompleter!.complete();
    }
    isCrossfading = true;
    pendingIndex = targetIndex;
    _crossfadeCompleter = Completer<void>();
  }

  /// Concludes the active crossfade state.
  void finishCrossfade() {
    isCrossfading = false;
    pendingIndex = null;
    // FIX-B04: Guard against completing an already completed crossfade completer
    if (_crossfadeCompleter != null && !_crossfadeCompleter!.isCompleted) {
      _crossfadeCompleter!.complete();
    }
    _crossfadeCompleter = null;
  }

  /// Disposes active timers and resources.
  void dispose() {
    _fadeId++;
    for (final t in _activeTimers) {
      t.cancel();
    }
    _activeTimers.clear();
    _fadeTimer?.cancel();
    _fadeTimer = null;
    isCrossfading = false;
    pendingIndex = null;
    // FIX-B04: Guard against completing an already completed crossfade completer
    if (_crossfadeCompleter != null && !_crossfadeCompleter!.isCompleted) {
      _crossfadeCompleter!.complete();
    }
    _crossfadeCompleter = null;
  }
}
