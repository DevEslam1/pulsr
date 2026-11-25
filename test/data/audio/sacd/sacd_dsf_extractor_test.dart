// test/data/audio/sacd/sacd_dsf_extractor_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/audio/dsd_header_probe.dart';
import 'package:pulsr/data/audio/sacd/sacd_dsf_cache.dart';
import 'package:pulsr/data/audio/sacd/sacd_dsf_extractor.dart';
import 'package:pulsr/data/audio/sacd/sacd_limits.dart';
import 'package:pulsr/data/audio/sacd/sacd_toc.dart';

import 'sacd_iso_fixture.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pulsr_sacd_dsf');
  });

  tearDown(() async {
    SacdDsfExtractor.debugFailAfterPayloadBytes = null;
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> writeIso(SacdIsoFixture fixture, String name) async {
    final file = File('${temp.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(fixture.bytes);
    return file;
  }

  SacdTrack firstTrack(SacdIsoFixture fixture, {int channels = 2}) => SacdTrack(
        index: 1,
        startSector: fixture.dataSector,
        lengthSectors: fixture.trackSectors.first,
        durationSeconds: 5,
        channels: channels,
        isTwoChannel: channels == 2,
        dsdRateMultiplier: 64,
      );

  group('DsfHeaderWriter', () {
    test('writes the 92-byte DSF preamble', () {
      final header = DsfHeaderWriter(
        channels: 2,
        sampleRateHz: 2822400,
        sampleCount: 1000,
      ).write(8192);
      final view = ByteData.sublistView(header);

      expect(header.length, 92);
      expect(String.fromCharCodes(header, 0, 4), 'DSD ');
      expect(view.getUint64(4, Endian.little), 28);
      expect(view.getUint64(12, Endian.little), 92 + 8192);
      expect(view.getUint64(20, Endian.little), 0);

      expect(String.fromCharCodes(header, 28, 32), 'fmt ');
      expect(view.getUint64(32, Endian.little), 52);
      expect(view.getUint32(40, Endian.little), 1);
      expect(view.getUint32(44, Endian.little), 0);
      expect(view.getUint32(48, Endian.little), 2);
      expect(view.getUint32(52, Endian.little), 2);
      expect(view.getUint32(56, Endian.little), 2822400);
      expect(view.getUint32(60, Endian.little), 1);
      expect(view.getUint64(64, Endian.little), 1000);
      expect(view.getUint32(72, Endian.little), 4096);
      expect(view.getUint32(76, Endian.little), 0);

      expect(String.fromCharCodes(header, 80, 84), 'data');
      expect(view.getUint64(84, Endian.little), 8192 + 12);
    });

    test('maps channel counts to DSF channel types', () {
      expect(DsfHeaderWriter.channelTypeFor(1), 1);
      expect(DsfHeaderWriter.channelTypeFor(2), 2);
      expect(DsfHeaderWriter.channelTypeFor(6), 6);
      expect(DsfHeaderWriter.channelTypeFor(8), 7);
      expect(DsfHeaderWriter.channelTypeFor(7), 0);
    });

    test('rejects header fields DSF cannot describe', () {
      expect(
        () => DsfHeaderWriter(channels: 7, sampleRateHz: 1, sampleCount: 0),
        throwsArgumentError,
      );
      expect(
        () => DsfHeaderWriter(channels: 2, sampleRateHz: 0, sampleCount: 0),
        throwsArgumentError,
      );
      expect(
        () => DsfHeaderWriter(channels: 2, sampleRateHz: 1, sampleCount: -1),
        throwsArgumentError,
      );
      expect(
        () => DsfHeaderWriter(
          channels: 2,
          sampleRateHz: 1,
          sampleCount: 0,
          bitsPerSample: 2,
        ),
        throwsArgumentError,
      );
      expect(
        () => DsfHeaderWriter(
          channels: 2,
          sampleRateHz: 1,
          sampleCount: 0,
          blockSizePerChannel: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('SacdDsfExtractor.extractTrack', () {
    test('writes a playable stereo DSF with de-interleaved blocks', () async {
      final fixture = SacdIsoFixture();
      final iso = await writeIso(fixture, 'disc.iso');
      final track = firstTrack(fixture);

      final output = await SacdDsfExtractor().extractTrack(
        iso,
        track,
        outDir: temp,
      );

      expect(output.existsSync(), isTrue);
      // Content addressed: image path hash + mtime + track + parameters. Two
      // discs carrying "track 01" can no longer overwrite each other.
      expect(
        RegExp(r'^sacd_[0-9a-f]{8}_\d+_t01_[0-9a-f]{8}\.dsf$')
            .hasMatch(_baseName(output.path)),
        isTrue,
        reason: output.path,
      );

      final bytes = await output.readAsBytes();
      final view = ByteData.sublistView(bytes);
      final sectors = track.lengthSectors;
      final totalPayload = sectors * fixture.payloadPerSector;
      final bytesPerChannel = totalPayload ~/ track.channels;
      final blocks = (bytesPerChannel + 4095) ~/ 4096;
      final dataBytes = blocks * 4096 * track.channels;

      expect(String.fromCharCodes(bytes, 0, 4), 'DSD ');
      expect(view.getUint64(4, Endian.little), 28);
      expect(view.getUint64(12, Endian.little), bytes.length);
      expect(bytes.length, 92 + dataBytes);
      expect(view.getUint32(48, Endian.little), 2);
      expect(view.getUint32(52, Endian.little), 2);
      expect(view.getUint32(56, Endian.little), 2822400);
      // Image bytes are copied verbatim (MSB-first), so the header must say 8.
      expect(view.getUint32(60, Endian.little), 8);
      expect(view.getUint64(64, Endian.little), bytesPerChannel * 8);
      expect(view.getUint32(72, Endian.little), 4096);
      expect(String.fromCharCodes(bytes, 80, 84), 'data');
      expect(view.getUint64(84, Endian.little), dataBytes + 12);

      final expected = _expectedDsfData(
        fixture,
        channels: track.channels,
        sectors: sectors,
      );
      expect(bytes.sublist(92), equals(expected));
    });

    test('bit order round-trips through the probe and the DSF parser',
        () async {
      final fixture = SacdIsoFixture();
      final iso = await writeIso(fixture, 'roundtrip.iso');
      final track = firstTrack(fixture);

      final output = await SacdDsfExtractor().extractTrack(
        iso,
        track,
        outDir: temp,
      );
      final bytes = await output.readAsBytes();

      // DsdHeaderProbe reads the same fmt fields the router uses...
      expect(await DsdHeaderProbe.probeMultiple(output.path), 64);
      expect(await DsdHeaderProbe.probeBitsPerSample(output.path), 8);
      expect(DsdHeaderProbe.parseDsfBitsPerSample(bytes), 8);

      // ...and the decoder parser must agree on MSB-first and on the payload.
      final parsed = DsdDecoderHelper.parseDsfBytes(bytes);
      expect(parsed.msbFirst, isTrue);
      expect(parsed.dsdRate, 64);
      final expectedL = <int>[];
      final expectedR = <int>[];
      for (var sector = 0; sector < track.lengthSectors; sector++) {
        for (var i = 0; i < fixture.payloadPerSector; i++) {
          final value = fixture.payloadByte(sector, i);
          if (i.isEven) {
            expectedL.add(value);
          } else {
            expectedR.add(value);
          }
        }
      }
      expect(parsed.dsdL, equals(expectedL));
      expect(parsed.dsdR, equals(expectedR));

      // Reversed bits are LSB-first, so the header says 1 and the parser says
      // MSB-first is false.
      final reversed = await SacdDsfExtractor(reverseBits: true).extractTrack(
        iso,
        track,
        outDir: temp,
      );
      final reversedBytes = await reversed.readAsBytes();
      expect(DsdHeaderProbe.parseDsfBitsPerSample(reversedBytes), 1);
      expect(DsdDecoderHelper.parseDsfBytes(reversedBytes).msbFirst, isFalse);
    });

    test('rejects multichannel extraction until the decoder supports it',
        () async {
      final fixture = SacdIsoFixture(
        channels: 6,
        tocFileNames: const <String>['SACD_MCH.TOC'],
        areaFlags: 0x02,
      );
      final iso = await writeIso(fixture, 'mch.iso');
      final track = firstTrack(fixture, channels: 6);

      await expectLater(
        SacdDsfExtractor().extractTrack(iso, track, outDir: temp),
        throwsA(
          isA<SacdDsfException>().having(
            (error) => error.message,
            'message',
            contains('multichannel'),
          ),
        ),
      );
      // Nothing was written for the rejected track.
      expect(temp.listSync().where((entry) => entry.path.endsWith('.dsf')),
          isEmpty);
    });

    test('reverses the bit order when asked', () async {
      final fixture = SacdIsoFixture();
      final iso = await writeIso(fixture, 'disc.iso');
      final track = firstTrack(fixture);

      final output = await SacdDsfExtractor(reverseBits: true).extractTrack(
        iso,
        track,
        outDir: temp,
      );
      final bytes = await output.readAsBytes();
      final expected = _expectedDsfData(
        fixture,
        channels: 2,
        sectors: track.lengthSectors,
        reverse: true,
      );
      expect(bytes.sublist(92), equals(expected));
    });

    test('validates block geometry before any division', () async {
      expect(
        () => SacdDsfExtractor(blockSizePerChannel: 0),
        throwsArgumentError,
      );
      expect(
        () => SacdDsfExtractor(blockSizePerChannel: -4096),
        throwsArgumentError,
      );
      expect(
        () => SacdDsfExtractor(
            blockSizePerChannel: SacdDsfExtractor.maxBlockSize + 1),
        throwsArgumentError,
      );
      expect(
          () => SacdDsfExtractor(sectorHeaderBytes: 2048), throwsArgumentError);
      expect(
          () => SacdDsfExtractor(sectorHeaderBytes: -1), throwsArgumentError);
      expect(() => SacdDsfExtractor(maxOutputBytes: 0), throwsArgumentError);
    });

    test('uses the shared in-memory limit and rejects oversized tracks',
        () async {
      expect(kMaxDsdFileBytes, lessThanOrEqualTo(150 * 1024 * 1024));
      expect(DsdDecoderHelper.kMaxInMemoryDecodeBytes, kMaxDsdFileBytes);
      expect(SacdDsfExtractor().maxOutputBytes, kMaxDsdFileBytes);

      final fixture = SacdIsoFixture();
      final iso = await writeIso(fixture, 'cap.iso');
      final track = firstTrack(fixture);
      await expectLater(
        SacdDsfExtractor(maxOutputBytes: 1024)
            .extractTrack(iso, track, outDir: temp),
        throwsA(isA<SacdDsfException>()),
      );
      expect(temp.listSync().where((entry) => entry.path.endsWith('.dsf')),
          isEmpty);
    });

    test('deletes the partial file when the write fails', () async {
      final fixture = SacdIsoFixture();
      final iso = await writeIso(fixture, 'partial.iso');
      final track = firstTrack(fixture);
      SacdDsfExtractor.debugFailAfterPayloadBytes = 4096;

      await expectLater(
        SacdDsfExtractor().extractTrack(iso, track, outDir: temp),
        throwsA(isA<StateError>()),
      );
      expect(temp.listSync().where((entry) => entry.path.endsWith('.dsf')),
          isEmpty,
          reason: 'the partial DSF must not survive a failed extraction');
    });

    test('two discs never collide on the same track number', () async {
      final fixture = SacdIsoFixture();
      final discA = await writeIso(fixture, 'discA.iso');
      final discB = await writeIso(fixture, 'discB.iso');
      final track = firstTrack(fixture);

      final a = await SacdDsfExtractor().extractTrack(
        discA,
        track,
        outDir: temp,
      );
      final b = await SacdDsfExtractor().extractTrack(
        discB,
        track,
        outDir: temp,
      );
      expect(a.path, isNot(b.path));
      expect(
        await SacdDsfCache(directory: temp).isReusable(
          a,
          await a.length(),
        ),
        isTrue,
      );
    });

    test('rejects a track that leaves the image', () async {
      final fixture = SacdIsoFixture();
      final iso = await writeIso(fixture, 'disc.iso');
      final track = SacdTrack(
        index: 9,
        startSector: fixture.bytes.length ~/ fixtureSectorSize,
        lengthSectors: 2,
        durationSeconds: 1,
        channels: 2,
        isTwoChannel: true,
        dsdRateMultiplier: 64,
      );

      expect(
        SacdDsfExtractor().extractTrack(iso, track, outDir: temp),
        throwsA(isA<SacdDsfException>()),
      );
    });

    test('rejects a track with no sectors', () async {
      final fixture = SacdIsoFixture();
      final iso = await writeIso(fixture, 'disc.iso');
      final track = SacdTrack(
        index: 1,
        startSector: fixture.dataSector,
        lengthSectors: 0,
        durationSeconds: 0,
        channels: 2,
        isTwoChannel: true,
        dsdRateMultiplier: 64,
      );

      expect(
        SacdDsfExtractor().extractTrack(iso, track, outDir: temp),
        throwsA(isA<SacdDsfException>()),
      );
    });

    test('rejects an image that is not ISO9660', () async {
      final iso = File('${temp.path}${Platform.pathSeparator}junk.iso');
      await iso.writeAsBytes(Uint8List(20 * fixtureSectorSize));
      final track = SacdTrack(
        index: 1,
        startSector: 20,
        lengthSectors: 1,
        durationSeconds: 1,
        channels: 2,
        isTwoChannel: true,
        dsdRateMultiplier: 64,
      );

      expect(
        SacdDsfExtractor().extractTrack(iso, track, outDir: temp),
        throwsA(isA<Exception>()),
      );
    });
  });
}

String _baseName(String path) {
  final clean = path.replaceAll(r'\', '/');
  return clean.substring(clean.lastIndexOf('/') + 1);
}

/// Rebuilds the expected DSF payload from the fixture's byte generator.
Uint8List _expectedDsfData(
  SacdIsoFixture fixture, {
  required int channels,
  required int sectors,
  int blockSize = 4096,
  bool reverse = false,
}) {
  final payloadPerSector = fixture.payloadPerSector;
  final totalPayload = sectors * payloadPerSector;
  final bytesPerChannel = totalPayload ~/ channels;
  final blocks = (bytesPerChannel + blockSize - 1) ~/ blockSize;
  final data = Uint8List(blocks * blockSize * channels);
  for (var global = 0; global < bytesPerChannel * channels; global++) {
    final sector = global ~/ payloadPerSector;
    final inSector = global % payloadPerSector;
    final value = fixture.payloadByte(sector, inSector);
    final channel = global % channels;
    final sampleIndex = global ~/ channels;
    final blockIndex = sampleIndex ~/ blockSize;
    final offset = blockIndex * blockSize * channels +
        channel * blockSize +
        sampleIndex % blockSize;
    data[offset] = reverse ? _bitReverse(value) : value;
  }
  return data;
}

int _bitReverse(int value) {
  var reversed = 0;
  for (var bit = 0; bit < 8; bit++) {
    reversed = (reversed << 1) | ((value >> bit) & 1);
  }
  return reversed;
}
