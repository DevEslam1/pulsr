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
  int openReadCount = 0;
  final List<({int start, int? end})> requests = <({int start, int? end})>[];

  @override
  Future<List<RemoteEntry>> list(String path) async => const [];

  @override
  Future<RemoteEntry?> stat(String path) async {
    final data = files[path];
    if (data == null) return null;
    return RemoteEntry(
      path: path,
      name: path.split('/').last,
      isDirectory: false,
      sizeBytes: data.length,
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
    final stop = end == null ? data.length - 1 : end;
    yield data.sublist(start, stop + 1);
  }

  @override
  Future<bool> testConnection() async => true;

  @override
  Future<void> close() async {}
}

RemoteSource _source() {
  return RemoteSource.create(
    kind: RemoteSourceKind.webdav,
    displayName: 'Fake',
    host: '127.0.0.1',
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
      server.registerProvider(provider);
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

    test('uriFor encodes the path as base64url', () {
      final uri = server.uriFor(_source(), 'Music/a.mp3');

      expect(uri.host, '127.0.0.1');
      expect(uri.pathSegments.first, 'stream');
      expect(uri.pathSegments[1], _source().id);
      expect(
        utf8.decode(base64Url.decode(base64Url.normalize(uri.pathSegments[2]))),
        'Music/a.mp3',
      );
    });

    test('a full GET answers 200 with the whole file', () async {
      final response = await send('Music/a.mp3');
      final body = await response.expand((chunk) => chunk).toList();

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value(HttpHeaders.contentLengthHeader), '64');
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
      expect(body, payload.sublist(10, 20));
      expect(provider.requests.single.start, 10);
      expect(provider.requests.single.end, 19);
    });

    test('HEAD answers headers without a body', () async {
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

    test('an unknown source id answers 404', () async {
      final uri = Uri.parse(
        'http://127.0.0.1:${server.port}/stream/unknown/${base64UrlEncode(utf8.encode('a.mp3'))}',
      );
      final request = await client.getUrl(uri);
      final response = await request.close();

      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
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
      warming.registerProvider(provider);
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
      } finally {
        await warming.stop();
      }
    });
  });
}
