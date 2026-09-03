import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('google-services.json Validity Gate (B-54 / B-55)', () {
    final targets = [
      'google-services.json',
      'android/app/google-services.json',
      'android/app/src/dev/google-services.json',
      'android/app/src/prod/google-services.json',
      'android/app/src/ytm/google-services.json',
    ];

    for (final target in targets) {
      test('verifies $target has valid JSON, no placeholder bundle_id, and no double commas', () async {
        final file = File(target);
        if (!await file.exists()) return;

        final raw = await file.readAsString();
        expect(raw.contains(',,'), isFalse, reason: 'Must not contain double commas');
        expect(raw.contains('com.example.'), isFalse, reason: 'Must not contain placeholder com.example');

        final json = jsonDecode(raw) as Map<String, dynamic>;
        expect(json.containsKey('project_info'), isTrue);
        expect(json.containsKey('client'), isTrue);
      });
    }
  });
}
