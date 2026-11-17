// Regression test for P1-2.2: eviction follows last ACCESS, not insertion
// order, the TTL refreshes on access, and an entry a renderer read in the last
// two minutes is never evicted (a long track kept streaming).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/dlna/media_http_server.dart';

void main() {
  late Directory tempDir;
  late File mediaFile;
  late HttpClient client;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_media_http_lru');
    mediaFile = File('${tempDir.path}/track.mp3');
    await mediaFile.writeAsBytes(List<int>.generate(2048, (index) => index % 251));
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> fetch(MediaHttpServer server, String token) async {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/media/$token'),
    );
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  }

  test('an actively read token survives 32 later registrations', () async {
    final server = MediaHttpServer(maxEntries: 32);
    await server.start();
    addTearDown(server.stop);

    server.register('active', MediaSource.file(mediaFile.path));
    expect(await fetch(server, 'active'), 200);

    for (var index = 0; index < 33; index++) {
      server.register('token$index', MediaSource.file(mediaFile.path));
    }

    expect(await fetch(server, 'active'), 200,
        reason: 'a token read in the last two minutes must not be evicted');
    // The cap still holds for the never-read tokens.
    expect(await fetch(server, 'token0'), 403);
    expect(await fetch(server, 'token32'), 200);
  });

  test('access order decides eviction, not registration order', () async {
    final server = MediaHttpServer(maxEntries: 2);
    await server.start();
    addTearDown(server.stop);

    server.register('first', MediaSource.file(mediaFile.path));
    server.register('second', MediaSource.file(mediaFile.path));
    // Read the older token so it becomes the freshest one.
    expect(await fetch(server, 'first'), 200);

    server.register('third', MediaSource.file(mediaFile.path));

    expect(await fetch(server, 'second'), 403,
        reason: 'the least recently read token is the one evicted');
    expect(await fetch(server, 'first'), 200);
    expect(await fetch(server, 'third'), 200);
  });

  test('reading a token refreshes its TTL', () async {
    final server = MediaHttpServer(
      maxEntries: 4,
      tokenTtl: const Duration(milliseconds: 120),
    );
    await server.start();
    addTearDown(server.stop);

    server.register('short', MediaSource.file(mediaFile.path));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    // Halfway through the TTL: this read must extend it.
    expect(await fetch(server, 'short'), 200);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(await fetch(server, 'short'), 200,
        reason: 'the TTL was refreshed by the read at 80 ms');

    // Without another read it still expires on the new deadline.
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(await fetch(server, 'short'), 403);
  });

  test('a never-read token is evicted by registration order', () async {
    final server = MediaHttpServer(maxEntries: 2);
    await server.start();
    addTearDown(server.stop);

    server.register('a', MediaSource.file(mediaFile.path));
    server.register('b', MediaSource.file(mediaFile.path));
    server.register('c', MediaSource.file(mediaFile.path));

    expect(await fetch(server, 'a'), 403);
    expect(await fetch(server, 'b'), 200);
    expect(await fetch(server, 'c'), 200);
  });
}
