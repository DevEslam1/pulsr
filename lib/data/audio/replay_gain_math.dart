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
    if (gainDb != null && gainDb != 0.0) {
      preampDb = preampWithRg;
    } else {
      preampDb = preampWithoutRg;
      gainDb = 0.0;
    }

    final totalGainDb = (gainDb) + preampDb;
    var multiplier = math.pow(10.0, totalGainDb / 20.0).toDouble();

    // Clipping prevention: limit gain so output <= 1.0 with 0.5 dB
    // inter-sample peak headroom.
    final effectivePeak = (peak != null && peak > 0.0) ? peak : 1.0;
    final interSampleHeadroom =
        math.pow(10.0, -0.5 / 20.0).toDouble(); // ~0.944 (-0.5 dB)
    final maxGain = interSampleHeadroom / effectivePeak;
    if (multiplier > maxGain) {
      multiplier = maxGain;
    }

    return (volume * multiplier).clamp(0.0, 1.0).toDouble();
  }
}