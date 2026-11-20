// test/data/audio/mp4_box_parser_test.dart
//
// Comprehensive unit tests for Mp4BoxParser with synthetic ISO BMFF fixtures:
// - Real ALAC atom probing (16-bit, 24-bit, 32-bit, sample rates 44.1k/96k/192k)
// - AAC (mp4a) atom probing
// - Lossless vs Lossy classification
// - Container variations (mdat before moov, multi-track, video-only)
// - Corrupted / truncated buffers
// - Disk file I/O (probePath / probeFile)
// - Integration with AudioConflicts and GaplessTrimHandler

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/audio_feature_info.dart';
import 'package:pulsr/data/audio/gapless_trim_handler.dart';
import 'package:pulsr/data/audio/mp4_box_parser.dart';

// ---------------------------------------------------------------------------
// Synthetic ISO BMFF Fixture Helpers
// ---------------------------------------------------------------------------

Uint8List _box(String type, List<int> payload) {
  final size = 8 + payload.length;
  final bytes = Uint8List(size);
  final b = ByteData.sublistView(bytes);
  b.setUint32(0, size);
  for (var i = 0; i < 4; i++) {
    bytes[4 + i] = type.codeUnitAt(i);
  }
  bytes.setRange(8, size, payload);
  return bytes;
}

Uint8List _fullBox(String type, int version, int flags, List<int> payload) {
  final size = 12 + payload.length;
  final bytes = Uint8List(size);
  final b = ByteData.sublistView(bytes);
  b.setUint32(0, size);
  for (var i = 0; i < 4; i++) {
    bytes[4 + i] = type.codeUnitAt(i);
  }
  bytes[8] = version;
  bytes[9] = (flags >> 16) & 0xFF;
  bytes[10] = (flags >> 8) & 0xFF;
  bytes[11] = flags & 0xFF;
  bytes.setRange(12, size, payload);
  return bytes;
}

Uint8List _makeAlacConfig({
  int frameLength = 4096,
  int compatibleVersion = 0,
  int bitDepth = 24,
  int pb = 40,
  int mb = 10,
  int kb = 14,
  int numChannels = 2,
  int maxRun = 255,
  int maxFrameBytes = 0,
  int avgBitRate = 2304000,
  int sampleRate = 96000,
}) {
  final bytes = Uint8List(24);
  final b = ByteData.sublistView(bytes);
  b.setUint32(0, frameLength);
  bytes[4] = compatibleVersion;
  bytes[5] = bitDepth;
  bytes[6] = pb;
  bytes[7] = mb;
  bytes[8] = kb;
  bytes[9] = numChannels;
  b.setUint16(10, maxRun);
  b.setUint32(12, maxFrameBytes);
  b.setUint32(16, avgBitRate);
  b.setUint32(20, sampleRate);
  return bytes;
}

Uint8List _makeAlacAtom(Uint8List config, {bool fullBox = true}) {
  if (fullBox) {
    final payload = Uint8List(4 + config.length);
    payload.setRange(4, payload.length, config);
    return _box('alac', payload);
  } else {
    return _box('alac', config);
  }
}

Uint8List _makeAudioSampleEntry({
  required String format,
  int channels = 2,
  int sampleSize = 16,
  int sampleRate = 44100,
  List<int> childBoxes = const [],
}) {
  final header = Uint8List(28);
  final b = ByteData.sublistView(header);
  b.setUint16(6, 1); // data_reference_index
  b.setUint16(16, channels);
  b.setUint16(18, sampleSize);
  b.setUint32(24, sampleRate << 16); // 16.16 fixed-point

  final payload = <int>[...header, ...childBoxes];
  return _box(format, payload);
}

Uint8List _makeStsd(List<Uint8List> sampleEntries) {
  final countBytes = Uint8List(4);
  ByteData.sublistView(countBytes).setUint32(0, sampleEntries.length);
  final payload = <int>[...countBytes];
  for (final entry in sampleEntries) {
    payload.addAll(entry);
  }
  return _fullBox('stsd', 0, 0, payload);
}

