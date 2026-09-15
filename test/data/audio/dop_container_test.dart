import 'dart:io';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/audio_quality_info.dart';

/// Locks the DoP container-width selection: 24-bit standard packing vs
/// zero-padded 32-bit frames, plus fallback for invalid values.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const caps = DsdDacCapabilities(
    dsd64: true,
    dsd128: true,
    dsd256: true,
    dop: true,
    nativeDac: true,
  );

  Future<File> writeMinimalDsf(Directory dir, String name) async {
    final file = File('${dir.path}/$name');
    final builder = BytesBuilder();
    builder.add(Uint8List.fromList([0x44, 0x53, 0x44, 0x20])); // 'DSD '
    final dsdHeader = ByteData(24);
    dsdHeader.setUint64(0, 28, Endian.little);
    dsdHeader.setUint64(8, 200, Endian.little);
    dsdHeader.setUint64(16, 0, Endian.little);
    builder.add(dsdHeader.buffer.asUint8List());
    builder.add(Uint8List.fromList([0x66, 0x6D, 0x74, 0x20])); // 'fmt '
    final fmtHeader = ByteData(48);
    fmtHeader.setUint64(0, 52, Endian.little);
    fmtHeader.setUint32(8, 1, Endian.little);
    fmtHeader.setUint32(12, 0, Endian.little);
    fmtHeader.setUint32(16, 2, Endian.little);
    fmtHeader.setUint32(20, 2, Endian.little);
    fmtHeader.setUint32(24, 2822400, Endian.little); // DSD64
    fmtHeader.setUint32(28, 1, Endian.little);
    fmtHeader.setUint64(32, 1000, Endian.little);
    fmtHeader.setUint32(40, 16, Endian.little); // 16 bytes per channel
    fmtHeader.setUint32(44, 0, Endian.little);
    builder.add(fmtHeader.buffer.asUint8List());
    builder.add(Uint8List.fromList([0x64, 0x61, 0x74, 0x61])); // 'data'
    final dataHeader = ByteData(8);
    dataHeader.setUint64(0, 44, Endian.little);
    builder.add(dataHeader.buffer.asUint8List());
    builder.add(Uint8List(32)); // 16 L + 16 R
    await file.writeAsBytes(builder.takeBytes());
    return file;
  }

  SongsTableData songFor(String path) => SongsTableData(
        id: 901,
        title: 'DoP Container',
        artist: 'Artist',
        album: 'Album',
        durationMs: 1000,
        path: path,
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        isDownloaded: false,
      );

  Future<Uint8List> readSourceBytes(DsdPcmStreamAudioSource source) async {
    final response = await source.request();
    final chunks = await response.stream.toList();
    final bytes = BytesBuilder();
    for (final chunk in chunks) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  group('DoP container width selection', () {
    tearDown(() {
      AudioQualityInfo.dsdDopActive = false;
    });

    test('24-bit (default) frames 16 DSD bytes/channel into 48 PCM bytes',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('dop24_test');
      try {
        final file = await writeMinimalDsf(tempDir, 't24.dsf');
        final source = await DsdDecoderHelper.decodeDsdFile(
          songFor(file.path),
          MediaItem(id: '901', title: 'DoP 24'),
          forceDop: true,
          dopCapabilities: caps,
          dopContainerBits: 24,
        );
        expect(source, isA<DsdPcmStreamAudioSource>());
        expect(AudioQualityInfo.dsdDopActive, isTrue);
        final wav = await readSourceBytes(source as DsdPcmStreamAudioSource);
        // 8 stereo frames x 6 bytes (24-bit packed) + 44-byte header.
        expect(wav.length, equals(44 + 48));
        final headers = ByteData.sublistView(wav);
        expect(headers.getUint32(24, Endian.little), equals(176400));
        expect(headers.getUint16(34, Endian.little), equals(24));
        // First frame carries the 0x05 marker on both channels.
        expect(wav[44 + 2], equals(0x05));
        expect(wav[44 + 5], equals(0x05));
        // Second frame alternates to 0xFA.
        expect(wav[44 + 8], equals(0xFA));
        expect(wav[44 + 11], equals(0xFA));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('32-bit frames into zero-padded 64 PCM bytes', () async {
      final tempDir = await Directory.systemTemp.createTemp('dop32_test');
      try {
        final file = await writeMinimalDsf(tempDir, 't32.dsf');
        final source = await DsdDecoderHelper.decodeDsdFile(
          songFor(file.path),
          MediaItem(id: '901', title: 'DoP 32'),
          forceDop: true,
          dopCapabilities: caps,
          dopContainerBits: 32,
        );
        expect(source, isA<DsdPcmStreamAudioSource>());
        final wav = await readSourceBytes(source as DsdPcmStreamAudioSource);
        // 8 stereo frames x 8 bytes (32-bit padded) + 44-byte header.
        expect(wav.length, equals(44 + 64));
        final headers = ByteData.sublistView(wav);
        expect(headers.getUint32(24, Endian.little), equals(176400));
        expect(headers.getUint16(34, Endian.little), equals(32));
        // Pad byte is zero, marker is the 4th byte per channel.
        expect(wav[44 + 0], equals(0x00));
        expect(wav[44 + 3], equals(0x05));
        expect(wav[44 + 4], equals(0x00));
        expect(wav[44 + 7], equals(0x05));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('invalid container width falls back to 24-bit', () async {
      final tempDir = await Directory.systemTemp.createTemp('dopXX_test');
      try {
        final file = await writeMinimalDsf(tempDir, 'txx.dsf');
        final source = await DsdDecoderHelper.decodeDsdFile(
          songFor(file.path),
          MediaItem(id: '901', title: 'DoP fallback'),
          forceDop: true,
          dopCapabilities: caps,
          dopContainerBits: 20,
        );
        final wav = await readSourceBytes(source as DsdPcmStreamAudioSource);
        expect(wav.length, equals(44 + 48));
        expect(ByteData.sublistView(wav).getUint16(34, Endian.little),
            equals(24));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
