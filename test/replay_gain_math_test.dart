import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/replay_gain_math.dart';

void main() {
  group('ReplayGainMath.apply', () {
    test('off mode is a pure passthrough regardless of tags', () {
      expect(
        ReplayGainMath.apply(
            mode: 'off', volume: 0.8, trackGainDb: -6.0, trackPeak: 0.5),
        0.8,
      );
    });

    test('track mode applies gain linearly (-6 dB -> x0.5012)', () {
      final out = ReplayGainMath.apply(
          mode: 'track', volume: 1.0, trackGainDb: -6.0, trackPeak: 0.5);
      expect(out, closeTo(1.0 * 0.5012, 0.001));
    });

    test('preamp without RG is applied when tags are missing', () {
      final out = ReplayGainMath.apply(
          mode: 'track',
          volume: 1.0,
          trackGainDb: null,
          preampWithoutRg: -3.0);
      expect(out, closeTo(0.7079, 0.001));
    });

    test('clipping prevention caps the multiplier for hot peaks', () {
      // +20 dB with peak 0.5 would be x10 without the cap; capped multiplier
      // is headroom/peak ~= 0.9441/0.5 = 1.8882 -> output clamps at 1.0.
      final out = ReplayGainMath.apply(
          mode: 'track', volume: 1.0, trackGainDb: 20.0, trackPeak: 0.5);
      expect(out, 1.0);
    });

    test('album mode falls back to track gain when album tags are missing',
        () {
      final out = ReplayGainMath.apply(
        mode: 'album',
        volume: 1.0,
        trackGainDb: -6.0,
        trackPeak: 1.0,
        albumGainDb: null,
        albumPeak: null,
      );
      expect(out, closeTo(0.5012, 0.001));
    });

    test('auto uses album gain only in album context', () {
      final inAlbumContext = ReplayGainMath.apply(
        mode: 'auto',
        volume: 1.0,
        trackGainDb: -6.0,
        trackPeak: 1.0,
        albumGainDb: -3.0,
        albumPeak: 1.0,
        albumContext: true,
      );
      expect(inAlbumContext, closeTo(0.7079, 0.001));

      final outsideAlbumContext = ReplayGainMath.apply(
        mode: 'auto',
        volume: 1.0,
        trackGainDb: -6.0,
        trackPeak: 1.0,
        albumGainDb: -3.0,
        albumPeak: 1.0,
        albumContext: false,
      );
      expect(outsideAlbumContext, closeTo(0.5012, 0.001));
    });

    test('output never exceeds 1.0 even with extreme gain', () {
      final out = ReplayGainMath.apply(
          mode: 'track',
          volume: 1.0,
          trackGainDb: 60.0,
          trackPeak: 0.01,
          preampWithRg: 15.0);
      expect(out, lessThanOrEqualTo(1.0));
    });

    test('zero gain tags behave like missing tags (preampWithoutRg)', () {
      final zeroGain = ReplayGainMath.apply(
          mode: 'track', volume: 1.0, trackGainDb: 0.0, preampWithoutRg: -3.0);
      expect(zeroGain, closeTo(0.7079, 0.001));
    });
  });

  group('ReplayGainMath.sanitizeGainDb', () {
    test('passes through finite in-range values', () {
      expect(ReplayGainMath.sanitizeGainDb(-6.5), -6.5);
      expect(ReplayGainMath.sanitizeGainDb(0.0), 0.0);
    });

    test('null and non-finite values become 0.0', () {
      expect(ReplayGainMath.sanitizeGainDb(null), 0.0);
      expect(ReplayGainMath.sanitizeGainDb(double.nan), 0.0);
      expect(ReplayGainMath.sanitizeGainDb(double.infinity), 0.0);
      expect(ReplayGainMath.sanitizeGainDb(double.negativeInfinity), 0.0);
    });

    test('clamps absurd magnitudes to the ±100 dB window', () {
      expect(ReplayGainMath.sanitizeGainDb(1e38), 100.0);
      expect(ReplayGainMath.sanitizeGainDb(-1e38), -100.0);
    });
  });

  group('ReplayGainMath.sanitizePeak', () {
    test('passes through finite positive values', () {
      expect(ReplayGainMath.sanitizePeak(0.98), 0.98);
    });

    test('null, non-finite, zero and negative values become 1.0', () {
      expect(ReplayGainMath.sanitizePeak(null), 1.0);
      expect(ReplayGainMath.sanitizePeak(double.nan), 1.0);
      expect(ReplayGainMath.sanitizePeak(double.infinity), 1.0);
      expect(ReplayGainMath.sanitizePeak(0.0), 1.0);
      expect(ReplayGainMath.sanitizePeak(-0.5), 1.0);
    });
  });
}