Uint8List _makeHdlr(String handlerType) {
  final payload = Uint8List(8);
  for (var i = 0; i < 4; i++) {
    payload[4 + i] = handlerType.codeUnitAt(i);
  }
  return _fullBox('hdlr', 0, 0, payload);
}

Uint8List _makeFtyp({
  String majorBrand = 'M4A ',
  List<String> compatible = const ['M4A ', 'mp42'],
}) {
  final payload = <int>[];
  for (var i = 0; i < 4; i++) {
    payload.add(majorBrand.codeUnitAt(i));
  }
  payload.addAll([0, 0, 0, 0]); // minor_version
  for (final brand in compatible) {
    for (var i = 0; i < 4; i++) {
      payload.add(brand.codeUnitAt(i));
    }
  }
  return _box('ftyp', payload);
}

Uint8List _makeMp4AudioFile({
  required Uint8List stsdBox,
  String handlerType = 'soun',
  String majorBrand = 'M4A ',
  Uint8List? preMdat,
}) {
  final stbl = _box('stbl', stsdBox);
  final minf = _box('minf', [..._box('smhd', [0, 0, 0, 0]), ...stbl]);
  final hdlr = _makeHdlr(handlerType);
  final mdia = _box('mdia', [...hdlr, ...minf]);
  final trak = _box('trak', [..._box('tkhd', [0, 0, 0, 0]), ...mdia]);
  final moov = _box('moov', [..._box('mvhd', [0, 0, 0, 0]), ...trak]);
  final ftyp = _makeFtyp(majorBrand: majorBrand);

  final fileBytes = <int>[...ftyp];
  if (preMdat != null) {
    fileBytes.addAll(_box('mdat', preMdat));
  }
  fileBytes.addAll(moov);
  return Uint8List.fromList(fileBytes);
}

