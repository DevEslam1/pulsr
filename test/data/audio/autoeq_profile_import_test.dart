// test/data/audio/autoeq_profile_import_test.dart
//
// End-to-end coverage of the parametric AutoEQ import path at the data layer:
// a real `ParametricEQ.txt` snippet becomes a HeadphoneProfile whose filters
// are authoritative (gains empty), the repository persists it, and a reload
// brings the filters back intact. The rejection cases pin the validation the
// repository still applies.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/autoeq_parametric_parser.dart';
import 'package:pulsr/data/audio/headphone_profiles_repository.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real AutoEQ `ParametricEQ.txt` shape: ten filters in the common case, a
/// preamp, and mixed peaking/shelf types. Values are representative of a
/// correction curve, not a copied measurement.
const String _parametricEqTxt = '''
Preamp: -6.0 dB
Filter 1: ON LSC Fc 105 Hz Gain 5.0 dB Q 0.70
Filter 2: ON PK Fc 220 Hz Gain -2.5 dB Q 1.41
Filter 3: ON PK Fc 2800 Hz Gain 3.2 dB Q 1.20
Filter 4: ON HSC Fc 10000 Hz Gain -4.0 dB Q 0.70
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('parametric AutoEQ import', () {
    test('round-trips a parsed profile through the repository', () async {
      final repo = HeadphoneProfilesRepository();
      final parsed = AutoEqParametricParser.parse(
        _parametricEqTxt,
        name: 'Import Test HP',
      )!;
      final profile = AutoEqParametricParser.toHeadphoneProfile(parsed);

      // The id must be persistable, and the filters (not gains) carry the
      // correction.
      expect(profile.id, 'custom_autoeq_import_test_hp');
      expect(profile.gains, isEmpty);
      expect(profile.filters.length, 4);
      expect(profile.filters.first.filterType, EqFilterType.lowShelf);
      expect(profile.filters.last.filterType, EqFilterType.highShelf);

      await repo.addCustomProfile(profile);
      expect(repo.getProfileById(profile.id), isNotNull);

      // The repository writes only `custom_` ids to SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString('custom_eq_profiles')!) as List<dynamic>;
      expect(
        stored.whereType<Map<String, dynamic>>().any(
              (json) => json['id'] == profile.id,
            ),
        isTrue,
      );

      // Reload: `loadProfiles()` is the cold-start path and re-reads the
      // persisted JSON through HeadphoneProfile.fromJson.
      final loaded = await repo.loadProfiles();
      final restored = loaded.firstWhere((p) => p.id == profile.id);
      expect(restored.filters.length, profile.filters.length);
      expect(restored.filters, profile.filters);
      expect(restored.preampGain, profile.preampGain);
      expect(restored.hasParametricFilters, isTrue);
      expect(restored.source, 'AutoEQ ParametricEQ');
    });

    test('rejects a profile with neither gains nor filters', () async {
      final repo = HeadphoneProfilesRepository();
      const empty = HeadphoneProfile(
        id: 'custom_empty_profile',
        name: 'Empty',
        brand: '',
        model: '',
        category: 'AutoEq',
        gains: <double>[],
      );

      await repo.addCustomProfile(empty);

      expect(repo.getProfileById('custom_empty_profile'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('custom_eq_profiles') ?? '',
          isNot(contains('custom_empty_profile')));
    });

    test('still rejects gain curves with out-of-range gains', () async {
      final repo = HeadphoneProfilesRepository();
      const invalid = HeadphoneProfile(
        id: 'custom_invalid_gain_profile',
        name: 'Invalid',
        brand: '',
        model: '',
        category: 'AutoEq',
        gains: <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 40],
      );

      await repo.addCustomProfile(invalid);

      expect(repo.getProfileById('custom_invalid_gain_profile'), isNull);
    });
  });
}
