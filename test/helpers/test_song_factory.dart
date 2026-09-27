// test/helpers/test_song_factory.dart
import 'package:pulsr/data/db/app_database.dart';

SongsTableData createTestSong({
  int id = 1,
  String title = 'Test Song',
  String artist = 'Test Artist',
  String album = 'Test Album',
  int durationMs = 180000,
  String path = '/storage/emulated/0/Music/test.mp3',
  bool isFavorite = false,
  bool isMissing = false,
  int playCount = 0,
  int lastPositionMs = 0,
  String source = 'local',
  bool isDownloaded = false,
  int? bitrateKbps,
  int? year,
  String? genre,
}) {
  return SongsTableData(
    id: id,
    title: title,
    artist: artist,
    album: album,
    durationMs: durationMs,
    path: path,
    isFavorite: isFavorite,
    isMissing: isMissing,
    playCount: playCount,
    lastPositionMs: lastPositionMs,
    source: source,
    isDownloaded: isDownloaded,
    bitrateKbps: bitrateKbps,
    year: year,
    genre: genre,
  );
}
