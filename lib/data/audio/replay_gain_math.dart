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

    // Clipping prevention: limit gain so output <= 1.0 with 0.5 dB
    // inter-sample peak headroom.
    final effectivePeak = (peak != null && peak.isFinite && peak > 0.0) ? peak : 1.0;
    final interSampleHeadroom =
        math.pow(10.0, -0.5 / 20.0).toDouble(); // ~0.944 (-0.5 dB)
    final maxGain = interSampleHeadroom / effectivePeak;
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
}