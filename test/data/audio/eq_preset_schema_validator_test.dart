// test/data/audio/eq_preset_schema_validator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/eq_preset_schema_validator.dart';
import 'package:pulsr/domain/models/eq_preset.dart';

void main() {
  group('EqPresetSchemaValidator Tests', () {
    test('validates and parses standard 10-band JSON preset', () {
      const json = '''
      {
        "schemaVersion": 1,
        "name": "Audiophile Reference",
        "gains": [1.5, 2.0, 0.0, -1.0, -0.5, 0.5, 1.0, 2.5, 3.0, 2.0],
        "bassBoost": 0.25,
        "customFrequencies": [32.0, 64.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]
      }
      ''';

      final result = EqPresetSchemaValidator.validateAndParse(json);
      expect(result.isValid, isTrue);
      expect(result.preset, isNotNull);
      expect(result.preset!.name, equals('Audiophile Reference'));
      expect(result.preset!.gains.length, equals(10));
      expect(result.preset!.gains[0], equals(1.5));
      expect(result.preset!.bassBoost, equals(0.25));
      expect(result.preset!.customFrequencies?.length, equals(10));
    });

    test('rejects empty payload', () {
      final result = EqPresetSchemaValidator.validateAndParse('   ');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('cannot be empty'));
    });

    test('rejects invalid JSON syntax', () {
      final result = EqPresetSchemaValidator.validateAndParse('{ invalid json: true }');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Malformed JSON structure'));
    });

    test('rejects missing or empty gains list', () {
      const noGainsJson = '{"name": "No Gains"}';
      final res1 = EqPresetSchemaValidator.validateAndParse(noGainsJson);
      expect(res1.isValid, isFalse);
      expect(res1.errorMessage, contains("Missing or invalid 'gains'"));

      const emptyGainsJson = '{"name": "Empty Gains", "gains": []}';
      final res2 = EqPresetSchemaValidator.validateAndParse(emptyGainsJson);
      expect(res2.isValid, isFalse);
      expect(res2.errorMessage, contains("cannot be empty"));
    });

    test('rejects non-numeric or non-finite gain values', () {
      const stringGainJson = '{"name": "Test", "gains": [1.0, "high", 0.0]}';
      final res = EqPresetSchemaValidator.validateAndParse(stringGainJson);
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('not numeric'));
    });

    test('rejects non-ascending custom frequencies', () {
      const badFreqJson = '''
      {
        "name": "Bad Freqs",
        "gains": [0, 0, 0],
        "customFrequencies": [100.0, 80.0, 200.0]
      }
      ''';
      final res = EqPresetSchemaValidator.validateAndParse(badFreqJson);
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('strictly ascending'));
    });

    test('parses EqualizerAPO / AutoEQ GraphicEQ format', () {
      const graphicEqStr =
          'GraphicEQ: 20 -2.5; 50 1.0; 100 2.5; 500 0.0; 1000 -1.5; 10000 3.0';
      final result = EqPresetSchemaValidator.validateAndParse(graphicEqStr);

      expect(result.isValid, isTrue);
      expect(result.preset, isNotNull);
      expect(result.preset!.name, equals('AutoEQ GraphicEQ'));
      expect(result.preset!.gains.length, equals(6));
      expect(result.preset!.gains[0], equals(-2.5));
      expect(result.preset!.customFrequencies?[0], equals(20.0));
      expect(result.preset!.customFrequencies?[5], equals(10000.0));
    });

    test('exports preset to valid schema JSON and round-trips correctly', () {
      const preset = EqPreset(
        name: 'Harmonic Warmth',
        gains: [3.0, 2.5, 1.5, 0.5, 0.0, 0.0, -0.5, -1.0, -1.5, -2.0],
        bassBoost: 0.15,
        customFrequencies: [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000],
      );

      final jsonStr = EqPresetSchemaValidator.exportToJson(preset, pretty: true);
      expect(jsonStr, contains('"schemaVersion": 1'));
      expect(jsonStr, contains('"Harmonic Warmth"'));

      final parsed = EqPresetSchemaValidator.validateAndParse(jsonStr);
      expect(parsed.isValid, isTrue);
      expect(parsed.preset!.name, equals('Harmonic Warmth'));
      expect(parsed.preset!.gains, equals(preset.gains));
      expect(parsed.preset!.bassBoost, equals(preset.bassBoost));
    });

    test('validatePreset detects out of bounds gains', () {
      const outOfBoundsPreset = EqPreset(
        name: 'Extreme Boost',
        gains: [55.0, 0.0, 0.0],
      );

      final res = EqPresetSchemaValidator.validatePreset(outOfBoundsPreset);
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('exceeds allowed range'));
    });
  });
}
