// test/core/services/xdm_backend_service_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/services/xdm_backend_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';
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
    YtmRateLimiter.debugReset();
  });

  group('XdmBackendService', () {
    test('checkHealth returns ok when backend responds with 200', () async {
      when(() => mockClient.get(
            Uri.parse('https://test-xdm-backend.app/health?strict=true'),
          )).thenAnswer((_) async => http.Response(
            jsonEncode({
              'status': 'ok',
              'backend_version': '2.0.0',
              'ytdlp_version': '2026.07.04',
              'proxy_pool_size': 10,
            }),
            200,
          ));

      final health = await service.checkHealth(force: true);
      expect(health.ok, isTrue);
      expect(health.backendVersion, '2.0.0');
      expect(health.ytdlpVersion, '2026.07.04');
      expect(health.proxyPoolSize, 10);
      expect(health.circuitState, BackendCircuitState.closed);
    });

    test('resolveStream calls /resolve/audio and parses audio ladder', () async {
      final sampleAudioLadderResponse = {
        'videoId': 'dQw4w9WgXcQ',
        'title': 'Test Song Title',
        'author': 'Test Artist',
        'audio': [
          {
            'src': 'https://cdn.youtube.com/audio_webm_160',
            'ext': 'webm',
            'codec': 'opus',
            'abr': 160,
            'filesize': 5000000,
            'expiresAt': 1800000000000,
          },
          {
            'src': 'https://cdn.youtube.com/audio_m4a_128',
            'ext': 'm4a',
            'codec': 'mp4a.40.2',
            'abr': 128,
            'filesize': 4000000,
            'expiresAt': 1800000000000,
          },
          {
            'src': 'https://cdn.youtube.com/audio_m4a_48',
            'ext': 'm4a',
            'codec': 'mp4a.40.2',
            'abr': 48,
            'filesize': 1500000,
            'expiresAt': 1800000000000,
          }
        ]
      };

      when(() => mockClient.get(
            Uri.parse('https://test-xdm-backend.app/resolve/audio?videoId=dQw4w9WgXcQ'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => http.Response(
            jsonEncode(sampleAudioLadderResponse),
            200,
          ));

      // High Quality -> selects 128kbps AAC over Opus
      final highResult = await service.resolveStream('dQw4w9WgXcQ', quality: 'high');
      expect(highResult, isNotNull);
      expect(highResult!.url, 'https://cdn.youtube.com/audio_m4a_128');
      expect(highResult.container, 'm4a');
      expect(highResult.bitrateKbps, 128);
      expect(highResult.expiresAt, 1800000000000);

      // Low Quality -> selects 48kbps AAC
      final lowResult = await service.resolveStream('dQw4w9WgXcQ', quality: 'low');
      expect(lowResult, isNotNull);
      expect(lowResult!.url, 'https://cdn.youtube.com/audio_m4a_48');
      expect(lowResult.container, 'm4a');
      expect(lowResult.bitrateKbps, 48);
    });

    test('Circuit breaker trips to open after 3 consecutive infra failures', () async {
      when(() => mockClient.get(
            any(),
            headers: any(named: 'headers'),
          )).thenThrow(const SocketException('Connection refused'));

      expect(service.isCircuitOpen, isFalse);
      expect(service.circuitState, BackendCircuitState.closed);

      await service.resolveStream('vid1');
      expect(service.consecutiveInfraFailures, 1);
      expect(service.isCircuitOpen, isFalse);

      await service.resolveStream('vid2');
      expect(service.consecutiveInfraFailures, 2);
      expect(service.isCircuitOpen, isFalse);

      await service.resolveStream('vid3');
      expect(service.consecutiveInfraFailures, 3);
      expect(service.isCircuitOpen, isTrue);
      expect(service.circuitState, BackendCircuitState.open);
      expect(await service.isEnabled(), isFalse);
    });

    test('429 rate limit maps error code and honors Retry-After header', () async {
      when(() => mockClient.get(
            any(),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => http.Response(
            jsonEncode({'error_code': 'RATE_LIMITED', 'message': 'Too many requests'}),
            429,
            headers: {'retry-after': '45'},
          ));

      await expectLater(
        service.resolveStream('rate_limited_vid'),
        throwsA(isA<YtmException>().having((e) => e.code, 'code', 'RATE_LIMITED')),
      );

      expect(YtmRateLimiter.shared.isBackendCoolingDown, isTrue);
      expect(YtmRateLimiter.shared.backendCooldownRemaining.inSeconds, greaterThanOrEqualTo(40));
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
            Uri.parse(
                'https://test-xdm-backend.app/api/playlist?url=https%3A%2F%2Fwww.youtube.com%2Fplaylist%3Flist%3DPL123'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => http.Response(
            jsonEncode(samplePlaylistResponse),
            200,
          ));

      final tracks = await service
          .getPlaylist('https://www.youtube.com/playlist?list=PL123');

      expect(tracks.length, 2);
      expect(tracks[0].videoId, 'video_1');
      expect(tracks[0].title, 'Song One');
      expect(tracks[0].artist, 'Artist A');
      expect(tracks[0].duration.inSeconds, 180);
    });
  });
}
