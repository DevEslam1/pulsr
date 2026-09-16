// Regression tests for the Local/Online classification predicate shared by the
// favorites tab and the standalone /favorites screen (Pulsr).
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/song_classification.dart';
import 'package:pulsr/data/db/app_database.dart';

SongsTableData _song({
  int id = 1,
  String path = '/music/track.mp3',
  String source = SongSource.local,
  String? remoteId,
  bool isDownloaded = false,
}) =>
    SongsTableData(
      id: id,
      title: 'T',
      artist: 'A',
      album: 'Al',
      durationMs: 1000,
      path: path,
      isFavorite: true,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
      source: source,
      remoteId: remoteId,
      isDownloaded: isDownloaded,
    );

void main() {
  group('isOnlineFavorite', () {
    test('local file with no remote id is Local', () {
      expect(isOnlineFavorite(_song()), isFalse);
    });

    test('streaming youtube sentinel with no file is Online', () {
      expect(
        isOnlineFavorite(
            _song(source: SongSource.youtube, path: 'ytmusic://abc')),
        isTrue,
      );
    });

    test('downloaded youtube track with content: uri stays Local', () {
      expect(
        isOnlineFavorite(_song(
          source: SongSource.youtube,
          path: 'content://media/external/audio/1',
          isDownloaded: true,
        )),
        isFalse,
      );
    });

    test('downloaded youtube track with a real path stays Local', () {
      expect(
        isOnlineFavorite(_song(
          source: SongSource.youtube,
          path: '/data/music/yt/dl.m4a',
          isDownloaded: true,
        )),
        isFalse,
      );
    });

    test('non-youtube row with a remoteId is Online', () {
      expect(isOnlineFavorite(_song(remoteId: 'vid123')), isTrue);
    });

    test('empty remoteId string does not count as online', () {
      expect(isOnlineFavorite(_song(remoteId: '')), isFalse);
    });
  });

  group('isDownloadedOnlineTrack', () {
    test('empty path is not a downloaded track', () {
      expect(isDownloadedOnlineTrack(_song(path: '')), isFalse);
    });

    test('ytmusic sentinel is not treated as downloaded', () {
      expect(
        isDownloadedOnlineTrack(
            _song(source: SongSource.youtube, path: 'ytmusic://x')),
        isFalse,
      );
    });

    test('isDownloaded flag marks it downloaded', () {
      expect(
        isDownloadedOnlineTrack(_song(path: '/m/a.mp3', isDownloaded: true)),
        isTrue,
      );
    });

    test('local row with a remoteId is a downloaded online track', () {
      expect(isDownloadedOnlineTrack(_song(remoteId: 'v1')), isTrue);
    });
  });
}
