import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/presentation/widgets/eq_sheet_math.dart';

/// Expected values in this file are derived from the ORIGINAL inline formulas
/// that lived in `_EqualizerSheetState`, `_VerticalEqSliderState` and
/// `_showCustomFrequencyEditor` before the extraction — they encode existing
/// behaviour, not a desired behaviour. Do not "fix" an expectation here: a
/// failure means the extraction changed what the sheet does.
void main() {
  // 10-band ISO plan the sheet falls back to when the manager is absent.
  const iso10 = <double>[
    31.0,
    62.0,
    125.0,
    250.0,
    500.0,
    1000.0,
    2000.0,
    4000.0,
    8000.0,
    16000.0,
  ];

  // 64 strictly-ascending log-spaced centers, 20 Hz..20 kHz.
  final iso64 = List<double>.generate(
    64,
    (i) => 20.0 * math.pow(20000.0 / 20.0, i / 63.0),
    growable: false,
  );

  group('normalizedBandCount', () {
    test('only 32 and 64 survive, everything else collapses to 10', () {
      expect(EqSheetMath.normalizedBandCount(32), 32);
      expect(EqSheetMath.normalizedBandCount(64), 64);
      for (final n in [0, 1, 10, 31, 33, 128]) {
        expect(EqSheetMath.normalizedBandCount(n), 10, reason: 'n=$n');
      }
    });

    test('single-band plan collapses to the 10-band default', () {
      // The sheet renders 10 sliders for a 1-band preset, so its labels come
      // from the 10-band plan rather than the emitted gains.
      expect(EqSheetMath.normalizedBandCount(1), 10);
    });
  });

  group('findClosestBand', () {
    test('empty list returns index 0 instead of throwing', () {
      expect(EqSheetMath.findClosestBand(const <double>[], 1000.0), 0);
    });

    test('exact centers resolve to their own index', () {
      expect(EqSheetMath.findClosestBand(iso10, 62.0), 1);
      expect(EqSheetMath.findClosestBand(iso10, 1000.0), 5);
      expect(EqSheetMath.findClosestBand(iso10, 8000.0), 8);
    });

    test('off-center targets snap to the nearer neighbor', () {
      expect(EqSheetMath.findClosestBand(iso10, 150.0), 2);
      expect(EqSheetMath.findClosestBand(iso10, 45.0), 0);
    });

    test('targets outside the plan clamp to the first/last index', () {
      expect(EqSheetMath.findClosestBand(iso10, 0.0), 0);
      expect(EqSheetMath.findClosestBand(iso10, 30000.0), 9);
    });

    test('exact ties keep the lower index (strict less-than in the scan)', () {
      expect(EqSheetMath.findClosestBand(const [100.0, 200.0], 150.0), 0);
      expect(
          EqSheetMath.findClosestBand(const [100.0, 150.0, 200.0], 150.0), 1);
    });

    test('every one of the 64 log-spaced centers maps to its own index', () {
      for (var i = 0; i < iso64.length; i++) {
        expect(EqSheetMath.findClosestBand(iso64, iso64[i]), i, reason: 'i=$i');
      }
    });

    test('single-band plan always resolves to index 0', () {
      expect(EqSheetMath.findClosestBand(const [1000.0], 20.0), 0);
      expect(EqSheetMath.findClosestBand(const [1000.0], 20000.0), 0);
    });
  });

  group('macroGain', () {
    test('empty gains return 0.0', () {
      expect(EqSheetMath.macroGain(const <double>[], iso10, 62.0), 0.0);
      expect(
          EqSheetMath.macroGain(const <double>[], const <double>[], 62.0), 0.0);
    });

    test('reads the nearest band gain for each macro anchor', () {
      final gains = List<double>.generate(10, (i) => i.toDouble());
      expect(EqSheetMath.macroGain(gains, iso10, 62.0), 1.0);
      expect(EqSheetMath.macroGain(gains, iso10, 1000.0), 5.0);
      expect(EqSheetMath.macroGain(gains, iso10, 8000.0), 8.0);
    });

    test('clamps the reading to +/-12 dB', () {
      expect(
        EqSheetMath.macroGain(List<double>.filled(10, 15.0), iso10, 62.0),
        12.0,
      );
      expect(
        EqSheetMath.macroGain(List<double>.filled(10, -15.0), iso10, 62.0),
        -12.0,
      );
    });

    test('a frequency plan longer than the gains list clamps into range', () {
      // idx 8 would overflow a 1-element gains list.
      expect(EqSheetMath.macroGain(const [-5.0], iso10, 8000.0), -5.0);
    });

    test('64-band plan anchors on the nearest of its 64 centers', () {
      final gains = List<double>.generate(64, (i) => (i - 32).toDouble());
      expect(EqSheetMath.macroGain(gains, iso64, iso64[40]), 8.0);
    });
  });

  group('formatFrequencyText', () {
    test('integers drop the decimal, fractions keep one', () {
      expect(EqSheetMath.formatFrequencyText(31.0), '31');
      expect(EqSheetMath.formatFrequencyText(1000.0), '1000');
      expect(EqSheetMath.formatFrequencyText(62.5), '62.5');
      expect(EqSheetMath.formatFrequencyText(31.25), '31.3');
      expect(EqSheetMath.formatFrequencyText(99.95), '100.0');
    });
  });

  group('formatHz', () {
    test('sub-kilo labels keep the raw frequency', () {
      expect(EqSheetMath.formatHz(31.0), '31');
      expect(EqSheetMath.formatHz(62.0), '62');
      expect(EqSheetMath.formatHz(62.5), '62.5');
      expect(EqSheetMath.formatHz(125.0), '125');
    });

    test('kilo labels drop a whole-number decimal and keep a fractional one',
        () {
      expect(EqSheetMath.formatHz(1000.0), '1K');
      expect(EqSheetMath.formatHz(8000.0), '8K');
      expect(EqSheetMath.formatHz(8500.0), '8.5K');
      expect(EqSheetMath.formatHz(10500.0), '10.5K');
      expect(EqSheetMath.formatHz(20000.0), '20K');
    });

    test('a non-integral kilo value always renders one decimal', () {
      // 1005/1000 = 1.005 is not integral, so the label reads 1.0K.
      expect(EqSheetMath.formatHz(1005.0), '1.0K');
    });
  });

  group('formatGainDb', () {
    test('signs only strictly positive values', () {
      expect(EqSheetMath.formatGainDb(0.0), '0.0 dB');
      expect(EqSheetMath.formatGainDb(3.5), '+3.5 dB');
      expect(EqSheetMath.formatGainDb(12.0), '+12.0 dB');
      expect(EqSheetMath.formatGainDb(-12.0), '-12.0 dB');
    });

    test('one-decimal rounding happens after the sign is chosen', () {
      // 0.04 still counts as positive, so it renders as +0.0 dB.
      expect(EqSheetMath.formatGainDb(0.04), '+0.0 dB');
      expect(EqSheetMath.formatGainDb(0.05), '+0.1 dB');
      expect(EqSheetMath.formatGainDb(-0.04), '-0.0 dB');
    });
  });

  group('boost clamp detection', () {
    test('epsilon value is unchanged', () {
      expect(boostClampEpsilon, 0.01);
    });

    test('a delta of exactly epsilon is NOT a clamp', () {
      expect(
        EqSheetMath.isBoostClamped(requestedBoost: 0.01, effectiveBoost: 0.0),
        isFalse,
      );
    });

    test('just below epsilon is NOT a clamp', () {
      expect(
        EqSheetMath.isBoostClamped(
          requestedBoost: 0.01 - 1e-9,
          effectiveBoost: 0.0,
        ),
        isFalse,
      );
    });

    test('just above epsilon IS a clamp', () {
      expect(
        EqSheetMath.isBoostClamped(
          requestedBoost: 0.01 + 1e-9,
          effectiveBoost: 0.0,
        ),
        isTrue,
      );
    });

    test('no reduction and negative deltas are never clamps', () {
      expect(
        EqSheetMath.isBoostClamped(requestedBoost: 6.0, effectiveBoost: 6.0),
        isFalse,
      );
      expect(
        EqSheetMath.isBoostClamped(requestedBoost: 0.0, effectiveBoost: 0.0),
        isFalse,
      );
      expect(
        EqSheetMath.isBoostClamped(requestedBoost: 2.0, effectiveBoost: 3.0),
        isFalse,
      );
    });
  });

  group('peakGain', () {
    test('empty plan is 0.0', () {
      expect(EqSheetMath.peakGain(const <double>[]), 0.0);
    });

    test('an all-cut curve stays negative (reduce semantics)', () {
      expect(EqSheetMath.peakGain(const [-3.0, -5.0]), -3.0);
    });

    test('returns the largest boost', () {
      expect(EqSheetMath.peakGain(const [1.0, 4.0, 2.0]), 4.0);
      expect(EqSheetMath.peakGain(const [7.0]), 7.0);
    });

    test('64-band plan returns its maximum', () {
      final gains = List<double>.generate(64, (i) => (i - 32).toDouble() / 2.0);
      expect(EqSheetMath.peakGain(gains), 15.5);
    });
  });

  group('autoPreampFor', () {
    test('no positive band means no attenuation', () {
      expect(EqSheetMath.autoPreampFor(const <double>[]), 0.0);
      expect(EqSheetMath.autoPreampFor(const [-2.0, 0.0, -7.0]), 0.0);
      expect(EqSheetMath.autoPreampFor(const [0.0, 0.0]), 0.0);
    });

    test('cancels the largest boost', () {
      expect(EqSheetMath.autoPreampFor(const [1.0, 4.0, 2.0]), -4.0);
      expect(EqSheetMath.autoPreampFor(const [7.0]), -7.0);
      expect(EqSheetMath.autoPreampFor(const [-2.0, 0.0, 3.0]), -3.0);
    });

    test('64-band plan cancels its single peak', () {
      final gains = List<double>.filled(64, -1.0)..[41] = 5.5;
      expect(EqSheetMath.autoPreampFor(gains), -5.5);
    });
  });

  group('autoHeadroomDb', () {
    test('disabled EQ never engages headroom', () {
      expect(
        EqSheetMath.autoHeadroomDb(const [6.0, 6.0], isEqEnabled: false),
        0.0,
      );
    });

    test('a peak at or below 1.5 dB does not engage', () {
      expect(EqSheetMath.autoHeadroomDb(const [1.5], isEqEnabled: true), 0.0);
      expect(EqSheetMath.autoHeadroomDb(const [0.0, -2.0], isEqEnabled: true),
          0.0);
      expect(
          EqSheetMath.autoHeadroomDb(const <double>[], isEqEnabled: true), 0.0);
      expect(EqSheetMath.autoHeadroomDb(const [-3.0, -5.0], isEqEnabled: true),
          0.0);
    });

    test('just above 1.5 dB engages with a near-zero trim', () {
      final trim = EqSheetMath.autoHeadroomDb(const [1.6], isEqEnabled: true);
      // -(0.1 * 0.55) exactly, before float noise.
      expect(trim, closeTo(-0.055, 1e-12));
      expect(trim, lessThan(0.0));
    });

    test('blend is 65% peak + 35% RMS of the positive bands', () {
      expect(
        EqSheetMath.autoHeadroomDb(const [6.0, 6.0, 0.0], isEqEnabled: true),
        closeTo(-2.475, 1e-12),
      );
      expect(
        EqSheetMath.autoHeadroomDb(const [-2.0, 0.0, 3.0], isEqEnabled: true),
        closeTo(-0.825, 1e-12),
      );
      expect(
        EqSheetMath.autoHeadroomDb(const [12.0, 12.0, 12.0], isEqEnabled: true),
        closeTo(-5.775, 1e-12),
      );
    });

    test('trim is capped at 6 dB of headroom', () {
      expect(EqSheetMath.autoHeadroomDb(const [15.0], isEqEnabled: true), -6.0);
    });

    test('64-band plan trims proportionally', () {
      final gains = List<double>.filled(64, 0.0)..[10] = 3.0;
      // maxBoost 3.0, RMS 3.0 -> -(1.5 * 0.55)
      expect(
        EqSheetMath.autoHeadroomDb(gains, isEqEnabled: true),
        closeTo(-0.825, 1e-12),
      );
    });
  });

  group('hasClipRisk', () {
    test('preamp plus boost above 0 dBFS warns', () {
      expect(
        EqSheetMath.hasClipRisk(
          preampDb: 0.0,
          gains: const [2.0],
          isEqEnabled: true,
        ),
        isTrue,
      );
    });

    test('enough negative preamp clears the warning', () {
      expect(
        EqSheetMath.hasClipRisk(
          preampDb: -2.0,
          gains: const [2.0],
          isEqEnabled: true,
        ),
        isFalse,
      );
    });

    test('exactly 0 dBFS is not a risk (strict greater-than)', () {
      // Disabled EQ contributes no headroom: -2 + 2 + 0 == 0.0 exactly.
      expect(
        EqSheetMath.hasClipRisk(
          preampDb: -2.0,
          gains: const [2.0],
          isEqEnabled: false,
        ),
        isFalse,
      );
    });

    test('empty plan risks only on a positive manual preamp', () {
      expect(
        EqSheetMath.hasClipRisk(
          preampDb: 0.5,
          gains: const <double>[],
          isEqEnabled: true,
        ),
        isTrue,
      );
      expect(
        EqSheetMath.hasClipRisk(
          preampDb: 0.0,
          gains: const <double>[],
          isEqEnabled: true,
        ),
        isFalse,
      );
    });
  });

  group('hapticStepFor', () {
    test('maps -12..+12 dB onto 0..48 half-dB steps', () {
      expect(EqSheetMath.hapticStepFor(-12.0), 0);
      expect(EqSheetMath.hapticStepFor(0.0), 24);
      expect(EqSheetMath.hapticStepFor(12.0), 48);
      expect(EqSheetMath.hapticStepFor(3.3), 31);
    });

    test('out-of-range values still produce a monotonic step', () {
      expect(EqSheetMath.hapticStepFor(-12.1), 0);
      expect(EqSheetMath.hapticStepFor(-0.25), 24);
      expect(EqSheetMath.hapticStepFor(0.25), 25);
      expect(EqSheetMath.hapticStepFor(0.26), 25);
    });
  });

  group('macro weights', () {
    test('bass shelf tapers from 1.0 to the 0.2 floor', () {
      expect(EqSheetMath.bassMacroWeight(0.0), 1.0);
      expect(
        EqSheetMath.bassMacroWeight(62.0),
        closeTo(0.7785714285714286, 1e-12),
      );
      expect(EqSheetMath.bassMacroWeight(250.0), 0.2);
      expect(EqSheetMath.bassMacroWeight(280.0), 0.2);
      expect(EqSheetMath.bassMacroWeight(1000.0), 0.2);
    });

    test('mid bell peaks at 1 kHz and floors at 0.3', () {
      expect(EqSheetMath.midMacroWeight(1000.0), 1.0);
      expect(EqSheetMath.midMacroWeight(500.0), 0.5);
      expect(EqSheetMath.midMacroWeight(2000.0), 0.5);
      expect(EqSheetMath.midMacroWeight(250.0), 0.3);
      expect(EqSheetMath.midMacroWeight(3500.0), 0.3);
    });

    test('treble shelf rises from the 0.4 floor to 1.0', () {
      expect(EqSheetMath.trebleMacroWeight(3500.0), 0.4);
      expect(EqSheetMath.trebleMacroWeight(8000.0), 0.5);
      expect(EqSheetMath.trebleMacroWeight(13000.0), 1.0);
      expect(EqSheetMath.trebleMacroWeight(20000.0), 1.0);
    });
  });

  group('roundGain', () {
    test('quantises to one decimal', () {
      expect(EqSheetMath.roundGain(2.04), 2.0);
      expect(EqSheetMath.roundGain(2.06), 2.1);
      expect(EqSheetMath.roundGain(2.44), 2.4);
      expect(EqSheetMath.roundGain(2.46), 2.5);
      expect(EqSheetMath.roundGain(3.14), 3.1);
      expect(EqSheetMath.roundGain(-3.14), -3.1);
    });

    test('already-quantised values pass through untouched', () {
      expect(EqSheetMath.roundGain(0.0), 0.0);
      expect(EqSheetMath.roundGain(15.0), 15.0);
      expect(EqSheetMath.roundGain(-15.0), -15.0);
    });
  });

  group('gainFromPointerY', () {
    test('collapsed or inverted tracks return null', () {
      expect(EqSheetMath.gainFromPointerY(12.0, 24.0, min: -15.0, max: 15.0),
          isNull);
      expect(EqSheetMath.gainFromPointerY(5.0, 20.0, min: -15.0, max: 15.0),
          isNull);
      expect(EqSheetMath.gainFromPointerY(0.0, 0.0, min: -15.0, max: 15.0),
          isNull);
    });

    test('top and bottom of the track hit max and min', () {
      expect(EqSheetMath.gainFromPointerY(12.0, 100.0, min: -15.0, max: 15.0),
          15.0);
      expect(EqSheetMath.gainFromPointerY(88.0, 100.0, min: -15.0, max: 15.0),
          -15.0);
    });

    test('track centre is 0 dB for a symmetric range', () {
      expect(EqSheetMath.gainFromPointerY(50.0, 100.0, min: -15.0, max: 15.0),
          0.0);
    });

    test('pointer outside the track clamps to the range ends', () {
      expect(EqSheetMath.gainFromPointerY(-50.0, 100.0, min: -15.0, max: 15.0),
          15.0);
      expect(EqSheetMath.gainFromPointerY(500.0, 100.0, min: -15.0, max: 15.0),
          -15.0);
    });

    test('result is one-decimal quantised', () {
      expect(
        EqSheetMath.gainFromPointerY(12.0 + 76.0 / 3.0, 100.0,
            min: -15.0, max: 15.0),
        5.0,
      );
      expect(EqSheetMath.gainFromPointerY(12.0, 25.0, min: -15.0, max: 15.0),
          15.0);
    });

    test('honours a custom min/max range', () {
      expect(
          EqSheetMath.gainFromPointerY(50.0, 100.0, min: 0.0, max: 10.0), 5.0);
    });
  });

  group('adjustedGain / clampGain', () {
    test('semantic step is clamped then quantised', () {
      expect(
        EqSheetMath.adjustedGain(0.0, 1.0, min: -15.0, max: 15.0),
        1.0,
      );
      expect(
        EqSheetMath.adjustedGain(0.0, -1.0, min: -15.0, max: 15.0),
        -1.0,
      );
      expect(
        EqSheetMath.adjustedGain(14.6, 1.0, min: -15.0, max: 15.0),
        15.0,
      );
      expect(
        EqSheetMath.adjustedGain(-14.6, -1.0, min: -15.0, max: 15.0),
        -15.0,
      );
    });

    test('clampGain does not quantise', () {
      expect(EqSheetMath.clampGain(3.33, min: -15.0, max: 15.0), 3.33);
      expect(EqSheetMath.clampGain(16.0, min: -15.0, max: 15.0), 15.0);
      expect(EqSheetMath.clampGain(-16.0, min: -15.0, max: 15.0), -15.0);
      expect(EqSheetMath.clampGain(14.6 + 1.0, min: -15.0, max: 15.0), 15.0);
    });
  });

  group('parseCenterFrequencies', () {
    test('accepts an ascending in-range plan', () {
      final result =
          EqSheetMath.parseCenterFrequencies(const ['31', '62', '125']);
      expect(result.isValid, isTrue);
      expect(result.issue, isNull);
      expect(result.values, [31.0, 62.0, 125.0]);
    });

    test('accepts a single band and an empty plan', () {
      expect(
        EqSheetMath.parseCenterFrequencies(const ['31']).values,
        [31.0],
      );
      final empty = EqSheetMath.parseCenterFrequencies(const []);
      expect(empty.isValid, isTrue);
      expect(empty.values, isEmpty);
    });

    test('accepts the 10 Hz and 30 kHz range boundaries', () {
      expect(EqSheetMath.parseCenterFrequencies(const ['10']).isValid, isTrue);
      expect(
        EqSheetMath.parseCenterFrequencies(const ['30000']).isValid,
        isTrue,
      );
      expect(
        EqSheetMath.parseCenterFrequencies(const ['10.0', '10.5']).values,
        [10.0, 10.5],
      );
    });

    test('a 64-band ascending plan is accepted', () {
      final texts = [for (final f in iso64) f.toString()];
      final result = EqSheetMath.parseCenterFrequencies(texts);
      expect(result.isValid, isTrue);
      expect(result.values, hasLength(64));
    });

    test('a non-numeric field anywhere wins over range and order', () {
      for (final bad in ['abc', 'NaN', 'Infinity', '']) {
        final result = EqSheetMath.parseCenterFrequencies(['31', bad, '10']);
        expect(result.issue, CenterFrequencyIssue.notANumber, reason: bad);
        expect(result.values, isNull);
        expect(result.isValid, isFalse);
      }
      // Non-numeric beats out-of-range (5 Hz) and non-ascending (100, 50).
      expect(
        EqSheetMath.parseCenterFrequencies(const ['5', 'abc']).issue,
        CenterFrequencyIssue.notANumber,
      );
    });

    test('range violations are reported before order violations', () {
      // 5 Hz is out of range at index 0, so it wins over the 4 Hz ordering.
      expect(
        EqSheetMath.parseCenterFrequencies(const ['5', '4']).issue,
        CenterFrequencyIssue.outOfRange,
      );
      expect(
        EqSheetMath.parseCenterFrequencies(const ['9.99']).issue,
        CenterFrequencyIssue.outOfRange,
      );
      expect(
        EqSheetMath.parseCenterFrequencies(const ['30001']).issue,
        CenterFrequencyIssue.outOfRange,
      );
    });

    test('equal or descending neighbors are rejected', () {
      expect(
        EqSheetMath.parseCenterFrequencies(const ['100', '100']).issue,
        CenterFrequencyIssue.notAscending,
      );
      expect(
        EqSheetMath.parseCenterFrequencies(const ['200', '100']).issue,
        CenterFrequencyIssue.notAscending,
      );
      expect(
        EqSheetMath.parseCenterFrequencies(const ['100', '50', '0']).issue,
        CenterFrequencyIssue.notAscending,
      );
    });
  });
}
