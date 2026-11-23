// P0-1 remote sources: local Range arithmetic and the loopback stream bridge.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/interfaces/remote_fs_provider.dart';
import 'package:pulsr/domain/models/remote_source.dart';
import 'package:pulsr/features/remote_sources/remote_cache_store.dart';
import 'package:pulsr/features/remote_sources/remote_stream_server.dart';

class _FakeProvider implements RemoteFsProvider {
  _FakeProvider(this.source, this.files);

  @override
  final RemoteSource source;

  final Map<String, List<int>> files;
  String? etag;
  DateTime? modifiedAt;
  int openReadCount = 0;
  int statCount = 0;
  int closeCount = 0;
  final List<({int start, int? end})> requests = <({int start, int? end})>[];

  @override
  Future<List<RemoteEntry>> list(String path) async => const [];

  @override
  Future<RemoteEntry?> stat(String path) async {
    statCount++;
    final data = files[path];
    if (data == null) return null;
    return RemoteEntry(
      path: path,
      name: path.split('/').last,
      isDirectory: false,
      sizeBytes: data.length,
      etag: etag,
      modifiedAt: modifiedAt,
    );
  }

  @override
  Stream<List<int>> openRead(String path, {int start = 0, int? end}) async* {
    openReadCount++;
    requests.add((start: start, end: end));
    final data = files[path];
    if (data == null) {
      throw const RemoteNotFoundError(
        code: 'FAKE_NOT_FOUND',
        userMessage: 'No such file.',
      );
    }
    final stop = end ?? data.length - 1;
    yield data.sublist(start, stop + 1);
  }

  @override
  Future<bool> testConnection() async => true;

  @override
  Future<void> close() async {
    closeCount++;
  }
}

/// Cache store that counts [lookup] calls, so a test can prove one request
/// performs at most one lookup.
class _CountingCacheStore extends RemoteCacheStore {
  _CountingCacheStore({
    required super.directoryProvider,
    super.maxBytes,
  });

  int lookups = 0;

  @override
  Future<File?> lookup(
    String sourceId,
    String path, {
    String? etag,
    DateTime? modifiedAt,
  }) {
    lookups++;
    return super.lookup(sourceId, path, etag: etag, modifiedAt: modifiedAt);
  }
}

RemoteSource _source({String host = '127.0.0.1'}) {
  return RemoteSource.create(
    kind: RemoteSourceKind.webdav,
    displayName: 'Fake',
    host: host,
    port: 80,
    rootPath: '/',
  );
}

