// test/data/audio/sacd/sacd_dsf_cache_test.dart
//
// Cache naming, janitor, eviction, source-change pruning and partial-file
// validation for extracted SACD DSF tracks.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/sacd/sacd_dsf_cache.dart';
import 'package:pulsr/data/audio/sacd/sacd_dsf_extractor.dart';
import 'package:pulsr/data/audio/sacd/sacd_toc.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pulsr_sacd_cache');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  SacdTrack track(int index) => SacdTrack(
        index: index,
        startSector: 100 + index,
        lengthSectors: 2,
        durationSeconds: 5,
        channels: 2,
        isTwoChannel: true,
        dsdRateMultiplier: 64,
      );

  Future<File> writeCacheFile(
    String imagePath,
    int modifiedUs,
    int index,
    int size, {
    DateTime? modified,
  }) async {
    final file = SacdDsfCache.trackFileFor(
      directory: temp,
      imagePath: imagePath,
      imageModifiedUs: modifiedUs,
      track: track(index),
      sectorHeaderBytes: 12,
      blockSizePerChannel: 4096,
      reverseBits: false,
    );
    await file.writeAsBytes(List<int>.filled(size, 0x11));
    if (modified != null) {
      await file.setLastModified(modified);
    }
    return file;
  }

  test('names entries from image path, mtime, track and parameters', () {
    final a = SacdDsfCache.trackFileFor(
      directory: temp,
      imagePath: 'D:/discs/a.iso',
      imageModifiedUs: 1000,
      track: track(1),
      sectorHeaderBytes: 12,
      blockSizePerChannel: 4096,
      reverseBits: false,
    );
    final b = SacdDsfCache.trackFileFor(
      directory: temp,
      imagePath: 'D:/discs/b.iso',
      imageModifiedUs: 1000,
      track: track(1),
      sectorHeaderBytes: 12,
      blockSizePerChannel: 4096,
      reverseBits: false,
    );
    final c = SacdDsfCache.trackFileFor(
      directory: temp,
      imagePath: 'D:/discs/a.iso',
      imageModifiedUs: 2000,
      track: track(1),
      sectorHeaderBytes: 12,
      blockSizePerChannel: 4096,
      reverseBits: false,
    );
    final d = SacdDsfCache.trackFileFor(
      directory: temp,
      imagePath: 'D:/discs/a.iso',
      imageModifiedUs: 1000,
      track: track(2),
      sectorHeaderBytes: 12,
      blockSizePerChannel: 4096,
      reverseBits: false,
    );
    expect(<String>{a.path, b.path, c.path, d.path}, hasLength(4));
  });

  test('janitor deletes expired entries', () async {
    final cache = SacdDsfCache(
      directory: temp,
      maxAge: const Duration(days: 1),
      clock: () => DateTime(2026, 1, 10),
    );
    final fresh = await writeCacheFile(
      'D:/a.iso',
      1,
      1,
      1024,
      modified: DateTime(2026, 1, 9, 23),
    );
    final stale = await writeCacheFile(
      'D:/a.iso',
      1,
      2,
      1024,
      modified: DateTime(2025, 12, 1),
    );

    await cache.runJanitor();

    expect(await fresh.exists(), isTrue);
    expect(await stale.exists(), isFalse);
  });

  test('janitor enforces the byte budget oldest-first', () async {
    final cache = SacdDsfCache(
      directory: temp,
      byteBudget: 2500,
      maxAge: const Duration(days: 30),
      clock: () => DateTime(2026, 1, 5),
    );
    final oldest = await writeCacheFile(
      'D:/a.iso',
      1,
      1,
      1000,
      modified: DateTime(2026, 1, 1),
    );
    final middle = await writeCacheFile(
      'D:/b.iso',
      1,
      1,
      1000,
      modified: DateTime(2026, 1, 2),
    );
    final newest = await writeCacheFile(
      'D:/c.iso',
      1,
      1,
      1000,
      modified: DateTime(2026, 1, 3),
    );

    await cache.runJanitor();

    expect(await oldest.exists(), isFalse);
    expect(await middle.exists(), isTrue);
    expect(await newest.exists(), isTrue);
    final total = (await temp.list().toList())
        .whereType<File>()
        .fold<int>(0, (sum, file) => sum + file.lengthSync());
    expect(total, lessThanOrEqualTo(2500));
  });

  test('deletes stale revisions when the source image changes', () async {
    final image = File('${temp.path}${Platform.pathSeparator}disc.iso');
    await image.writeAsBytes(<int>[1, 2, 3]);
    var stat = await image.stat();
    final oldTrack = await writeCacheFile(
      image.path,
      stat.modified.microsecondsSinceEpoch,
      1,
      500,
    );
    final otherDisc = await writeCacheFile('D:/other.iso', 1, 1, 500);
    final currentStat = await image.stat();

    final cache = SacdDsfCache(directory: temp);
    await cache.pruneSource(image, currentStat);
    expect(await oldTrack.exists(), isTrue,
        reason: 'the current revision must survive pruning');

    // A different image content gets a new mtime; the old revision is pruned.
    await image.writeAsBytes(<int>[9, 9, 9, 9]);
    await image.setLastModified(DateTime.now().add(const Duration(minutes: 1)));
    stat = await image.stat();
    final newTrack = await writeCacheFile(
      image.path,
      stat.modified.microsecondsSinceEpoch,
      1,
      500,
    );

    await cache.pruneSource(image, stat);

    expect(await oldTrack.exists(), isFalse);
    expect(await newTrack.exists(), isTrue);
    expect(await otherDisc.exists(), isTrue);
  });

  test('ensureRoom evicts other images but keeps the current source', () async {
    final cache = SacdDsfCache(directory: temp, byteBudget: 2000);
    final mine = await writeCacheFile(
      'D:/mine.iso',
      1,
      1,
      1000,
      modified: DateTime(2026, 1, 1),
    );
    final other = await writeCacheFile(
      'D:/other.iso',
      1,
      1,
      1500,
      modified: DateTime(2026, 1, 2),
    );

    await cache.ensureRoom(1000, keepSourcePath: 'D:/mine.iso');

    expect(await mine.exists(), isTrue);
    expect(await other.exists(), isFalse);
  });

  test('ensureRoom fails cleanly when the request exceeds the budget',
      () async {
    final cache = SacdDsfCache(directory: temp, byteBudget: 1024);
    await expectLater(
      cache.ensureRoom(2048, keepSourcePath: 'D:/mine.iso'),
      throwsA(isA<SacdDsfException>()),
    );
  });

  test('a failing free-space probe fails the room check cleanly', () async {
    final cache = SacdDsfCache(
      directory: temp,
      byteBudget: 4096,
      freeSpaceProbe: (_) async => 10,
    );
    await expectLater(
      cache.ensureRoom(2048, keepSourcePath: 'D:/mine.iso'),
      throwsA(isA<SacdDsfException>()),
    );
  });

  test('a missing probe is not required: room checks still succeed', () async {
    final cache = SacdDsfCache(directory: temp, byteBudget: 4096);
    await cache.ensureRoom(2048, keepSourcePath: 'D:/mine.iso');
  });

  test('isReusable deletes short (partial) files and keeps complete ones',
      () async {
    final cache = SacdDsfCache(directory: temp);
    final file = await writeCacheFile('D:/a.iso', 1, 1, 100);

    expect(await cache.isReusable(file, 200), isFalse);
    expect(await file.exists(), isFalse);

    await file.writeAsBytes(List<int>.filled(200, 0x22));
    expect(await cache.isReusable(file, 200), isTrue);
    expect(await file.exists(), isTrue);
  });
}
