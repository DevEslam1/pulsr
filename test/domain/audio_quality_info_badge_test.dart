import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/audio_quality_info.dart';

import '../helpers/test_song_factory.dart';

void main() {
  group('AudioQualityInfo badge honesty', () {
    test('missing bitrate shows the format only, never "bitrate unknown"', () {
      final info = AudioQualityInfo.fromSong(
        createTestSong(bitrateKbps: null),
        explicitFormat: 'MP3',
      );

      expect(info.shortBadgeLabel, 'MP3');
      expect(info.shortBadgeLabel.toLowerCase(), isNot(contains('unknown')));
    });

    test('known bitrate keeps the format + kbps label', () {
      final info = AudioQualityInfo.fromSong(
        createTestSong(bitrateKbps: 320),
        explicitFormat: 'MP3',
      );

      expect(info.shortBadgeLabel, contains('320'));
    });
  });
}
