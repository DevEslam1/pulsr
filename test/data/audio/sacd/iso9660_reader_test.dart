// test/data/audio/sacd/iso9660_reader_test.dart

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
  });
}
