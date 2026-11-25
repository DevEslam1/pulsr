// P0-1 remote sources: LRU disk cache, atomic writes and single-flight fetch.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pulsr/features/remote_sources/remote_cache_store.dart';

void main() {
  late Directory tempDir;
  late DateTime now;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_remote_cache_test');
    now = DateTime(2024, 1, 1, 12);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  RemoteCacheStore buildStore({int maxBytes = 4096, int? maxEntryBytes}) {
    return RemoteCacheStore(
      directoryProvider: () async => tempDir,
      clock: () => now,
      maxBytes: maxBytes,
      maxEntryBytes: maxEntryBytes,
    );
  }

  List<String> fileNames() {
    if (!tempDir.existsSync()) return const [];
    return tempDir
        .listSync()
        .whereType<File>()
        .map((file) => p.basename(file.path))
        .toList(growable: false);
  }

  test('store then lookup returns the exact bytes', () async {
    final store = buildStore();
    final payload = utf8.encode('audio-bytes');

    final file = await store.store('src', 'Music/a.mp3', Stream.value(payload));

    expect(file, isNotNull);
    expect(await file!.readAsBytes(), payload);
    expect(await store.contains('src', 'Music/a.mp3'), isTrue);
    expect(await store.currentBytes(), payload.length);
    final looked = await store.lookup('src', 'Music/a.mp3');
    expect(await looked!.readAsBytes(), payload);
  });

  test('writes land through a partial file that is renamed away', () async {
    final store = buildStore();

    await store.store('src', 'a.mp3', Stream.value(utf8.encode('chunk')));

    final names = fileNames();
    expect(names.any((name) => name.endsWith(RemoteCacheStore.partialSuffix)),
        isFalse,
        reason: 'a committed entry must not leave a .partial behind');
    expect(names, contains(RemoteCacheStore.indexFileName));
    expect(names.where((name) => name.endsWith('.bin')), hasLength(1));
  });

  test('least-recently-used entries are evicted past the cap', () async {
    final store = buildStore(maxBytes: 100);

    await store.store('src', 'first', Stream.value(List<int>.filled(40, 1)));
    now = now.add(const Duration(minutes: 1));
    await store.store('src', 'second', Stream.value(List<int>.filled(40, 2)));
    now = now.add(const Duration(minutes: 1));
    await store.store('src', 'third', Stream.value(List<int>.filled(40, 3)));

    expect(await store.contains('src', 'first'), isFalse);
    expect(await store.contains('src', 'second'), isTrue);
    expect(await store.contains('src', 'third'), isTrue);
    expect(await store.currentBytes(), lessThanOrEqualTo(100));
  });

  test('a pinned entry survives eviction', () async {
    final store = buildStore(maxBytes: 100);

    await store.store(
      'src',
      'important',
      Stream.value(List<int>.filled(40, 1)),
      pin: true,
    );
    now = now.add(const Duration(minutes: 1));
    await store.store('src', 'second', Stream.value(List<int>.filled(40, 2)));
    now = now.add(const Duration(minutes: 1));
    await store.store('src', 'third', Stream.value(List<int>.filled(40, 3)));

    expect(await store.contains('src', 'important'), isTrue);
    expect(await store.contains('src', 'third'), isTrue);
  });

  test('an entry larger than the per-entry limit is not cached', () async {
    final store = buildStore(maxBytes: 4096, maxEntryBytes: 32);

    final file = await store.store(
      'src',
      'huge.flac',
      Stream.value(List<int>.filled(64, 7)),
    );

    expect(file, isNull);
    expect(await store.contains('src', 'huge.flac'), isFalse);
    expect(await store.currentBytes(), 0);
    expect(
      fileNames()
          .where((name) => name.endsWith(RemoteCacheStore.partialSuffix)),
      isEmpty,
    );
  });

  test('concurrent fetches for one key download once', () async {
    final store = buildStore();
    final controller = StreamController<List<int>>();
    var opens = 0;

    Stream<List<int>> open() {
      opens++;
      return controller.stream;
    }

    final first = store.fetch('src', 'a.mp3', openStream: open);
    final second = store.fetch('src', 'a.mp3', openStream: open);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.add(utf8.encode('shared'));
    await controller.close();

    final results = await Future.wait([first, second]);
    expect(opens, 1);
    expect(results.first, isNotNull);
    expect(await results.first!.readAsBytes(), utf8.encode('shared'));
    expect(results.last!.path, results.first!.path);
  });

  test('the index is rebuilt from disk by a new instance', () async {
    final first = buildStore();
    await first.store('src', 'a.mp3', Stream.value(utf8.encode('persisted')));
    final expectedBytes = await first.currentBytes();

    final second = buildStore();
    final file = await second.lookup('src', 'a.mp3');

    expect(file, isNotNull);
    expect(await file!.readAsBytes(), utf8.encode('persisted'));
    expect(await second.currentBytes(), expectedBytes);
  });

  test('clear removes every cached file', () async {
    final store = buildStore();
    await store.store('src', 'a.mp3', Stream.value(utf8.encode('one')));
    await store.store('other', 'b.mp3', Stream.value(utf8.encode('two')));

    await store.clear();

    expect(await store.currentBytes(), 0);
    expect(await store.contains('src', 'a.mp3'), isFalse);
    expect(fileNames(), isEmpty);
  });

  test('removeSource deletes only that source', () async {
    final store = buildStore();
    await store.store('src', 'a.mp3', Stream.value(utf8.encode('one')));
    await store.store('other', 'b.mp3', Stream.value(utf8.encode('two')));

    await store.removeSource('src');

    expect(await store.contains('src', 'a.mp3'), isFalse);
    expect(await store.contains('other', 'b.mp3'), isTrue);
  });

  test('a leftover partial file is cleaned on the next start', () async {
    final stale = File(p.join(tempDir.path, 'stale.bin.partial'));
    await stale.writeAsBytes(List<int>.filled(10, 0));

    final store = buildStore();
    await store.ensureInitialized();

    expect(await stale.exists(), isFalse);
    expect(await store.currentBytes(), 0);
  });

  test('a matching etag is served and a changed one invalidates the entry',
      () async {
    final store = buildStore();
    await store.store(
      'src',
      'a.mp3',
      Stream.value(utf8.encode('one')),
      etag: '"v1"',
    );

    expect(await store.lookup('src', 'a.mp3', etag: '"v1"'), isNotNull);
    expect(await store.lookup('src', 'a.mp3', etag: '"v2"'), isNull);
    expect(await store.contains('src', 'a.mp3'), isFalse,
        reason: 'the stale entry must be deleted, not just hidden');
    expect(await store.currentBytes(), 0);
  });

  test('a changed modification time invalidates, same second still hits',
      () async {
    final store = buildStore();
    final modified = DateTime.utc(2024, 1, 1, 12, 0, 0);
    await store.store(
      'src',
      'a.mp3',
      Stream.value(utf8.encode('one')),
      modifiedAt: modified,
    );

    expect(
      await store.lookup(
        'src',
        'a.mp3',
        modifiedAt: modified.add(const Duration(milliseconds: 400)),
      ),
      isNotNull,
      reason: 'HTTP/FTP timestamps only carry second precision',
    );
    expect(
      await store.lookup(
        'src',
        'a.mp3',
        modifiedAt: modified.add(const Duration(seconds: 2)),
      ),
      isNull,
    );
  });

  test('validators survive an index reload', () async {
    final first = buildStore();
    await first.store(
      'src',
      'a.mp3',
      Stream.value(utf8.encode('one')),
      etag: 'v1',
      modifiedAt: DateTime.utc(2024, 1, 1),
    );

    final matching = buildStore();
    expect(
      await matching.lookup(
        'src',
        'a.mp3',
        etag: 'v1',
        modifiedAt: DateTime.utc(2024, 1, 1),
      ),
      isNotNull,
    );

    final changed = buildStore();
    expect(await changed.lookup('src', 'a.mp3', etag: 'v2'), isNull);
  });

  test('pin before commit marks the committed entry as pinned', () async {
    final store = buildStore(maxBytes: 10);
    await store.pin('src', 'keep.mp3');
    final sink = await store.beginWrite('src', 'keep.mp3');
    sink.add(List<int>.filled(6, 1));
    await sink.commit();

    // Writing another 6 bytes pushes over maxBytes (10); the unpinned one
    // cannot be evicted because keep.mp3 was pinned before its write finished.
    await store.store('src', 'other.mp3', Stream.value(List<int>.filled(6, 2)));

    expect(await store.contains('src', 'keep.mp3'), isTrue);
  });

  test('pinSource unpinning evicts unpinned entries above cap', () async {
    final store = buildStore(maxBytes: 8);
    await store.store(
      'src',
      'a.mp3',
      Stream.value(List<int>.filled(6, 1)),
      pin: true,
    );
    await store.store(
      'src',
      'b.mp3',
      Stream.value(List<int>.filled(6, 2)),
      pin: true,
    );
    expect(await store.currentBytes(), 12);

    await store.pinSource('src', pinned: false);
    expect(await store.currentBytes(), lessThanOrEqualTo(8));
  });

  test('clear aborts active sinks and blocks old commits from resurrecting',
      () async {
    final store = buildStore();
    final sink = await store.beginWrite('src', 'inprogress.mp3');
    sink.add(utf8.encode('partial'));

    await store.clear();

    expect(await sink.commit(), isNull);
    expect(await store.contains('src', 'inprogress.mp3'), isFalse);
    expect(await tempDir.list().toList(), isEmpty);
  });
}
