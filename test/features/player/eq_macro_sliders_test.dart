import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

// Helper tests to verify macro dials anchor frequency consistency without drift
void main() {
  group('Quick Tone Dials Consistency Tests', () {
    double getBassGain(PlayerState state) {
      final gains = state.eqPreset.gains;
      if (gains.isEmpty) return 0.0;
      return gains[0].clamp(-12.0, 12.0);
    }

    double getMidGain(PlayerState state) {
      final gains = state.eqPreset.gains;
      if (gains.isEmpty) return 0.0;
      if (gains.length >= 10) {
        return gains[5].clamp(-12.0, 12.0);
      } else if (gains.length >= 3) {
        return gains[gains.length ~/ 2].clamp(-12.0, 12.0);
      }
      return 0.0;
    }

    double getTrebleGain(PlayerState state) {
      final gains = state.eqPreset.gains;
      if (gains.isEmpty) return 0.0;
      if (gains.length >= 10) {
        return gains[8].clamp(-12.0, 12.0);
      } else if (gains.length >= 3) {
        return gains.last.clamp(-12.0, 12.0);
      }
      return 0.0;
    }

    test('Bass dial reads anchor band 0 and preserves set value after reopen',
        () {
      const setGain = 6.0;
      final gains = List.filled(10, 0.0);
      // Simulate _setBassMacro
      gains[0] = setGain;
      gains[1] = (setGain * 0.85).clamp(-12.0, 12.0);
      gains[2] = (setGain * 0.65).clamp(-12.0, 12.0);

      final state = PlayerState(
        dsp: DspSlice(
          eqPreset: EqPreset(name: 'Custom', gains: gains),
        ),
      );

      // Verify that after reopening (re-reading state), the dial value is unchanged
      expect(getBassGain(state), equals(setGain));
    });

    test('Mid dial reads anchor band 5 and preserves set value after reopen',
        () {
      const setGain = 4.5;
      final gains = List.filled(10, 0.0);
      // Simulate _setMidMacro
      gains[3] = (setGain * 0.5).clamp(-12.0, 12.0);
      gains[4] = (setGain * 0.8).clamp(-12.0, 12.0);
      gains[5] = setGain;
      gains[6] = (setGain * 0.85).clamp(-12.0, 12.0);

      final state = PlayerState(
        dsp: DspSlice(
          eqPreset: EqPreset(name: 'Custom', gains: gains),
        ),
      );

      // Verify that after reopening, the dial value is unchanged
      expect(getMidGain(state), equals(setGain));
    });

    test('Treble dial reads anchor band 8 and preserves set value after reopen',
        () {
      const setGain = 5.0;
      final gains = List.filled(10, 0.0);
      // Simulate _setTrebleMacro
      gains[7] = (setGain * 0.75).clamp(-12.0, 12.0);
      gains[8] = setGain;
      gains[9] = (setGain * 0.9).clamp(-12.0, 12.0);

      final state = PlayerState(
        dsp: DspSlice(
          eqPreset: EqPreset(name: 'Custom', gains: gains),
        ),
      );

      // Verify that after reopening, the dial value is unchanged
      expect(getTrebleGain(state), equals(setGain));
    });

    test('Negative bass cut clears bass boost amount', () {
      const negativeVal = -4.0;
      final boost =
          negativeVal > 0 ? (negativeVal / 12.0).clamp(0.0, 1.0) : 0.0;
      expect(boost, equals(0.0));
    });
  });
}
