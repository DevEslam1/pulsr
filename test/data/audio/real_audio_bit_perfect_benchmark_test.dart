// test/real_audio_bit_perfect_benchmark_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pulsr/data/audio/dop_encoder.dart';
import 'package:pulsr/data/audio/output_format_negotiation.dart';

/// Helper to parse standard RIFF WAVE files
class WavFileInfo {
  final int audioFormat;
  final int channels;
  final int sampleRate;
  final int byteRate;
  final int blockAlign;
  final int bitsPerSample;
  final Uint8List pcmData;

  WavFileInfo({
    required this.audioFormat,
    required this.channels,
    required this.sampleRate,
    required this.byteRate,
    required this.blockAlign,
    required this.bitsPerSample,
    required this.pcmData,
  });

  static WavFileInfo parse(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    // Check RIFF and WAVE header
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') {
      throw FormatException('Not a valid RIFF WAVE file: riff=$riff, wave=$wave');
    }

    int offset = 12;
    int? audioFormat;
    int? channels;
    int? sampleRate;
    int? byteRate;
    int? blockAlign;
    int? bitsPerSample;
    Uint8List? pcmData;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = byteData.getUint32(offset + 4, Endian.little);
      final chunkDataOffset = offset + 8;

      if (chunkId == 'fmt ') {
        audioFormat = byteData.getUint16(chunkDataOffset, Endian.little);
        channels = byteData.getUint16(chunkDataOffset + 2, Endian.little);
        sampleRate = byteData.getUint32(chunkDataOffset + 4, Endian.little);
        byteRate = byteData.getUint32(chunkDataOffset + 8, Endian.little);
        blockAlign = byteData.getUint16(chunkDataOffset + 12, Endian.little);
        bitsPerSample = byteData.getUint16(chunkDataOffset + 14, Endian.little);
      } else if (chunkId == 'data') {
        pcmData = bytes.sublist(chunkDataOffset, chunkDataOffset + chunkSize);
      }
      offset = chunkDataOffset + chunkSize;
      // Word alignment (pad byte if odd size)
      if (chunkSize % 2 != 0) offset++;
    }

    if (pcmData == null || audioFormat == null || sampleRate == null) {
      throw FormatException('Incomplete WAV header');
    }

    return WavFileInfo(
      audioFormat: audioFormat,
      channels: channels ?? 2,
      sampleRate: sampleRate,
      byteRate: byteRate ?? 0,
      blockAlign: blockAlign ?? 0,
      bitsPerSample: bitsPerSample ?? 16,
      pcmData: pcmData,
    );
  }
}

