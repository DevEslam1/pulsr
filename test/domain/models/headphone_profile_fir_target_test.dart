// test/domain/models/headphone_profile_fir_target_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';

HeadphoneProfile _profile() => const HeadphoneProfile(
      id: 'test',
      name: 'Test',
      brand: 'Test',
      model: 'Test',
      category: 'Test',
      gains: [],
      filters: [
        EqFilter(
          frequency: 100,
          gain: -6,
          q: 0.7,
          filterType: EqFilterType.lowShelf,
        ),
        EqFilter(
          frequency: 1000,
          gain: 5,
          q: 1.5,
          filterType: EqFilterType.peaking,
        ),
        EqFilter(
          frequency: 8000,
          gain: -3,
          q: 0.7,
          filterType: EqFilterType.highShelf,
        ),
      ],
    );

({List<double> freqs, List<double> gains}) _parse(String text) {
  final body = text.replaceFirst('GraphicEq:', '').trim();
  final freqs = <double>[];
  final gains = <double>[];
  for (final pair in body.split(';')) {
    final parts = pair.trim().split(RegExp(r'\s+'));
    if (parts.length != 2) continue;
    freqs.add(double.parse(parts[0]));
    gains.add(double.parse(parts[1]));
  }
  return (freqs: freqs, gains: gains);
}

void main() {
  test('FIR target string matches the native-form profile curve', () {
    final profile = _profile();
    final text = profile.toGraphicEqString(sampleRate: 48000.0);
    final parsed = _parse(text);
    expect(parsed.freqs.length, 512);
    final expected = profile.gainsFromFilters(
      centers: parsed.freqs,
      sampleRate: 48000.0,
    );
    for (var i = 0; i < parsed.gains.length; i++) {
      expect(parsed.gains[i], closeTo(expected[i], 0.011),
          reason: 'node ${parsed.freqs[i]} Hz');
    }
  });

  test('FIR target carries safe headroom inside the native ±30 dB clamp', () {
    final profile = _profile();
    final preamp = profile.computeFirPreamp(sampleRate: 48000.0);
    expect(preamp, lessThanOrEqualTo(-5.0));
    expect(preamp, greaterThanOrEqualTo(-30.0));
    final parsed = _parse(profile.toGraphicEqString(
      sampleRate: 48000.0,
      preampDb: preamp,
    ));
    expect(
        parsed.gains.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(0.011));
    expect(parsed.gains.reduce((a, b) => a < b ? a : b),
        greaterThanOrEqualTo(-30.0));
  });

  test('computeFirPreamp uses the peak boost, not the sum of positives', () {
    const profile = HeadphoneProfile(
      id: 'peaks',
      name: 'Peaks',
      brand: 'Test',
      model: 'Test',
      category: 'Test',
      gains: [],
      filters: [
        EqFilter(
          frequency: 1000,
          gain: 6,
          q: 2.0,
          filterType: EqFilterType.peaking,
        ),
        EqFilter(
          frequency: 4000,
          gain: 6,
          q: 2.0,
          filterType: EqFilterType.peaking,
        ),
      ],
    );
    final preamp = profile.computeFirPreamp(sampleRate: 48000.0);
    // The two peaks barely overlap: ~-7 dB, not -13 dB (the positive sum).
    expect(preamp, greaterThan(-10.0));
    expect(preamp, lessThan(-6.0));
  });

  group('HeadphoneProfile mathematical edge-case guards', () {
    test(
        'toGraphicEqString guards gains.isEmpty, gains.length == 1, numPoints <= 1 and non-finite gains',
        () {
      const emptyProfile = HeadphoneProfile(
        id: 'empty',
        name: 'Empty',
        brand: 'Test',
        model: 'Test',
        category: 'Test',
        gains: [],
        filters: [],
      );
      final emptyStr = emptyProfile.toGraphicEqString(numPoints: 0);
      expect(emptyStr, 'GraphicEq: 20.0 0.00; 20000.0 0.00');
      expect(emptyStr.contains('NaN'), isFalse);
      expect(emptyStr.contains('Infinity'), isFalse);

      const singleGainProfile = HeadphoneProfile(
        id: 'single',
        name: 'Single',
        brand: 'Test',
        model: 'Test',
        category: 'Test',
        gains: [4.5],
        filters: [],
      );
      final singleStr = singleGainProfile.toGraphicEqString();
      expect(singleStr, 'GraphicEq: 1000.0 4.50');
      expect(singleStr.contains('NaN'), isFalse);
      expect(singleStr.contains('Infinity'), isFalse);

      const nonFiniteGainsProfile = HeadphoneProfile(
        id: 'nan',
        name: 'Nan',
        brand: 'Test',
        model: 'Test',
        category: 'Test',
        gains: [double.nan, double.infinity, -double.infinity],
        filters: [],
      );
      final nanStr = nonFiniteGainsProfile.toGraphicEqString();
      expect(nanStr.contains('NaN'), isFalse);
      expect(nanStr.contains('Infinity'), isFalse);

      final filterProfile = _profile();
      final numPoints1 = filterProfile.toGraphicEqString(numPoints: 1);
      expect(numPoints1.contains('NaN'), isFalse);
      expect(numPoints1.contains('Infinity'), isFalse);
      expect(numPoints1.startsWith('GraphicEq: 1000.0 '), isTrue);

      final numPoints0 = filterProfile.toGraphicEqString(numPoints: 0);
      expect(numPoints0, 'GraphicEq: 20.0 0.00; 20000.0 0.00');
    });

    test(
        'computeFirPreamp guards gains.isEmpty, gains.length == 1, points <= 1 and non-finite gains',
        () {
      const emptyProfile = HeadphoneProfile(
        id: 'empty',
        name: 'Empty',
        brand: 'Test',
        model: 'Test',
        category: 'Test',
        gains: [],
        filters: [],
      );
      expect(emptyProfile.computeFirPreamp(), 0.0);

      const singleGainProfile = HeadphoneProfile(
        id: 'single',
        name: 'Single',
        brand: 'Test',
        model: 'Test',
        category: 'Test',
        gains: [5.0],
        filters: [],
      );
      final singlePreamp = singleGainProfile.computeFirPreamp();
      expect(singlePreamp, -6.0); // -(5.0 + 1.0)
      expect(singlePreamp.isFinite, isTrue);

      const nonFiniteProfile = HeadphoneProfile(
        id: 'nan',
        name: 'Nan',
        brand: 'Test',
        model: 'Test',
        category: 'Test',
        gains: [double.nan, double.infinity],
        filters: [],
      );
      expect(nonFiniteProfile.computeFirPreamp(), 0.0);

      final filterProfile = _profile();
      final points0Preamp = filterProfile.computeFirPreamp(points: 0);
      expect(points0Preamp, 0.0);

      final points1Preamp = filterProfile.computeFirPreamp(points: 1);
      expect(points1Preamp.isFinite, isTrue);
      expect(points1Preamp.isNaN, isFalse);
    });
  });
}
