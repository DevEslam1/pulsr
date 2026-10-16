// test/data/repositories/lyrics_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/lrclib_service.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/data/repositories/lyrics_repository.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';

class MockLrclibService extends Mock implements LrclibService {}

class MockYtmAccountService extends Mock implements YtmAccountService {}

void main() {
  group('LyricsRepository', () {
    late MockLrclibService mockLrclib;
    late MockYtmAccountService mockYtm;
    late LyricsRepository repository;

    setUp(() {
      mockLrclib = MockLrclibService();
      mockYtm = MockYtmAccountService();
      repository = LyricsRepository(
        lrclibService: mockLrclib,
        ytmAccountService: mockYtm,
      );
    });

    test('fetches synced lyrics from LRCLIB and formats to LRC', () async {
      const line1 = LyricsLine(
        timestamp: Duration(seconds: 10),
        text: 'First line',
      );
      const line2 = LyricsLine(
        timestamp: Duration(seconds: 15),
        text: 'Second line',
      );
      const fakeResult = LyricsResult(
        lines: [line1, line2],
        source: LyricsSource.lrclib,
      );

      when(() => mockLrclib.fetchLyrics(
            trackName: any(named: 'trackName'),
            artistName: any(named: 'artistName'),
            albumName: any(named: 'albumName'),
            durationSeconds: any(named: 'durationSeconds'),
          )).thenAnswer((_) async => fakeResult);

      final lrc = await repository.fetchLyricsLrc(
        title: 'Song',
        artist: 'Artist',
      );

      expect(lrc, isNotNull);
      expect(lrc, contains('[00:10.00]First line'));
      expect(lrc, contains('[00:15.00]Second line'));
    });

    test('falls back to YtmAccountService when LRCLIB returns null', () async {
      when(() => mockLrclib.fetchLyrics(
            trackName: any(named: 'trackName'),
            artistName: any(named: 'artistName'),
            albumName: any(named: 'albumName'),
            durationSeconds: any(named: 'durationSeconds'),
          )).thenAnswer((_) async => null);

      const ytmResult = LyricsResult(
        lines: [
          LyricsLine(timestamp: Duration.zero, text: 'Unsynced YTM line 1'),
          LyricsLine(timestamp: Duration.zero, text: 'Unsynced YTM line 2'),
        ],
        source: LyricsSource.ytmusic,
      );

      when(() => mockYtm.fetchYtmLyrics('video_xyz'))
          .thenAnswer((_) async => ytmResult);

      final lrc = await repository.fetchLyricsLrc(
        title: 'Song',
        artist: 'Artist',
        videoId: 'video_xyz',
      );

      expect(lrc, isNotNull);
      expect(lrc, contains('Unsynced YTM line 1\nUnsynced YTM line 2'));
    });

    test('returns null when no providers find lyrics', () async {
      when(() => mockLrclib.fetchLyrics(
            trackName: any(named: 'trackName'),
            artistName: any(named: 'artistName'),
            albumName: any(named: 'albumName'),
            durationSeconds: any(named: 'durationSeconds'),
          )).thenAnswer((_) async => null);

      when(() => mockYtm.fetchYtmLyrics(any())).thenAnswer((_) async => null);

      final lrc = await repository.fetchLyricsLrc(
        title: 'Unknown Track',
        artist: 'Unknown Artist',
        videoId: 'no_lyrics_video',
      );

      expect(lrc, isNull);
    });
  });
}
