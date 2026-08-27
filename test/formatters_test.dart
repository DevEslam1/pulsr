// test/formatters_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/formatters.dart';

void main() {
  group('Formatters Unit Tests', () {
    test('formatDuration formats null, negative and zero duration', () {
      expect(Formatters.formatDuration(null), '0:00');
      expect(Formatters.formatDuration(Duration.zero), '0:00');
      expect(Formatters.formatDuration(const Duration(seconds: -10)), '0:00');
    });

    test('formatDuration formats standard mm:ss durations', () {
      expect(Formatters.formatDuration(const Duration(seconds: 45)), '0:45');
      expect(Formatters.formatDuration(const Duration(minutes: 3, seconds: 5)), '3:05');
      expect(Formatters.formatDuration(const Duration(minutes: 12, seconds: 34)), '12:34');
      expect(Formatters.formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '62:03');
    });

    test('formatDurationMs handles null, negative, and positive ms', () {
      expect(Formatters.formatDurationMs(null), '0:00');
      expect(Formatters.formatDurationMs(-500), '0:00');
      expect(Formatters.formatDurationMs(0), '0:00');
      expect(Formatters.formatDurationMs(185000), '3:05');
    });

    test('formatTrackCount and formatSongCount pluralization', () {
      expect(Formatters.formatTrackCount(0), '0 tracks');
      expect(Formatters.formatTrackCount(1), '1 track');
      expect(Formatters.formatTrackCount(5), '5 tracks');

      expect(Formatters.formatSongCount(0), '0 songs');
      expect(Formatters.formatSongCount(1), '1 song');
      expect(Formatters.formatSongCount(42), '42 songs');
    });
  });
}
