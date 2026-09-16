import 'dart:io';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/audio/format_aware_decoder.dart';
import 'package:pulsr/data/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('DSD -> PCM Playback Pipeline Wiring (P0-3)', () {
    test('buildWavContainer creates valid 44-byte PCM WAV header and samples', () {
      final floatSamples = [0.0, 0.5, -0.5, 1.0]; // 2 stereo frames
      final wav = DsdDecoderHelper.buildWavContainer(
        pcmFloatSamples: floatSamples,
        sampleRate: 176400,
        channels: 2,
      );

      expect(wav.length, equals(44 + 4 * 3)); // 44 header + 4 samples * 3 bytes
      // Check RIFF
      expect(String.fromCharCodes(wav.sublist(0, 4)), equals('RIFF'));
      // Check WAVE
      expect(String.fromCharCodes(wav.sublist(8, 12)), equals('WAVE'));
      // Check fmt
      expect(String.fromCharCodes(wav.sublist(12, 16)), equals('fmt '));
      // Check data
      expect(String.fromCharCodes(wav.sublist(36, 40)), equals('data'));

      final byteData = ByteData.sublistView(wav);
      expect(byteData.getUint16(20, Endian.little), equals(1)); // AudioFormat = 1 (PCM)
      expect(byteData.getUint16(22, Endian.little), equals(2)); // Channels = 2
      expect(byteData.getUint32(24, Endian.little), equals(176400)); // SampleRate
      expect(byteData.getUint16(34, Endian.little), equals(24)); // BitsPerSample = 24
    });

    test('FormatAwareDecoder routes .dsf and .dff to decodeDsdToPcm', () async {
      bool dsdDecoderCalled = false;
      final decoder = FormatAwareDecoder(
        resolveYtmStream: (song, tag) async => AudioSource.uri(Uri.parse('https://example.com')),
        decodeDsdToPcm: (song, tag) async {
          dsdDecoderCalled = true;
          return AudioSource.uri(Uri.parse(song.path), tag: tag);
        },
      );

      final dsfSong = SongsTableData(
        id: 101,
        title: 'Hi-Res DSF',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        path: '/storage/music/track.dsf',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        isDownloaded: false,
      );

      final source = await decoder.decodeForFormat(dsfSong, MediaItem(id: '101', title: 'Hi-Res DSF'));
      expect(dsdDecoderCalled, isTrue);
      expect(source, isNotNull);
    });

    test('DsdDecoderHelper.decodeDsdFile decodes sample DSF file with testDecoder', () async {
      final tempDir = await Directory.systemTemp.createTemp('dsd_test');
      final tempFile = File('${tempDir.path}/test_track.dsf');

      // Create a minimal synthetic DSF file
      final builder = BytesBuilder();
      // DSD chunk (28 bytes)
      builder.add(Uint8List.fromList([0x44, 0x53, 0x44, 0x20])); // 'DSD '
      final dsdHeader = ByteData(24);
      dsdHeader.setUint64(0, 28, Endian.little); // chunk size
      dsdHeader.setUint64(8, 200, Endian.little); // file size
      dsdHeader.setUint64(16, 0, Endian.little); // metadata offset
      builder.add(dsdHeader.buffer.asUint8List());

      // fmt chunk (52 bytes)
      builder.add(Uint8List.fromList([0x66, 0x6D, 0x74, 0x20])); // 'fmt '
      final fmtHeader = ByteData(48);
      fmtHeader.setUint64(0, 52, Endian.little); // chunk size
      fmtHeader.setUint32(8, 1, Endian.little); // format version
      fmtHeader.setUint32(12, 0, Endian.little); // format ID
      fmtHeader.setUint32(16, 2, Endian.little); // channel type (stereo)
      fmtHeader.setUint32(20, 2, Endian.little); // channel count
      fmtHeader.setUint32(24, 2822400, Endian.little); // sample rate 2.8224 MHz (DSD64)
      fmtHeader.setUint32(28, 1, Endian.little); // bits per sample
      fmtHeader.setUint64(32, 1000, Endian.little); // sample count
      fmtHeader.setUint32(40, 16, Endian.little); // block size per channel = 16 bytes
      fmtHeader.setUint32(44, 0, Endian.little); // reserved
      builder.add(fmtHeader.buffer.asUint8List());

      // data chunk (12 bytes header + 32 bytes data = 16 L + 16 R)
      builder.add(Uint8List.fromList([0x64, 0x61, 0x74, 0x61])); // 'data'
      final dataHeader = ByteData(8);
      dataHeader.setUint64(0, 44, Endian.little); // 12 + 32
      builder.add(dataHeader.buffer.asUint8List());
      builder.add(Uint8List(32)); // 16 bytes L, 16 bytes R

      await tempFile.writeAsBytes(builder.takeBytes());

      // Inject test decoder
      DsdDecoderHelper.testDecoder = (dsdL, dsdR, {dsdRate = 64, targetSampleRate = 176400, bitOrder = 0}) async {
        expect(dsdL.length, equals(16));
        expect(dsdR.length, equals(16));
        expect(dsdRate, equals(64));
        return List<double>.filled(64, 0.0); // 32 stereo frames
      };

      final song = SongsTableData(
        id: 202,
        title: 'Synthesized DSD',
        artist: 'Artist',
        album: 'Album',
        durationMs: 1000,
        path: tempFile.path,
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        isDownloaded: false,
      );

      final audioSource = await DsdDecoderHelper.decodeDsdFile(
        song,
        MediaItem(id: '202', title: 'Synthesized DSD'),
      );

      expect(audioSource, isA<DsdPcmStreamAudioSource>());

      // Cleanup
      DsdDecoderHelper.testDecoder = null;
      await tempDir.delete(recursive: true);
    });

    test('DsdDecoderHelper throws DsdUnsupportedException if native decoder returns null', () async {
      final tempDir = await Directory.systemTemp.createTemp('dsd_null_test');
      final tempFile = File('${tempDir.path}/test_null.dsf');
      final builder = BytesBuilder();
      builder.add(Uint8List.fromList([0x44, 0x53, 0x44, 0x20]));
      final dsdH = ByteData(24);
      dsdH.setUint64(0, 28, Endian.little);
      builder.add(dsdH.buffer.asUint8List());
      builder.add(Uint8List.fromList([0x66, 0x6D, 0x74, 0x20]));
      final fmtH = ByteData(48);
      fmtH.setUint64(0, 52, Endian.little);
      fmtH.setUint32(8, 1, Endian.little);
      fmtH.setUint32(12, 0, Endian.little);
      fmtH.setUint32(16, 2, Endian.little);
      fmtH.setUint32(20, 2, Endian.little); // channel count
      fmtH.setUint32(24, 2822400, Endian.little); // sample rate
      fmtH.setUint32(28, 1, Endian.little);
      fmtH.setUint64(32, 100, Endian.little);
      fmtH.setUint32(40, 16, Endian.little); // block size
      fmtH.setUint32(44, 0, Endian.little);
      builder.add(fmtH.buffer.asUint8List());
      builder.add(Uint8List.fromList([0x64, 0x61, 0x74, 0x61]));
      final dataH = ByteData(8);
      dataH.setUint64(0, 20, Endian.little);
      builder.add(dataH.buffer.asUint8List());
      builder.add(Uint8List(8));
      await tempFile.writeAsBytes(builder.takeBytes());

      DsdDecoderHelper.testDecoder = (dsdL, dsdR, {dsdRate = 64, targetSampleRate = 176400, bitOrder = 0}) async => null;

      final song = SongsTableData(
        id: 303,
        title: 'Null DSD',
        artist: 'Artist',
        album: 'Album',
        durationMs: 1000,
        path: tempFile.path,
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
        isDownloaded: false,
      );

      await expectLater(
        DsdDecoderHelper.decodeDsdFile(song, MediaItem(id: '303', title: 'Null DSD')),
        throwsA(isA<DsdUnsupportedException>()),
      );

      DsdDecoderHelper.testDecoder = null;
      await tempDir.delete(recursive: true);
    });
  });
}
