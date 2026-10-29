import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/yt_download_metadata.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

SongsTableData _song({
  String title = 'Unknown Title',
  String artist = 'Unknown Artist',
  int durationMs = 0,
  String? artworkUrl,
}) =>
    SongsTableData(
      id: -1,
      title: title,
      artist: artist,
      album: '',
      path: 'ytmusic://vid',
      source: SongSource.youtube,
      remoteId: 'vid00000001',
      remoteArtworkUrl: artworkUrl,
      durationMs: durationMs,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );

YtmStream _stream({
  String title = 'Real Title',
  String artist = 'Real Artist',
  Duration duration = const Duration(minutes: 3),
  String? artworkUrl,
}) =>
    YtmStream(
      videoId: 'vid00000001',
      url: 'https://example.invalid/audio',
      mimeType: 'audio/mp4',
      container: 'm4a',
      bitrateKbps: 128,
      duration: duration,
      title: title,
      artist: artist,
      artworkUrl: artworkUrl,
    );

void main() {
  test('repairs placeholder title and artist from the resolved stream', () {
    final resolved = YtDownloadMetadataResolver.resolve(_song(), _stream());

    expect(resolved.title, 'Real Title');
    expect(resolved.artist, 'Real Artist');
    expect(resolved.durationMs, 180000);
  });

  test('keeps real task metadata instead of replacing it', () {
    final resolved = YtDownloadMetadataResolver.resolve(
      _song(title: 'Known Title', artist: 'Known Artist', durationMs: 1000),
      _stream(title: 'Other Title', artist: 'Other Artist'),
    );

    expect(resolved.title, 'Known Title');
    expect(resolved.artist, 'Known Artist');
    expect(resolved.durationMs, 1000);
  });

  test('fills missing artwork from the stream', () {
    final resolved = YtDownloadMetadataResolver.resolve(
      _song(artist: 'Known Artist'),
      _stream(artworkUrl: 'https://img.example/cover.jpg'),
    );

    expect(resolved.remoteArtworkUrl, 'https://img.example/cover.jpg');
  });
}
