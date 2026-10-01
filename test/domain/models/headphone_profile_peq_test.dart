// test/domain/models/headphone_profile_peq_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';

void main() {
  group('EqFilter', () {
    test('round-trips through JSON with type and Q', () {
      const f = EqFilter(
        frequency: 105.0,
        gain: -3.2,
        q: 0.7,
        filterType: EqFilterType.lowShelf,
      );
      final revived = EqFilter.fromJson(f.toJson());
      expect(revived.frequency, 105.0);
      expect(revived.gain, -3.2);
      expect(revived.q, 0.7);
      expect(revived.filterType, EqFilterType.lowShelf);
    });
  });

  group('HeadphoneProfile parametric filters', () {
    test('parses filters from JSON and flags hasParametricFilters', () {
      final json = {
        'id': 'autoeq_oratory1990_over_ear_sony_wh_1000xm5',
        'name': 'Sony WH-1000XM5',
        'brand': 'Sony',
        'model': 'WH-1000XM5',
        'category': 'Over-Ear',
        'gains': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        'preampGain': -6.2,
        'filters': [
          {'frequency': 105.0, 'gain': -3.2, 'q': 0.7, 'type': 1},
          {'frequency': 2448.0, 'gain': 6.9, 'q': 2.46, 'type': 0},
          {'frequency': 10000.0, 'gain': 4.9, 'q': 0.7, 'type': 2},
        ],
        'source': 'AutoEQ/oratory1990',
      };
      final profile = HeadphoneProfile.fromJson(json);
      expect(profile.hasParametricFilters, isTrue);
      expect(profile.filters.length, 3);
      expect(profile.filters[1].filterType, EqFilterType.peaking);
      expect(profile.source, 'AutoEQ/oratory1990');
    });

    test('drops non-finite/invalid filters on load', () {
      final json = {
        'id': 'bad',
        'name': 'Bad',
        'brand': 'X',
        'model': 'Y',
        'category': 'Over-Ear',
        'gains': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        'filters': [
          {'frequency': 0.0, 'gain': 1.0, 'q': 1.0, 'type': 0},
          {'frequency': 100.0, 'gain': 1.0, 'q': 1.0, 'type': 0},
        ],
      };
      final profile = HeadphoneProfile.fromJson(json);
      expect(profile.filters.length, 1);
      expect(profile.filters.first.frequency, 100.0);
    });

    test('computeSafePreamp is negative and bounded by positive gains', () {
      const profile = HeadphoneProfile(
        id: 'p',
        name: 'p',
        brand: 'b',
        model: 'm',
        category: 'Over-Ear',
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        preampGain: 99.0,
        filters: [
          EqFilter(frequency: 100, gain: 6.0),
          EqFilter(frequency: 1000, gain: -3.0),
          EqFilter(frequency: 5000, gain: 4.0),
        ],
      );
      final preamp = profile.computeSafePreamp(safetyMarginDb: 1.0);
      expect(preamp, lessThan(0));
      // -(6 + 4 + 1) = -11
      expect(preamp, closeTo(-11.0, 0.001));
    });

    test('computeSafePreamp is zero with no positive gains', () {
      const profile = HeadphoneProfile(
        id: 'p',
        name: 'p',
        brand: 'b',
        model: 'm',
        category: 'Over-Ear',
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        filters: [EqFilter(frequency: 1000, gain: -3.0)],
      );
      expect(profile.computeSafePreamp(), 0.0);
    });

    test('computeSafePreamp is zero for a legacy gain-only profile', () {
      const profile = HeadphoneProfile(
        id: 'p',
        name: 'p',
        brand: 'b',
        model: 'm',
        category: 'Over-Ear',
        gains: [5, 4, 3, 2, 1, 0, 0, 0, 0, 0],
        preampGain: -3.0,
      );
      expect(profile.computeSafePreamp(), 0.0);
    });

    test('gainsFromFilters evaluates a peaking boost near its center', () {
      const profile = HeadphoneProfile(
        id: 'p',
        name: 'p',
        brand: 'b',
        model: 'm',
        category: 'Over-Ear',
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        filters: [
          EqFilter(frequency: 1000, gain: 6.0, q: 1.0),
        ],
      );
      final gains = profile.gainsFromFilters();
      expect(gains.length, EqPreset.centerFrequencies.length);
      // The 1 kHz band (~index 5) should show the boost.
      final idx =
          EqPreset.centerFrequencies.indexOf(1000);
      expect(gains[idx], greaterThan(4.0));
      // Far-away bands are near flat.
      expect(gains[0].abs(), lessThan(1.0));
    });

    test('low-shelf filter boosts lows and not highs', () {
      const profile = HeadphoneProfile(
        id: 'p',
        name: 'p',
        brand: 'b',
        model: 'm',
        category: 'Over-Ear',
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        filters: [
          EqFilter(
            frequency: 200,
            gain: 6.0,
            q: 0.7,
            filterType: EqFilterType.lowShelf,
          ),
        ],
      );
      final gains = profile.gainsFromFilters();
      final low = gains.first;
      final high = gains.last;
      expect(low, greaterThan(3.0));
      expect(high.abs(), lessThan(1.0));
    });

    test('toJson preserves filters for a custom profile round-trip', () {
      const profile = HeadphoneProfile(
        id: 'custom_1',
        name: 'Custom',
        brand: 'Me',
        model: 'Mine',
        category: 'Custom',
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        filters: [
          EqFilter(frequency: 250, gain: 2.5, q: 1.2),
        ],
      );
      final json = profile.toJson();
      expect(json['filters'], isA<List<dynamic>>());
      final revived = HeadphoneProfile.fromJson(json);
      expect(revived.filters.length, 1);
      expect(revived.filters.first.frequency, 250.0);
      expect(revived.filters.first.gain, 2.5);
    });
  });
}
