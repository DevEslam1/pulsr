// test/data/audio/sacd/sacd_toc_test.dart

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/sacd/sacd_toc.dart';

import 'sacd_iso_fixture.dart';

void main() {
  final fixture = SacdIsoFixture();
  final imageSectors = fixture.bytes.length ~/ fixtureSectorSize;

  SacdToc parseFixtureToc({
    String name = 'SACD_2CH.TOC',
    int? imageLengthSectors,
  }) {
    return SacdToc.parse(
      fixture.tocFiles[name]!,
      fileName: name,
      imageLengthSectors: imageLengthSectors ?? imageSectors,
    );
  }

  group('SacdToc.parse', () {
    test('parses the assumed area header and track table', () {
      final toc = parseFixtureToc();

      expect(toc.fileName, 'SACD_2CH.TOC');
      expect(toc.area, SacdAreaKind.twoChannel);
      expect(toc.isTwoChannel, isTrue);
      expect(toc.channels, 2);
      expect(toc.dsdRateMultiplier, 64);
      expect(toc.tracks, hasLength(2));

      final first = toc.tracks.first;
      expect(first.index, 1);
      expect(first.startSector, fixture.dataSector);
      expect(first.lengthSectors, fixture.trackSectors.first);
      expect(first.channels, 2);
      expect(first.isTwoChannel, isTrue);
      expect(first.durationSeconds, 5);
      expect(first.sampleRateHz, 2822400);
      expect(first.startOffsetBytes, fixture.dataSector * fixtureSectorSize);
      expect(
        first.lengthBytes,
        fixture.trackSectors.first * fixtureSectorSize,
      );

      final second = toc.tracks.last;
      expect(second.index, 2);
      expect(second.startSector, first.startSector + first.lengthSectors);
      expect(toc.totalDurationSeconds, 10);
    });

    test('classifies areas from the TOC file name and flags', () {
      final mchBytes = fixture.buildAreaToc(
        fileName: 'SACD_MCH.TOC',
        channels: 6,
        tracks: const [(start: 30, length: 4)],
        areaFlags: 0x02,
      );
      final mch = SacdToc.parse(mchBytes, fileName: 'SACD_MCH.TOC');
      expect(mch.area, SacdAreaKind.multiChannel);
      expect(mch.isTwoChannel, isFalse);
      expect(mch.tracks.single.isTwoChannel, isFalse);
      expect(mch.channels, 6);

      final master = SacdToc.parse(
        fixture.buildAreaToc(
          fileName: 'SACD_MS.TOC',
          channels: 2,
          tracks: const [(start: 30, length: 4)],
        ),
        fileName: 'SACD_MS.TOC',
      );
      expect(master.area, SacdAreaKind.master);

      final unnamed = SacdToc.parse(
        fixture.buildAreaToc(
          fileName: 'AREA.TOC',
          channels: 6,
          tracks: const [(start: 30, length: 4)],
          areaFlags: 0x00,
        ),
        fileName: 'AREA.TOC',
      );
      expect(unnamed.area, SacdAreaKind.multiChannel);
    });

    test('derives the duration when the entry leaves it at zero', () {
      final bytes = fixture.buildAreaToc(
        fileName: 'SACD_2CH.TOC',
        channels: 2,
        tracks: const [(start: 30, length: 2)],
        durationSeconds: 0,
      );
      final toc = SacdToc.parse(bytes, fileName: 'SACD_2CH.TOC');
      final expected = (2 * fixtureSectorSize * 8 / 2) / 2822400;
      expect(toc.tracks.single.durationSeconds, closeTo(expected, 1e-9));
    });

    test('accepts a 12-byte entry without a duration field', () {
      final bytes = fixture.buildAreaToc(
        fileName: 'SACD_2CH.TOC',
        channels: 2,
        tracks: const [(start: 30, length: 2)],
        entrySize: 12,
      );
      final toc = SacdToc.parse(bytes, fileName: 'SACD_2CH.TOC');
      expect(toc.tracks.single.lengthSectors, 2);
      expect(toc.tracks.single.durationSeconds, greaterThan(0));
    });
  });

  group('SacdToc.parse hostile input', () {
    void expectTocError(Uint8List bytes, {String name = 'SACD_2CH.TOC'}) {
      expect(
        () => SacdToc.parse(bytes, fileName: name),
        throwsA(isA<SacdTocError>()),
      );
    }

    test('rejects an empty or short file', () {
      expectTocError(Uint8List(0));
      expectTocError(Uint8List(31));
      expectTocError(Uint8List(8));
    });

    test('rejects a file without the SACD tag', () {
      final bytes = Uint8List.fromList(
        fixture.buildAreaToc(
          fileName: 'SACD_2CH.TOC',
          channels: 2,
          tracks: const [(start: 30, length: 2)],
        ),
      );
      bytes.setRange(0, 8, 'XXXXXXXX'.codeUnits);
      expectTocError(bytes);
    });

    test('rejects impossible entry sizes and counts', () {
      expectTocError(
        fixture.buildAreaToc(
          fileName: 'SACD_2CH.TOC',
          channels: 2,
          tracks: const [(start: 30, length: 2)],
          entrySize: 8,
        ),
      );
      expectTocError(
        fixture.buildAreaToc(
          fileName: 'SACD_2CH.TOC',
          channels: 2,
          tracks: const [(start: 30, length: 2)],
          declaredEntryCount: 0,
        ),
      );
      expectTocError(
        fixture.buildAreaToc(
          fileName: 'SACD_2CH.TOC',
          channels: 2,
          tracks: const [(start: 30, length: 2)],
          declaredEntryCount: 200,
        ),
      );
      expectTocError(
        fixture.buildAreaToc(
          fileName: 'SACD_2CH.TOC',
          channels: 2,
          tracks: const [(start: 30, length: 2)],
          declaredTableOffset: 0x10,
        ),
      );
    });

    test('rejects empty and unordered track extents', () {
      expectTocError(
        fixture.buildAreaToc(
          fileName: 'SACD_2CH.TOC',
          channels: 2,
          tracks: const [(start: 30, length: 0)],
        ),
      );
      expectTocError(
        fixture.buildAreaToc(
          fileName: 'SACD_2CH.TOC',
          channels: 2,
          tracks: const [(start: 0, length: 2)],
        ),
      );
      expectTocError(
        fixture.buildAreaToc(
          fileName: 'SACD_2CH.TOC',
          channels: 2,
          tracks: const [(start: 40, length: 2), (start: 30, length: 2)],
        ),
      );
    });

    test('rejects a track that leaves the image', () {
      expect(
        () => parseFixtureToc(imageLengthSectors: 4),
        throwsA(isA<SacdTocError>()),
      );
    });

    test('rejects an unsupported DSD rate and channel count', () {
      final badRate = fixture.buildAreaToc(
        fileName: 'SACD_2CH.TOC',
        channels: 2,
        tracks: const [(start: 30, length: 2)],
        rateMultiplier: 100,
      );
      expectTocError(badRate);

      final badChannels = fixture.buildAreaToc(
        fileName: 'SACD_2CH.TOC',
        channels: 9,
        tracks: const [(start: 30, length: 2)],
      );
      expectTocError(badChannels);
    });

    test('rejects all-ones garbage of a plausible size', () {
      expectTocError(Uint8List(1024)..fillRange(0, 1024, 0xff));
    });
  });

  group('SacdLayout', () {
    test('classifies TOC file names', () {
      expect(
        SacdLayout.areaKindForFileName('/SACD/SACD_2CH.TOC'),
        SacdAreaKind.twoChannel,
      );
      expect(
        SacdLayout.areaKindForFileName('SACD_MCH.TOC'),
        SacdAreaKind.multiChannel,
      );
      expect(
        SacdLayout.areaKindForFileName('SACD_MS.TOC'),
        SacdAreaKind.master,
      );
      expect(SacdLayout.areaKindForFileName('notes.txt'), isNull);
      expect(SacdLayout.isAreaTocFileName('SACD_2CH.TOC'), isTrue);
      expect(SacdLayout.isAreaTocFileName('SACD_2CH.TOC.bak'), isFalse);
    });

    test('BUG-P1-6: parses Scarlet Book TWOCHTOC with SACDTRL1 and rejects DST frame_format == 0', () {
      final buf = Uint8List(4096);
      final view = ByteData.sublistView(buf);
      void writeAscii(int off, String s) {
        for (var i = 0; i < s.length; i++) {
          buf[off + i] = s.codeUnitAt(i);
        }
      }

      writeAscii(0, 'TWOCHTOC');
      view.setUint8(0x08, 1); // versionMajor
      view.setUint8(0x09, 20); // versionMinor
      view.setUint16(0x14, 4, Endian.big); // 64x fs
      view.setUint8(0x16, 2); // frame_format = 2 (uncompressed DSD)
      view.setUint8(0x20, 2); // 2 channels
      view.setUint8(0x46, 2); // 2 tracks

      writeAscii(2048, 'SACDTRL1');
      view.setUint32(2048 + 8 + 0, 600, Endian.big);
      view.setUint32(2048 + 8 + 4, 610, Endian.big);
      view.setUint32(2048 + 8 + 255 * 4 + 0, 10, Endian.big);
      view.setUint32(2048 + 8 + 255 * 4 + 4, 15, Endian.big);

      final toc = SacdToc.parse(buf, fileName: 'TWOCHTOC.TOC', imageLengthSectors: 1000);
      expect(toc.area, SacdAreaKind.twoChannel);
      expect(toc.channels, 2);
      expect(toc.tracks, hasLength(2));
      expect(toc.tracks[0].startSector, 600);
      expect(toc.tracks[0].lengthSectors, 10);
      expect(toc.tracks[1].startSector, 610);
      expect(toc.tracks[1].lengthSectors, 15);

      // frame_format == 0 (DST) throws SacdDstTocError
      view.setUint8(0x16, 0);
      expect(
        () => SacdToc.parse(buf, fileName: 'TWOCHTOC.TOC'),
        throwsA(isA<SacdDstTocError>()),
      );
    });

    test('BUG-P1-6: parses Scarlet Book SACDMTOC at LBA 510', () {
      final masterBytes = Uint8List(2048);
      final view = ByteData.sublistView(masterBytes);
      for (var i = 0; i < 'SACDMTOC'.length; i++) {
        masterBytes[i] = 'SACDMTOC'.codeUnitAt(i);
      }
      view.setUint8(0x08, 1);
      view.setUint8(0x09, 20);
      view.setUint32(0x40, 520, Endian.big);
      view.setUint16(0x48, 2, Endian.big);

      final master = SacdMasterToc.parse(masterBytes, imageLengthSectors: 1000);
      expect(master.area1Toc1Start, 520);
      expect(master.area1TocSizeSectors, 2);
    });
  });
}
