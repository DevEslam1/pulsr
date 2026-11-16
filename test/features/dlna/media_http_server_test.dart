// Real loopback tests for the DLNA media server: full GET, byte ranges, HEAD,
// 416, unknown tokens, token TTL and registry eviction.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/dlna/media_http_server.dart';

typedef _Response = ({
  int status,
  Map<String, String> headers,
  List<int> body,
});

void main() {
  late Directory tempDir;
  late File mediaFile;
  late List<int> sourceBytes;
  late MediaHttpServer server;
  late HttpClient client;

  Future<_Response> fetch(
    String path, {
    String method = 'GET',
    String? range,
  }) async {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (range != null) {
      request.headers.set(HttpHeaders.rangeHeader, range);
    }
    final response = await request.close();
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(', ');
    });
    final body = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    return (status: response.statusCode, headers: headers, body: body);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_dlna_');
    sourceBytes = List<int>.generate(1000, (index) => index % 251);
    mediaFile = File('${tempDir.path}${Platform.pathSeparator}track.mp3');
    await mediaFile.writeAsBytes(sourceBytes);
    server = MediaHttpServer(tokenTtl: const Duration(minutes: 5));
    await server.start();
    server.register('token-1', MediaSource.file(mediaFile.path));
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await tempDir.delete(recursive: true);
  });

  test('serves a full GET with length, range support and MIME type', () async {
    final response = await fetch('/media/token-1');

    expect(response.status, 200);
    expect(response.body, sourceBytes);
    expect(response.headers['content-length'], '1000');
    expect(response.headers['accept-ranges'], 'bytes');
    expect(response.headers['content-type'], 'audio/mpeg');
    expect(response.headers.containsKey('content-range'), isFalse);
  });

  test('serves an exact byte slice for a Range request', () async {
    final response = await fetch('/media/token-1', range: 'bytes=100-199');

    expect(response.status, 206);
    expect(response.body, sourceBytes.sublist(100, 200));
    expect(response.headers['content-range'], 'bytes 100-199/1000');
    expect(response.headers['content-length'], '100');
    expect(response.headers['accept-ranges'], 'bytes');
  });

  test('serves a suffix range from the end of the file', () async {
    final response = await fetch('/media/token-1', range: 'bytes=-50');

    expect(response.status, 206);
    expect(response.body, sourceBytes.sublist(950));
    expect(response.headers['content-range'], 'bytes 950-999/1000');
  });

  test('HEAD returns headers without a body', () async {
    final response = await fetch('/media/token-1', method: 'HEAD');

    expect(response.status, 200);
    expect(response.body, isEmpty);
    expect(response.headers['content-length'], '1000');
    expect(response.headers['content-type'], 'audio/mpeg');
  });

  test('returns 416 for an unsatisfiable range', () async {
    final response = await fetch('/media/token-1', range: 'bytes=5000-6000');

    expect(response.status, 416);
    expect(response.headers['content-range'], 'bytes */1000');
    expect(response.body, isEmpty);
  });

  test('returns 404 for an unknown token', () async {
    final response = await fetch('/media/missing-token');

    expect(response.status, 404);
  });

  test('serves a byte-callback source with its declared MIME type', () async {
    server.register(
      'token-bytes',
      MediaSource.bytes(
        () async => sourceBytes.sublist(0, 10),
        contentType: 'audio/ogg',
      ),
    );

    final response = await fetch('/media/token-bytes');

    expect(response.status, 200);
    expect(response.body, sourceBytes.sublist(0, 10));
    expect(response.headers['content-type'], 'audio/ogg');
  });

  test('resolves URLs through tokens only and exposes the port', () {
    final uri = server.uriFor('token-1');

    expect(uri.scheme, 'http');
    expect(uri.port, server.port);
    expect(uri.pathSegments, <String>['media', 'token-1']);
  });

  test('expired tokens stop resolving', () async {
    final shortLived = MediaHttpServer(
      tokenTtl: const Duration(milliseconds: 30),
    );
    await shortLived.start();
    shortLived.register('short', MediaSource.file(mediaFile.path));
    final shortUri = Uri.parse(
      'http://127.0.0.1:${shortLived.port}/media/short',
    );

    final before = await client.getUrl(shortUri);
    final beforeResponse = await before.close();
    await beforeResponse.drain<void>();
    expect(beforeResponse.statusCode, 200);

    await Future<void>.delayed(const Duration(milliseconds: 80));

    final after = await client.getUrl(shortUri);
    final afterResponse = await after.close();
    await afterResponse.drain<void>();
    expect(afterResponse.statusCode, 404);
    await shortLived.stop();
  });

  test('evicts the oldest token when the registry is full', () async {
    final bounded = MediaHttpServer(maxEntries: 2);
    await bounded.start();
    bounded.register('a', MediaSource.file(mediaFile.path));
    bounded.register('b', MediaSource.file(mediaFile.path));
    bounded.register('c', MediaSource.file(mediaFile.path));

    Future<int> statusOf(String token) async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${bounded.port}/media/$token'),
      );
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    expect(await statusOf('a'), 404);
    expect(await statusOf('b'), 200);
    expect(await statusOf('c'), 200);
    await bounded.stop();
  });

  test('derives content types from file extensions', () {
    expect(MediaHttpServer.contentTypeFor('a.mp3'), 'audio/mpeg');
    expect(MediaHttpServer.contentTypeFor('a.FLAC'), 'audio/flac');
    expect(MediaHttpServer.contentTypeFor('a.m4a'), 'audio/mp4');
    expect(MediaHttpServer.contentTypeFor('no-extension'), 'application/octet-stream');
  });
}
