// test/architecture/wiring_matrix_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Wiring Matrix Architecture Guard', () {
    test('Wiring matrix contract contains all 14 mandatory sections with required fields', () {
      final file = File('test/fixtures/contracts/wiring_matrix.json');
      expect(file.existsSync(), isTrue, reason: 'Wiring matrix fixture must exist');

      final rawList = jsonDecode(file.readAsStringSync()) as List<dynamic>;
      expect(rawList.length, 14, reason: 'Wiring matrix must cover all 14 Section 8 features');

      final requiredKeys = [
        'feature',
        'uiEntry',
        'stateOwner',
        'persistence',
        'backendCall',
        'statusSource',
        'acceptanceTest',
      ];

      final expectedFeatures = {
        'Native DSD',
        'DoP',
        'Remaster',
        'PCM-to-DSD',
        'FIR',
        'HRTF',
        'MCH/LFE',
        'Low-power',
        'Cast',
        'UPnP',
        'ABX export',
        'ALAC probe',
        'Decoders',
        'Measurement',
      };

      final observedFeatures = <String>{};

      for (final item in rawList) {
        expect(item, isA<Map<String, dynamic>>());
        final map = item as Map<String, dynamic>;

        for (final k in requiredKeys) {
          expect(map.containsKey(k), isTrue, reason: 'Row missing key: $k');
          expect(map[k], isA<String>());
          expect((map[k] as String).trim(), isNotEmpty, reason: 'Row key $k must not be empty');
        }

        observedFeatures.add(map['feature'] as String);
      }

      expect(observedFeatures, equals(expectedFeatures),
          reason: 'Every required feature from Section 8 must be present');
    });
  });
}
