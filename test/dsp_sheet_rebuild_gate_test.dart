import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';

void main() {
  // Phase-1 toggle fields that MUST flip the sheet immediately on press.
  final boolToggles = {
    'isSaturationEnabled': (PlayerState s) => s.copyWith(isSaturationEnabled: true),
    'isStereoWidthEnabled': (PlayerState s) => s.copyWith(isStereoWidthEnabled: true),
    'isLoudnessContourEnabled': (PlayerState s) => s.copyWith(isLoudnessContourEnabled: true),
    'isSubCrossoverEnabled': (PlayerState s) => s.copyWith(isSubCrossoverEnabled: true),
    'isDynamicEqEnabled': (PlayerState s) => s.copyWith(isDynamicEqEnabled: true),
  };

  final doubleToggles = {
    'saturationDrive': (PlayerState s) => s.copyWith(saturationDrive: 0.9),
    'saturationMix': (PlayerState s) => s.copyWith(saturationMix: 0.9),
    'saturationTilt': (PlayerState s) => s.copyWith(saturationTilt: 0.9),
    'stereoWidth': (PlayerState s) => s.copyWith(stereoWidth: 1.4),
    'loudnessContourIntensity': (PlayerState s) => s.copyWith(loudnessContourIntensity: 0.7),
    'subCrossoverCornerHz': (PlayerState s) => s.copyWith(subCrossoverCornerHz: 120.0),
    'subCrossoverSlopeDbPerOct': (PlayerState s) => s.copyWith(subCrossoverSlopeDbPerOct: 12.0),
    'subCrossoverGain': (PlayerState s) => s.copyWith(subCrossoverGain: 0.4),
  };

  group('dspSheetRebuildGate', () {
    test('no-change copyWith does not request a rebuild', () {
      expect(dspSheetRebuildGate(const PlayerState(), const PlayerState()), isFalse);
    });

    test('position-only change stays excluded (10 Hz tick guard)', () {
      final a = const PlayerState();
      final b = a.copyWith(position: const Duration(seconds: 5));
      expect(dspSheetRebuildGate(a, b), isFalse);
    });

    for (final entry in boolToggles.entries) {
      test('${entry.key} toggling requests an immediate rebuild', () {
        final a = const PlayerState();
        final b = entry.value(a);
        expect(dspSheetRebuildGate(a, b), isTrue, reason: entry.key);
        expect(dspSheetRebuildGate(b, a), isTrue, reason: '${entry.key} (reverse)');
      });
    }

    for (final entry in doubleToggles.entries) {
      test('${entry.key} change requests an immediate rebuild', () {
        final a = const PlayerState();
        final b = entry.value(a);
        expect(dspSheetRebuildGate(a, b), isTrue, reason: entry.key);
      });
    }

    test('existing legacy fields are still gated in', () {
      final a = const PlayerState();
      expect(
        dspSheetRebuildGate(a, a.copyWith(isEqEnabled: true)),
        isTrue,
      );
      expect(
        dspSheetRebuildGate(a, a.copyWith(isCrossfeedEnabled: true)),
        isTrue,
      );
    });

    test('dynamicEqBands content change requests a rebuild', () {
      final a = const PlayerState();
      final b = a.copyWith(
        dynamicEqBands: const [
          DynamicEqBandConfig(frequency: 2000.0, thresholdDb: -24.0),
        ],
      );
      expect(dspSheetRebuildGate(a, b), isTrue);
    });

    test('identical dynamicEqBands content does not force a rebuild', () {
      const band = DynamicEqBandConfig(frequency: 1000.0);
      final a = const PlayerState().copyWith(dynamicEqBands: const [band]);
      final b = const PlayerState()
          .copyWith(position: const Duration(seconds: 1))
          .copyWith(dynamicEqBands: const [DynamicEqBandConfig(frequency: 1000.0)]);
      expect(dspSheetRebuildGate(a, b), isFalse);
    });
  });

  group('DynamicEqBandConfig value equality', () {
    test('equal content, different instance -> == and same hashCode', () {
      const a = DynamicEqBandConfig(frequency: 500.0, thresholdDb: -20.0);
      final b = a.copyWith();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('changed field -> not equal', () {
      const a = DynamicEqBandConfig(frequency: 500.0);
      final b = a.copyWith(frequency: 800.0);
      expect(a, isNot(equals(b)));
    });
  });
}