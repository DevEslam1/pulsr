// test/data/audio/autoeq_fir_roundtrip_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/autoeq_fir_generator.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<HeadphoneProfile> profiles;

  setUpAll(() {
    final file = File('assets/eq_profiles/headphone_profiles.json');
    expect(file.existsSync(), isTrue,
        reason: 'headphone_profiles.json must exist');
    final jsonList = json.decode(file.readAsStringSync()) as List<dynamic>;
    profiles = jsonList
        .map((item) => HeadphoneProfile.fromJson(item as Map<String, dynamic>))
        .toList();
  });

  group('AutoEq FIR round-trip tests', () {
    test('minimum-phase FIR matches parametric EQ biquad curve within 0.15 dB',
        () {
      // Find profiles with representative filters
      final testProfiles = profiles
          .where((p) => p.hasParametricFilters && p.filters.length >= 5)
          .take(10)
          .toList();

      expect(testProfiles.isNotEmpty, isTrue);

      const testFrequencies = [
        25.0,
        50.0,
        100.0,
        250.0,
        500.0,
        1000.0,
        2000.0,
        4000.0,
        8000.0,
        12000.0,
        16000.0
      ];

      for (final profile in testProfiles) {
        final fir = AutoEqFirGenerator.generateMinimumPhaseFromFilters(
          filters: profile.filters,
          preampGain: profile.preampGain,
          taps: 4096,
          sampleRate: 48000.0,
        );

        expect(fir.length, equals(4096));

        // Evaluate analytical biquad response at each frequency
        final scaleLinear = math.pow(10.0, profile.preampGain / 20.0);

        for (final freq in testFrequencies) {
          final firDb = AutoEqFirGenerator.evaluateFirMagnitudeDb(
            fir,
            freq,
            sampleRate: 48000.0,
          );

          // Calculate analytical response directly from filters
          var analyticalLinear = scaleLinear.toDouble();
          for (final f in profile.filters) {
            analyticalLinear *= _analyticalBiquadMag(f, freq, 48000.0);
          }
          final analyticalDb =
              20.0 * (math.log(analyticalLinear) / math.ln10);

          final diff = (firDb - analyticalDb).abs();
          expect(
            diff,
            lessThan(0.15),
            reason: 'Profile "${profile.name}" at ${freq}Hz: FIR=$firDb dB, '
                'PEQ=$analyticalDb dB (diff=$diff dB exceeded 0.15 dB)',
          );
        }
      }
    });

    test('linear-phase FIR exhibits symmetric impulse response', () {
      final profile = profiles.firstWhere(
        (p) => p.hasParametricFilters && p.filters.length >= 7,
      );

      final fir = AutoEqFirGenerator.generateLinearPhaseFromFilters(
        filters: profile.filters,
        preampGain: profile.preampGain,
        taps: 1024,
        sampleRate: 48000.0,
      );

      expect(fir.length, equals(1024));

      // In a symmetric linear-phase FIR of length N, h[i] == h[N - 1 - i]
      var maxAsymmetry = 0.0;
      for (var i = 0; i < 512; i++) {
        final diff = (fir[i] - fir[1023 - i]).abs();
        if (diff > maxAsymmetry) maxAsymmetry = diff;
      }
      expect(maxAsymmetry, lessThan(5e-4),
          reason: 'Linear phase FIR must be symmetric around center');
    });

    test('fallback FIR from 10-band gains reproduces shape', () {
      final testGains = [-3.0, -1.5, 0.0, 2.0, 3.5, 1.0, -1.0, -2.5, 0.0, 1.5];
      final fir = AutoEqFirGenerator.generateFromGains(
        gains: testGains,
        linearPhase: false,
        taps: 2048,
        sampleRate: 48000.0,
      );

      expect(fir.length, equals(2048));
      // Mid-band check at 1000 Hz (gains index 5 is 1.0 dB)
      final mag1k = AutoEqFirGenerator.evaluateFirMagnitudeDb(
        fir,
        1000.0,
        sampleRate: 48000.0,
      );
      expect(mag1k, closeTo(1.0, 1.0));
    });

    test('WAV serialization produces valid RIFF format', () {
      final profile = profiles.firstWhere((p) => p.hasParametricFilters);
      final fir = AutoEqFirGenerator.generateFir(profile: profile, taps: 512);
      final wav = AutoEqFirGenerator.toWavBytes(fir, sampleRate: 48000.0);

      expect(wav.length, equals(44 + 512 * 4));
      // Check RIFF header
      expect(String.fromCharCodes(wav.sublist(0, 4)), equals('RIFF'));
      expect(String.fromCharCodes(wav.sublist(8, 12)), equals('WAVE'));
      expect(String.fromCharCodes(wav.sublist(12, 16)), equals('fmt '));
      expect(String.fromCharCodes(wav.sublist(36, 40)), equals('data'));
    });
  });
}

double _analyticalBiquadMag(EqFilter filter, double freq, double sampleRate) {
  final f0 = filter.frequency;
  if (f0 <= 0 || !f0.isFinite) return 1.0;
  final a = filter.gain.abs() <= 1e-9
      ? 1.0
      : math.pow(10.0, filter.gain / 40.0).toDouble();
  final w0 = 2 * math.pi * f0 / sampleRate;
  final w = 2 * math.pi * freq / sampleRate;
  if (w0 <= 0 || w0 >= math.pi) return 1.0;
  final cosw0 = math.cos(w0);
  final sinw0 = math.sin(w0);

  double b0, b1, b2, a0, a1, a2;
  if (filter.filterType == EqFilterType.lowShelf) {
    final s = math.sqrt(a) / math.sqrt(math.max(filter.q, 0.1));
    final alpha = sinw0 / 2 * math.sqrt((a + 1 / a) * (1 / s - 1) + 2);
    b0 = a * ((a + 1) - (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha);
    b1 = 2 * a * ((a - 1) - (a + 1) * cosw0);
    b2 = a * ((a + 1) - (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha);
    a0 = (a + 1) + (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha;
    a1 = -2 * ((a - 1) + (a + 1) * cosw0);
    a2 = (a + 1) + (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha;
  } else if (filter.filterType == EqFilterType.highShelf) {
    final s = math.sqrt(a) / math.sqrt(math.max(filter.q, 0.1));
    final alpha = sinw0 / 2 * math.sqrt((a + 1 / a) * (1 / s - 1) + 2);
    b0 = a * ((a + 1) + (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha);
    b1 = -2 * a * ((a - 1) + (a + 1) * cosw0);
    b2 = a * ((a + 1) + (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha);
    a0 = (a + 1) - (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha;
    a1 = 2 * ((a - 1) - (a + 1) * cosw0);
    a2 = (a + 1) - (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha;
  } else {
    final alpha = sinw0 / (2 * math.max(filter.q, 0.1));
    b0 = 1 + alpha * a;
    b1 = -2 * cosw0;
    b2 = 1 - alpha * a;
    a0 = 1 + alpha / a;
    a1 = -2 * cosw0;
    a2 = 1 - alpha / a;
  }

  final cosw = math.cos(w);
  final cos2w = math.cos(2 * w);
  final num2 = b0 * b0 +
      b1 * b1 +
      b2 * b2 +
      2 * (b0 * b1 + b1 * b2) * cosw +
      2 * b0 * b2 * cos2w;
  final den2 = a0 * a0 +
      a1 * a1 +
      a2 * a2 +
      2 * (a0 * a1 + a1 * a2) * cosw +
      2 * a0 * a2 * cos2w;
  if (den2 <= 0) return 1.0;
  return math.sqrt(math.max(num2, 0) / den2);
}
