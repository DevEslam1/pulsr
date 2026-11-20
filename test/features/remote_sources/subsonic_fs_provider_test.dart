// P1-8: the Subsonic provider layers a browsable tree over the JSON API.
//
// These tests pin the tree shape (ids are encoded into one path segment), the
// metadata `stat` needs for range requests, and the streaming contract: a
// ranged GET is sent and a server that ignores it is handled locally.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pulsr/domain/interfaces/remote_fs_provider.dart';
import 'package:pulsr/domain/models/remote_source.dart';
import 'package:pulsr/features/remote_sources/subsonic_fs_provider.dart';

/// Fake transport: records requests and answers through [handler].
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.handler);

  final Future<http.StreamedResponse> Function(http.Request request) handler;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    expect(request, isA<http.Request>());
    final typed = request as http.Request;
    requests.add(typed);
    return handler(typed);
  }
}

http.StreamedResponse _json(Map<String, dynamic> payload, {int status = 200}) {
  final body = <String, dynamic>{
    'subsonic-response': <String, dynamic>{
      'status': 'ok',
      'version': '1.16.1',
      ...payload,
    },
  };
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    status,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

http.StreamedResponse _bytes(List<int> bytes, {int status = 200}) =>
    http.StreamedResponse(Stream<List<int>>.value(bytes), status);

const String _songPath = 'album/al%201/song/so%2B2';

RemoteSource _source() => RemoteSource(
      id: 'subsonic-1',
      kind: RemoteSourceKind.subsonic,
      displayName: 'Navidrome',
      host: 'music.example.com',
      port: 443,
      useTls: true,
      rootPath: '/',
      username: 'eslam',
      createdAt: DateTime.utc(2026),
    );

SubsonicFsProvider _provider(_FakeHttpClient client) => SubsonicFsProvider(
      _source(),
      username: 'eslam',
      password: 'secret',
      client: client,
      saltGenerator: () => 'salt',
    );

/// Answers the four API calls of the fixture library.
_FakeHttpClient _library({
  http.StreamedResponse Function(http.Request request)? stream,
}) {
  return _FakeHttpClient((request) async {
    switch (request.url.path) {
      case '/rest/ping.view':
        return _json(const <String, dynamic>{});
      case '/rest/getArtists.view':
        return _json(<String, dynamic>{
          'artists': <String, dynamic>{
            'index': <dynamic>[
              <String, dynamic>{
                'artist': <dynamic>[
                  <String, dynamic>{
                    'id': 'ar/1',
                    'name': 'Björk',
                    'albumCount': 1,
                  },
                ],
              },
            ],
          },
        });
      case '/rest/getArtist.view':
        expect(request.url.queryParameters['id'], 'ar/1');
        return _json(<String, dynamic>{
          'artist': <String, dynamic>{
            'id': 'ar/1',
            'name': 'Björk',
            'album': <dynamic>[
              <String, dynamic>{
                'id': 'al 1',
                'name': 'Homogenic',
                'songCount': 1,
              },
            ],
          },
        });
      case '/rest/getAlbum.view':
        expect(request.url.queryParameters['id'], 'al 1');
        return _json(<String, dynamic>{
          'album': <String, dynamic>{
            'id': 'al 1',
            'name': 'Homogenic',
            'song': <dynamic>[
              <String, dynamic>{
                'id': 'so+2',
                'title': 'Jóga',
                'size': 1234,
                'suffix': 'flac',
                'duration': 302,
              },
            ],
          },
        });
      case '/rest/stream.view':
        expect(request.url.queryParameters['id'], 'so+2');
        final handler = stream;
        if (handler == null) fail('the test did not expect a stream request');
        return handler(request);
      default:
        fail('unexpected request ${request.url}');
    }
  });
}

void main() {
  group('path mapping', () {
    test('ids with /, spaces and + stay inside one segment', () {
      expect(SubsonicFsProvider.artistPath('ar/1'), 'artist/ar%2F1');
      expect(SubsonicFsProvider.albumPath('al 1'), 'album/al%201');
      expect(
        SubsonicFsProvider.songPath('al 1', 'so+2'),
        'album/al%201/song/so%2B2',
      );
    });

    test('root lists artists as folders', () async {
      final provider = _provider(_library());
      final entries = await provider.list('');

      expect(entries, hasLength(1));
      expect(entries.single.path, 'artist/ar%2F1');
      expect(entries.single.name, 'Björk');
      expect(entries.single.isDirectory, isTrue);
    });

    test('an artist lists its albums; the encoded id is decoded for the API',
        () async {
      final provider = _provider(_library());
      final entries = await provider.list('artist/ar%2F1');

      expect(entries.single.path, 'album/al%201');
      expect(entries.single.name, 'Homogenic');
      expect(entries.single.isDirectory, isTrue);
    });

    test('an album lists its songs with size and a stable song path', () async {
      final provider = _provider(_library());
      final entries = await provider.list('album/al%201');

      expect(entries.single.path, _songPath);
      expect(entries.single.name, 'Jóga');
      expect(entries.single.isDirectory, isFalse);
      expect(entries.single.sizeBytes, 1234);
    });

    test('unknown folders are a typed protocol failure', () async {
      final provider = _provider(_library());

      await expectLater(
        provider.list('playlist/7'),
        throwsA(isA<RemoteProtocolError>()),
      );
      await expectLater(
        provider.list(_songPath),
        throwsA(isA<RemoteProtocolError>()),
      );
    });
  });

  group('stat', () {
    test('the root is a synthetic folder named after the source', () async {
      final provider = _provider(_library());
      final entry = await provider.stat('');

      expect(entry?.path, '');
      expect(entry?.name, 'Navidrome');
      expect(entry?.isDirectory, isTrue);
    });

    test('a song path reports the size range requests need', () async {
      final provider = _provider(_library());
      final entry = await provider.stat(_songPath);

      expect(entry?.isDirectory, isFalse);
      expect(entry?.name, 'Jóga');
      expect(entry?.sizeBytes, 1234);
    });

    test('a song that left the album is a miss, not an error', () async {
      final provider = _provider(_library());
      final entry = await provider.stat('album/al%201/song/so%2B9');

      expect(entry, isNull);
    });
  });

  group('openRead', () {
    final bytes = utf8.encode('0123456789');

    test('sends a Range header and returns exactly that window', () async {
      final client = _library(
        stream: (request) {
          expect(
            request.headers['range'] ?? request.headers['Range'],
            'bytes=2-5',
          );
          return http.StreamedResponse(
            Stream<List<int>>.value(bytes.sublist(2, 6)),
            206,
          );
        },
      );
      final provider = _provider(client);

      final received = await provider
          .openRead(_songPath, start: 2, end: 5)
          .expand((chunk) => chunk)
          .toList();

      expect(received, bytes.sublist(2, 6));
    });

    test('skips locally when the server ignores Range', () async {
      final client = _library(
        stream: (request) {
          expect(
            request.headers['range'] ?? request.headers['Range'],
            'bytes=2-5',
          );
          return _bytes(bytes);
        },
      );
      final provider = _provider(client);

      final received = await provider
          .openRead(_songPath, start: 2, end: 5)
          .expand((chunk) => chunk)
          .toList();

      expect(received, bytes.sublist(2, 6));
    });

    test('a full read sends no Range header', () async {
      final client = _library(
        stream: (request) {
          expect(request.headers.containsKey('range'), isFalse);
          expect(request.headers.containsKey('Range'), isFalse);
          return _bytes(bytes);
        },
      );
      final provider = _provider(client);

      final received =
          await provider.openRead(_songPath).expand((chunk) => chunk).toList();

      expect(received, bytes);
    });

    test('maps HTTP failures to the typed remote errors', () async {
      Future<void> expectFailure(int status, Matcher matcher) async {
        final provider = _provider(
          _library(
            stream: (_) => http.StreamedResponse(
              Stream<List<int>>.value(const <int>[]),
              status,
            ),
          ),
        );
        await expectLater(provider.openRead(_songPath).toList(), matcher);
      }

      await expectFailure(401, throwsA(isA<RemoteAuthError>()));
      await expectFailure(404, throwsA(isA<RemoteNotFoundError>()));
      await expectFailure(416, throwsA(isA<RemoteProtocolError>()));
      await expectFailure(500, throwsA(isA<RemoteUnavailableError>()));
    });

    test('a non-song path cannot be streamed', () async {
      final provider = _provider(_library());

      await expectLater(
        provider.openRead('album/al%201').toList(),
        throwsA(isA<RemoteProtocolError>()),
      );
    });
  });

  group('testConnection', () {
    test('falls back to the source login when the store has no username',
        () async {
      final client = _library();
      final provider = SubsonicFsProvider(
        _source(),
        username: '   ',
        password: 'secret',
        client: client,
        saltGenerator: () => 'salt',
      );

      expect(await provider.testConnection(), isTrue);
      expect(client.requests.single.url.queryParameters['u'], 'eslam');
    });

    test('pings and returns true', () async {
      final client = _library();
      final provider = _provider(client);

      expect(await provider.testConnection(), isTrue);
      expect(client.requests.single.url.path, '/rest/ping.view');
    });

    test('returns false instead of throwing when credentials are rejected',
        () async {
      final provider = _provider(
        _FakeHttpClient(
          (_) async => http.StreamedResponse(
            Stream<List<int>>.value(const <int>[]),
            401,
          ),
        ),
      );

      expect(await provider.testConnection(), isFalse);
    });
  });

  group('search and coverArt', () {
    test('search returns matching artists, albums and tracks', () async {
      final fake = _FakeHttpClient((request) async {
        expect(request.url.path, '/rest/search3.view');
        expect(request.url.queryParameters['query'], 'homogenic');
        return _json(<String, dynamic>{
          'searchResult3': <String, dynamic>{
            'album': <dynamic>[
              <String, dynamic>{
                'id': 'al-homogenic',
                'name': 'Homogenic',
                'artist': 'Björk',
                'coverArt': 'cov-homo',
              }
            ],
            'song': <dynamic>[
              <String, dynamic>{
                'id': 's-joga',
                'title': 'Jóga',
                'artist': 'Björk',
                'album': 'Homogenic',
                'coverArt': 'cov-homo',
              }
            ],
          }
        });
      });
      final provider = _provider(fake);

      final result = await provider.search('homogenic');
      expect(result.albums, hasLength(1));
      expect(result.albums.first.name, 'Homogenic');
      expect(result.songs, hasLength(1));
      expect(result.songs.first.title, 'Jóga');
    });

    test('getCoverArtUrl builds signed URI with auth parameters', () {
      final provider = _provider(_library());
      final uri = provider.getCoverArtUrl('cov-homo', size: 400);

      expect(uri, isNotNull);
      expect(uri!.path, '/rest/getCoverArt.view');
      expect(uri.queryParameters['id'], 'cov-homo');
      expect(uri.queryParameters['size'], '400');
      expect(uri.queryParameters['u'], 'eslam');
      expect(uri.queryParameters['s'], 'salt');
    });

    test('getCoverArtUrl returns null for blank id', () {
      final provider = _provider(_library());
      expect(provider.getCoverArtUrl(null), isNull);
      expect(provider.getCoverArtUrl('   '), isNull);
    });

    test('getCoverArtCacheKey returns stable cache key and null for blank', () {
      final provider = _provider(_library());
      expect(provider.getCoverArtCacheKey('cov-homo', size: 200),
          'subsonic://music.example.com/rest/getCoverArt?id=cov-homo&size=200');
      expect(provider.getCoverArtCacheKey(null), isNull);
      expect(provider.getCoverArtCacheKey('   '), isNull);
    });
  });
}
