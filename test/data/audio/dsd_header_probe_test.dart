// test/data/audio/dsd_header_probe_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dsd_header_probe.dart';

Uint8List _ascii(String value) => Uint8List.fromList(value.codeUnits);

void _writeLe32(Uint8List target, int offset, int value) {
  target[offset] = value & 0xFF;
  target[offset + 1] = (value >> 8) & 0xFF;
  target[offset + 2] = (value >> 16) & 0xFF;
  target[offset + 3] = (value >> 24) & 0xFF;
}

void _writeBe32(Uint8List target, int offset, int value) {
  target[offset] = (value >> 24) & 0xFF;
  target[offset + 1] = (value >> 16) & 0xFF;
  target[offset + 2] = (value >> 8) & 0xFF;
  target[offset + 3] = value & 0xFF;
}

void _writeBe64(Uint8List target, int offset, int value) {
  for (var i = 0; i < 8; i++) {
    target[offset + i] = (value >> (8 * (7 - i))) & 0xFF;
  }
}

Uint8List _dsfHeader(int sampleRate) {
  final bytes = Uint8List(0x60);
  bytes.setRange(0, 4, _ascii('DSD '));
  bytes.setRange(0x1C, 0x20, _ascii('fmt '));
  _writeLe32(bytes, 0x20, 52);
  _writeLe32(bytes, 0x24, 1); // format version
  _writeLe32(bytes, 0x28, 0); // format id (DSD raw)
  _writeLe32(bytes, 0x2C, 2); // channel type
  _writeLe32(bytes, 0x30, 2); // channel count
  _writeLe32(bytes, 0x34, sampleRate);
  _writeLe32(bytes, 0x38, 1); // bits per sample
  return bytes;
}

Uint8List _dffHeader(int sampleRate) {
  // FRM8 + size, 'DSD ', then a PROP chunk containing 'SND ' + 'FS  '.
  final propSize = 4 + 12 + 4; // 'SND ' + FS header + 4-byte rate
  final total = 12 + 4 + 12 + propSize; // FRM8 hdr + form type + PROP hdr + data
  final bytes = Uint8List(total);
  bytes.setRange(0, 4, _ascii('FRM8'));
  _writeBe64(bytes, 4, total - 12);
  bytes.setRange(12, 16, _ascii('DSD '));
  bytes.setRange(16, 20, _ascii('PROP'));
  _writeBe64(bytes, 20, propSize);
  bytes.setRange(28, 32, _ascii('SND '));
  bytes.setRange(32, 36, _ascii('FS  '));
  _writeBe64(bytes, 36, 4);
  _writeBe32(bytes, 44, sampleRate);
  return bytes;
}

void main() {
  group('DSF header', () {
    test('reads the sampling frequency for every DSD rate', () {
      const rates = {
        2822400: 64,
        5644800: 128,
        11289600: 256,
        22579200: 512,
      };
      rates.forEach((rate, multiple) {
        expect(DsdHeaderProbe.parseDsfMultiple(_dsfHeader(rate)), multiple,
            reason: '$rate Hz should map to DSD$multiple');
      });
    });

    test('rejects a non-DSF magic and a truncated header', () {
      final notDsf = _dsfHeader(2822400);
      notDsf.setRange(0, 4, _ascii('RIFF'));
      expect(DsdHeaderProbe.parseDsfMultiple(notDsf), 0);
      expect(DsdHeaderProbe.parseDsfMultiple(Uint8List(8)), 0);
    });

    test('rejects a rate that is not a 44.1 kHz multiple', () {
      expect(DsdHeaderProbe.parseDsfMultiple(_dsfHeader(48000)), 0);
      expect(DsdHeaderProbe.parseDsfMultiple(_dsfHeader(0)), 0);
    });

    test('rejects an unknown multiple such as DSD32', () {
      expect(DsdHeaderProbe.parseDsfMultiple(_dsfHeader(1411200)), 0);
    });
  });

  group('DFF header', () {
    test('walks PROP/SND/FS and reads a big-endian rate', () {
      expect(DsdHeaderProbe.parseDffMultiple(_dffHeader(2822400)), 64);
      expect(DsdHeaderProbe.parseDffMultiple(_dffHeader(5644800)), 128);
      expect(DsdHeaderProbe.parseDffMultiple(_dffHeader(11289600)), 256);
    });

    test('returns 0 for a non-FRM8 container', () {
      final bytes = _dffHeader(2822400);
      bytes.setRange(0, 4, _ascii('FORM'));
      expect(DsdHeaderProbe.parseDffMultiple(bytes), 0);
    });

    test('returns 0 when the declared chunk size overruns the buffer', () {
      final bytes = _dffHeader(2822400);
      _writeBe64(bytes, 20, 1 << 20); // PROP claims 1 MB inside a ~60-byte buffer
      expect(DsdHeaderProbe.parseDffMultiple(bytes), 0);
    });
  });

  group('file probe', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dsd_probe_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reads a real DSF file and ignores other extensions', () async {
      final dsf = File('${tempDir.path}/track.dsf');
      await dsf.writeAsBytes(_dsfHeader(5644800));
      expect(await DsdHeaderProbe.probeMultiple(dsf.path), 128);

      final flac = File('${tempDir.path}/track.flac');
      await flac.writeAsBytes(_dsfHeader(2822400));
      expect(await DsdHeaderProbe.probeMultiple(flac.path), 0);
    });

    test('returns 0 instead of throwing for a missing file', () async {
      expect(
        await DsdHeaderProbe.probeMultiple('${tempDir.path}/missing.dsf'),
        0,
      );
    });
  });
}
