// test/core/services/radio_browser_service_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/core/services/radio_browser_service.dart';

void main() {
  group('RadioBrowserService', () {
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

      expect(stations, hasLength(1));
      expect(stations.single.name, 'Jazz FM');
      expect(stations.single.url, 'https://stream.example/jazz');
      expect(stations.single.genre, 'jazz');
      expect(stations.single.artworkUrl, 'https://art.example/jazz.png');

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
    });
  });
}
