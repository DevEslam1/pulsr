import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

double calculateReplayGainVolume({
  required double volume,
  required String mode,
  double? trackGain,
  double? albumGain,
  double? trackPeak,
  double? albumPeak,
  double preampWithRg = 0.0,
  double preampWithoutRg = -3.0,
}) {
  double? gainDb;
  double? peak;

  switch (mode) {
    case 'track':
      gainDb = trackGain;
      peak = trackPeak;
      break;
    case 'album':
      gainDb = albumGain ?? trackGain;
      peak = albumPeak ?? trackPeak;
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

  // Peak clipping prevention with -0.5 dB inter-sample peak headroom
  final effectivePeak = (peak != null && peak > 0.0) ? peak : 1.0;
  final interSampleHeadroom = math.pow(10.0, -0.5 / 20.0).toDouble(); // ~0.944 (-0.5 dB)
  final maxGain = interSampleHeadroom / effectivePeak;
  if (multiplier > maxGain) {
    multiplier = maxGain;
  }

  return (volume * multiplier).clamp(0.0, 1.0).toDouble();
}

void main() {
  group('Full ReplayGain Pipeline Tests', () {
    test('Mode "off" returns base volume unchanged', () {
      final vol = calculateReplayGainVolume(
        volume: 0.8,
        mode: 'off',
        trackGain: -6.0,
      );
      expect(vol, equals(0.8));
    });

    test('Mode "track" applies track gain + preamp with RG', () {
      final vol = calculateReplayGainVolume(
        volume: 1.0,
        mode: 'track',
        trackGain: -6.0206,
        preampWithRg: 0.0,
      );
      expect(vol, closeTo(0.5, 0.01));
    });

    test('Mode "album" applies album gain when present', () {
      final vol = calculateReplayGainVolume(
        volume: 1.0,
        mode: 'album',
        trackGain: -6.0206,
        albumGain: -12.0412,
        preampWithRg: 0.0,
      );
      expect(vol, closeTo(0.25, 0.01));
    });

    test('Mode "album" falls back to track gain when album gain is null', () {
      final vol = calculateReplayGainVolume(
        volume: 1.0,
        mode: 'album',
        trackGain: -6.0206,
        albumGain: null,
        preampWithRg: 0.0,
      );
      expect(vol, closeTo(0.5, 0.01));
    });

    test('Missing RG tag applies preampWithoutRg', () {
      final vol = calculateReplayGainVolume(
        volume: 1.0,
        mode: 'track',
        trackGain: null,
        preampWithoutRg: -6.0206,
      );
      expect(vol, closeTo(0.5, 0.01));
    });

    test('Clipping prevention limits multiplier with -0.5 dB inter-sample headroom', () {
      // +6 dB multiplier would be 2.0, but peak is 0.8 with -0.5 dB headroom (0.944) -> maxGain = 1.180
      final vol = calculateReplayGainVolume(
        volume: 0.5,
        mode: 'track',
        trackGain: 6.0206,
        trackPeak: 0.8,
      );
      // Expected volume = 0.5 * 1.180 = 0.590
      expect(vol, closeTo(0.590, 0.01));
    });
  });
}
