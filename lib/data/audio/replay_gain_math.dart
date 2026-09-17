// lib/data/audio/replay_gain_math.dart
import 'dart:math' as math;

/// Pure ReplayGain volume math, extracted from [PulsrAudioHandler] so the
/// gain staging, preamp selection and clipping prevention can be unit-tested
/// deterministically. Semantics replicate the original handler logic exactly.
class ReplayGainMath {
  /// Returns the final player volume for [volume] given the ReplayGain
  /// [mode] ('off' | 'track' | 'album' | 'auto'), the track/album gain and
  /// peak tags, and the configured preamp values.
  static double apply({
    required String mode,
    required double volume,
    double? trackGainDb,
    double? trackPeak,
    double? albumGainDb,
    double? albumPeak,
    bool albumContext = false,
    double preampWithRg = 0.0,
    double preampWithoutRg = -3.0,
  }) {
    double? gainDb;
    double? peak;

    switch (mode) {
      case 'track':
        gainDb = trackGainDb;
        peak = trackPeak;
        break;
      case 'album':
        gainDb = albumGainDb ?? trackGainDb;
        peak = albumPeak ?? trackPeak;
        break;
      case 'auto':
        if (albumContext && albumGainDb != null) {
          gainDb = albumGainDb;
          peak = albumPeak ?? trackPeak;
        } else {
          gainDb = trackGainDb;
          peak = trackPeak;
        }
        break;
      case 'off':
      default:
        return volume;
    }

    double preampDb;
    // Guard against NaN/Infinity from corrupt tags — fall back to no gain.
    if (gainDb != null &&
        gainDb.isFinite &&
        gainDb != 0.0 &&
        preampWithRg.isFinite &&
        preampWithoutRg.isFinite &&
        volume.isFinite) {
      preampDb = preampWithRg;
    } else {
      if (gainDb == null || !gainDb.isFinite) gainDb = 0.0;
      preampDb = preampWithoutRg.isFinite ? preampWithoutRg : 0.0;
    }
    if (!volume.isFinite) return 0.0;

    final totalGainDb = (gainDb) + preampDb;
    var multiplier = math.pow(10.0, totalGainDb / 20.0).toDouble();

    // Clipping prevention: limit OUTPUT (volume x gain x peak) to 1.0 with
    // 0.5 dB inter-sample peak headroom. The ceiling is expressed as a gain
    // cap relative to the current volume, so quiet slider positions are not
    // needlessly attenuated: unity in always means unity out.
    final effectivePeak = (peak != null && peak.isFinite && peak > 0.0) ? peak : 1.0;
    final interSampleHeadroom =
        math.pow(10.0, -0.5 / 20.0).toDouble(); // ~0.944 (-0.5 dB)
    final maxGain = (volume > 0.0)
        ? interSampleHeadroom / (effectivePeak * volume)
        : interSampleHeadroom / effectivePeak;
    if (multiplier > maxGain) {
      multiplier = maxGain;
    }

    return (volume * multiplier).clamp(0.0, 1.0).toDouble();
  }

  /// Maps a UI mode string to the native DSP mode int (0=off, 1=track, 2=album).
  /// 'auto' resolves via [albumContext], mirroring [apply].
  static int nativeModeFor(String mode, {bool albumContext = false}) {
    switch (mode) {
      case 'track':
        return 1;
      case 'album':
        return 2;
      case 'auto':
        return albumContext ? 2 : 1;
      case 'off':
      default:
        return 0;
    }
  }

  /// Selects the effective preamp: [preampWithRg] when a finite non-zero tag
  /// exists, else [preampWithoutRg]. Mirrors [apply] without volume scaling —
  /// the native stage applies gain itself, so the mixer stays at unity.
  static double nativePreAmpFor({
    required String mode,
    double? trackGainDb,
    double? albumGainDb,
    bool albumContext = false,
    double preampWithRg = 0.0,
    double preampWithoutRg = -3.0,
  }) {
    double? gainDb;
    switch (mode) {
      case 'track':
        gainDb = trackGainDb;
        break;
      case 'album':
        gainDb = albumGainDb ?? trackGainDb;
        break;
      case 'auto':
        gainDb = (albumContext && albumGainDb != null) ? albumGainDb : trackGainDb;
        break;
      default:
        return 0.0;
    }
    final hasTag = gainDb != null && gainDb.isFinite && gainDb != 0.0;
    if (hasTag) return preampWithRg.isFinite ? preampWithRg : 0.0;
    return preampWithoutRg.isFinite ? preampWithoutRg : 0.0;
  }

  /// Sanitizes a ReplayGain dB tag before it is handed to the native pre-gain
  /// stage. Corrupt file metadata can carry NaN, ±inf or absurd magnitudes;
  /// the Dart math guards against them, but the native engine consumes the raw
  /// double and a single non-finite value poisons its smoothed gain for the
  /// rest of the session (every following track then plays as noise). Returns
  /// 0.0 (no gain) for anything unusable and clamps to a sane ±100 dB window.
  static double sanitizeGainDb(double? value) {
    if (value == null || !value.isFinite) return 0.0;
    return value.clamp(-100.0, 100.0).toDouble();
  }

  /// Sanitizes a ReplayGain peak tag to a finite positive value. Returns 1.0
  /// (unity, "no known peak") for anything unusable.
  static double sanitizePeak(double? value) {
    if (value == null || !value.isFinite || value <= 0.0) return 1.0;
    return value.clamp(1e-6, 100.0).toDouble();
  }
}