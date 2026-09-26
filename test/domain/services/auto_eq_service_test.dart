// test/domain/services/auto_eq_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/auto_eq_profile.dart';
import 'package:pulsr/domain/services/auto_eq_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoEqProfile', () {
    test('serializes and deserializes correctly', () {
      final profile = AutoEqProfile(
        id: 'sony_wh1000xm4',
        name: 'Sony WH-1000XM4',
        brand: 'Sony',
        model: 'WH-1000XM4',
        category: 'Over-Ear',
        gains: const [2.0, -1.0, 0.5, 3.0, -2.0],
        bassBoost: 0.15,
        preampGain: -2.5,
      );

      final json = profile.toJson();
      final revived = AutoEqProfile.fromJson(json);

      expect(revived.id, profile.id);
      expect(revived.name, profile.name);
      expect(revived.brand, profile.brand);
      expect(revived.model, profile.model);
      expect(revived.gains, profile.gains);
      expect(revived.preampGain, profile.preampGain);
    });

    test('generates valid EqualizerAPO GraphicEq string', () {
      final profile = AutoEqProfile(
        id: 'hd650',
        name: 'Sennheiser HD650',
        brand: 'Sennheiser',
        model: 'HD650',
        category: 'Open-Back',
        gains: const [4.0, 1.5, 0.0, -2.0, 1.0],
      );

      final eqStr = profile.toGraphicEqString();
      expect(eqStr, startsWith('GraphicEq: '));
      expect(eqStr, contains('20 4.00'));
      expect(eqStr, contains('60 4.00'));
      expect(eqStr, contains('250 1.50'));
      expect(eqStr, contains('1000 0.00'));
      expect(eqStr, contains('4000 -2.00'));
      expect(eqStr, contains('12000 1.00'));
      expect(eqStr, contains('20000 1.00'));
    });

    test('uses customGraphicEq verbatim if provided', () {
      const custom = 'GraphicEq: 30 2.5; 500 -1.0; 8000 3.2';
      final profile = AutoEqProfile(
        id: 'custom_curve',
        name: 'Custom Curve',
        brand: 'Custom',
        model: 'Custom',
        category: 'Custom',
        gains: const [],
        customGraphicEq: custom,
      );

      expect(profile.toGraphicEqString(), custom);
    });
  });

  group('AutoEqService Import/Export & Matching', () {
    test('exports and imports profile list via JSON', () {
      final service = AutoEqService();
      final profiles = [
        AutoEqProfile(
          id: 'p1',
          name: 'Model 1',
          brand: 'BrandA',
          model: 'M1',
          category: 'IEM',
          gains: const [1.0, 2.0],
        ),
        AutoEqProfile(
          id: 'p2',
          name: 'Model 2',
          brand: 'BrandB',
          model: 'M2',
          category: 'Over-Ear',
          gains: const [-1.0, 0.0],
        ),
      ];

      final jsonStr = service.exportProfilesJson(profiles);
      final imported = service.importProfilesJson(jsonStr);

      expect(imported.length, 2);
      expect(imported[0].id, 'p1');
      expect(imported[1].id, 'p2');
    });
  });
}
