// test/data/audio/sacd/iso9660_reader_test.dart

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/sacd/iso9660_reader.dart';

import 'sacd_iso_fixture.dart';

void main() {
  final fixture = SacdIsoFixture();

  group('Iso9660Reader', () {
    test('resolves the root directory and lists its children', () async {
      final reader = await Iso9660Reader.fromBytes(fixture.bytes);
      addTearDown(reader.close);

      expect(reader.root.isDirectory, isTrue);
      expect(reader.fileLength, fixture.bytes.length);
      final entries = await reader.list(reader.root);
      final names = entries.map((entry) => entry.name).toList();
      expect(names, containsAll(<String>['SACD', 'README.TXT']));
      expect(
        entries.firstWhere((entry) => entry.name == 'SACD').isDirectory,
        isTrue,
      );
      expect(
        entries.firstWhere((entry) => entry.name == 'README.TXT').sizeBytes,
        SacdIsoFixture.readmeText.length,
      );
    });

    test('looks up nested paths case-insensitively', () async {
      final reader = await Iso9660Reader.fromBytes(fixture.bytes);
      addTearDown(reader.close);

      final area = await reader.lookupPath('sacd');
      expect(area, isNotNull);
      expect(area!.isDirectory, isTrue);

      final toc = await reader.lookupPath('SACD/sacd_2ch.toc');
      expect(toc, isNotNull);
      expect(toc!.sizeBytes, fixture.tocFiles['SACD_2CH.TOC']!.length);
      final tocBytes = await reader.readFile(toc);
      expect(tocBytes, equals(fixture.tocFiles['SACD_2CH.TOC']));

      expect(await reader.lookupPath('SACD/MISSING.TOC'), isNull);
      expect(await reader.lookupPath('NOT_THERE'), isNull);
      expect(await reader.lookupPath('README.TXT/CHILD'), isNull);
    });

    test('reads a file extent and strips the ISO version suffix', () async {
      final reader = await Iso9660Reader.fromBytes(fixture.bytes);
      addTearDown(reader.close);

      final readme = await reader.lookupPath('README.TXT');
      expect(readme, isNotNull);
      expect(readme!.isoName, 'README.TXT');
      final text = String.fromCharCodes(await reader.readFile(readme));
      expect(text, SacdIsoFixture.readmeText);
    });

    test('surfaces Rock Ridge NM names', () async {
      final reader = await Iso9660Reader.fromBytes(fixture.bytes);
      addTearDown(reader.close);
      final area = await reader.lookupPath('SACD');
      final children = await reader.list(area!);
      final rockRidge = children.firstWhere(
        (entry) => entry.name == SacdIsoFixture.rockRidgeName,
      );
      expect(rockRidge.isoName, 'OBJ_0001.DSF');

      final plain = SacdIsoFixture(includeRockRidge: false);
      final plainReader = await Iso9660Reader.fromBytes(plain.bytes);
      addTearDown(plainReader.close);
      final plainArea = await plainReader.lookupPath('SACD');
      final plainChildren = await plainReader.list(plainArea!);
      expect(
        plainChildren.map((entry) => entry.name),
        isNot(contains(SacdIsoFixture.rockRidgeName)),
      );
    });

    test('rejects listing a file and reading a directory', () async {
      final reader = await Iso9660Reader.fromBytes(fixture.bytes);
      addTearDown(reader.close);

      final area = await reader.lookupPath('SACD');
      expect(reader.readFile(area!), throwsA(isA<IsoFormatException>()));

      final readme = await reader.lookupPath('README.TXT');
      expect(reader.list(readme!), throwsA(isA<IsoFormatException>()));
    });

    test('rejects a truncated image and a bad descriptor magic', () async {
      expect(
        Iso9660Reader.fromBytes(Uint8List(0)),
        throwsA(isA<IsoFormatException>()),
      );
      final truncated = Uint8List.sublistView(
        fixture.bytes,
        0,
        16 * fixtureSectorSize + 512,
      );
      expect(
        Iso9660Reader.fromBytes(truncated),
        throwsA(isA<IsoFormatException>()),
      );
      final badMagic = Uint8List.fromList(fixture.bytes);
      badMagic[16 * fixtureSectorSize + 1] = 0x58;
      expect(
        Iso9660Reader.fromBytes(badMagic),
        throwsA(isA<IsoFormatException>()),
      );
      final noMagic = Uint8List(20 * fixtureSectorSize);
      expect(
        Iso9660Reader.fromBytes(noMagic),
        throwsA(isA<IsoFormatException>()),
      );
    });

    test('rejects an extent that leaves the image', () async {
      final patched = SacdIsoFixture.withBothEndianU32(
        fixture.bytes,
        16 * fixtureSectorSize + 156 + 10,
        64 * fixtureSectorSize,
      );
      final reader = await Iso9660Reader.fromBytes(patched);
      addTearDown(reader.close);
      expect(reader.list(reader.root), throwsA(isA<IsoFormatException>()));
    });

    test('rejects both-endian fields that disagree', () async {
      final patched = Uint8List.fromList(fixture.bytes);
      patched[16 * fixtureSectorSize + 156 + 6] ^= 0x01;
      expect(
        Iso9660Reader.fromBytes(patched),
        throwsA(isA<IsoFormatException>()),
      );
    });

    test('clamps readAt at the image end and rejects negative reads', () async {
      final reader = await Iso9660Reader.fromBytes(fixture.bytes);
      addTearDown(reader.close);
      final length = fixture.bytes.length;

      expect((await reader.readAt(0, 8)).length, 8);
      expect((await reader.readAt(length - 10, 100)).length, 10);
      expect(await reader.readAt(length, 100), isEmpty);
      expect(reader.readAt(-1, 4), throwsA(isA<IsoFormatException>()));
      expect(reader.readAt(0, -4), throwsA(isA<IsoFormatException>()));
    });

    test('a 4-byte Rock Ridge NM at the extent end is not read past',
        () async {
      // The NM record is the last thing in the directory extent: signature NM,
      // entry length 4, version 1 — and therefore no flags byte. Reading the
      // flags at position + 4 used to index one byte past the buffer.
      final image = _isoWithTrailingShortNm();
      final reader = await Iso9660Reader.fromBytes(image);
      addTearDown(reader.close);

      final entries = await reader.list(reader.root);
      final bin = entries.singleWhere((entry) => entry.isoName == 'BIN1');
      expect(bin.name, 'BIN1', reason: 'a malformed NM is ignored, not thrown');
    });

    test('survives mutated images without RangeError or TypeError', () async {
      final random = Random(20261117);
      for (var round = 0; round < 200; round++) {
        final mutated = Uint8List.fromList(fixture.bytes);
        final mutations = 1 + random.nextInt(10);
        for (var i = 0; i < mutations; i++) {
          mutated[random.nextInt(mutated.length)] = random.nextInt(256);
        }
        try {
          final reader = await Iso9660Reader.fromBytes(mutated);
          try {
            await reader.lookupPath('SACD');
            await reader.lookupPath('SACD/SACD_2CH.TOC');
            await reader.list(reader.root);
          } finally {
            await reader.close();
          }
        } catch (error) {
          expect(error, isNot(isA<RangeError>()),
              reason: 'round $round: $error');
          expect(error, isNot(isA<TypeError>()),
              reason: 'round $round: $error');
        }
      }
    });

    test('survives every truncation prefix of the fixture', () async {
      final fixtureBytes = fixture.bytes;
      for (var cut = 0; cut <= fixtureBytes.length; cut += 1024) {
        final truncated = Uint8List.sublistView(fixtureBytes, 0, cut);
        try {
          final reader = await Iso9660Reader.fromBytes(truncated);
          try {
            await reader.lookupPath('SACD');
            await reader.list(reader.root);
          } finally {
            await reader.close();
          }
        } catch (error) {
          expect(error, isNot(isA<RangeError>()), reason: 'cut $cut');
          expect(error, isNot(isA<TypeError>()), reason: 'cut $cut');
        }
      }
    });
  });
}

