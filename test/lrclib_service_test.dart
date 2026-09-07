import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/lrclib_service.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';

class MockHttpClient extends Mock implements HttpClient {}

class MockHttpClientRequest extends Mock implements HttpClientRequest {}

class MockHttpClientResponse extends Mock implements HttpClientResponse {}

class MockHttpHeaders extends Mock implements HttpHeaders {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://lrclib.net/api/get'));
    registerFallbackValue(utf8.decoder);
  });

  group('LrclibService Tests', () {
    late MockHttpClient mockClient;
    late MockHttpClientRequest mockRequest;
    late MockHttpClientResponse mockResponse;
    late MockHttpHeaders mockHeaders;
    late LrclibService service;

    setUp(() {
      mockClient = MockHttpClient();
      mockRequest = MockHttpClientRequest();
      mockResponse = MockHttpClientResponse();
      mockHeaders = MockHttpHeaders();

      when(() => mockRequest.headers).thenReturn(mockHeaders);
      when(() => mockClient.getUrl(any())).thenAnswer((_) async => mockRequest);
      when(() => mockRequest.close()).thenAnswer((_) async => mockResponse);

      service = LrclibService(client: mockClient);
    });

    test('Parses synced lyrics from valid LRCLIB response', () async {
      final jsonResponse = jsonEncode({
        'syncedLyrics': '[00:12.34] Hello World\n[00:15.67] Test Line',
        'plainLyrics': 'Hello World\nTest Line',
      });

      when(() => mockResponse.statusCode).thenReturn(200);
      when(() => mockResponse.transform<String>(any())).thenAnswer(
        (_) => Stream.value(jsonResponse),
      );

      final result =
          await service.fetchLyrics(trackName: 'Test', artistName: 'Artist');

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.lrclib));
      expect(result.lines.length, equals(2));
      expect(result.lines.first.text, equals('Hello World'));
      expect(result.lines.first.timestamp,
          equals(const Duration(seconds: 12, milliseconds: 340)));
    });

    test('Returns null gracefully on network failure or 404', () async {
      when(() => mockResponse.statusCode).thenReturn(404);
      when(() => mockResponse.transform<String>(any())).thenAnswer(
        (_) => Stream.value('{"message":"Not found"}'),
      );

      final result = await service.fetchLyrics(
          trackName: 'NonExistent', artistName: 'Nobody');
      expect(result, isNull);
    });

    group('wrong-track relevance filtering', () {
      late MockHttpClientRequest searchRequest;
      late MockHttpClientResponse searchResponse;
      late MockHttpHeaders searchHeaders;

      setUp(() {
        searchRequest = MockHttpClientRequest();
        searchResponse = MockHttpClientResponse();
        searchHeaders = MockHttpHeaders();
        when(() => searchRequest.headers).thenReturn(searchHeaders);
        when(() => searchRequest.close()).thenAnswer((_) async => searchResponse);
      });

      void routeByEndpoint({
        required Object? getBody,
        required int getStatusCode,
        required Object? searchBody,
        required int searchStatusCode,
      }) {
        when(() => mockClient.getUrl(any())).thenAnswer((inv) async {
          final uri = inv.positionalArguments[0] as Uri;
          if (uri.path.contains('/api/search')) {
            when(() => searchResponse.statusCode).thenReturn(searchStatusCode);
            when(() => searchResponse.transform<String>(any()))
                .thenAnswer((_) => Stream.value(searchBody.toString()));
            return searchRequest;
          }
          when(() => mockResponse.statusCode).thenReturn(getStatusCode);
          when(() => mockResponse.transform<String>(any()))
              .thenAnswer((_) => Stream.value(getBody.toString()));
          return mockRequest;
        });
      }

      Map<String, dynamic> lrclibItem({
        required String artist,
        required String track,
        int? duration,
        String? synced,
        String? plain,
      }) =>
          {
            'artistName': artist,
            'trackName': track,
            if (duration != null) 'duration': duration,
            'syncedLyrics': synced ?? '[00:10.00] Wrong song line',
            'plainLyrics': plain ?? 'Wrong song line',
          };

      test(
        'search result of a DIFFERENT song (no artist/duration match) is rejected',
        () async {
          routeByEndpoint(
            getStatusCode: 404,
            getBody: 'not found',
            searchStatusCode: 200,
            searchBody: jsonEncode([
              lrclibItem(
                  artist: 'Someone Else',
                  track: 'Adrenaline',
                  duration: 271,
                  synced: '[00:10.00] Other song lyrics'),
            ]),
          );

          final result = await service.fetchLyrics(
            trackName: 'Adrenaline',
            artistName: 'Mohamed Hamaki',
            durationSeconds: 200,
          );

          expect(result, isNull,
              reason: 'lyrics of a different song must not be shown');
        },
      );

      test(
        'search picks the matching-artist result among same-title noise',
        () async {
          routeByEndpoint(
            getStatusCode: 404,
            getBody: 'not found',
            searchStatusCode: 200,
            searchBody: jsonEncode([
              lrclibItem(
                  artist: 'Someone Else',
                  track: 'Adrenaline',
                  duration: 271,
                  synced: '[00:10.00] Other song lyrics'),
              lrclibItem(
                  artist: 'Hamaki',
                  track: 'Adrenaline',
                  duration: 202,
                  synced: '[00:10.00] Correct song lyrics'),
            ]),
          );

          final result = await service.fetchLyrics(
            trackName: 'Adrenaline',
            artistName: 'Mohamed Hamaki',
            durationSeconds: 200,
          );

          expect(result, isNotNull);
          expect(result!.lines.first.text, equals('Correct song lyrics'));
        },
      );

      test('duration match alone anchors a result with differing artist',
          () async {
        routeByEndpoint(
          getStatusCode: 404,
          getBody: 'not found',
          searchStatusCode: 200,
          searchBody: jsonEncode([
            lrclibItem(
                artist: 'feat. listing differs',
                track: 'Adrenaline',
                duration: 203,
                synced: '[00:10.00] Correct song lyrics'),
          ]),
        );

        final result = await service.fetchLyrics(
          trackName: 'Adrenaline',
          artistName: 'Mohamed Hamaki',
          durationSeconds: 200,
        );

        expect(result, isNotNull);
        expect(result!.lines.first.text, equals('Correct song lyrics'));
      });

      test('get result for a different song is rejected (swapped candidate)',
          () async {
        routeByEndpoint(
          getStatusCode: 200,
          getBody: jsonEncode(lrclibItem(
              artist: 'Adrenaline',
              track: 'Hamaki',
              duration: 271,
              synced: '[00:10.00] Other song lyrics')),
          searchStatusCode: 404,
          searchBody: 'not found',
        );

        final result = await service.fetchLyrics(
          trackName: 'Adrenaline',
          artistName: 'Mohamed Hamaki',
          durationSeconds: 200,
        );

        expect(result, isNull);
      });
    });
  });
}
