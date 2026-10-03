// test/core/services/missing_artwork_service_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/missing_artwork_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

AlbumsTableData _album(
  int id, {
  String title = 'Album',
  String artist = 'Artist',
  String? artworkUri,
}) =>
    AlbumsTableData(
      id: id,
      title: title,
      artist: artist,
      songCount: 1,
      artworkUri: artworkUri,
    );

Map<String, dynamic> _itunesBody(List<Object?> results) => {
      'resultCount': results.length,
      'results': results,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('findMissingArtworkAlbums', () {
    test('returns only albums with a null or empty artworkUri', () {
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response('{}', 200);
      }));

      final missing = service.findMissingArtworkAlbums([
        _album(1),
        _album(2, artworkUri: ''),
        _album(3, artworkUri: 'file:///art.jpg'),
      ]);

      expect(missing.map((a) => a.id), [1, 2]);
    });

    test('returns empty for an empty library', () {
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response('{}', 200);
      }));
      expect(service.findMissingArtworkAlbums(const []), isEmpty);
    });
  });

  group('fetchArtworkForAlbum', () {
    test('offline-only mode short-circuits before any HTTP request', () async {
      SharedPreferences.setMockInitialValues(
          {'setting_offline_only_mode': true});
      var calls = 0;
      final service = MissingArtworkService(MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }));

      expect(await service.fetchArtworkForAlbum('A', 'B'), isNull);
      expect(calls, 0);
    });

    test('upgrades the 100x100 artwork URL to 600x600', () async {
      Uri? requested;
      final service = MissingArtworkService(MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode(_itunesBody([
            {'artworkUrl100': 'https://is1.mzstatic.com/a/100x100bb.jpg'}
          ])),
          200,
        );
      }));

      final url =
          await service.fetchArtworkForAlbum('OK Computer', 'Radiohead');

      expect(url, 'https://is1.mzstatic.com/a/600x600bb.jpg');
      expect(requested!.host, 'itunes.apple.com');
      expect(requested!.queryParameters['entity'], 'album');
      expect(requested!.queryParameters['limit'], '1');
      expect(requested!.queryParameters['term'], 'OK Computer Radiohead');
    });

    test('uses the first result when several are returned', () async {
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response(
          jsonEncode(_itunesBody([
            {'artworkUrl100': 'https://x/first_100x100bb.jpg'},
            {'artworkUrl100': 'https://x/second_100x100bb.jpg'},
          ])),
          200,
        );
      }));

      expect(await service.fetchArtworkForAlbum('A', 'B'),
          'https://x/first_600x600bb.jpg');
    });

    test('an empty result list resolves to null', () async {
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response(jsonEncode(_itunesBody(const [])), 200);
      }));

      expect(await service.fetchArtworkForAlbum('A', 'B'), isNull);
    });

    test('a result without artworkUrl100 resolves to null', () async {
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response(
            jsonEncode(_itunesBody([
              {'collectionName': 'x'}
            ])),
            200);
      }));

      expect(await service.fetchArtworkForAlbum('A', 'B'), isNull);
    });

    test('a non-200 response resolves to null', () async {
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response('server error', 500);
      }));

      expect(
          await service.fetchArtworkForAlbum('A', 'B', maxRetries: 0), isNull);
    });

    test('an invalid JSON body resolves to null', () async {
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response('not json', 200);
      }));

      expect(
          await service.fetchArtworkForAlbum('A', 'B', maxRetries: 0), isNull);
    });

    test('a 429 without retries left resolves to null', () async {
      var calls = 0;
      final service = MissingArtworkService(MockClient((_) async {
        calls++;
        return http.Response('slow down', 429);
      }));

      expect(
          await service.fetchArtworkForAlbum('A', 'B', maxRetries: 0), isNull);
      expect(calls, 1);
    });

    test('a 429 is retried and a later success is returned', () async {
      var calls = 0;
      final service = MissingArtworkService(MockClient((_) async {
        calls++;
        if (calls == 1) return http.Response('slow down', 429);
        return http.Response(
          jsonEncode(_itunesBody([
            {'artworkUrl100': 'https://x/recovered_100x100bb.jpg'}
          ])),
          200,
        );
      }));

      final url = await service.fetchArtworkForAlbum('A', 'B', maxRetries: 1);
      expect(url, 'https://x/recovered_600x600bb.jpg');
      expect(calls, 2);
    });

    test('an exception with no retries left resolves to null', () async {
      var calls = 0;
      final service = MissingArtworkService(MockClient((_) async {
        calls++;
        throw http.ClientException('socket closed');
      }));

      expect(
          await service.fetchArtworkForAlbum('A', 'B', maxRetries: 0), isNull);
      expect(calls, 1);
    });

    test('a transient exception is retried', () async {
      var calls = 0;
      final service = MissingArtworkService(MockClient((_) async {
        calls++;
        if (calls == 1) throw http.ClientException('blip');
        return http.Response(
          jsonEncode(_itunesBody([
            {'artworkUrl100': 'https://x/retry_100x100bb.jpg'}
          ])),
          200,
        );
      }));

      final url = await service.fetchArtworkForAlbum('A', 'B', maxRetries: 1);
      expect(url, 'https://x/retry_600x600bb.jpg');
      expect(calls, 2);
    });
  });

  group('batchFetchArtwork', () {
    test('an empty album list returns an empty map and no progress', () async {
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response(jsonEncode(_itunesBody(const [])), 200);
      }));
      final progress = <List<int>>[];

      final results = await service.batchFetchArtwork(
        const [],
        onProgress: (p, t) => progress.add([p, t]),
      );

      expect(results, isEmpty);
      expect(progress, isEmpty);
    });

    test('batches lookups and reports progress', () async {
      final service = MissingArtworkService(MockClient((request) async {
        final term = request.url.queryParameters['term'] ?? '';
        if (term.startsWith('Missing')) {
          return http.Response(jsonEncode(_itunesBody(const [])), 200);
        }
        return http.Response(
          jsonEncode(_itunesBody([
            {'artworkUrl100': 'https://x/${term.hashCode}_100x100bb.jpg'}
          ])),
          200,
        );
      }));
      final progress = <List<int>>[];

      final results = await service.batchFetchArtwork(
        [
          _album(1, title: 'Found One'),
          _album(2, title: 'Missing'),
          _album(3, title: 'Found Two'),
        ],
        onProgress: (p, t) => progress.add([p, t]),
      );

      expect(results.keys.toList()..sort(), [1, 3]);
      expect(results[1], contains('600x600bb.jpg'));
      expect(progress, [
        [3, 3]
      ]);
    });

    test('more than one batch still completes and reports cumulative progress',
        () async {
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response(
          jsonEncode(_itunesBody([
            {'artworkUrl100': 'https://x/ok_100x100bb.jpg'}
          ])),
          200,
        );
      }));
      final progress = <List<int>>[];

      final results = await service.batchFetchArtwork(
        List.generate(7, (i) => _album(i + 1)),
        onProgress: (p, t) => progress.add([p, t]),
      );

      expect(results.length, 7);
      expect(progress.last, [7, 7]);
    });
  });

  group('fetchAndPersistMissingArtwork', () {
    test('returns 0 when offline-only mode is on', () async {
      SharedPreferences.setMockInitialValues(
          {'setting_offline_only_mode': true});
      getIt.registerSingleton<IMusicRepository>(MockMusicRepository());
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response(jsonEncode(_itunesBody(const [])), 200);
      }));

      expect(await service.fetchAndPersistMissingArtwork(), 0);
    });

    test('returns 0 when the repository is not registered', () async {
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response(jsonEncode(_itunesBody(const [])), 200);
      }));

      expect(await service.fetchAndPersistMissingArtwork(), 0);
    });

    test('returns 0 when the repository result is a failure', () async {
      final repo = MockMusicRepository();
      when(() => repo.getAlbums())
          .thenAnswer((_) async => const Left(DatabaseFailure('boom')));
      getIt.registerSingleton<IMusicRepository>(repo);
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response(jsonEncode(_itunesBody(const [])), 200);
      }));

      expect(await service.fetchAndPersistMissingArtwork(), 0);
    });

    test('returns 0 when every album already has artwork', () async {
      final repo = MockMusicRepository();
      when(() => repo.getAlbums()).thenAnswer(
          (_) async => Right([_album(1, artworkUri: 'file:///a.jpg')]));
      getIt.registerSingleton<IMusicRepository>(repo);
      var calls = 0;
      final service = MissingArtworkService(MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }));

      expect(await service.fetchAndPersistMissingArtwork(), 0);
      expect(calls, 0);
    });

    test('writes every resolved URL back and counts successes only', () async {
      final repo = MockMusicRepository();
      when(() => repo.getAlbums()).thenAnswer((_) async => Right([
            _album(1, title: 'One'),
            _album(2, title: 'Two'),
            _album(3, title: 'Three'),
          ]));
      when(() => repo.updateAlbumArtwork(1, any()))
          .thenAnswer((_) async => const Right(null));
      when(() => repo.updateAlbumArtwork(2, any()))
          .thenAnswer((_) async => const Left(DatabaseFailure('nope')));
      when(() => repo.updateAlbumArtwork(3, any()))
          .thenAnswer((_) async => const Right(null));
      getIt.registerSingleton<IMusicRepository>(repo);
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response(
          jsonEncode(_itunesBody([
            {'artworkUrl100': 'https://x/a_100x100bb.jpg'}
          ])),
          200,
        );
      }));

      final persisted = await service.fetchAndPersistMissingArtwork();

      expect(persisted, 2);
      verify(() => repo.updateAlbumArtwork(1, 'https://x/a_600x600bb.jpg'))
          .called(1);
      verify(() => repo.updateAlbumArtwork(2, any())).called(1);
      verify(() => repo.updateAlbumArtwork(3, 'https://x/a_600x600bb.jpg'))
          .called(1);
    });

    test('forwards the progress callback', () async {
      final repo = MockMusicRepository();
      when(() => repo.getAlbums())
          .thenAnswer((_) async => Right([_album(1), _album(2)]));
      when(() => repo.updateAlbumArtwork(any(), any()))
          .thenAnswer((_) async => const Right(null));
      getIt.registerSingleton<IMusicRepository>(repo);
      final service = MissingArtworkService(MockClient((_) async {
        return http.Response(
          jsonEncode(_itunesBody([
            {'artworkUrl100': 'https://x/b_100x100bb.jpg'}
          ])),
          200,
        );
      }));
      final progress = <List<int>>[];

      await service.fetchAndPersistMissingArtwork(
          onProgress: (p, t) => progress.add([p, t]));

      expect(progress, [
        [2, 2]
      ]);
    });
  });

  group('dispose', () {
    test('closes the underlying http client without throwing', () {
      final service = MissingArtworkService(
          MockClient((_) async => http.Response('', 200)));
      expect(service.dispose, returnsNormally);
    });
  });
}
