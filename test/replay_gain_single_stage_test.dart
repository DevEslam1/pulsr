import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/replay_gain_math.dart';

/// Regression tests for the single-stage ReplayGain contract the
/// [PulsrAudioHandler] relies on after the double-apply fix:
///
/// * the mixer in `_calculateReplayGainVolume` is the ONLY gain stage
///   (the native DSP stage is forced off), and
/// * untagged tracks are left at unity — the handler passes
///   `preampWithoutRg: 0.0`, never the math default of -3 dB.
void main() {
  group('ReplayGain single-stage contract', () {
    test('untagged track at handler default (0 dB) is unity', () {
      expect(
        ReplayGainMath.apply(
          mode: 'track',
          volume: 0.8,
          trackGainDb: null,
          preampWithoutRg: 0.0,
        ),
        0.8,
      );
      expect(
        ReplayGainMath.apply(
          mode: 'album',
          volume: 0.6,
          albumGainDb: null,
          preampWithoutRg: 0.0,
        ),
        0.6,
      );
    });

    test('zero-valued tags count as untagged (headroom only at full scale)',
        () {
      // At volume 1.0 with peak 1.0 the -0.5 dB inter-sample headroom
      // legitimately trims to ~0.9441; below full scale there is no trim.
      expect(
        ReplayGainMath.apply(
          mode: 'track',
          volume: 1.0,
          trackGainDb: 0.0,
          preampWithoutRg: 0.0,
        ),
        closeTo(0.9441, 0.001),
      );
      expect(
        ReplayGainMath.apply(
          mode: 'track',
          volume: 0.8,
          trackGainDb: 0.0,
          preampWithoutRg: 0.0,
        ),
        closeTo(0.8, 0.0001),
      );
    });

    test('tagged track scales exactly once (no double staging)', () {
      // -6 dB -> x0.5012 applied a single time; a second staging would
      // square it to ~0.2512.
      final out = ReplayGainMath.apply(
        mode: 'track',
        volume: 1.0,
        trackGainDb: -6.0,
        trackPeak: 0.5,
        preampWithRg: 0.0,
        preampWithoutRg: 0.0,
      );
      expect(out, closeTo(0.5012, 0.001));
    });

    test('per-song dB offsets compose linearly in the same stage', () {
      // Handler math: RG factor x per-song factor. +6 dB on a -6 dB track
      // must restore unity (modulo the -0.5 dB inter-sample headroom cap).
      final rg = ReplayGainMath.apply(
        mode: 'track',
        volume: 1.0,
        trackGainDb: -6.0,
        trackPeak: 1.0,
        preampWithRg: 0.0,
        preampWithoutRg: 0.0,
      );
      expect(rg, closeTo(0.5012, 0.001));
    });

    test('non-finite tags and volumes never produce NaN output', () {
      for (final gain in [double.nan, double.infinity, double.negativeInfinity]) {
        final out = ReplayGainMath.apply(
          mode: 'track',
          volume: 0.7,
          trackGainDb: gain,
          preampWithoutRg: 0.0,
        );
        expect(out.isFinite, isTrue, reason: 'gain=$gain');
        expect(out, closeTo(0.7, 0.0001));
      }
      expect(
        ReplayGainMath.apply(
          mode: 'track',
          volume: double.nan,
          trackGainDb: -6.0,
          preampWithoutRg: 0.0,
        ),
        0.0,
      );
    });

    test('output never exceeds 1.0 even for extreme positive tags', () {
      final out = ReplayGainMath.apply(
        mode: 'track',
        volume: 1.0,
        trackGainDb: 30.0,
        trackPeak: 0.1,
        preampWithRg: 0.0,
        preampWithoutRg: 0.0,
      );
      expect(out, lessThanOrEqualTo(1.0));
    });
  });
}
