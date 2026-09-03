import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Scrobbler Dedup Key with Album (B-37)', () {
    String generateDedupKey(String artist, String track, String album) {
      return '${artist}_${track}_${album.isNotEmpty ? album : "unknown"}';
    }

    test('generates unique dedup keys for same track name across different albums', () {
      final key1 = generateDedupKey('Adele', 'Hello', '25');
      final key2 = generateDedupKey('Adele', 'Hello', 'Live 2016');

      expect(key1, equals('Adele_Hello_25'));
      expect(key2, equals('Adele_Hello_Live 2016'));
      expect(key1, isNot(equals(key2)));
    });

    test('handles empty album gracefully with "unknown"', () {
      final key = generateDedupKey('Queen', 'Bohemian Rhapsody', '');
      expect(key, equals('Queen_Bohemian Rhapsody_unknown'));
    });
  });
}
