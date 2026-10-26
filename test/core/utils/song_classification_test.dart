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

  group('isQuranTrack', () {
    test('null song returns false', () {
      expect(isQuranTrack(null), isFalse);
    });

    test('regular pop song returns false', () {
      final song = _song(
        id: 1,
        path: '/music/billie_jean.mp3',
        source: SongSource.local,
      ).copyWith(
        title: 'Billie Jean',
        artist: 'Michael Jackson',
        album: 'Thriller',
      );
      expect(isQuranTrack(song), isFalse);
    });

    test('Quran radio station by name / genre returns true', () {
      final stationSong = _song(
        id: -1,
        path: 'https://stream.radiojar.com/hussary',
        source: SongSource.radio,
      ).copyWith(
        title: 'إذاعة الشيخ محمود خليل الحصري',
        artist: 'Quran',
      );
      expect(isQuranTrack(stationSong), isTrue);
    });

    test('Cairo Quran radio returns true', () {
      final stationSong = _song(
        id: -2,
        path: 'https://stream.radiojar.com/8s5u5tpdtwzuv',
        source: SongSource.radio,
      ).copyWith(
        title: 'إذاعة القرآن الكريم من القاهرة',
        artist: 'Islamic',
      );
      expect(isQuranTrack(stationSong), isTrue);
    });

    test('Minshawi recitation with diacritics returns true', () {
      final song = _song(
        id: 10,
        path: '/storage/quran/minshawi_rahman.mp3',
        source: SongSource.local,
      ).copyWith(
        title: 'سُورَةُ الرَّحْمَنِ - الشَّيْخِ مُحَمَّد صِدِّيق المِنْشَاوِي',
        artist: 'محمد صديق المنشاوي',
        album: 'المصحف المجود',
      );
      expect(isQuranTrack(song), isTrue);
    });

    test('Abdulbasit Tajweed recitation returns true', () {
      final song = _song(
        id: 11,
        path: 'ytmusic://abdulbasit123',
        source: SongSource.youtube,
      ).copyWith(
        title: 'Surah Maryam',
        artist: 'Abdulbasit Abdulsamad',
        album: 'Mujawwad',
      );
      expect(isQuranTrack(song), isTrue);
    });

    test('BBC News radio returns false', () {
      final newsSong = _song(
        id: -3,
        path: 'https://stream.live.vc.bbcmedia.co.uk/bbc_world_service',
        source: SongSource.radio,
      ).copyWith(
        title: 'BBC World Service',
        artist: 'News',
      );
      expect(isQuranTrack(newsSong), isFalse);
    });
  });
}
