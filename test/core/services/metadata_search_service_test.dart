import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/core/services/metadata_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MetadataSearchService Tests', () {
    test(
        'searchMetadata parses iTunes response and upgrades artwork resolution',
        () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'itunes.apple.com') {
          final payload = {
            'resultCount': 1,
            'results': [
              {
                'trackName': 'Comfortably Numb',
                'artistName': 'Pink Floyd',
                'collectionName': 'The Wall',
                'primaryGenreName': 'Progressive Rock',
                'releaseDate': '1979-11-30T08:00:00Z',
                'trackNumber': 19,
                'artworkUrl100':
                    'https://is1-ssl.mzstatic.com/image/thumb/100x100bb.jpg',
              }
            ]
          };
          return http.Response(jsonEncode(payload), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = MetadataSearchService(mockClient);
      final results = await service.searchMetadata(
          title: 'Comfortably Numb', artist: 'Pink Floyd');

      expect(results.length, equals(1));
      final track = results.first;
      expect(track.title, equals('Comfortably Numb'));
      expect(track.artist, equals('Pink Floyd'));
      expect(track.album, equals('The Wall'));
      expect(track.genre, equals('Progressive Rock'));
      expect(track.releaseYear, equals('1979'));
      expect(track.trackNumber, equals('19'));
      expect(track.artworkUrl, contains('1400x1400'));
    });

    test('searchMetadata handles network error gracefully', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Network unreachable');
      });

      final service = MetadataSearchService(mockClient);
      final results = await service.searchMetadata(title: 'Unknown Title');

      expect(results, isEmpty);
    });

    test('searchMetadata escapes Lucene special characters in MusicBrainz query',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      String? capturedQuery;

      final mockClient = MockClient((request) async {
        if (request.url.host == 'itunes.apple.com') {
          return http.Response(jsonEncode({'resultCount': 0, 'results': []}), 200);
        }
        if (request.url.host == 'musicbrainz.org') {
          capturedQuery = request.url.queryParameters['query'];
          return http.Response(jsonEncode({'recordings': []}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = MetadataSearchService(mockClient);
      await service.searchMetadata(
        title: r'A+B-C && D||E !F (G) {H} [I]^"J"~*?:\/K',
        artist: r'AC/DC & Friends "Live"',
      );

      expect(capturedQuery, isNotNull);
      expect(
        capturedQuery,
        contains(
          r'recording:"A\+B\-C \&\& D\|\|E \!F \(G\) \{H\} \[I\]\^\"J\"\~\*\?\:\\\/K"',
        ),
      );
      expect(
        capturedQuery,
        contains(r'artist:"AC\/DC \& Friends \"Live\""'),
      );
    });

    test(
        'downloadArtworkToTemp rejects payloads > 10 MB via contentLength and streamed bytes',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final tempDir = Directory.systemTemp.createTempSync('ms_art_cap');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      const pathProviderChannel =
          MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
      });

      var streamChunksYielded = 0;
      final oversizedHeaderClient = _StreamedMockClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([Uint8List(1024)]),
          200,
          contentLength: 10 * 1024 * 1024 + 1,
        );
      });

      final headerService = MetadataSearchService(oversizedHeaderClient);
      final headerResult = await headerService
          .downloadArtworkToTemp('https://example.com/big_header.jpg');
      expect(headerResult, isNull);

      final oversizedStreamClient = _StreamedMockClient((request) async {
        Stream<List<int>> gen() async* {
          final chunk = Uint8List(1024 * 1024);
          for (var i = 0; i < 12; i++) {
            streamChunksYielded++;
            yield chunk;
          }
        }

        return http.StreamedResponse(gen(), 200, contentLength: null);
      });

      final streamService = MetadataSearchService(oversizedStreamClient);
      final streamResult = await streamService
          .downloadArtworkToTemp('https://example.com/big_stream.jpg');
      expect(streamResult, isNull);
      expect(streamChunksYielded, lessThanOrEqualTo(11));
      expect(tempDir.listSync(), isEmpty);
    });

    test('searchMetadata uses AppConfig.appVersion in MusicBrainz User-Agent',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      String? capturedUserAgent;

      final mockClient = MockClient((request) async {
        if (request.url.host == 'itunes.apple.com') {
          return http.Response(jsonEncode({'resultCount': 0, 'results': []}), 200);
        }
        if (request.url.host == 'musicbrainz.org') {
          capturedUserAgent = request.headers['User-Agent'];
          return http.Response(jsonEncode({'recordings': []}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = MetadataSearchService(mockClient);
      await service.searchMetadata(title: 'Test Title');

      expect(capturedUserAgent, contains('Pulsr/'));
      expect(capturedUserAgent, contains('( https://pulsr.music )'));
    });

    test('downloadArtworkToTemp rejects redirects pointing to private host',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});

      final redirectClient = _StreamedMockClient((request) async {
        if (request.url.toString() == 'https://example.com/art.jpg') {
          return http.StreamedResponse(
            const Stream.empty(),
            302,
            headers: {'location': 'http://127.0.0.1/private.jpg'},
          );
        }
        return http.StreamedResponse(
          Stream.fromIterable([Uint8List(100)]),
          200,
        );
      });

      final service = MetadataSearchService(redirectClient);
      final result =
          await service.downloadArtworkToTemp('https://example.com/art.jpg');
      expect(result, isNull);
    });

    test('downloadArtworkToTemp follows safe redirect up to 3 hops',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final tempDir = Directory.systemTemp.createTempSync('ms_art_redir');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      const pathProviderChannel =
          MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
      });

      final redirectClient = _StreamedMockClient((request) async {
        if (request.url.toString() == 'https://example.com/art.jpg') {
          return http.StreamedResponse(
            const Stream.empty(),
            302,
            headers: {'location': 'https://example.com/final.jpg'},
          );
        }
        if (request.url.toString() == 'https://example.com/final.jpg') {
          return http.StreamedResponse(
            Stream.fromIterable([Uint8List(100)]),
            200,
          );
        }
        return http.StreamedResponse(const Stream.empty(), 404);
      });

      final service = MetadataSearchService(redirectClient);
      final result =
          await service.downloadArtworkToTemp('https://example.com/art.jpg');
      expect(result, isNotNull);
      expect(File(result!).existsSync(), isTrue);
    });

    test('dispose does not close an injected http.Client', () {
      final client = _StreamedMockClient(
        (_) async => http.StreamedResponse(const Stream.empty(), 200),
      );
      MetadataSearchService(client).dispose();
      expect(client.closed, isFalse);
    });
  });
}

class _StreamedMockClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) _handler;
  bool closed = false;

  _StreamedMockClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);

  @override
  void close() {
    closed = true;
  }
}
