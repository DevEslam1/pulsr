// test/data/services/spotify_importer_service_test.dart
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/services/spotify_importer_service.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/repositories/smart_playlist_engine_interface.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/data/repositories/music_repository.dart';

class MockYtmService extends Mock implements YtmService {}

class MockSmartPlaylistEngine extends Mock implements ISmartPlaylistEngine {}

void main() {
  group('SpotifyImporterService URL Parsing', () {
    test('extracts valid 22-char ID from standard web URL', () {
      const url =
          'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=ab12cd34ef56';
      expect(
        SpotifyImporterService.extractPlaylistId(url),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
    });

    test('extracts valid ID from URL without query params', () {
      const url =
          'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M';
      expect(
        SpotifyImporterService.extractPlaylistId(url),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
    });

    test('extracts valid ID from spotify URI format', () {
      const uri = 'spotify:playlist:37i9dQZF1DXcBWIGoYBM5M';
      expect(
        SpotifyImporterService.extractPlaylistId(uri),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
    });

    test('extracts raw 22-character playlist ID', () {
      const rawId = '37i9dQZF1DXcBWIGoYBM5M';
      expect(
        SpotifyImporterService.extractPlaylistId(rawId),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
    });

    test('returns null for non-spotify or invalid IDs', () {
      expect(SpotifyImporterService.extractPlaylistId(''), isNull);
      expect(SpotifyImporterService.extractPlaylistId('invalid-id'), isNull);
      expect(
        SpotifyImporterService.extractPlaylistId(
            'https://youtube.com/playlist?list=PL12345'),
        isNull,
      );
      expect(
        SpotifyImporterService.extractPlaylistId(
            'https://open.spotify.com/album/37i9dQZF1DXcBWIGoYBM5M'),
        isNull,
      );
    });
  });

  group('SpotifyImporterService Embed Parsing', () {
    test('parses playlist title and tracks from __NEXT_DATA__ JSON', () async {
      const nextDataJson = {
        'props': {
          'pageProps': {
            'state': {
              'data': {
                'entity': {
                  'name': 'Today Top Hits',
                  'trackList': [
                    {
                      'title': 'Blinding Lights',
                      'subtitle': 'The Weeknd',
                    },
                    {
                      'name': 'Levitating',
                      'artists': [
                        {'name': 'Dua Lipa'},
                        {'name': 'DaBaby'},
                      ],
                    },
                  ],
                },
              },
            },
          },
        },
      };

      final fakeHtml = '''
<!DOCTYPE html>
<html>
  <head>
    <script id="__NEXT_DATA__" type="application/json">${jsonEncode(nextDataJson)}</script>
  </head>
  <body></body>
</html>
''';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/embed/playlist/37i9dQZF1DXcBWIGoYBM5M')) {
          return http.Response(fakeHtml, 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = SpotifyImporterService(httpClient: mockClient);
      final result =
          await service.fetchPlaylistTracks('37i9dQZF1DXcBWIGoYBM5M');

      expect(result.title, 'Today Top Hits');
      expect(result.tracks.length, 2);
      expect(result.tracks[0].title, 'Blinding Lights');
      expect(result.tracks[0].artist, 'The Weeknd');
      expect(result.tracks[1].title, 'Levitating');
      expect(result.tracks[1].artist, 'Dua Lipa, DaBaby');
    });

    test('falls back to oEmbed when embed lacks title', () async {
      const nextDataJson = {
        'props': {
          'pageProps': {
            'state': {
              'data': {
                'entity': {
                  'trackList': [
                    {
                      'title': 'Song One',
                      'subtitle': 'Artist One',
                    },
                  ],
                },
              },
            },
          },
        },
      };

      final fakeHtml = '''
<script id="__NEXT_DATA__" type="application/json">${jsonEncode(nextDataJson)}</script>
''';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/embed/playlist/37i9dQZF1DXcBWIGoYBM5M')) {
          return http.Response(fakeHtml, 200);
        }
        if (request.url.path.contains('/oembed')) {
          return http.Response(
            jsonEncode({'title': 'Fallback oEmbed Playlist Title'}),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = SpotifyImporterService(httpClient: mockClient);
      final result =
          await service.fetchPlaylistTracks('37i9dQZF1DXcBWIGoYBM5M');

      expect(result.title, 'Fallback oEmbed Playlist Title');
      expect(result.tracks.length, 1);
      expect(result.tracks.first.title, 'Song One');
    });
  });

  group('SpotifyImporterService Full Import Workflow', () {
    late AppDatabase db;
    late MusicRepository musicRepo;
    late PlaylistUseCases playlistUseCases;
    late MockYtmService mockYtmService;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      musicRepo = MusicRepository(db);
      playlistUseCases = PlaylistUseCases(musicRepo, MockSmartPlaylistEngine());
      mockYtmService = MockYtmService();
    });

    tearDown(() async {
      await db.close();
    });

    test('imports Spotify playlist, resolves YTM tracks and creates local playlist',
        () async {
      const nextDataJson = {
        'props': {
          'pageProps': {
            'state': {
              'data': {
                'entity': {
                  'name': 'Workout Vibes',
                  'trackList': [
                    {
                      'title': 'Stronger',
                      'subtitle': 'Kanye West',
                    },
                  ],
                },
              },
            },
          },
        },
      };

      final fakeHtml =
          '<script id="__NEXT_DATA__" type="application/json">${jsonEncode(nextDataJson)}</script>';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/embed/playlist/37i9dQZF1DXcBWIGoYBM5M')) {
          return http.Response(fakeHtml, 200);
        }
        return http.Response('Not Found', 404);
      });

      const ytmCandidate = YtmTrack(
        videoId: 'vid_stronger_123',
        title: 'Stronger',
        artist: 'Kanye West',
        duration: Duration(seconds: 311),
        artworkUrl: 'https://i.ytimg.com/vi/vid_stronger_123/hqdefault.jpg',
      );

      when(() => mockYtmService.search(any(), limit: any(named: 'limit')))
          .thenAnswer((_) async => [ytmCandidate]);

      final service = SpotifyImporterService(
        httpClient: mockClient,
        ytmService: mockYtmService,
        playlistUseCases: playlistUseCases,
        db: db,
      );

      final importResult = await service.importPlaylist(
        'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
      );

      expect(importResult.playlistTitle, 'Workout Vibes');
      expect(importResult.matchedCount, 1);
      expect(importResult.unmatchedCount, 0);

      // Verify playlist exists in database
      final playlists = await db.select(db.playlistsTable).get();
      expect(playlists.length, 1);
      expect(playlists.first.name, 'Workout Vibes');
      expect(playlists.first.id, importResult.playlistId);

      // Verify track was inserted into songsTable
      final songs = await db.select(db.songsTable).get();
      expect(songs.length, 1);
      expect(songs.first.remoteId, 'vid_stronger_123');
      expect(songs.first.title, 'Stronger');

      // Verify playlist entry was created
      final entries = await db.select(db.playlistEntriesTable).get();
      expect(entries.length, 1);
      expect(entries.first.playlistId, importResult.playlistId);
      expect(entries.first.songId, songs.first.id);
    });
  });
}
