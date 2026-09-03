import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_quality_info.dart';

void main() {
  group('AudioQualityInfo Unknown Bitrate (B-39)', () {
    test('marks unknown bitrate without defaulting to 320 kbps', () {
      const song = SongsTableData(
        id: 1,
        title: 'Unknown Track',
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        durationMs: 180000,
        path: '/storage/emulated/0/Music/track.mp3',
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        source: SongSource.local,
        isDownloaded: false,
        bitrateKbps: null,
      );

      final qualityInfo = AudioQualityInfo.fromSong(song);

      expect(qualityInfo.format, equals('Audio'));
      expect(qualityInfo.tierLabel, equals('Unknown Quality'));
      expect(qualityInfo.shortBadgeLabel, equals('Audio'));
      expect(qualityInfo.bitrateKbps, isNull);
    });

    test('retains high quality label when explicit high bitrate is present', () {
      const song = SongsTableData(
        id: 2,
        title: 'HQ Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        path: '/storage/emulated/0/Music/track.mp3',
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        source: SongSource.local,
        isDownloaded: false,
        bitrateKbps: 320,
      );

      final qualityInfo = AudioQualityInfo.fromSong(song);

      expect(qualityInfo.format, equals('MP3'));
      expect(qualityInfo.tierLabel, equals('High Quality MP3'));
      expect(qualityInfo.shortBadgeLabel, equals('MP3 • 320k'));
      expect(qualityInfo.bitrateKbps, equals(320));
    });
  });
}
