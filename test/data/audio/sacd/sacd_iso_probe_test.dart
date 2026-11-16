// test/data/audio/sacd/sacd_iso_probe_test.dart

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/sacd/sacd_iso_probe.dart';

import 'sacd_iso_fixture.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pulsr_sacd_probe');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> writeImage(String name, List<int> bytes) async {
    final file = File('${temp.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  test('accepts an image that exposes a SACD area directory', () async {
    final file = await writeImage('disc.iso', SacdIsoFixture().bytes);
    expect(await isSacdIso(file.path), isTrue);
  });

  test('matches the extension case-insensitively', () async {
    final file = await writeImage('DISC.ISO', SacdIsoFixture().bytes);
    expect(await isSacdIso(file.path), isTrue);
  });

  test('rejects a SACD image under a non-iso extension', () async {
    final file = await writeImage('disc.bin', SacdIsoFixture().bytes);
    expect(await isSacdIso(file.path), isFalse);
  });

  test('rejects an ISO without a volume descriptor', () async {
    final file =
        await writeImage('blank.iso', Uint8List(20 * fixtureSectorSize));
    expect(await isSacdIso(file.path), isFalse);
  });

  test('rejects an ISO without a SACD directory', () async {
    final file = await writeImage(
      'plain.iso',
      SacdIsoFixture(includeSacdDirectory: false).bytes,
    );
    expect(await isSacdIso(file.path), isFalse);
  });

  test('rejects an ISO whose SACD directory has no TOC file', () async {
    final file = await writeImage(
      'notoc.iso',
      SacdIsoFixture(tocFileNames: const <String>[]).bytes,
    );
    expect(await isSacdIso(file.path), isFalse);
  });

  test('rejects a truncated image', () async {
    final fixture = SacdIsoFixture();
    final file = await writeImage(
      'cut.iso',
      Uint8List.sublistView(fixture.bytes, 0, 8 * fixtureSectorSize),
    );
    expect(await isSacdIso(file.path), isFalse);
  });

  test('rejects a missing file and an empty path', () async {
    final path = '${temp.path}${Platform.pathSeparator}missing.iso';
    expect(await isSacdIso(path), isFalse);
    expect(await isSacdIso(''), isFalse);
  });

  test('never throws on truncated or mutated images', () async {
    final fixture = SacdIsoFixture();
    final random = Random(777);
    for (var round = 0; round < 40; round++) {
      final cut =
          round.isEven ? random.nextInt(fixture.bytes.length + 1) : fixture.bytes.length;
      final mutated = Uint8List.fromList(
        Uint8List.sublistView(fixture.bytes, 0, cut),
      );
      final mutations = 1 + random.nextInt(6);
      if (mutated.isNotEmpty) {
        for (var i = 0; i < mutations; i++) {
          mutated[random.nextInt(mutated.length)] = random.nextInt(256);
        }
      }
      final file = await writeImage('fuzz$round.iso', mutated);
      expect(await isSacdIso(file.path), isA<bool>(),
          reason: 'round $round must return a bool, never throw');
    }

    // Purely random garbage under the .iso extension.
    for (var round = 0; round < 10; round++) {
      final garbage =
          Uint8List.fromList(List<int>.generate(4096, (_) => random.nextInt(256)));
      final file = await writeImage('garbage$round.iso', garbage);
      expect(await isSacdIso(file.path), isFalse);
    }
  });
}