void main() {
  group('ALAC Atom Probe', () {
    test('extracts 24-bit / 96kHz ALAC track accurately', () {
      final config = _makeAlacConfig(
        bitDepth: 24,
        sampleRate: 96000,
        numChannels: 2,
        avgBitRate: 2304000,
      );
      final alacAtom = _makeAlacAtom(config, fullBox: true);
      final sampleEntry = _makeAudioSampleEntry(
        format: 'alac',
        channels: 2,
        sampleSize: 16, // container may declare 16, ALAC cookie overrides with 24
        sampleRate: 96000,
        childBoxes: alacAtom,
      );
      final stsd = _makeStsd([sampleEntry]);
      final mp4Bytes = _makeMp4AudioFile(stsdBox: stsd);

      final probe = Mp4BoxParser.probeBytes(mp4Bytes);

      expect(probe.hasAudioTrack, isTrue);
      expect(probe.codec, 'ALAC');
      expect(probe.codecType, Mp4AudioCodec.alac);
      expect(probe.isAlac, isTrue);
      expect(probe.isLossless, isTrue);
      expect(probe.isHiRes, isTrue);
      expect(probe.bitDepth, 24);
      expect(probe.sampleRate, 96000);
      expect(probe.channels, 2);
      expect(probe.bitrateKbps, 2304);
      expect(probe.fourcc, 'alac');
      expect(probe.majorBrand, 'M4A ');
    });

    test('extracts 16-bit / 44.1kHz ALAC track without Hi-Res flag', () {
      final config = _makeAlacConfig(
        bitDepth: 16,
        sampleRate: 44100,
        numChannels: 2,
        avgBitRate: 850000,
      );
      final alacAtom = _makeAlacAtom(config, fullBox: true);
      final sampleEntry = _makeAudioSampleEntry(
        format: 'alac',
        channels: 2,
        sampleSize: 16,
        sampleRate: 44100,
        childBoxes: alacAtom,
      );
      final stsd = _makeStsd([sampleEntry]);
      final mp4Bytes = _makeMp4AudioFile(stsdBox: stsd);

      final probe = Mp4BoxParser.probeBytes(mp4Bytes);

      expect(probe.hasAudioTrack, isTrue);
      expect(probe.codec, 'ALAC');
      expect(probe.isLossless, isTrue);
      expect(probe.isHiRes, isFalse);
      expect(probe.bitDepth, 16);
      expect(probe.sampleRate, 44100);
      expect(probe.channels, 2);
      expect(probe.bitrateKbps, 850);
    });

    test('extracts 24-bit ALAC without FullBox version/flags header in alac box', () {
      final config = _makeAlacConfig(
        bitDepth: 24,
        sampleRate: 192000,
        numChannels: 2,
        avgBitRate: 4608000,
      );
      // Non-fullbox (size 32 = 8 box header + 24 config)
      final alacAtom = _makeAlacAtom(config, fullBox: false);
      final sampleEntry = _makeAudioSampleEntry(
        format: 'alac',
        channels: 2,
        sampleRate: 192000,
        childBoxes: alacAtom,
      );
      final stsd = _makeStsd([sampleEntry]);
      final mp4Bytes = _makeMp4AudioFile(stsdBox: stsd);

      final probe = Mp4BoxParser.probeBytes(mp4Bytes);

      expect(probe.hasAudioTrack, isTrue);
      expect(probe.codec, 'ALAC');
      expect(probe.bitDepth, 24);
      expect(probe.sampleRate, 192000);
      expect(probe.bitrateKbps, 4608);
      expect(probe.isHiRes, isTrue);
    });

    test('extracts ALAC when wrapped in mp4a format entry (§8.3)', () {
      final config = _makeAlacConfig(
        bitDepth: 24,
        sampleRate: 48000,
        avgBitRate: 1536000,
      );
      final alacAtom = _makeAlacAtom(config, fullBox: true);
      final sampleEntry = _makeAudioSampleEntry(
        format: 'mp4a',
        channels: 2,
        sampleRate: 48000,
        childBoxes: alacAtom,
      );
      final stsd = _makeStsd([sampleEntry]);
      final mp4Bytes = _makeMp4AudioFile(stsdBox: stsd);

      final probe = Mp4BoxParser.probeBytes(mp4Bytes);

      expect(probe.hasAudioTrack, isTrue);
      expect(probe.codec, 'ALAC');
      expect(probe.isLossless, isTrue);
      expect(probe.bitDepth, 24);
      expect(probe.sampleRate, 48000);
    });

    test('extracts ALAC when wrapped in mp4a via wave atom (§8.3)', () {
      final config = _makeAlacConfig(
        bitDepth: 16,
        sampleRate: 44100,
        avgBitRate: 800000,
      );
      final alacAtom = _makeAlacAtom(config, fullBox: true);
      final waveAtom = _box('wave', alacAtom);
      final sampleEntry = _makeAudioSampleEntry(
        format: 'mp4a',
        channels: 2,
        sampleRate: 44100,
        childBoxes: waveAtom,
      );
      final stsd = _makeStsd([sampleEntry]);
      final mp4Bytes = _makeMp4AudioFile(stsdBox: stsd);

      final probe = Mp4BoxParser.probeBytes(mp4Bytes);

      expect(probe.hasAudioTrack, isTrue);
      expect(probe.codec, 'ALAC');
      expect(probe.isLossless, isTrue);
      expect(probe.bitDepth, 16);
      expect(probe.sampleRate, 44100);
    });

    test('rejects ALAC with invalid bit depth (§8.3)', () {
      final config = _makeAlacConfig(
        bitDepth: 12, // Invalid bit depth (not 16/20/24/32)
        sampleRate: 44100,
      );
      final alacAtom = _makeAlacAtom(config, fullBox: true);
      final sampleEntry = _makeAudioSampleEntry(
        format: 'alac',
        channels: 2,
        sampleRate: 44100,
        sampleSize: 12,
        childBoxes: alacAtom,
      );
      final stsd = _makeStsd([sampleEntry]);
      final mp4Bytes = _makeMp4AudioFile(stsdBox: stsd);

      final probe = Mp4BoxParser.probeBytes(mp4Bytes);

      expect(probe.isRecognised, isFalse);
    });

    test('rejects ALAC with invalid sample rate (§8.3)', () {
      final config = _makeAlacConfig(
        bitDepth: 24,
        sampleRate: 0, // Invalid sample rate (< 8000)
      );
      final alacAtom = _makeAlacAtom(config, fullBox: true);
      final sampleEntry = _makeAudioSampleEntry(
        format: 'alac',
        channels: 2,
        sampleRate: 0,
        sampleSize: 24,
        childBoxes: alacAtom,
      );
      final stsd = _makeStsd([sampleEntry]);
      final mp4Bytes = _makeMp4AudioFile(stsdBox: stsd);

      final probe = Mp4BoxParser.probeBytes(mp4Bytes);

      expect(probe.isRecognised, isFalse);
    });
  });

  group('AAC (mp4a) Probe', () {
    test('identifies AAC accurately with lossy classification and null bitDepth', () {
      final sampleEntry = _makeAudioSampleEntry(
        format: 'mp4a',
        channels: 2,
        sampleRate: 48000,
      );
      final stsd = _makeStsd([sampleEntry]);
      final mp4Bytes = _makeMp4AudioFile(stsdBox: stsd);

      final probe = Mp4BoxParser.probeBytes(mp4Bytes);

      expect(probe.hasAudioTrack, isTrue);
      expect(probe.codec, 'AAC');
      expect(probe.codecType, Mp4AudioCodec.aac);
      expect(probe.isAac, isTrue);
      expect(probe.isAlac, isFalse);
      expect(probe.isLossless, isFalse);
      expect(probe.bitDepth, isNull);
      expect(probe.sampleRate, 48000);
      expect(probe.channels, 2);
    });
  });

  group('Other Codecs & Containers', () {
    test('identifies FLAC in MP4 container', () {
      final sampleEntry = _makeAudioSampleEntry(
        format: 'flac',
        channels: 2,
        sampleSize: 24,
        sampleRate: 48000,
      );
      final stsd = _makeStsd([sampleEntry]);
      final mp4Bytes = _makeMp4AudioFile(stsdBox: stsd);

      final probe = Mp4BoxParser.probeBytes(mp4Bytes);

      expect(probe.hasAudioTrack, isTrue);
      expect(probe.codec, 'FLAC');
      expect(probe.codecType, Mp4AudioCodec.flac);
      expect(probe.isLossless, isTrue);
      expect(probe.bitDepth, 24);
      expect(probe.sampleRate, 48000);
    });

    test('identifies Opus in MP4 container with 48kHz standard rate', () {
      final sampleEntry = _makeAudioSampleEntry(
        format: 'opus',
        channels: 2,
        sampleRate: 48000,
      );
      final stsd = _makeStsd([sampleEntry]);
      final mp4Bytes = _makeMp4AudioFile(stsdBox: stsd);

      final probe = Mp4BoxParser.probeBytes(mp4Bytes);

      expect(probe.hasAudioTrack, isTrue);
      expect(probe.codec, 'OPUS');
      expect(probe.codecType, Mp4AudioCodec.opus);
      expect(probe.isLossless, isFalse);
      expect(probe.sampleRate, 48000);
    });

    test('seeks past large mdat placed before moov', () {
      final config = _makeAlacConfig(bitDepth: 16, sampleRate: 44100);
      final alacAtom = _makeAlacAtom(config);
      final sampleEntry = _makeAudioSampleEntry(
        format: 'alac',
        sampleRate: 44100,
        childBoxes: alacAtom,
      );
      final stsd = _makeStsd([sampleEntry]);
      final dummyMediaBytes = Uint8List(512); // Simulate mdat payload
      final mp4Bytes = _makeMp4AudioFile(stsdBox: stsd, preMdat: dummyMediaBytes);

      final probe = Mp4BoxParser.probeBytes(mp4Bytes);

      expect(probe.hasAudioTrack, isTrue);
      expect(probe.codec, 'ALAC');
      expect(probe.sampleRate, 44100);
    });

    test('reports noAudio when container only has video track', () {
      final videoSampleEntry = _box('avc1', Uint8List(32));
      final stsd = _makeStsd([videoSampleEntry]);
      final mp4Bytes = _makeMp4AudioFile(stsdBox: stsd, handlerType: 'vide');

      final probe = Mp4BoxParser.probeBytes(mp4Bytes);

      expect(probe.hasAudioTrack, isFalse);
      expect(probe.codec, 'NONE');
      expect(probe.codecType, Mp4AudioCodec.none);
    });
  });

  group('Corruption and Robustness', () {
    test('empty bytes return unrecognised', () {
      final probe = Mp4BoxParser.probeBytes(Uint8List(0));
      expect(probe.hasAudioTrack, isFalse);
      expect(probe.codec, 'UNKNOWN');
    });

    test('random short noise returns unrecognised', () {
      final probe = Mp4BoxParser.probeBytes(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(probe.hasAudioTrack, isFalse);
      expect(probe.codec, 'UNKNOWN');
    });

    test('truncated box header does not throw', () {
      final validHeader = _makeFtyp();
      final truncated = validHeader.sublist(0, validHeader.length - 2);
      final probe = Mp4BoxParser.probeBytes(truncated);
      expect(probe.hasAudioTrack, isFalse);
    });

    test('nonexistent file returns unrecognised without throwing', () async {
      final probe = await Mp4BoxParser.probePath('nonexistent_path_file.m4a');
      expect(probe.hasAudioTrack, isFalse);
      expect(probe.codec, 'UNKNOWN');
    });
  });

  group('File I/O Verification', () {
    test('probeFile and probePath match probeBytes on disk', () async {
      final config = _makeAlacConfig(
        bitDepth: 24,
        sampleRate: 96000,
        numChannels: 2,
        avgBitRate: 2304000,
      );
      final alacAtom = _makeAlacAtom(config);
      final sampleEntry = _makeAudioSampleEntry(
        format: 'alac',
        sampleRate: 96000,
        childBoxes: alacAtom,
      );
      final stsd = _makeStsd([sampleEntry]);
      final bytes = _makeMp4AudioFile(stsdBox: stsd);

      final tempDir = await Directory.systemTemp.createTemp('pulsr_alac_test_');
      final tempFile = File('${tempDir.path}/test_track.m4a');
      await tempFile.writeAsBytes(bytes);

      try {
        final pathProbe = await Mp4BoxParser.probePath(tempFile.path);
        final fileProbe = await Mp4BoxParser.probeFile(tempFile);
        final memProbe = Mp4BoxParser.probeBytes(bytes);

        expect(pathProbe.codec, 'ALAC');
        expect(pathProbe.bitDepth, 24);
        expect(pathProbe.sampleRate, 96000);
        expect(pathProbe.isLossless, isTrue);

        expect(fileProbe.codec, pathProbe.codec);
        expect(fileProbe.bitDepth, pathProbe.bitDepth);
        expect(fileProbe.sampleRate, pathProbe.sampleRate);

        expect(memProbe.codec, pathProbe.codec);
        expect(memProbe.bitDepth, pathProbe.bitDepth);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('Integration with Audio Classification & Gapless Trim', () {
    test('probed ALAC is classified as lossless by AudioConflicts', () {
      final state = AudioConflicts.classifySourceCodec(
        path: 'album/song.m4a',
        codec: 'ALAC',
      );
      expect(state, AudioSourceCodecState.lossless);

      final sampleFormat = AudioConflicts.classifySourceSampleFormat(
        codec: 'ALAC',
        path: 'album/song.m4a',
      );
      expect(sampleFormat, AudioSourceSampleFormat.integer);
    });

    test('probed AAC is classified as lossy by AudioConflicts', () {
      final state = AudioConflicts.classifySourceCodec(
        path: 'album/song.m4a',
        codec: 'AAC',
      );
      expect(state, AudioSourceCodecState.lossy);
    });

    test('unprobed m4a remains unknown / unconfirmed', () {
      final state = AudioConflicts.classifySourceCodec(
        path: 'album/song.m4a',
        codec: null,
      );
      expect(state, AudioSourceCodecState.unknown);
    });

    test('GaplessTrimHandler does NOT apply AAC encoder delay when codec is ALAC', () {
      final alacTrim = GaplessTrimHandler.trimFor(
        path: '/storage/music/track.m4a',
        codec: 'ALAC',
      );
      expect(alacTrim.preSkip, Duration.zero);

      final aacTrim = GaplessTrimHandler.trimFor(
        path: '/storage/music/track.m4a',
        codec: 'AAC',
      );
      expect(aacTrim.preSkip, GaplessTrimHandler.aacEncoderDelay);
    });
  });
}
