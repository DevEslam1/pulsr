// test/core/services/xdm_backend_service_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/services/xdm_backend_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHttpClient mockClient;
  late XdmBackendService service;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.ytdlpBackendEnabled: true,
      PrefsKeys.ytdlpBackendUrl: 'https://test-xdm-backend.app',
      PrefsKeys.ytdlpBackendToken: 'test-token-123',
    });
    mockClient = MockHttpClient();
    service = XdmBackendService.withClient(mockClient);
  });

  group('XdmBackendService', () {
    test('checkHealth returns ok when backend responds with 200', () async {
      when(() => mockClient.get(
            Uri.parse('https://test-xdm-backend.app/health'),
          )).thenAnswer((_) async => http.Response(
            jsonEncode({
              'status': 'ok',
              'ytdlp': '2026.07.04',
              'proxy_pool_size': 10,
            }),
            200,
          ));

      final health = await service.checkHealth();
      expect(health.ok, isTrue);
      expect(health.ytdlpVersion, '2026.07.04');
      expect(health.proxyPoolSize, 10);
    });

    test('resolveStream uses YouTube Music URL and prioritizes AAC stream by quality', () async {
      final sampleStreamResponse = {
        'url': 'https://music.youtube.com/watch?v=dQw4w9WgXcQ',
        'title': 'Test Song Title',
        'streams': [
          {
            'type': 'muxed',
            'quality': '720p',
            'ext': 'mp4',
            'src': 'https://cdn.youtube.com/video_muxed',
          },
          {
            'type': 'audio',
            'quality': '160kbps',
            'ext': 'webm',
            'src': 'https://cdn.youtube.com/audio_webm_160',
          },
          {
            'type': 'audio',
            'quality': '128kbps',
            'ext': 'm4a',
            'src': 'https://cdn.youtube.com/audio_m4a_128',
          },
          {
            'type': 'audio',
            'quality': '48kbps',
            'ext': 'm4a',
            'src': 'https://cdn.youtube.com/audio_m4a_48',
          }
        ]
      };

      when(() => mockClient.get(
            Uri.parse('https://test-xdm-backend.app/api/streams?url=https%3A%2F%2Fmusic.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => http.Response(
            jsonEncode(sampleStreamResponse),
            200,
          ));

      // High Quality -> selects 128kbps AAC over 160kbps Opus webm
      final highResult = await service.resolveStream('dQw4w9WgXcQ', quality: 'high');
      expect(highResult, isNotNull);
      expect(highResult!.url, 'https://cdn.youtube.com/audio_m4a_128');
      expect(highResult.container, 'm4a');
      expect(highResult.bitrateKbps, 128);

      // Low Quality -> selects 48kbps AAC
      final lowResult = await service.resolveStream('dQw4w9WgXcQ', quality: 'low');
      expect(lowResult, isNotNull);
      expect(lowResult!.url, 'https://cdn.youtube.com/audio_m4a_48');
      expect(lowResult.container, 'm4a');
      expect(lowResult.bitrateKbps, 48);
    });

    test('getPlaylist parses videos into YtmTrack list', () async {
      final samplePlaylistResponse = {
        'info': {'title': 'Sample Playlist', 'author': 'Test Channel'},
        'videos': [
          {
            'id': 'video_1',
            'title': 'Song One',
            'author': 'Artist A',
            'duration': 180,
            'thumbnailUrl': 'https://img.youtube.com/vi/video_1/0.jpg',
            'url': 'https://www.youtube.com/watch?v=video_1',
          },
          {
            'id': 'video_2',
            'title': 'Song Two',
            'author': 'Artist B',
            'duration': 240,
            'thumbnailUrl': 'https://img.youtube.com/vi/video_2/0.jpg',
            'url': 'https://www.youtube.com/watch?v=video_2',
          }
        ]
      };

      when(() => mockClient.get(
            Uri.parse('https://test-xdm-backend.app/api/playlist?url=https%3A%2F%2Fwww.youtube.com%2Fplaylist%3Flist%3DPL123'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => http.Response(
            jsonEncode(samplePlaylistResponse),
            200,
          ));

      final tracks = await service.getPlaylist('https://www.youtube.com/playlist?list=PL123');

      expect(tracks.length, 2);
      expect(tracks[0].videoId, 'video_1');
      expect(tracks[0].title, 'Song One');
      expect(tracks[0].artist, 'Artist A');
      expect(tracks[0].duration.inSeconds, 180);
      expect(tracks[1].videoId, 'video_2');
    });

    test('search parses search results into YtmTrack list', () async {
      final sampleSearchResponse = {
        'results': [
          {
            'id': 'search_vid_1',
            'title': 'Search Result 1',
            'author': 'Artist Result',
            'duration': 210,
            'thumbnailUrl': 'https://img.youtube.com/vi/search_vid_1/0.jpg',
          }
        ]
      };

      when(() => mockClient.get(
            Uri.parse('https://test-xdm-backend.app/api/search?q=Adele'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => http.Response(
            jsonEncode(sampleSearchResponse),
            200,
          ));

      final results = await service.search('Adele');

      expect(results.length, 1);
      expect(results[0].videoId, 'search_vid_1');
      expect(results[0].title, 'Search Result 1');
      expect(results[0].artist, 'Artist Result');
      expect(results[0].duration.inSeconds, 210);
    });

    test('returns null / empty when backend is disabled in preferences', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.ytdlpBackendEnabled: false,
      });

      final streamResult = await service.resolveStream('dQw4w9WgXcQ');
      final searchResult = await service.search('Adele');
      final playlistResult = await service.getPlaylist('https://www.youtube.com/playlist?list=PL123');

      expect(streamResult, isNull);
      expect(searchResult, isEmpty);
      expect(playlistResult, isEmpty);
    });
  });
}
