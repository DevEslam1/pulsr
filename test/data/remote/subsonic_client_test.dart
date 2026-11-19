// Tests for the Navidrome / Subsonic client: deterministic salted-token auth,
// exact query parameters, tolerant JSON mapping, typed failures that never
// leak credentials, and streamUrl round-tripping without double encoding.
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pulsr/data/remote/subsonic_client.dart';

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

http.StreamedResponse _jsonResponse(Object body, {int status = 200}) =>
    http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

http.StreamedResponse _textResponse(String body, {int status = 200}) =>
    http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      status,
      headers: const {'content-type': 'text/plain'},
    );

Map<String, dynamic> _envelope([Map<String, dynamic>? payload]) => {
      'subsonic-response': {
        'status': 'ok',
        'version': '1.16.1',
        if (payload != null) ...payload,
      },
    };

Map<String, dynamic> _apiError(int code, String message) => {
      'subsonic-response': {
        'status': 'failed',
        'version': '1.16.1',
        'error': {'code': code, 'message': message},
      },
    };

const String _user = 'eslam';
const String _password = 'p@ss w0rd';
const String _salt = 'fixed-salt';

String _tokenFor(String salt) =>
    md5.convert(utf8.encode('$_password$salt')).toString();

SubsonicClient _client(
  _FakeHttpClient fake, {
  String salt = _salt,
  Uri? baseUrl,
}) =>
    SubsonicClient(
      baseUrl: baseUrl ?? Uri.parse('https://music.example.com'),
      username: _user,
      password: _password,
      client: fake,
      saltGenerator: () => salt,
    );

