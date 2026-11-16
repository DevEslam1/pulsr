// test/data/audio/sacd/sacd_iso_library_test.dart
//
// End-to-end open path over the synthetic fixture: probe -> index -> expand
// stereo tracks to cached DSF files -> re-open from cache -> source change.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/audio/dsd_header_probe.dart';
import 'package:pulsr/data/audio/sacd/sacd_dsf_cache.dart';
import 'package:pulsr/data/audio/sacd/sacd_dsf_extractor.dart';
import 'package:pulsr/data/audio/sacd/sacd_iso_library.dart';

import 'sacd_iso_fixture.dart';

void main() {
  late Directory temp;
  late Directory cacheDir;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pulsr_sacd_library');
    cacheDir = Directory('${temp.path}${Platform.pathSeparator}cache');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> writeIso(SacdIsoFixture fixture, String name) async {
    final file = File('${temp.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(fixture.bytes);
    return file;
  }

  SacdIsoLibrary library({SacdDsfCache? cache}) => SacdIsoLibrary(
        cache: cache ?? SacdDsfCache(directory: cacheDir),
      );

  test('expands every stereo track into a decodable DSF file', () async {
    final fixture = SacdIsoFixture();
    final iso = await writeIso(fixture, 'disc.iso');

    final opened = await library().openStereo(iso);

    expect(opened, hasLength(2));
    for (final entry in opened) {
      expect(entry.track.channels, 2);
      expect(entry.track.isTwoChannel, isTrue);
      expect(entry.file.existsSync(), isTrue);
      expect(await DsdHeaderProbe.probeMultiple(entry.file.path), 64);
      expect(await DsdHeaderProbe.probeBitsPerSample(entry.file.path), 8);
      final bytes = await entry.file.readAsBytes();
      final parsed = DsdDecoderHelper.parseDsfBytes(bytes);
      expect(parsed.msbFirst, isTrue);
      expect(parsed.dsdL, isNotEmpty);
      expect(parsed.dsdL.length, parsed.dsdR.length);
    }
    expect(opened[0].track.index, 1);
    expect(opened[1].track.index, 2);
  });

  test('can expand selected stereo tracks only', () async {
    final fixture = SacdIsoFixture();
    final iso = await writeIso(fixture, 'selected.iso');

    final opened = await library().openStereo(iso, trackNumbers: <int>{2});

    expect(opened, hasLength(1));
    expect(opened.single.track.index, 2);
    expect(
      cacheDir.listSync().whereType<File>(),
      hasLength(1),
      reason: 'unselected tracks must not be extracted',
    );
  });

  test('reuses complete cache entries on a second open', () async {
    final fixture = SacdIsoFixture();
    final iso = await writeIso(fixture, 'disc.iso');
    final lib = library();

    final first = await lib.openStereo(iso);
    final second = await lib.openStereo(iso);

    expect(second.map((entry) => entry.file.path),
        first.map((entry) => entry.file.path));
    expect(
      cacheDir.listSync().whereType<File>(),
      hasLength(2),
      reason: 'a unchanged image must not be extracted twice',
    );
  });

  test('re-extracts after the image changes and prunes the old revision',
      () async {
    final fixture = SacdIsoFixture();
    final iso = await writeIso(fixture, 'disc.iso');
    final lib = library();
    final first = await lib.openStereo(iso);

    await iso.writeAsBytes(
      Uint8List.fromList([...fixture.bytes, 0, 0, 0, 0]),
    );
    await iso.setLastModified(DateTime.now().add(const Duration(minutes: 1)));

    final second = await lib.openStereo(iso);

    expect(second.map((entry) => entry.file.path),
        isNot(first.map((entry) => entry.file.path)));
    for (final old in first) {
      expect(await old.file.exists(), isFalse,
          reason: 'a changed source must delete its stale extractions');
    }
    expect(cacheDir.listSync().whereType<File>(), hasLength(2));
  });

  test('rejects a multichannel-only image before writing anything', () async {
    final fixture = SacdIsoFixture(
      channels: 6,
      tocFileNames: const <String>['SACD_MCH.TOC'],
      areaFlags: 0x02,
    );
    final iso = await writeIso(fixture, 'mch.iso');

    await expectLater(
      library().openStereo(iso),
      throwsA(
        isA<SacdDsfException>().having(
          (error) => error.message,
          'message',
          contains('no stereo area'),
        ),
      ),
    );
    expect(
      cacheDir.existsSync()
          ? cacheDir.listSync().whereType<File>().where(
                (file) => file.path.endsWith('.dsf'),
              )
          : const <File>[],
      isEmpty,
      reason: 'a rejected multichannel image must not be extracted',
    );
  });

  test('fails cleanly when the cache budget cannot hold a track', () async {
    final fixture = SacdIsoFixture();
    final iso = await writeIso(fixture, 'disc.iso');

    await expectLater(
      library(cache: SacdDsfCache(directory: cacheDir, byteBudget: 100))
          .openStereo(iso),
      throwsA(isA<SacdDsfException>()),
    );
    expect(
      cacheDir.existsSync()
          ? cacheDir.listSync().whereType<File>().where(
                (file) => file.path.endsWith('.dsf'),
              )
          : const <File>[],
      isEmpty,
    );
  });

  test('reports an unreadable image instead of guessing', () async {
    final iso = File('${temp.path}${Platform.pathSeparator}junk.iso');
    await iso.writeAsBytes(Uint8List(20 * fixtureSectorSize));

    await expectLater(
      library().isSacdImage(iso.path),
      completion(isFalse),
    );
    await expectLater(
      library().openStereo(iso),
      throwsA(isA<Exception>()),
    );
  });
}
