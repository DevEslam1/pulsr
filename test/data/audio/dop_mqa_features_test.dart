import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/audio_feature_info.dart';
import 'package:pulsr/data/audio/adaptive_buffer_engine.dart';
import 'package:pulsr/data/audio/collaborators/playback_volume_controller.dart';
import 'package:pulsr/data/audio/dop_encoder.dart';
import 'package:pulsr/data/audio/dsd_decoder_helper.dart';
import 'package:pulsr/data/audio/ir_file_parser.dart';
import 'package:pulsr/data/audio/mqa_decoder_helper.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  group('DoP DSD Framing & Unity Gain Tests', () {
    test('dsdNative registry states DoP output is unavailable', () {
      final info = AudioFeatureRegistry.dsdNative;
      expect(info.subtitle.toLowerCase(), contains('dop'));
      expect(info.description.toLowerCase(), contains('not implemented'));
    });

    test('DopEncoder.encodeToDopPcm24 produces valid DoP 0x05 / 0xFA marker bytes', () {
      final dsdLeft = Uint8List.fromList(List.generate(8, (i) => 0xAA));
      final dsdRight = Uint8List.fromList(List.generate(8, (i) => 0x55));
      final dopPcm = DopEncoder.encodeToDopPcm24(
        dsdLeft: dsdLeft,
        dsdRight: dsdRight,
      );

      // 8 bytes per channel -> 4 16-bit pairs -> 4 frames * 6 bytes = 24 bytes
      expect(dopPcm.length, equals(24));

      // Little-endian 24-bit: byte 0 = DSD0, byte 1 = DSD1, byte 2 = Marker
      // Frame 0 (even): L Marker = dopPcm[2], R Marker = dopPcm[5]
      expect(dopPcm[2], equals(0x05));
      expect(dopPcm[5], equals(0x05));

      // Frame 1 (odd): L Marker = dopPcm[8], R Marker = dopPcm[11]
      expect(dopPcm[8], equals(0xFA));
      expect(dopPcm[11], equals(0xFA));
    });

    test('DsdDecoderHelper.buildDopWavContainer creates valid 24-bit PCM WAV header', () {
      final dopData = Uint8List(480);
      final wav = DsdDecoderHelper.buildDopWavContainer(
        dopPcmBytes: dopData,
        sampleRate: 176400,
        channels: 2,
      );

      expect(wav.length, equals(44 + 480));
      expect(String.fromCharCodes(wav.sublist(0, 4)), equals('RIFF'));
      expect(String.fromCharCodes(wav.sublist(8, 12)), equals('WAVE'));
      expect(String.fromCharCodes(wav.sublist(12, 16)), equals('fmt '));

      final byteData = ByteData.sublistView(wav);
      expect(byteData.getUint16(20, Endian.little), equals(1));
      expect(byteData.getUint16(22, Endian.little), equals(2));
      expect(byteData.getUint32(24, Endian.little), equals(176400));
      expect(byteData.getUint16(34, Endian.little), equals(24));
      expect(String.fromCharCodes(wav.sublist(36, 40)), equals('data'));
      expect(byteData.getUint32(40, Endian.little), equals(480));
    });

    test('PlaybackVolumeController locks volume strictly to 1.0 during DoP transmission', () async {
      final activePlayer = MockAudioPlayer();
      final inactivePlayer = MockAudioPlayer();
      when(() => activePlayer.setVolume(any())).thenAnswer((_) async {});
      when(() => activePlayer.volume).thenReturn(1.0);

      final controller = PlaybackVolumeController(
        getActivePlayer: () => activePlayer,
        getInactivePlayer: () => inactivePlayer,
      );

      controller.updateSettings(
        userVolume: 0.5,
        preampWithoutRg: -6.0,
      );

      // Normal mode without DoP
      final normalVolume = controller.calculateTargetVolume(null);
      expect(normalVolume, equals(0.5));

      // DoP active: volume must be strictly locked to 1.0 (unity gain) to prevent corrupting marker bits
      controller.setDopActive(true);
      final dopVolume = controller.calculateTargetVolume(null);
      expect(dopVolume, equals(1.0));

      // Even when ducked, DoP must maintain 1.0
      await controller.setDucked(true, null);
      final dopVolumeWhileDucked = controller.calculateTargetVolume(null);
      expect(dopVolumeWhileDucked, equals(1.0));
    });
  });

  group('MQA Decoding & Core Unfolding Tests', () {
    test('MqaDecoderHelper.containsMqaSignature identifies MQA sync word', () {
      final mqaBytes = Uint8List.fromList([
        0x00, 0x11, 0x22,
        0xBE, 0x04, 0x98, 0xC4,
        0x55, 0x66, 0x77,
      ]);
      expect(MqaDecoderHelper.containsMqaSignature(mqaBytes), isTrue);

      final normalBytes = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]);
      expect(MqaDecoderHelper.containsMqaSignature(normalBytes), isFalse);
    });

    test('MqaDecoderHelper.coreUnfoldPcm24 doubles frame count with reconstructed samples', () {
      final inBytes = Uint8List.fromList([
        0x30, 0x20, 0x10, 0x60, 0x50, 0x40,
        0x34, 0x24, 0x14, 0x64, 0x54, 0x44,
      ]);

      final unfolded = MqaDecoderHelper.coreUnfoldPcm24(
        pcm24Bytes: inBytes,
        inputSampleRate: 48000,
      );

      expect(unfolded.length, equals(24));
      expect(unfolded.sublist(0, 6), equals(inBytes.sublist(0, 6)));
      expect(unfolded.sublist(6, 12).length, equals(6));
    });

    test('MqaDecoderHelper.buildWavHeader builds valid 96kHz 24-bit WAV header', () {
      final header = MqaDecoderHelper.buildWavHeader(
        dataLength: 960,
        sampleRate: 96000,
        channels: 2,
        bitsPerSample: 24,
      );

      expect(header.length, equals(44));
      final byteData = ByteData.sublistView(header);
      expect(byteData.getUint32(24, Endian.little), equals(96000));
      expect(byteData.getUint16(34, Endian.little), equals(24));
      expect(byteData.getUint32(40, Endian.little), equals(960));
    });
  });

  group('Custom IR File Parser Tests', () {
    test('IrFileParser parses and converts 16-bit PCM WAV into float range [-1.0, 1.0]', () async {
      final samplesCount = 100;
      final pcmBytes = Uint8List(samplesCount * 2);
      final pcmView = ByteData.sublistView(pcmBytes);
      for (int i = 0; i < samplesCount; i++) {
        pcmView.setInt16(i * 2, (i == 50) ? 16000 : 8000, Endian.little);
      }

      final wavBytes = BytesBuilder();
      wavBytes.add(Uint8List.fromList('RIFF'.codeUnits));
      final fileLen = 36 + pcmBytes.length;
      final fileLenData = ByteData(4)..setUint32(0, fileLen, Endian.little);
      wavBytes.add(fileLenData.buffer.asUint8List());
      wavBytes.add(Uint8List.fromList('WAVEfmt '.codeUnits));
      final fmtChunk = ByteData(20)
        ..setUint32(0, 16, Endian.little)
        ..setUint16(4, 1, Endian.little)
        ..setUint16(6, 1, Endian.little)
        ..setUint32(8, 44100, Endian.little)
        ..setUint32(12, 88200, Endian.little)
        ..setUint16(16, 2, Endian.little)
        ..setUint16(18, 16, Endian.little);
      wavBytes.add(fmtChunk.buffer.asUint8List());
      wavBytes.add(Uint8List.fromList('data'.codeUnits));
      final dataLen = ByteData(4)..setUint32(0, pcmBytes.length, Endian.little);
      wavBytes.add(dataLen.buffer.asUint8List());
      wavBytes.add(pcmBytes);

      final tempFile = File('/test_ir_16bit_.wav');
      await tempFile.writeAsBytes(wavBytes.toBytes());

      try {
        final parsed = await IrFileParser.parseWavFile(tempFile);
        expect(parsed.length, equals(samplesCount));
        // Peak sample is 16000 / 32768.0 = 0.48828...
        double maxAbs = 0.0;
        for (final s in parsed) {
          if (s.abs() > maxAbs) maxAbs = s.abs();
        }
        expect(maxAbs, closeTo(16000.0 / 32768.0, 0.001));
      } finally {
        try {
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
      }
    });

    test('IrFileParser throws FormatException on invalid WAV header', () async {
      final tempFile = File('/invalid_.wav');
      await tempFile.writeAsBytes([0x00, 0x01, 0x02, 0x03]);

      try {
        expect(
          () async => await IrFileParser.parseWavFile(tempFile),
          throwsA(isA<FormatException>()),
        );
      } finally {
        try {
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
      }
    });
  });

  group('Adaptive Bitrate Switching Tests', () {
    test('AdaptiveBufferEngine requests quality step-down upon >= 2 underruns within 30s', () async {
      final engine = AdaptiveBufferEngine();
      final requestedQualities = <String>[];

      final sub = engine.onStepDownQualityRequested.listen((q) {
        requestedQualities.add(q);
      });

      engine.recordBufferUnderrun(currentQuality: 'high');
      expect(requestedQualities, isEmpty);

      engine.recordBufferUnderrun(currentQuality: 'high');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(requestedQualities, contains('medium'));

      await sub.cancel();
      engine.dispose();
    });

    test('AdaptiveBufferEngine steps down from medium to low', () async {
      final engine = AdaptiveBufferEngine();
      final requestedQualities = <String>[];

      final sub = engine.onStepDownQualityRequested.listen((q) {
        requestedQualities.add(q);
      });

      engine.recordBufferUnderrun(currentQuality: 'medium');
      engine.recordBufferUnderrun(currentQuality: 'medium');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(requestedQualities, contains('low'));

      await sub.cancel();
      engine.dispose();
    });

    test('AdaptiveBufferEngine does not step down below low', () async {
      final engine = AdaptiveBufferEngine();
      final requestedQualities = <String>[];

      final sub = engine.onStepDownQualityRequested.listen((q) {
        requestedQualities.add(q);
      });

      engine.recordBufferUnderrun(currentQuality: 'low');
      engine.recordBufferUnderrun(currentQuality: 'low');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(requestedQualities, isEmpty);

      await sub.cancel();
      engine.dispose();
    });
  });
}