void main() {
  group('salted token authentication', () {
    test('ping sends u/t/s/v/c/f once and never the password', () async {
      final fake = _FakeHttpClient(
          (_) async => _jsonResponse(_envelope({'version': '1.16.1'})));
      final client = _client(fake);

      await client.ping();

      expect(fake.requests, hasLength(1));
      final request = fake.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/ping.view');
      final query = request.url.queryParameters;
      expect(query['u'], _user);
      expect(query['s'], _salt);
      expect(query['t'], _tokenFor(_salt));
      expect(query['v'], '1.16.1');
      expect(query['c'], 'Pulsr');
      expect(query['f'], 'json');
      expect(query, isNot(contains('p')));
      expect(request.url.toString(), isNot(contains(_password)));
      expect(client.toString(), isNot(contains(_password)));
      expect(client.toString(), isNot(contains(_user)));
      expect(client.toString(), 'SubsonicClient(music.example.com)');
    });

    test('generates a fresh salt and matching token per request', () async {
      var counter = 0;
      final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope()));
      final client = SubsonicClient(
        baseUrl: Uri.parse('https://music.example.com'),
        username: _user,
        password: _password,
        client: fake,
        saltGenerator: () => 'salt-${counter++}',
      );

      await client.ping();
      await client.ping();

      expect(fake.requests, hasLength(2));
      final salts = fake.requests.map((r) => r.url.queryParameters['s']);
      final tokens = fake.requests.map((r) => r.url.queryParameters['t']);
      expect(salts, ['salt-0', 'salt-1']);
      expect(tokens, [
        md5.convert(utf8.encode('${_password}salt-0')).toString(),
        md5.convert(utf8.encode('${_password}salt-1')).toString(),
      ]);
    });

    test('rejects an empty salt from an injected generator', () async {
      final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope()));
      final client = SubsonicClient(
        baseUrl: Uri.parse('https://music.example.com'),
        username: _user,
        password: _password,
        client: fake,
        saltGenerator: () => '',
      );

      await expectLater(
        client.ping(),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_CONFIG')),
      );
      expect(fake.requests, isEmpty);
    });
  });

  group('JSON mapping', () {
    test('getArtists flattens index buckets and tolerates missing fields',
        () async {
      final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope({
            'artists': {
              'ignoredArticles': 'The El La',
              'index': [
                {
                  'name': 'B',
                  'artist': [
                    {
                      'id': '1',
                      'name': 'Bj\u00f6rk',
                      'albumCount': 7,
                      'coverArt': 'ar-1',
                    },
                    {'id': 2, 'name': 'Boards of Canada'},
                    {'id': '', 'name': 'Dropped'},
                    {'name': 'Also dropped'},
                  ],
                },
                {
                  'name': 'N',
                  'artist': [
                    {
                      'id': '3',
                      'name': 'Nils Frahm',
                      'albumCount': 2,
                      'artistImageUrl': 'https://img.example.com/nf.jpg',
                    },
                  ],
                },
                {'name': 'empty'},
              ],
            },
          })));
      final client = _client(fake);

      final artists = await client.getArtists();

      expect(artists.map((artist) => artist.id), ['1', '2', '3']);
      expect(artists.first.name, 'Bj\u00f6rk');
      expect(artists.first.albumCount, 7);
      expect(artists.first.coverArt, 'ar-1');
      expect(artists[1].albumCount, 0);
      expect(artists[1].coverArt, isNull);
      expect(artists[2].imageUrl, 'https://img.example.com/nf.jpg');
      expect(artists.every((artist) => artist.albums.isEmpty), isTrue);
    });

    test('getArtists returns an empty list when the payload is absent',
        () async {
      final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope()));
      final client = _client(fake);

      expect(await client.getArtists(), isEmpty);
      expect(await client.getPlaylists(), isEmpty);
    });

    test('getArtist maps albums and falls back to the id for a name', () async {
      final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope({
            'artist': {
              'id': '10',
              'name': 'Portishead',
              'albumCount': 2,
              'artistImageUrl': 'https://img.example.com/ph.jpg',
              'album': [
                {
                  'id': '20',
                  'name': 'Dummy',
                  'artist': 'Portishead',
                  'songCount': 10,
                  'duration': 3600,
                  'year': 1994,
                  'coverArt': 'al-20',
                  'genre': 'Trip-Hop',
                },
                {'id': '21', 'artist': 'Portishead'},
                {'name': 'No id'},
              ],
            },
          })));
      final client = _client(fake);

      final artist = await client.getArtist(' 10 ');

      expect(fake.requests.single.url.queryParameters['id'], '10');
      expect(artist.id, '10');
      expect(artist.name, 'Portishead');
      expect(artist.albumCount, 2);
      expect(artist.albums, hasLength(2));
      expect(artist.albums.first.name, 'Dummy');
      expect(artist.albums.first.year, 1994);
      expect(artist.albums.first.duration, const Duration(hours: 1));
      expect(artist.albums.last.name, '21');
      expect(artist.albums.last.songCount, 0);
    });

    test('getAlbum maps songs and defaults missing counters', () async {
      final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope({
            'album': {
              'id': '20',
              'name': 'Dummy',
              'artist': 'Portishead',
              'year': 1994,
              'genre': 'Trip-Hop',
              'songCount': 3,
              'duration': 3600,
              'song': [
                {
                  'id': '100',
                  'title': 'Mysterons',
                  'album': 'Dummy',
                  'artist': 'Portishead',
                  'duration': 305,
                  'track': 1,
                  'discNumber': 1,
                  'suffix': 'flac',
                  'bitRate': 900,
                  'size': 123456,
                  'contentType': 'audio/flac',
                  'path': 'Portishead/Dummy/01.flac',
                },
                {
                  'id': '101',
                  'title': 'Sour Times',
                  'duration': '250',
                  'isDir': false,
                },
                {'id': '102'},
                {'title': 'No id'},
              ],
            },
          })));
      final client = _client(fake);

      final album = await client.getAlbum('20');

      expect(album.songs, hasLength(3));
      expect(album.songCount, 3);
      final first = album.songs.first;
      expect(first.title, 'Mysterons');
      expect(first.duration, const Duration(minutes: 5, seconds: 5));
      expect(first.track, 1);
      expect(first.discNumber, 1);
      expect(first.suffix, 'flac');
      expect(first.bitRateKbps, 900);
      expect(first.sizeBytes, 123456);
      expect(first.path, 'Portishead/Dummy/01.flac');
      expect(album.songs[1].duration, const Duration(seconds: 250));
      expect(album.songs[1].isDirectory, isFalse);
      expect(album.songs[2].title, '102');
      expect(album.songs[2].duration, Duration.zero);
    });

    test('getPlaylists maps list entries and stays empty on no payload',
        () async {
      final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope({
            'playlists': {
              'playlist': [
                {
                  'id': 'p1',
                  'name': 'Late Night',
                  'owner': 'eslam',
                  'public': true,
                  'songCount': 12,
                  'duration': 4200,
                  'comment': 'for headphones',
                  'coverArt': 'pl-1',
                },
                {'id': 'p2'},
              ],
            },
          })));
      final client = _client(fake);

      final playlists = await client.getPlaylists();

      expect(playlists, hasLength(2));
      expect(playlists.first.name, 'Late Night');
      expect(playlists.first.owner, 'eslam');
      expect(playlists.first.isPublic, isTrue);
      expect(playlists.first.songCount, 12);
      expect(playlists.first.duration, const Duration(minutes: 70));
      expect(playlists.first.comment, 'for headphones');
      expect(playlists.last.name, 'p2');
      expect(playlists.last.isPublic, isFalse);
      expect(playlists.last.songCount, 0);
      expect(playlists.last.songs, isEmpty);
    });

    test('getPlaylist maps entries and falls back to songCount', () async {
      final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope({
            'playlist': {
              'id': 'p1',
              'name': 'Late Night',
              'owner': 'eslam',
              'entry': [
                {'id': '100', 'title': 'Mysterons', 'duration': 305},
                {'id': '101', 'title': 'Sour Times', 'duration': 250},
              ],
            },
          })));
      final client = _client(fake);

      final playlist = await client.getPlaylist('p1');

      expect(playlist.songs, hasLength(2));
      expect(playlist.songCount, 2);
      expect(playlist.songs.map((song) => song.id), ['100', '101']);
      expect(playlist.songs.first.duration, const Duration(seconds: 305));
    });

    test('rejects a missing payload as a typed bad response', () async {
      final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope()));
      final client = _client(fake);

      await expectLater(
        client.getAlbum('20'),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_BAD_RESPONSE')
            .having((error) => error.method, 'method', 'getAlbum')),
      );
      await expectLater(
        client.getPlaylist('p1'),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_BAD_RESPONSE')),
      );
    });

    test('rejects a blank id before issuing a request', () async {
      final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope()));
      final client = _client(fake);

      await expectLater(
        client.getArtist('  '),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_BAD_ID')),
      );
      expect(fake.requests, isEmpty);
    });
  });

  group('error paths', () {
    test('maps an API error envelope to a stable reason code', () async {
      final fake = _FakeHttpClient((_) async =>
          _jsonResponse(_apiError(40, 'Wrong username or password')));
      final client = _client(fake);

      await expectLater(
        client.getAlbum('20'),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_API_40')
            .having((error) => error.apiCode, 'apiCode', 40)
            .having((error) => error.apiMessage, 'apiMessage',
                'Wrong username or password')
            .having((error) => error.method, 'method', 'getAlbum')
            .having((error) => error.userMessage, 'userMessage',
                'Wrong username or password')),
      );
    });

    test('redacts the password and token echoed by the server', () async {
      final token = _tokenFor(_salt);
      final fake = _FakeHttpClient((_) async => _jsonResponse(_apiError(
          40, 'bad token $token for password $_password salt $_salt')));
      final client = _client(fake);

      late SubsonicError error;
      try {
        await client.ping();
        fail('expected a SubsonicError');
      } on SubsonicError catch (caught) {
        error = caught;
      }

      expect(error.code, 'SUBSONIC_API_40');
      expect(error.userMessage, contains('***'));
      expect(error.userMessage, isNot(contains(token)));
      expect(error.userMessage, isNot(contains(_password)));
      expect(error.userMessage, isNot(contains(_salt)));
      expect(error.toString(), isNot(contains(_password)));
      expect(error.toString(), isNot(contains(token)));
    });

    test('maps a non-200 response without echoing the body', () async {
      final fake = _FakeHttpClient(
          (_) async => _textResponse('server exploded', status: 503));
      final client = _client(fake);

      await expectLater(
        client.ping(),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_HTTP_503')
            .having((error) => error.userMessage, 'message',
                isNot(contains('exploded')))),
      );
    });

    test('maps malformed JSON and redacts it in the cause', () async {
      final token = _tokenFor(_salt);
      final fake = _FakeHttpClient(
          (_) async => _textResponse('{"subsonic-response": "broken $token'));
      final client = _client(fake);

      late SubsonicError error;
      try {
        await client.ping();
        fail('expected a SubsonicError');
      } on SubsonicError catch (caught) {
        error = caught;
      }

      expect(error.code, 'SUBSONIC_MALFORMED_JSON');
      expect(error.cause.toString(), isNot(contains(token)));
      expect(error.cause.toString(), isNot(contains(_password)));
    });

    test('rejects a non-object JSON document', () async {
      final fake = _FakeHttpClient((_) async => _jsonResponse([1, 2, 3]));
      final client = _client(fake);

      await expectLater(
        client.ping(),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_BAD_RESPONSE')),
      );
    });

    test('rejects an envelope without a status', () async {
      final fake = _FakeHttpClient((_) async => _jsonResponse({
            'subsonic-response': {'version': '1.16.1'},
          }));
      final client = _client(fake);

      await expectLater(
        client.ping(),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_BAD_RESPONSE')),
      );
    });

    test('maps a failed status without an error object', () async {
      final fake = _FakeHttpClient((_) async => _jsonResponse({
            'subsonic-response': {'status': 'failed'},
          }));
      final client = _client(fake);

      await expectLater(
        client.ping(),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_API_ERROR')),
      );
    });

    test('maps timeout and client failures to network errors', () async {
      final slow = _client(
          _FakeHttpClient((_) async => throw TimeoutException('no answer')));
      await expectLater(
        slow.ping(),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_TIMEOUT')),
      );

      final broken = _client(_FakeHttpClient((request) async =>
          throw http.ClientException('socket closed', request.url)));
      late SubsonicError error;
      try {
        await broken.ping();
        fail('expected a SubsonicError');
      } on SubsonicError catch (caught) {
        error = caught;
      }
      expect(error.code, 'SUBSONIC_NETWORK');
      expect(error.cause.toString(), isNot(contains('t=')));
      expect(error.cause.toString(), isNot(contains(_password)));
      expect(error.toString(), isNot(contains(_password)));
    });
  });

  group('streamUrl', () {
    test('carries auth params and encodes the id exactly once', () {
      final client = _client(_FakeHttpClient((_) async => _textResponse('')));

      const songId = 'a b&c+d/e%f';
      final uri = client.streamUrl(songId);

      expect(uri.path, '/rest/stream.view');
      final query = uri.queryParameters;
      expect(query['id'], songId);
      expect(query['u'], _user);
      expect(query['s'], _salt);
      expect(query['t'], _tokenFor(_salt));
      expect(query['v'], '1.16.1');
      expect(query['c'], 'Pulsr');
      expect(query['f'], 'json');
      expect(query.containsKey('p'), isFalse);
      expect(uri.toString(), contains('id=a+b%26c%2Bd%2Fe%25f'));
      expect('%25'.allMatches(uri.toString()).length, 1,
          reason: 'only the literal % is encoded; nothing is encoded twice');
      expect(uri.toString(), isNot(contains('p@ss')));
    });

    test('round-trips through Uri.parse', () {
      final client = _client(_FakeHttpClient((_) async => _textResponse('')));
      final uri = client.streamUrl('al-20/tr-100 & more');

      final reparsed = Uri.parse(uri.toString());

      expect(reparsed, uri);
      expect(reparsed.queryParameters['id'], 'al-20/tr-100 & more');
      expect(reparsed.queryParameters['t'], _tokenFor(_salt));
    });

    test('accepts a server mounted under a path', () {
      final client = _client(
        _FakeHttpClient((_) async => _textResponse('')),
        baseUrl: Uri.parse('https://music.example.com/music/'),
      );

      final uri = client.streamUrl('100');

      expect(uri.path, '/music/rest/stream.view');
      expect(uri.queryParameters['id'], '100');
    });

    test('rejects a blank song id', () {
      final client = _client(_FakeHttpClient((_) async => _textResponse('')));

      expect(
        () => client.streamUrl('   '),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_BAD_SONG_ID')),
      );
    });
  });

  group('configuration', () {
    test('refuses a private server unless it is allowlisted', () {
      final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope()));
      final lan = Uri.parse('http://192.168.1.20:4533');

      expect(
        () => SubsonicClient(
          baseUrl: lan,
          username: _user,
          password: _password,
          client: fake,
        ),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_UNSAFE_TARGET')),
      );

      final allowed = SubsonicClient(
        baseUrl: lan,
        username: _user,
        password: _password,
        client: fake,
        allowedHostSuffixes: {'192.168.1.20'},
        saltGenerator: () => _salt,
      );
      expect(allowed.toString(), 'SubsonicClient(192.168.1.20)');
    });

    test('validates scheme, host, credentials, query and fragment', () {
      final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope()));
      SubsonicClient build(Uri url, {String username = _user}) =>
          SubsonicClient(
            baseUrl: url,
            username: username,
            password: _password,
            client: fake,
            saltGenerator: () => _salt,
          );

      for (final url in <Uri>[
        Uri.parse('ftp://music.example.com'),
        Uri.parse('https://music.example.com?x=1'),
        Uri.parse('https://music.example.com/#frag'),
        Uri.parse('https://user:pass@music.example.com'),
      ]) {
        expect(
          () => build(url),
          throwsA(isA<SubsonicError>()
              .having((error) => error.code, 'code', 'SUBSONIC_CONFIG')),
          reason: 'should reject $url',
        );
      }
      expect(
        () => build(Uri.parse('https://music.example.com'), username: ' '),
        throwsA(isA<SubsonicError>()
            .having((error) => error.code, 'code', 'SUBSONIC_CONFIG')),
      );
    });

    test('normalizes base paths without duplicating /rest', () async {
      for (final entry in <String, String>{
        'https://music.example.com': '/rest/ping.view',
        'https://music.example.com/': '/rest/ping.view',
        'https://music.example.com/music/': '/music/rest/ping.view',
        'https://music.example.com/music/rest/': '/music/rest/ping.view',
        'https://music.example.com/rest': '/rest/ping.view',
      }.entries) {
        final fake = _FakeHttpClient((_) async => _jsonResponse(_envelope()));
        final client = _client(fake, baseUrl: Uri.parse(entry.key));

        await client.ping();

        expect(fake.requests.single.url.path, entry.value,
            reason: 'base ${entry.key}');
      }
    });
  });
}
