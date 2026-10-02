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
  });
}
