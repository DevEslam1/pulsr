// test/core/services/radio_browser_service_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/core/services/radio_browser_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RadioBrowserService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('maps valid stations, rejects unsafe URLs and dedupes', () async {
      final requested = <Uri>[];
      final client = MockClient((request) async {
        requested.add(request.url);
        return http.Response(
          jsonEncode([
            {
              'name': 'Jazz FM',
              'url_resolved': 'https://stream.example/jazz',
              'favicon': 'https://art.example/jazz.png',
              'tags': 'jazz, smooth',
              'bitrate': 320,
              'codec': 'MP3',
              'stationuuid': 'uuid-1234',
            },
            {
              'name': 'Radio with Private Favicon',
              'url_resolved': 'https://stream.example/safe',
              'favicon': 'http://192.168.1.1/art.png',
            },
            {
              'name': 'Private',
              'url_resolved': 'http://192.168.1.5/stream',
            },
            {
              'name': 'Duplicate',
              'url_resolved': 'https://stream.example/jazz',
            },
            {
              'name': 'Missing URL',
              'url_resolved': '',
            },
          ]),
          200,
        );
      });

      final stations = await RadioBrowserService(client: client).search(
        query: 'jazz',
        country: 'us',
        tag: 'smooth',
      );

      expect(stations, hasLength(2));
      expect(stations[0].name, 'Jazz FM');
      expect(stations[0].url, 'https://stream.example/jazz');
      expect(stations[0].genre, 'jazz');
      expect(stations[0].artworkUrl, 'https://art.example/jazz.png');
      expect(stations[0].bitrate, 320);
      expect(stations[0].codec, 'MP3');
      expect(stations[0].stationUuid, 'uuid-1234');
      expect(stations[0].qualityLabel, '320 kbps MP3');

      expect(stations[1].name, 'Radio with Private Favicon');
      expect(stations[1].artworkUrl, isNull);

      final params = requested.single.queryParameters;
      expect(params['name'], 'jazz');
      expect(params['countrycode'], 'US');
      expect(params['tag'], 'smooth');
      expect(params['hidebroken'], 'true');
      expect(params['order'], 'clickcount');
      expect(params['reverse'], 'true');
    });

    test('rejects a non-200 response', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      expect(
        () => RadioBrowserService(client: client).search(query: 'x'),
        throwsA(isA<RadioBrowserException>()),
      );
    });

    test('rejects a non-list payload', () async {
      final client = MockClient(
          (_) async => http.Response(jsonEncode({'error': 'x'}), 200));
      expect(
        () => RadioBrowserService(client: client).search(),
        throwsA(isA<RadioBrowserException>()),
      );
    });

    test('caps the requested limit', () async {
      Uri? requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response('[]', 200);
      });
      await RadioBrowserService(client: client).search(limit: 500);
      expect(requested!.queryParameters['limit'], '40');
    });

    group('isReachable', () {
      test('accepts a 200/206 stream response', () async {
        final client = MockClient((request) async {
          expect(request.headers['Range'], 'bytes=0-0');
          expect(request.headers['Icy-MetaData'], '1');
          return http.Response('', 206);
        });

        expect(
          await RadioBrowserService(client: client)
              .isReachable('https://stream.example/live'),
          isTrue,
        );
      });

      test('rejects an HTTP error page', () async {
        final client = MockClient((_) async => http.Response('gone', 404));
        expect(
          await RadioBrowserService(client: client)
              .isReachable('https://stream.example/dead'),
          isFalse,
        );
      });

      test('rejects private or non-http URLs without a request', () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return http.Response('', 200);
        });
        final service = RadioBrowserService(client: client);

        expect(await service.isReachable('http://127.0.0.1/live'), isFalse);
        expect(await service.isReachable('file:///etc/passwd'), isFalse);
        expect(calls, 0);
      });

      test('returns false when the transport throws', () async {
        final client = MockClient((_) async => throw StateError('offline'));
        expect(
          await RadioBrowserService(client: client)
              .isReachable('https://stream.example/live'),
          isFalse,
        );
      });

      test('falls back to non-range probe if 416 Range Not Satisfiable', () async {
        var attempts = 0;
        final client = MockClient((request) async {
          attempts++;
          if (request.headers.containsKey('Range')) {
            return http.Response('range not supported', 416);
          }
          return http.Response('', 200);
        });

        final service = RadioBrowserService(client: client);
        expect(await service.isReachable('https://stream.example/hls'), isTrue);
        expect(attempts, 2);
      });

      test('rejects host resolving to private IP via DNS rebinding', () async {
        var networkCalls = 0;
        final client = MockClient((_) async {
          networkCalls++;
          return http.Response('', 200);
        });

        final service = RadioBrowserService(
          client: client,
          hostLookup: (host) async => ['192.168.1.100'],
        );

        expect(
          await service.isReachable('https://malicious-rebinding.com/live'),
          isFalse,
        );
        expect(networkCalls, 0);
      });

      test('rejects 302 redirect pointing to private IP', () async {
        final client = MockClient((request) async {
          if (request.url.toString() == 'https://stream.example/redirect') {
            return http.Response('', 302, headers: {
              'location': 'http://192.168.1.1/secret.mp3',
            });
          }
          return http.Response('', 200);
        });

        final service = RadioBrowserService(client: client);
        expect(await service.isReachable('https://stream.example/redirect'), isFalse);
      });

      test('follows 302 redirect pointing to safe public stream', () async {
        final client = MockClient((request) async {
          if (request.url.toString() == 'https://stream.example/redirect') {
            return http.Response('', 302, headers: {
              'location': 'https://stream.example/target.mp3',
            });
          }
          if (request.url.toString() == 'https://stream.example/target.mp3') {
            return http.Response('', 200);
          }
          return http.Response('', 404);
        });

        final service = RadioBrowserService(client: client);
        expect(await service.isReachable('https://stream.example/redirect'), isTrue);
      });

      test('rejects 302 without location header', () async {
        final client = MockClient((request) async {
          return http.Response('', 302);
        });

        final service = RadioBrowserService(client: client);
        expect(await service.isReachable('https://stream.example/live'), isFalse);
      });

      test('uses AppConfig.appVersion in User-Agent header', () async {
        String? capturedUserAgent;
        final client = MockClient((request) async {
          capturedUserAgent = request.headers['User-Agent'];
          return http.Response('', 200);
        });

        final service = RadioBrowserService(client: client);
        await service.isReachable('https://stream.example/live');
        expect(capturedUserAgent, contains('Pulsr/'));
        expect(capturedUserAgent, contains('(radio directory)'));
      });

      test('dispose closes owned client without throwing', () {
        final service = RadioBrowserService();
        expect(() => service.dispose(), returnsNormally);
      });
    });

    group('Mirror failover and voting', () {
      test('fails over to secondary mirror when primary returns 503', () async {
        final requested = <Uri>[];
        final client = MockClient((request) async {
          requested.add(request.url);
          if (request.url.host == 'de1.api.radio-browser.info') {
            return http.Response('server error', 503);
          }
          return http.Response('[]', 200);
        });

        final service = RadioBrowserService(client: client);
        final results = await service.search(query: 'test');
        expect(results, isEmpty);
        expect(requested.length, 2);
        expect(requested[0].host, 'de1.api.radio-browser.info');
        expect(requested[1].host, 'nl1.api.radio-browser.info');
      });

      test('voteForStation issues vote request and parses confirmation', () async {
        Uri? requested;
        final client = MockClient((request) async {
          requested = request.url;
          return http.Response(jsonEncode({'ok': true, 'message': 'voted'}), 200);
        });

        const validUuid = '960e57c0-0601-11e8-ae97-52543be04c81';
        final service = RadioBrowserService(client: client);
        final ok = await service.voteForStation(validUuid);
        expect(ok, isTrue);
        expect(requested!.path, '/json/vote/$validUuid');
      });

      test('voteForStation returns false on non-200 or failure', () async {
        final client = MockClient((_) async => http.Response('not found', 404));
        final service = RadioBrowserService(client: client);
        expect(
          await service.voteForStation('00000000-0000-0000-0000-000000000000'),
          isFalse,
        );
        expect(await service.voteForStation(''), isFalse);
      });

      test('voteForStation rejects invalid stationUuid without HTTP calls',
          () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return http.Response(jsonEncode({'ok': true}), 200);
        });
        final service = RadioBrowserService(client: client);

        for (final bad in [
          '../admin',
          'uuid-999',
          'abc123', // shorter than 8 chars
          'a' * 65, // longer than 64 chars
          '960e57c0 0601-11e8',
        ]) {
          expect(await service.voteForStation(bad), isFalse, reason: bad);
        }
        expect(calls, 0);
      });
    });
  });
}