/// Minimal ISO with a Rock Ridge `NM` entry that ends exactly at the directory
/// extent boundary and carries no flags byte.
Uint8List _isoWithTrailingShortNm() {
  const sectors = 21;
  final image = Uint8List(sectors * fixtureSectorSize);

  // Primary volume descriptor at sector 16.
  final pvd = 16 * fixtureSectorSize;
  image[pvd] = 0x01;
  _writeAscii(image, pvd + 1, 'CD001');
  image[pvd + 6] = 0x01;
  const directoryBytes = 34 + 34 + 42;
  _writeRecord(
    image,
    pvd + 156,
    identifier: const <int>[0x00],
    extentSector: 20,
    sizeBytes: directoryBytes,
    isDirectory: true,
  );

  // Root directory: self, parent, then the malformed NM entry.
  var offset = 20 * fixtureSectorSize;
  offset += _writeRecord(
    image,
    offset,
    identifier: const <int>[0x00],
    extentSector: 20,
    sizeBytes: directoryBytes,
    isDirectory: true,
  );
  offset += _writeRecord(
    image,
    offset,
    identifier: const <int>[0x01],
    extentSector: 20,
    sizeBytes: directoryBytes,
    isDirectory: true,
  );
  _writeRecord(
    image,
    offset,
    identifier: <int>[0x42, 0x49, 0x4E, 0x31], // 'BIN1', even -> pad byte
    extentSector: 20,
    sizeBytes: 1,
    isDirectory: false,
    systemUse: const <int>[0x4E, 0x4D, 0x04, 0x01], // 'NM', len 4, version 1
  );
  return image;
}

int _writeRecord(
  Uint8List image,
  int offset, {
  required List<int> identifier,
  required int extentSector,
  required int sizeBytes,
  required bool isDirectory,
  List<int> systemUse = const <int>[],
}) {
  final padAfterIdentifier = identifier.length.isEven ? 1 : 0;
  final length =
      33 + identifier.length + padAfterIdentifier + systemUse.length;
  final view = ByteData.sublistView(image, offset, offset + length);
  image[offset] = length;
  image[offset + 1] = 0;
  view.setUint32(2, extentSector, Endian.little);
  view.setUint32(6, extentSector, Endian.big);
  view.setUint32(10, sizeBytes, Endian.little);
  view.setUint32(14, sizeBytes, Endian.big);
  image[offset + 25] = isDirectory ? 0x02 : 0x00;
  view.setUint16(28, 1, Endian.little);
  view.setUint16(30, 1, Endian.big);
  image[offset + 32] = identifier.length;
  for (var i = 0; i < identifier.length; i++) {
    image[offset + 33 + i] = identifier[i];
  }
  var cursor = offset + 33 + identifier.length + padAfterIdentifier;
  for (final byte in systemUse) {
    image[cursor++] = byte;
  }
  return length;
}

void _writeAscii(Uint8List target, int offset, String text) {
  for (var i = 0; i < text.length; i++) {
    target[offset + i] = text.codeUnitAt(i);
  }
}
