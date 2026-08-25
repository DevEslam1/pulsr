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

      final result = await service.fetchLyrics(trackName: 'Test', artistName: 'Artist');

      expect(result, isNotNull);
      expect(result!.source, equals(LyricsSource.lrclib));
      expect(result.lines.length, equals(2));
      expect(result.lines.first.text, equals('Hello World'));
      expect(result.lines.first.timestamp, equals(const Duration(seconds: 12, milliseconds: 340)));
    });

    test('Returns null gracefully on network failure or 404', () async {
      when(() => mockResponse.statusCode).thenReturn(404);
      when(() => mockResponse.transform<String>(any())).thenAnswer(
        (_) => Stream.value('{"message":"Not found"}'),
      );

      final result = await service.fetchLyrics(trackName: 'NonExistent', artistName: 'Nobody');
      expect(result, isNull);
    });
  });
}
