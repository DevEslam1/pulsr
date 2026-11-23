// ignore_for_file: experimental_member_use
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/audio/mqa_decoder_helper.dart';
import 'package:pulsr/data/db/app_database.dart';

SongsTableData _song(String path) => SongsTableData(
      id: 1,
      title: 'Track',
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    MqaDecoderHelper.testUnfold = null;
    DsdDecoderHelper.testDecoder = null;
  });

  group('Stream range clamping', () {
    test('DsdPcmStreamAudioSource clamps out-of-range and inverted ranges',
        () async {
      final source =
          DsdPcmStreamAudioSource(Uint8List.fromList(List.filled(10, 7)));

      final overRun = await source.request(5, 999);
      expect(overRun.offset, 5);
      expect(overRun.sourceLength, 10);
      expect(overRun.contentLength, 5);

      final inverted = await source.request(999, 2);
      expect(inverted.offset, 10);
      expect(inverted.contentLength, 0);
    });

    test('Mqa stream clamps out-of-range range requests', () async {
      final dir = await Directory.systemTemp.createTemp('mqa_clamp');
      final file = File('${dir.path}/signed.flac');
      // Contains the MQA sync word; testUnfold bypasses the real decoder.
      await file.writeAsBytes(
        Uint8List.fromList([0xBE, 0x04, 0x98, 0xC4, 0, 0, 0, 0]),
      );
      MqaDecoderHelper.testUnfold =
          (bytes, {required originalRate}) async => Uint8List(12);

      final source = await MqaDecoderHelper.decodeMqaFile(
        _song(file.path),
        const MediaItem(id: '1', title: 'Track'),
      );
      expect(source, isA<StreamAudioSource>());

      final resp = await (source as StreamAudioSource).request(4, 1 << 20);
      expect(resp.sourceLength, greaterThan(0));
      expect(resp.contentLength, resp.sourceLength! - 4);
      expect(resp.offset, 4);

      await dir.delete(recursive: true);
    });
  });

  group('MQA signature gating', () {
    test('decodeMqaFile throws MqaUnsupportedException for non-MQA content',
        () async {
      final dir = await Directory.systemTemp.createTemp('mqa_gate');
      final file = File('${dir.path}/plain.flac');
      await file.writeAsBytes(Uint8List.fromList(List.filled(64, 0x11)));

      await expectLater(
        MqaDecoderHelper.decodeMqaFile(
          _song(file.path),
          const MediaItem(id: '1', title: 'Track'),
        ),
        throwsA(isA<MqaUnsupportedException>()),
      );

      await dir.delete(recursive: true);
    });

    test('BUG-P2-4: parseDsfBytes rejects DSF without data chunk and buildWavContainer handles odd float counts', () {
      final noDataDsf = Uint8List(80);
      final bd = ByteData.sublistView(noDataDsf);
      for (var i = 0; i < 4; i++) {
        noDataDsf[i] = 'DSD '.codeUnitAt(i);
        noDataDsf[28 + i] = 'fmt '.codeUnitAt(i);
      }
      bd.setUint64(4, 28, Endian.little);
      bd.setUint64(12, 80, Endian.little);
      bd.setUint64(32, 52, Endian.little);
      bd.setUint32(28 + 24, 2, Endian.little);
      bd.setUint32(28 + 28, 2822400, Endian.little);
      bd.setUint32(28 + 32, 1, Endian.little);
      bd.setUint32(28 + 44, 4096, Endian.little);

      expect(
        () => DsdDecoderHelper.parseDsfBytes(noDataDsf),
        throwsA(isA<FormatException>()),
      );

      // Odd number of stereo float samples must not throw RangeError
      final wav = DsdDecoderHelper.buildWavContainer(
        pcmFloatSamples: const <double>[0.1, -0.1, 0.2],
        sampleRate: 176400,
        channels: 2,
      );
      expect(wav.length, 44 + 6); // 1 complete stereo 24-bit frame (6 bytes)
    });

    test('BUG-P2-5: MQA unfold rejects truncated fmt chunk and non-PCM audioFormat', () async {
      final dir = await Directory.systemTemp.createTemp('mqa_fmt');
      final file = File('${dir.path}/float_mqa.wav');
      final buf = Uint8List(64);
      final bd = ByteData.sublistView(buf);
      void ascii(int off, String s) {
        for (var i = 0; i < s.length; i++) {
          buf[off + i] = s.codeUnitAt(i);
        }
      }

      ascii(0, 'RIFF');
      bd.setUint32(4, 56, Endian.little);
      ascii(8, 'WAVE');
      ascii(12, 'fmt ');
      bd.setUint32(16, 16, Endian.little);
      bd.setUint16(20, 3, Endian.little); // audioFormat = 3 (IEEE float, not PCM 1)
      bd.setUint16(22, 2, Endian.little);
      bd.setUint32(24, 48000, Endian.little);
      bd.setUint16(34, 24, Endian.little);
      ascii(36, 'data');
      bd.setUint32(40, 12, Endian.little);
      // Embed MQA sync word in payload
      buf[44] = 0xBE;
      buf[45] = 0x04;
      buf[46] = 0x98;
      buf[47] = 0xC4;
      await file.writeAsBytes(buf);

      await expectLater(
        MqaDecoderHelper.decodeMqaFile(
          _song(file.path),
          const MediaItem(id: '1', title: 'Track'),
        ),
        throwsA(isA<MqaUnsupportedException>()),
      );
      await dir.delete(recursive: true);
    });
  });
}
