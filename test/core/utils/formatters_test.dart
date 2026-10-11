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
      expect(Formatters.formatDuration(const Duration(minutes: 3, seconds: 5)),
          '3:05');
      expect(
          Formatters.formatDuration(const Duration(minutes: 12, seconds: 34)),
          '12:34');
      expect(
          Formatters.formatDuration(
              const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });

    test('formatDurationMs handles null, negative, and positive ms', () {
      expect(Formatters.formatDurationMs(null), '0:00');
      expect(Formatters.formatDurationMs(-500), '0:00');
      expect(Formatters.formatDurationMs(0), '0:00');
      expect(Formatters.formatDurationMs(185000), '3:05');
    });

    test('formatDuration switches to h:mm:ss past an hour (A-12 agreement)',
        () {
      // The AB-loop / bookmark labels now share this formatter with the seek
      // bar, so long tracks must render identically in both.
      expect(
          Formatters.formatDuration(const Duration(minutes: 59, seconds: 59)),
          '59:59');
      expect(Formatters.formatDuration(const Duration(hours: 1)), '1:00:00');
      expect(
          Formatters.formatDuration(
              const Duration(hours: 2, minutes: 5, seconds: 9)),
          '2:05:09');
    });

    test('formatTrackCount and formatSongCount pluralization', () {
      expect(Formatters.formatTrackCount(0), '0 tracks');
      expect(Formatters.formatTrackCount(1), '1 track');
      expect(Formatters.formatTrackCount(5), '5 tracks');

      expect(Formatters.formatSongCount(0), '0 songs');
      expect(Formatters.formatSongCount(1), '1 song');
      expect(Formatters.formatSongCount(42), '42 songs');
    });

    test('formatBytes promotes when rounding reaches a full unit', () {
      // 1,048,575 B divides to 1023.999 KB, which toStringAsFixed(1) rounds to
      // "1024.0" — the formatter must promote to the next suffix instead.
      expect(Formatters.formatBytes(1048575), '1.0 MB');
      expect(Formatters.formatBytes(1073741823), '1.0 GB');
      expect(Formatters.formatBytes(1099511627775), '1.0 TB');
    });

    test('formatBytes boundaries stay stable', () {
      expect(Formatters.formatBytes(0), '0 B');
      expect(Formatters.formatBytes(1023), '1023 B');
      expect(Formatters.formatBytes(1024), '1.0 KB');
      expect(Formatters.formatBytes(524288), '512.0 KB');
      expect(Formatters.formatBytes(1048576), '1.0 MB');
      // Rounds up to 1024.0 KB -> promotes; just below the rounding threshold
      // stays in KB.
      expect(Formatters.formatBytes(1048574), '1.0 MB');
      expect(Formatters.formatBytes(1048524), '1023.9 KB');
    });
  });
}
