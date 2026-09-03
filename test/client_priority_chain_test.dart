import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Client Capabilities Priority Chain (B-45)', () {
    test('verifies client_capabilities.json has no priority gaps greater than 3', () async {
      final file = File('android/app/src/ytmEnabled/assets/client_capabilities.json');
      expect(await file.exists(), isTrue, reason: 'client_capabilities.json must exist in assets');

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final clients = json['clients'] as Map<String, dynamic>;

      final priorities = <int>[];
      for (final entry in clients.entries) {
        final clientData = entry.value as Map<String, dynamic>;
        if (clientData.containsKey('priority')) {
          priorities.add((clientData['priority'] as num).toInt());
        }
      }

      priorities.sort();
      expect(priorities.isNotEmpty, isTrue);

      for (int i = 1; i < priorities.length; i++) {
        final gap = priorities[i] - priorities[i - 1];
        expect(
          gap <= 3,
          isTrue,
          reason: 'Priority gap between ${priorities[i - 1]} and ${priorities[i]} ($gap) must not exceed 3',
        );
      }
    });
  });
}
