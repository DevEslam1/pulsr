// Regression test for P0-1.4: two concurrent downloads of the same cache key
// must not share a partial file. They used to open the same
// `<digest>.bin.partial`, so the second writer deleted the first one's file and
// their bytes interleaved; one commit then renamed the mixed file into place.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pulsr/features/remote_sources/remote_cache_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_remote_collision');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  RemoteCacheStore buildStore() => RemoteCacheStore(
        directoryProvider: () async => tempDir,
        clock: () => DateTime(2024, 1, 1, 12),
        maxBytes: 8 * 1024 * 1024,
      );

  /// Emits [chunks] blocks of 1024 bytes with a yield between them so two
  /// concurrent writes interleave when they share a file.
  Stream<List<int>> slowPayload(int byte, int chunks) async* {
    for (var i = 0; i < chunks; i++) {
      yield List<int>.filled(1024, byte);
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<String> fileNames() => tempDir
      .listSync()
      .whereType<File>()
      .map((file) => p.basename(file.path))
      .toList(growable: false);

  Map<String, dynamic> readIndex() {
    final indexFile = File(p.join(tempDir.path, RemoteCacheStore.indexFileName));
    expect(indexFile.existsSync(), isTrue);
    return jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
  }

  test('two concurrent downloads of one key keep one intact entry', () async {
    final store = buildStore();
    const chunks = 8;
    const expectedBytes = chunks * 1024;

    final results = await Future.wait([
      store.store('src', 'Music/track.flac', slowPayload(0x41, chunks)),
      store.store('src', 'Music/track.flac', slowPayload(0x42, chunks)),
    ]);

    // Both commits are allowed to succeed; the last one wins the index.
    expect(results.whereType<File>(), isNotEmpty);

    final cached = await store.lookup('src', 'Music/track.flac');
    expect(cached, isNotNull);
    final bytes = await cached!.readAsBytes();
    expect(bytes.length, expectedBytes,
        reason: 'the final file must be one complete payload, not a mix');
    final first = bytes.first;
    expect(bytes.every((value) => value == first), isTrue,
        reason: 'bytes from the two writers must never interleave');

    final entries = readIndex()['entries'] as Map<String, dynamic>;
    expect(entries, hasLength(1));
    expect(await store.currentBytes(), expectedBytes);

    expect(
      fileNames().where((name) => name.endsWith(RemoteCacheStore.partialSuffix)),
      isEmpty,
      reason: 'neither writer may leave a .partial behind',
    );
    expect(fileNames().where((name) => name.endsWith('.bin')), hasLength(1));
  });

  test('aborting one writer leaves the other writer intact', () async {
    final store = buildStore();

    final kept = await store.beginWrite('src', 'keep.flac');
    final dropped = await store.beginWrite('src', 'keep.flac');

    kept.add(List<int>.filled(2048, 0x11));
    dropped.add(List<int>.filled(2048, 0x22));

    await dropped.abort();
    final committed = await kept.commit();

    expect(committed, isNotNull);
    final bytes = await committed!.readAsBytes();
    expect(bytes.length, 2048);
    expect(bytes.every((value) => value == 0x11), isTrue);
    expect(
      fileNames().where((name) => name.endsWith(RemoteCacheStore.partialSuffix)),
      isEmpty,
      reason: 'abort deletes only its own partial file',
    );
  });

  test('concurrent commits of different keys do not lose index rows', () async {
    final store = buildStore();

    await Future.wait([
      for (var i = 0; i < 6; i++)
        store.store('src', 'file-$i.flac', slowPayload(0x30 + i, 2)),
    ]);

    final entries = readIndex()['entries'] as Map<String, dynamic>;
    expect(entries, hasLength(6));
    for (var i = 0; i < 6; i++) {
      expect(await store.contains('src', 'file-$i.flac'), isTrue);
    }
  });
}
