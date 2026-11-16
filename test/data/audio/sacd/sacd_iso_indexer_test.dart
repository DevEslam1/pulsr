// test/data/audio/sacd/sacd_iso_indexer_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/sacd/iso9660_reader.dart';
import 'package:pulsr/data/audio/sacd/sacd_iso_indexer.dart';
import 'package:pulsr/data/audio/sacd/sacd_toc.dart';

import 'sacd_iso_fixture.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pulsr_sacd_index');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> writeIso(String name, List<int> bytes) async {
    final file = File('${temp.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  test('indexes the preferred two-channel area', () async {
    final fixture = SacdIsoFixture();
    final iso = await writeIso('disc.iso', fixture.bytes);
    final indexer = SacdIsoIndexer();

    final tracks = await indexer.index(iso);
    expect(tracks, hasLength(2));
    expect(tracks.first.channels, 2);
    expect(tracks.first.isTwoChannel, isTrue);
    expect(tracks.first.startSector, fixture.dataSector);
    expect(tracks.first.durationSeconds, 5);

    final index = await indexer.indexIso(iso);
    expect(
      index.areas.map((area) => area.fileName),
      <String>['SACD_2CH.TOC', 'SACD_MCH.TOC'],
    );
    expect(index.preferred!.area, SacdAreaKind.twoChannel);
    expect(index.imageLengthSectors, fixture.bytes.length ~/ fixtureSectorSize);
  });

  test('serves repeated lookups from the cache', () async {
    final fixture = SacdIsoFixture();
    final iso = await writeIso('disc.iso', fixture.bytes);
    final indexer = SacdIsoIndexer();

    final first = await indexer.indexIso(iso);
    final second = await indexer.indexIso(iso);
    expect(identical(first, second), isTrue);
    expect(indexer.cachedImageCount, 1);

    indexer.clearCache();
    expect(indexer.cachedImageCount, 0);
  });

  test('evicts the oldest image once the cache is full', () async {
    final fixture = SacdIsoFixture();
    final indexer = SacdIsoIndexer();

    final files = <File>[];
    for (var i = 0; i < 5; i++) {
      files.add(await writeIso('disc$i.iso', fixture.bytes));
    }
    for (final file in files) {
      expect(await indexer.index(file), hasLength(2));
      expect(indexer.cachedImageCount, lessThanOrEqualTo(4));
    }
    expect(indexer.cachedImageCount, 4);

    // Touching the newest entry again keeps it and evicts the oldest.
    await indexer.indexIso(files.last);
    expect(indexer.cachedImageCount, 4);
  });

  test('drops a cached entry when the image changes on disk', () async {
    final fixture = SacdIsoFixture();
    final iso = await writeIso('disc.iso', fixture.bytes);
    final indexer = SacdIsoIndexer();

    await indexer.index(iso);
    await iso.writeAsBytes(Uint8List(64));
    expect(indexer.index(iso), throwsA(isA<IsoFormatException>()));
    expect(indexer.cachedImageCount, 1);
  });

  test('rejects a missing image', () async {
    final indexer = SacdIsoIndexer();
    final path = '${temp.path}${Platform.pathSeparator}absent.iso';
    expect(indexer.index(File(path)), throwsA(isA<IsoFormatException>()));
  });

  test('exposes only the stereo area for playback', () async {
    final fixture = SacdIsoFixture();
    final iso = await writeIso('disc.iso', fixture.bytes);
    final index = await SacdIsoIndexer().indexIso(iso);

    expect(index.stereoToc, isNotNull);
    expect(index.stereoToc!.fileName, 'SACD_2CH.TOC');
    expect(index.stereoTracks, hasLength(2));
    expect(index.stereoTracks.every((track) => track.channels == 2), isTrue);
    expect(index.hasOnlyMultichannel, isFalse);
  });

  test('an image with only a multichannel area has no stereo tracks', () async {
    final fixture = SacdIsoFixture(
      channels: 6,
      tocFileNames: const <String>['SACD_MCH.TOC'],
      areaFlags: 0x02,
    );
    final iso = await writeIso('mch.iso', fixture.bytes);
    final index = await SacdIsoIndexer().indexIso(iso);

    expect(index.preferred!.channels, 6);
    expect(index.stereoToc, isNull);
    expect(index.stereoTracks, isEmpty);
    expect(index.hasOnlyMultichannel, isTrue);
  });

  test('rejects an ISO without a SACD directory', () async {
    final fixture = SacdIsoFixture(includeSacdDirectory: false);
    final iso = await writeIso('plain.iso', fixture.bytes);
    final indexer = SacdIsoIndexer();
    expect(indexer.index(iso), throwsA(isA<IsoFormatException>()));
  });

  test('rejects an ISO whose SACD directory holds no TOC', () async {
    final fixture = SacdIsoFixture(tocFileNames: const <String>[]);
    final iso = await writeIso('notoc.iso', fixture.bytes);
    final indexer = SacdIsoIndexer();
    expect(indexer.index(iso), throwsA(isA<SacdTocError>()));
  });

  test('rejects TOC files that do not match the assumed layout', () async {
    final fixture = SacdIsoFixture();
    final bytes = Uint8List.fromList(fixture.bytes);
    for (final sector in fixture.tocSectors.values) {
      bytes[sector * fixtureSectorSize] = 0x58; // break the "SACD" tag
    }
    final iso = await writeIso('garbage.iso', bytes);
    final indexer = SacdIsoIndexer();
    expect(indexer.index(iso), throwsA(isA<SacdTocError>()));
    expect(indexer.cachedImageCount, 0);
  });
}