void main() {
  group('parseRangeHeader', () {
    test('returns no range when the header is absent or unparsable', () {
      expect(
        RemoteStreamServer.parseRangeHeader(null, totalLength: 10).hasRange,
        isFalse,
      );
      expect(
        RemoteStreamServer.parseRangeHeader('items=0-1', totalLength: 10)
            .hasRange,
        isFalse,
      );
      expect(
        RemoteStreamServer.parseRangeHeader('bytes=abc', totalLength: 10)
            .hasRange,
        isFalse,
      );
    });

    test('parses closed, open and suffix windows', () {
      final closed =
          RemoteStreamServer.parseRangeHeader('bytes=2-5', totalLength: 10);
      expect(closed.range?.start, 2);
      expect(closed.range?.end, 5);
      expect(closed.range?.length, 4);

      final open =
          RemoteStreamServer.parseRangeHeader('bytes=7-', totalLength: 10);
      expect(open.range?.start, 7);
      expect(open.range?.end, 9);

      final suffix =
          RemoteStreamServer.parseRangeHeader('bytes=-3', totalLength: 10);
      expect(suffix.range?.start, 7);
      expect(suffix.range?.end, 9);
    });

    test('clamps an end past the file and uses the first of several windows', () {
      final clamped =
          RemoteStreamServer.parseRangeHeader('bytes=5-99', totalLength: 10);
      expect(clamped.range?.end, 9);

      final first =
          RemoteStreamServer.parseRangeHeader('bytes=0-1,4-5', totalLength: 10);
      expect(first.range?.start, 0);
      expect(first.range?.end, 1);
    });

    test('marks a window past the end as unsatisfiable', () {
      final result =
          RemoteStreamServer.parseRangeHeader('bytes=20-30', totalLength: 10);
      expect(result.unsatisfiable, isTrue);
      expect(result.range, isNull);
    });
  });

  group('loopback streaming', () {
    late Directory tempDir;
    late RemoteStreamServer server;
    late _FakeProvider provider;
    final payload = List<int>.generate(64, (index) => index);
    late HttpClient client;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pulsr_stream_test');
      provider = _FakeProvider(_source(), <String, List<int>>{
        'Music/a.mp3': payload,
      });
      server = RemoteStreamServer(
        cache: RemoteCacheStore(
          directoryProvider: () async => tempDir,
          maxBytes: 1024 * 1024,
        ),
      );
      await server.registerProvider(provider);
      await server.start();
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<HttpClientResponse> send(
      String path, {
      String method = 'GET',
      String? range,
    }) async {
      final request = await client.openUrl(method, server.uriFor(_source(), path));
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      return request.close();
    }

    test('uriFor throws before the server started', () {
      final cold = RemoteStreamServer();
      expect(
        () => cold.uriFor(_source(), 'a.mp3'),
        throwsA(isA<StateError>()),
      );
    });

    test('uriFor carries a random 128-bit token and the base64url path', () {
      final uri = server.uriFor(_source(), 'Music/a.mp3');
      final again = server.uriFor(_source(), 'Music/a.mp3');

      expect(uri.host, '127.0.0.1');
      expect(uri.pathSegments, hasLength(4));
      expect(uri.pathSegments.first, 'stream');
      expect(uri.pathSegments[1], _source().id);
      final token = uri.pathSegments[2];
      expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(base64Url.decode(base64Url.normalize(token)), hasLength(16));
      expect(
        utf8.decode(
          base64Url.decode(base64Url.normalize(uri.pathSegments[3])),
        ),
        'Music/a.mp3',
      );
      expect(again.pathSegments[2], token,
          reason: 'a source keeps one token across seeks');
    });

    test('a full GET answers 200 with the whole file as a chunked body',
        () async {
      final response = await send('Music/a.mp3');
      final body = await response.expand((chunk) => chunk).toList();

      expect(response.statusCode, HttpStatus.ok);
      expect(
        response.headers.value(HttpHeaders.contentLengthHeader),
        isNull,
        reason: 'a live provider stream is not length-verified: use chunked',
      );
      expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(body, payload);
    });

    test('a ranged GET answers 206 and asks the provider for that window',
        () async {
      final response = await send('Music/a.mp3', range: 'bytes=10-19');
      final body = await response.expand((chunk) => chunk).toList();

      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 10-19/64',
      );
      expect(
        response.headers.value(HttpHeaders.contentLengthHeader),
        isNull,
      );
      expect(body, payload.sublist(10, 20));
      expect(provider.requests.single.start, 10);
      expect(provider.requests.single.end, 19);
    });

    test('HEAD answers a metadata content length without a body', () async {
      final response = await send('Music/a.mp3', method: 'HEAD');
      final body = await response.expand((chunk) => chunk).toList();

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value(HttpHeaders.contentLengthHeader), '64');
      expect(body, isEmpty);
    });

    test('an unsatisfiable range answers 416', () async {
      final response = await send('Music/a.mp3', range: 'bytes=100-200');

      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes */64',
      );
      await response.drain<void>();
    });

    test('an unknown source id answers 404 even with a well-formed token', () async {
      final uri = Uri.parse(
        'http://127.0.0.1:${server.port}/stream/unknown/'
        '${'a' * 22}/${base64UrlEncode(utf8.encode('a.mp3'))}',
      );
      final request = await client.getUrl(uri);
      final response = await request.close();

      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    });

    test('a URL without the token segment is rejected', () async {
      final uri = Uri.parse(
        'http://127.0.0.1:${server.port}/stream/${_source().id}/'
        '${base64UrlEncode(utf8.encode('Music/a.mp3'))}',
      );
      final request = await client.getUrl(uri);
      final response = await request.close();

      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    });

    test('a wrong token answers 403 and never reaches the provider', () async {
      final uri = Uri.parse(
        'http://127.0.0.1:${server.port}/stream/${_source().id}/'
        '${'b' * 22}/${base64UrlEncode(utf8.encode('Music/a.mp3'))}',
      );
      final request = await client.getUrl(uri);
      final response = await request.close();

      expect(response.statusCode, HttpStatus.forbidden);
      expect(provider.openReadCount, 0);
      await response.drain<void>();
    });

    test('a decoded ../ traversal is rejected before the provider', () async {
      final uri = Uri.parse(
        'http://127.0.0.1:${server.port}/stream/${_source().id}/'
        '${server.uriFor(_source(), 'x').pathSegments[2]}/'
        '${base64UrlEncode(utf8.encode('../../etc/passwd'))}',
      );
      final request = await client.getUrl(uri);
      final response = await request.close();

      expect(response.statusCode, HttpStatus.badRequest);
      expect(provider.openReadCount, 0);
      await response.drain<void>();
    });

    test('unregisterSource revokes the token and closes the provider', () async {
      final uri = server.uriFor(_source(), 'Music/a.mp3');

      await server.unregisterSource(_source().id);

      expect(provider.closeCount, 1);
      final request = await client.getUrl(uri);
      final response = await request.close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    });

    test('registerProvider closes the previous provider and keeps the token',
        () async {
      final token = server.uriFor(_source(), 'Music/a.mp3').pathSegments[2];
      final replacement = _FakeProvider(_source(), <String, List<int>>{
        'Music/a.mp3': List<int>.filled(64, 9),
      });

      await server.registerProvider(replacement);

      expect(provider.closeCount, 1);
      final uri = server.uriFor(_source(), 'Music/a.mp3');
      expect(uri.pathSegments[2], token);
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.expand((chunk) => chunk).toList();
      expect(body, List<int>.filled(64, 9));
      expect(replacement.openReadCount, 1);
    });

    test('a missing file surfaces the provider error as 404', () async {
      final response = await send('Music/missing.mp3');

      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    });

    test('a full download warms the cache and is served from disk next time',
        () async {
      final cache = RemoteCacheStore(
        directoryProvider: () async => tempDir,
        maxBytes: 1024 * 1024,
      );
      final warming = RemoteStreamServer(cache: cache);
      await warming.registerProvider(provider);
      await warming.start();
      try {
        final first = await client.getUrl(warming.uriFor(_source(), 'Music/a.mp3'));
        final firstResponse = await first.close();
        await firstResponse.drain<void>();
        expect(provider.openReadCount, 1);

        var cached = false;
        for (var attempt = 0; attempt < 40 && !cached; attempt++) {
          cached = await cache.contains(_source().id, 'Music/a.mp3');
          if (!cached) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        }
        expect(cached, isTrue, reason: 'a 200 download should be cached');

        final second =
            await client.getUrl(warming.uriFor(_source(), 'Music/a.mp3'));
        final secondRequest = second;
        secondRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=0-3');
        final secondResponse = await secondRequest.close();
        final body = await secondResponse.expand((chunk) => chunk).toList();

        expect(secondResponse.statusCode, HttpStatus.partialContent);
        expect(body, payload.sublist(0, 4));
        expect(
          provider.openReadCount,
          1,
          reason: 'the cached file must serve the range without a provider read',
        );
        expect(
          secondResponse.headers.value(HttpHeaders.contentLengthHeader),
          '4',
          reason: 'a cached file proves the byte count',
        );
      } finally {
        await warming.stop();
      }
    });

    test('a changed etag invalidates the cached file', () async {
      final cache = RemoteCacheStore(
        directoryProvider: () async => tempDir,
        maxBytes: 1024 * 1024,
      );
      final revalidating = RemoteStreamServer(cache: cache);
      provider.etag = 'v1';
      await revalidating.registerProvider(provider);
      await revalidating.start();
      try {
        final first =
            await client.getUrl(revalidating.uriFor(_source(), 'Music/a.mp3'));
        await (await first.close()).drain<void>();

        var cached = false;
        for (var attempt = 0; attempt < 40 && !cached; attempt++) {
          cached = await cache.contains(_source().id, 'Music/a.mp3');
          if (!cached) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
        }
        expect(cached, isTrue);

        // The server now reports a different validator for the same path.
        provider.etag = 'v2';
        provider.files['Music/a.mp3'] = List<int>.filled(64, 3);

        final second =
            await client.getUrl(revalidating.uriFor(_source(), 'Music/a.mp3'));
        final body = await (await second.close()).expand((c) => c).toList();

        expect(provider.openReadCount, 2,
            reason: 'a stale cache entry must be re-downloaded');
        expect(body, List<int>.filled(64, 3));
      } finally {
        await revalidating.stop();
      }
    });
  });

  group('stat cache', () {
    final payload = List<int>.generate(64, (index) => index);
    late Directory tempDir;
    late _CountingCacheStore cache;
    late _FakeProvider provider;
    late RemoteStreamServer server;
    late HttpClient client;
    late DateTime now;

    setUp(() async {
      now = DateTime(2026, 1, 1, 12);
      tempDir = await Directory.systemTemp.createTemp('pulsr_stat_cache_test');
      provider = _FakeProvider(_source(), <String, List<int>>{
        'Music/a.mp3': payload,
      });
      cache = _CountingCacheStore(
        directoryProvider: () async => tempDir,
        maxBytes: 1024 * 1024,
      );
      server = RemoteStreamServer(cache: cache, clock: () => now);
      await server.registerProvider(provider);
      await server.start();
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    /// Opens [path] as HEAD: the cheapest request that still needs a stat.
    Future<HttpClientResponse> head(String path) async {
      final uri = server.uriFor(_source(), path);
      final request = await client.openUrl('HEAD', uri);
      final response = await request.close();
      await response.drain<void>();
      return response;
    }

    void advance(int seconds) => now = now.add(Duration(seconds: seconds));

    /// Commits an entry through the store, exactly as a finished download does.
    Future<void> warmCache() async {
      final sink = await cache.beginWrite(_source().id, 'Music/a.mp3');
      sink.add(payload);
      await sink.commit();
    }

    test('a second request within the TTL does not stat again', () async {
      await head('Music/a.mp3');
      expect(provider.statCount, 1);

      advance(4);
      await head('Music/a.mp3');
      expect(
        provider.statCount,
        1,
        reason: 'the memo is younger than the five-second TTL',
      );

      advance(2);
      await head('Music/a.mp3');
      expect(provider.statCount, 2, reason: 'the memo expired');
    });

    test('one request performs one lookup and one stat', () async {
      await warmCache();
      cache.lookups = 0;

      final response = await head('Music/a.mp3');

      expect(cache.lookups, 1, reason: 'a cache hit is looked up once');
      expect(provider.statCount, 1);
      expect(response.headers.value(HttpHeaders.contentLengthHeader), '64');
    });

    test('a cache commit and delete each invalidate the memo', () async {
      await head('Music/a.mp3');
      expect(provider.statCount, 1);

      await warmCache();
      await head('Music/a.mp3');
      expect(provider.statCount, 2, reason: 'a commit changes the entry');

      await head('Music/a.mp3');
      expect(provider.statCount, 2, reason: 'the refreshed memo is reused');

      await cache.remove(_source().id, 'Music/a.mp3');
      await head('Music/a.mp3');
      expect(provider.statCount, 3, reason: 'a delete changes the entry');
    });

    test('a replaced provider is statted instead of the old one', () async {
      await head('Music/a.mp3');
      expect(provider.statCount, 1);

      final replacement = _FakeProvider(_source(), <String, List<int>>{
        'Music/a.mp3': payload,
      });
      await server.registerProvider(replacement);

      await head('Music/a.mp3');
      expect(replacement.statCount, 1);
      expect(provider.statCount, 1, reason: 'the old provider is not consulted');
    });

    test('serves audio MIME type and 416 for unsatisfiable range on empty file',
        () async {
      provider.files['Music/empty.flac'] = const <int>[];

      final fullReq = await client.getUrl(
        server.uriFor(_source(), 'Music/a.mp3'),
      );
      final fullRes = await fullReq.close();
      await fullRes.drain<void>();
      expect(fullRes.headers.contentType?.mimeType, 'audio/mpeg');

      final rangeReq = await client.getUrl(
        server.uriFor(_source(), 'Music/empty.flac'),
      );
      rangeReq.headers.set(HttpHeaders.rangeHeader, 'bytes=0-10');
      final rangeRes = await rangeReq.close();
      await rangeRes.drain<void>();
      expect(rangeRes.headers.contentType?.mimeType, 'audio/flac');
      expect(rangeRes.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(rangeRes.headers.value(HttpHeaders.contentRangeHeader), 'bytes */0');
    });
  });

  group('truncation and pinning', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pulsr_srv_trunc_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('truncated upstream stream is not committed to cache and pin: true pins on commit',
        () async {
      final cache = RemoteCacheStore(
        directoryProvider: () async => tempDir,
        maxBytes: 12,
      );
      final truncating = _TruncatingProvider(_source(), expectedSize: 10);
      final srv = RemoteStreamServer(cache: cache);
      await srv.registerProvider(truncating);
      await srv.start();
      final client = HttpClient();
      try {
        // First: truncated stream (returns 4 of 10 bytes) must NOT commit.
        final req = await client.getUrl(srv.uriFor(_source(), 'Music/trunc.mp3'));
        final res = await req.close();
        try {
          await res.drain<void>();
        } on HttpException {
          // Server drops the socket so player sees an error instead of EOF.
        }
        expect(await cache.contains(_source().id, 'Music/trunc.mp3'), isFalse);

        // Second: complete pinned stream pins atomically on commit.
        final okProvider = _FakeProvider(_source(), <String, List<int>>{
          'Music/keep.mp3': List<int>.filled(8, 7),
          'Music/drop.mp3': List<int>.filled(8, 9),
        });
        await srv.registerProvider(okProvider);
        final keepUri = srv.uriFor(_source(), 'Music/keep.mp3', pin: true);
        await (await (await client.getUrl(keepUri)).close()).drain<void>();
        final dropUri = srv.uriFor(_source(), 'Music/drop.mp3');
        await (await (await client.getUrl(dropUri)).close()).drain<void>();

        expect(await cache.contains(_source().id, 'Music/keep.mp3'), isTrue);
      } finally {
        client.close(force: true);
        await srv.stop();
      }
    });
  });
}

class _TruncatingProvider extends _FakeProvider {
  _TruncatingProvider(RemoteSource source, {required this.expectedSize})
      : super(source, <String, List<int>>{
          'Music/trunc.mp3': List<int>.filled(expectedSize, 1),
        });

  final int expectedSize;

  @override
  Stream<List<int>> openRead(String path, {int start = 0, int? end}) async* {
    yield const <int>[1, 2, 3, 4];
  }
}
