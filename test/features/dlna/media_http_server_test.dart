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

  test('returns 403 for an unknown token', () async {
    final response = await fetch('/media/missing-token');

    expect(response.status, 403);
  });

  test('returns 403 when the token is missing or the path is not a token', () async {
    final withoutToken = await fetch('/media');
    final extraSegment = await fetch('/media/token-1/extra');

    expect(withoutToken.status, 403);
    expect(extraSegment.status, 403);
  });

  test('rejects percent-encoded and raw traversal attempts', () async {
    for (final path in <String>[
      '/media/%2e%2e',
      '/media/..%2F..%2Fsecret.mp3',
      '/media/%2e%2e%2f%2e%2e%2ftrack.mp3',
      r'/media/..\track.mp3',
    ]) {
      final response = await fetch(path);
      expect(response.status, 403, reason: 'path $path must be rejected');
    }
  });

  test('rejects methods other than GET and HEAD with 405', () async {
    final response = await fetch('/media/token-1', method: 'POST');

    expect(response.status, 405);
    expect(response.headers['allow'], 'GET, HEAD');
  });

  test('serves only the first range of a multi-range request', () async {
    final response =
        await fetch('/media/token-1', range: 'bytes=0-9, 20-29, 40-49');

    expect(response.status, 206);
    expect(response.body, sourceBytes.sublist(0, 10));
    expect(response.headers['content-range'], 'bytes 0-9/1000');
    expect(response.headers['content-length'], '10');
  });

  test('creates cryptographically random 128-bit hex tokens', () {
    final first = MediaHttpServer.newToken();
    final second = MediaHttpServer.newToken();

    expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(second, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(first, isNot(second));
  });

  test('a generated token authenticates a request', () async {
    final token = MediaHttpServer.newToken();
    server.register(token, MediaSource.file(mediaFile.path));

    final response = await fetch('/media/$token');

    expect(response.status, 200);
    expect(response.body, sourceBytes);
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
    expect(afterResponse.statusCode, 403);
    await shortLived.stop();
  });

  test('stopping the server drops every registered token', () async {
    server.register('token-drop', MediaSource.file(mediaFile.path));
    await server.stop();
    await server.start();

    final response = await fetch('/media/token-drop');

    expect(response.status, 403);
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

    expect(await statusOf('a'), 403);
    expect(await statusOf('b'), 200);
    expect(await statusOf('c'), 200);
    await bounded.stop();
  });

  test('derives content types from file extensions', () {
    expect(MediaHttpServer.contentTypeFor('a.mp3'), 'audio/mpeg');
    expect(MediaHttpServer.contentTypeFor('a.FLAC'), 'audio/flac');
    expect(MediaHttpServer.contentTypeFor('a.m4a'), 'audio/mp4');
    expect(MediaHttpServer.contentTypeFor('a.opus'), 'audio/opus');
    expect(MediaHttpServer.contentTypeFor('a.dsf'), 'audio/x-dsf');
    expect(MediaHttpServer.contentTypeFor('a.dff'), 'audio/x-dff');
    expect(MediaHttpServer.contentTypeFor('a.ape'), 'audio/x-ape');
    expect(MediaHttpServer.contentTypeFor('a.wv'), 'audio/x-wavpack');
    expect(
      MediaHttpServer.contentTypeFor('no-extension'),
      'application/octet-stream',
    );
  });

  test('coalesces concurrent start calls and skips VPN/TUN interfaces when selecting LAN IPv4',
      () async {
    final raceServer = MediaHttpServer();
    addTearDown(raceServer.stop);
    await Future.wait(<Future<void>>[
      raceServer.start(),
      raceServer.start(),
    ]);
    expect(raceServer.isRunning, isTrue);
    expect(raceServer.port, isPositive);

    final picked = MediaHttpServer.selectPreferredIpv4(<({String name, List<InternetAddress> addresses})>[
      (name: 'tun0', addresses: <InternetAddress>[InternetAddress('10.8.0.2')]),
      (name: 'wg0', addresses: <InternetAddress>[InternetAddress('100.64.0.5')]),
      (name: 'wlan0', addresses: <InternetAddress>[InternetAddress('192.168.1.42')]),
    ]);
    expect(picked, '192.168.1.42');
  });
}
