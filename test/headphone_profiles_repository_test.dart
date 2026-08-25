// test/headphone_profiles_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/headphone_profiles_repository.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HeadphoneProfilesRepository Tests', () {
    test(
        'search matches multi-token queries fuzzily across brand, model, and category',
        () async {
      final repo = HeadphoneProfilesRepository();
      const customA = HeadphoneProfile(
        id: 'custom_1',
        name: 'Sony WH-1000XM4 AutoEq',
        brand: 'Sony',
        model: 'WH-1000XM4',
        category: 'Over-Ear',
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );
      const customB = HeadphoneProfile(
        id: 'custom_2',
        name: 'Apple AirPods Pro 2',
        brand: 'Apple',
        model: 'AirPods Pro 2',
        category: 'In-Ear',
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );

      await repo.addCustomProfile(customA);
      await repo.addCustomProfile(customB);

      // Multi-token match
      final resultsSony = repo.search('sony 1000xm4');
      expect(resultsSony.any((p) => p.id == 'custom_1'), isTrue);
      expect(resultsSony.any((p) => p.id == 'custom_2'), isFalse);

      final resultsAirpods = repo.search('pro airpods');
      expect(resultsAirpods.any((p) => p.id == 'custom_2'), isTrue);

      // Category filter
      final resultsCategory = repo.search('sony', category: 'In-Ear');
      expect(resultsCategory.isEmpty, isTrue);
    });

    test('addCustomProfile and removeProfile persist to custom_eq_profiles',
        () async {
      final repo = HeadphoneProfilesRepository();
      const customProfile = HeadphoneProfile(
        id: 'custom_test_99',
        name: 'Custom Tuning',
        brand: 'CustomBrand',
        model: 'ModelSpecial',
        category: 'In-Ear',
        gains: [1, 2, 3, 4, 3, 2, 1, 0, -1, -2],
        bassBoost: 0.4,
        preampGain: -3.0,
      );

      await repo.addCustomProfile(customProfile);
      expect(repo.getProfileById('custom_test_99'), isNotNull);

      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString('custom_eq_profiles');
      expect(savedJson, isNotNull);
      expect(savedJson!.contains('custom_test_99'), isTrue);

      await repo.removeProfile('custom_test_99');
      expect(repo.getProfileById('custom_test_99'), isNull);
    });
  });
}