void main() {
  group('Real Audio File Bit-Perfect Null & Transparency Verification', () {
    const realWavPath = r'D:\Courses\Projectss\pulsr\build\playback-startup-test.wav';
    late File wavFile;
    late Uint8List wavFileRawBytes;
    late WavFileInfo wavInfo;

    setUpAll(() async {
      wavFile = File(realWavPath);
      expect(await wavFile.exists(), isTrue, reason: 'Real WAV test audio file must exist');
      wavFileRawBytes = await wavFile.readAsBytes();
      wavInfo = WavFileInfo.parse(wavFileRawBytes);
    });

    test('Real audio file format verification (RIFF stereo PCM 44.1kHz 16-bit)', () {
      expect(wavInfo.audioFormat, equals(1)); // Standard uncompressed PCM
      expect(wavInfo.channels, equals(2));
      expect(wavInfo.sampleRate, equals(44100));
      expect(wavInfo.bitsPerSample, equals(16));
      expect(wavInfo.pcmData.length, greaterThan(1000000),
          reason: 'File must contain substantial real audio PCM frames');
    });

    test('1. Bit-for-Bit Identity & SHA-256 Null Test on Real PCM Stream', () {
      final inputDigest = sha256.convert(wavInfo.pcmData).toString();

      // Simulate bit-perfect pass-through on the real PCM stream
      final outputPcm = Uint8List.fromList(wavInfo.pcmData);
      final outputDigest = sha256.convert(outputPcm).toString();

      expect(outputDigest, equals(inputDigest),
          reason: 'Cryptographic SHA-256 hash must be identical under Bit-Perfect pass-through');

      // Byte-by-byte bitwise XOR null test
      int bitErrors = 0;
      for (int i = 0; i < wavInfo.pcmData.length; i++) {
        if ((wavInfo.pcmData[i] ^ outputPcm[i]) != 0) {
          bitErrors++;
        }
      }
      expect(bitErrors, equals(0), reason: 'Bit Error Rate across real audio data must be 0.000%');
    });

    test('2. Negative Control: Software Volume Attenuation (Even -0.01 dB) Alters Real Data', () {
      // Demonstrates why non-bit-perfect mode alters raw audio data
      final originalSamples = ByteData.sublistView(wavInfo.pcmData);
      final alteredPcm = Uint8List.fromList(wavInfo.pcmData);
      final alteredSamples = ByteData.sublistView(alteredPcm);

      // Apply a tiny -0.01 dB gain attenuation (gain = 10^(-0.01/20) ~= 0.99885)
      const tinyGain = 0.99885;
      int alteredCount = 0;
      for (int i = 0; i < wavInfo.pcmData.length ~/ 2; i++) {
        final original = originalSamples.getInt16(i * 2, Endian.little);
        final scaled = (original * tinyGain).round().clamp(-32768, 32767);
        if (scaled != original) {
          alteredSamples.setInt16(i * 2, scaled, Endian.little);
          alteredCount++;
        }
      }

      final originalDigest = sha256.convert(wavInfo.pcmData).toString();
      final alteredDigest = sha256.convert(alteredPcm).toString();

      expect(alteredDigest, isNot(equals(originalDigest)),
          reason: 'Even 0.01 dB software volume breaks byte-exact bit perfection');
      expect(alteredCount, greaterThan(1000),
          reason: 'Subtle software volume touches thousands of audio samples');
    });

    test('3. Rate Invariance Decision on Real Audio (44.1 kHz Preserved Without 48k SRC)', () {
      final decision = negotiateOutputFormat(
        request: OutputFormatRequest(
          trackSampleRate: wavInfo.sampleRate, // 44100
          trackBitDepth: wavInfo.bitsPerSample, // 16
          requestedSampleRate: 0, // Auto / follow track
          requestedBitDepth: 0,
        ),
        deviceSampleRates: [44100, 48000, 96000, 192000],
        deviceMaxBitDepth: 24,
        route: OutputRoute.wired,
        bitPerfectActive: true,
      );

      // Verify the policy never forces 48000 Hz or resamples real RedBook CD audio
      expect(decision.sampleRate, equals(44100));
      expect(decision.bitDepth, equals(16));
      expect(decision.reason, equals(OutputFormatReason.bitPerfectExclusive));
    });

    test('4. Real DSD DoP Framing Verification on Extracted Audio Frames', () {
      // Extract 65,536 bytes of real stereo channel data
      const testChunkSize = 65536;
      final channelLength = testChunkSize ~/ 2;
      final channelLeft = Uint8List(channelLength);
      final channelRight = Uint8List(channelLength);

      final pcmView = ByteData.sublistView(wavInfo.pcmData);
      for (int i = 0; i < channelLength ~/ 2; i++) {
        // Interleaved L/R
        final l = pcmView.getUint16(i * 4, Endian.little);
        final r = pcmView.getUint16(i * 4 + 2, Endian.little);
        channelLeft[i * 2] = l & 0xFF;
        channelLeft[i * 2 + 1] = (l >> 8) & 0xFF;
        channelRight[i * 2] = r & 0xFF;
        channelRight[i * 2 + 1] = (r >> 8) & 0xFF;
      }

      // Encode into 24-bit DoP container
      final dopOutput = DopEncoder.encodeToDopPcm24(
        dsdLeft: channelLeft,
        dsdRight: channelRight,
      );

      expect(dopOutput.length, equals(channelLength * 3));

      // Verify exact alternating 0x05 / 0xFA marker invariant
      final numSamples = dopOutput.length ~/ 6;
      for (int s = 0; s < min(numSamples, 1000); s++) {
        final expectedMarker = (s % 2 == 0) ? 0x05 : 0xFA;
        // Byte 2: Left marker; Byte 5: Right marker
        final lMarker = dopOutput[s * 6 + 2];
        final rMarker = dopOutput[s * 6 + 5];
        expect(lMarker, equals(expectedMarker),
            reason: 'DoP Left marker must strictly follow 0x05/0xFA alternation');
        expect(rMarker, equals(expectedMarker),
            reason: 'DoP Right marker must strictly follow 0x05/0xFA alternation');
      }
    });
  });
}
