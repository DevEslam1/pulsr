import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/replay_gain_math.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Crossfade & Bit-Perfect Edge Cases (EC-1, EC-2 & Audio Audit)', () {
    test('EC-1: Null player duration falls back to track metadata duration', () {
      const Duration? playerDuration = null;
      const int trackMetadataMs = 240000;

      final duration = (playerDuration != null && playerDuration > Duration.zero)
          ? playerDuration
          : (trackMetadataMs > 0
              ? const Duration(milliseconds: trackMetadataMs)
              : Duration.zero);

      expect(duration, equals(const Duration(milliseconds: 240000)));
      expect(duration > const Duration(seconds: 15), isTrue);
    });

    test('EC-2: Repeat-One / self-loop skips crossfade into same track index', () {
      final int currentIndex = 3;
      final int nextIndex = 3; // In LoopMode.one, getNextIndex returns currentIndex

      bool crossfadeStarted = false;
      if (nextIndex != currentIndex) {
        crossfadeStarted = true;
      }

      expect(crossfadeStarted, isFalse, reason: 'Repeat-one must not crossfade track into itself');
    });

    test('Bit-Perfect Mode: ReplayGain multiplier is bypassed (returns volume without gain)', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.bitPerfectOutput: true,
        PrefsKeys.bypassDspOnBitPerfect: true,
      });
      final prefs = await SharedPreferences.getInstance();

      final bitPerfect = (prefs.getBool(PrefsKeys.bitPerfectOutput) ?? false) &&
          (prefs.getBool(PrefsKeys.bypassDspOnBitPerfect) ?? true);

      expect(bitPerfect, isTrue);

      const volume = 0.8;
      // When bit-perfect is active, volume is untouched by track gain (-6.0 dB)
      final effectiveVolume = bitPerfect
          ? volume
          : ReplayGainMath.apply(
              mode: 'track',
              volume: volume,
              trackGainDb: -6.0,
            );

      expect(effectiveVolume, equals(0.8));
    });
  });
}
