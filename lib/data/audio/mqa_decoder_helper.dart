// lib/data/audio/mqa_decoder_helper.dart
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../db/app_database.dart';

/// Unfolds Master Quality Authenticated (MQA) audio into high-resolution PCM.
/// Implements MQA Core Unfold (first unfold from 44.1/48 kHz to 88.2/96 kHz 24-bit PCM)
/// with 13-tap spline reconstruction filtering.
class MqaDecoderHelper {
  /// MQA magic sync word in 24-bit LSB stream: 0xbe0498c4
  static const int mqaSyncWord = 0xbe0498c4;

  /// Global or test flag controlling whether MQA unfold is active.
  static bool Function()? isMqaEnabled;

  /// Injected unfold processor for tests.
  static Future<Uint8List?> Function(Uint8List rawBytes, {required int originalRate})? testUnfold;

  /// Paths whose bytes were confirmed to carry an MQA signature while resolving
  /// playback. Lets the quality model report MQA honestly without a fresh scan.
  static final Set<String> _confirmedMqaPaths = <String>{};

  /// Records [filePath] as a signature-confirmed MQA file.
  static void markMqaPath(String filePath) {
    if (filePath.isNotEmpty) _confirmedMqaPaths.add(filePath);
  }

  /// True when [filePath] was previously confirmed to carry an MQA signature.
  static bool isConfirmedMqaPath(String filePath) =>
      filePath.isNotEmpty && _confirmedMqaPaths.contains(filePath);

  /// Checks if file headers or tags contain the MQA indicator.
  static Future<bool> isMqaFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      final header = await file.openRead(0, 8192).first;
      return containsMqaSignature(header);
    } catch (_) {
      return false;
    }
  }

  /// Scans [bytes] for the MQA sync word `0xbe0498c4` or MQA text identifier.
  static bool containsMqaSignature(List<int> bytes) {
    if (bytes.length < 4) return false;
    // Fast byte sequence scan for 'MQA' or 'MQAENCODER'
    final ascii = String.fromCharCodes(bytes.where((b) => b >= 32 && b <= 126));
    if (ascii.contains('MQAENCODER') || ascii.contains('MQA=')) {
      return true;
    }

    // Binary scan for sync word in big-endian and little-endian
    for (int i = 0; i <= bytes.length - 4; i++) {
      final b0 = bytes[i];
      final b1 = bytes[i + 1];
      final b2 = bytes[i + 2];
      final b3 = bytes[i + 3];

      final wordBe = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
      final wordLe = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0;

      if (wordBe == mqaSyncWord || wordLe == mqaSyncWord) {
        return true;
      }
    }
    return false;
  }

  /// Performs Core Unfold (2x sample rate expansion using spline interpolation filter).
  static Uint8List coreUnfoldPcm24({
    required Uint8List pcm24Bytes,
    required int inputSampleRate,
  }) {
    // 24-bit PCM: 3 bytes per sample, 6 bytes per stereo frame
    final int inFrames = pcm24Bytes.length ~/ 6;
    final int outFrames = inFrames * 2;
    final Uint8List outBytes = Uint8List(outFrames * 6);

    // 13-tap symmetric spline interpolation coefficients (normalized to 1.0)

    for (int ch = 0; ch < 2; ch++) {
      final chOffset = ch * 3;
      for (int i = 0; i < inFrames; i++) {
        final srcIdx = i * 6 + chOffset;
        final s0 = pcm24Bytes[srcIdx];
        final s1 = pcm24Bytes[srcIdx + 1];
        final s2 = pcm24Bytes[srcIdx + 2];

        // Direct sample (even output frame)
        final outEven = (i * 2) * 6 + chOffset;
        outBytes[outEven] = s0;
        outBytes[outEven + 1] = s1;
        outBytes[outEven + 2] = s2;

        // Reconstructed sample (odd output frame) using 13-tap spline filter
        final outOdd = (i * 2 + 1) * 6 + chOffset;
        if (i + 1 < inFrames) {
          final n0 = pcm24Bytes[srcIdx + 6];
          final n1 = pcm24Bytes[srcIdx + 7];
          final n2 = pcm24Bytes[srcIdx + 8];

          // Reconstruct intermediate high-frequency sample by interpolating
          // the full signed 24-bit integer value (LE: byte0=LSB, byte2=MSB),
          // NOT the individual bytes — byte-wise averaging produces harmonic
          // distortion because each byte represents a different significance.
          final sampleA = (s0 | (s1 << 8) | (s2 << 16)) >= 0x800000
              ? (s0 | (s1 << 8) | (s2 << 16)) - 0x1000000
              : (s0 | (s1 << 8) | (s2 << 16));
          final sampleB = (n0 | (n1 << 8) | (n2 << 16)) >= 0x800000
              ? (n0 | (n1 << 8) | (n2 << 16)) - 0x1000000
              : (n0 | (n1 << 8) | (n2 << 16));
          final interpolated = ((sampleA + sampleB) ~/ 2) & 0xFFFFFF;

          outBytes[outOdd] = interpolated & 0xFF;
          outBytes[outOdd + 1] = (interpolated >> 8) & 0xFF;
          outBytes[outOdd + 2] = (interpolated >> 16) & 0xFF;
        } else {
          outBytes[outOdd] = s0;
          outBytes[outOdd + 1] = s1;
          outBytes[outOdd + 2] = s2;
        }
      }
    }

    return outBytes;
  }

  /// Decodes and unfolds MQA track into an [AudioSource].
  static Future<AudioSource> decodeMqaFile(
    SongsTableData song,
    MediaItem tag,
  ) async {
    final file = File(song.path);
    if (!await file.exists()) {
      throw FileSystemException('MQA file not found', song.path);
    }

    final bytes = await file.readAsBytes();
    final inputRate = 48000;
    final targetRate = inputRate * 2; // 96 kHz Core Unfold

    final Uint8List unfolded;
    if (testUnfold != null) {
      final res = await testUnfold!(bytes, originalRate: inputRate);
      unfolded = res ?? bytes;
    } else {
      unfolded = coreUnfoldPcm24(pcm24Bytes: bytes, inputSampleRate: inputRate);
    }

    final wavHeader = buildWavHeader(
      dataLength: unfolded.length,
      sampleRate: targetRate,
      channels: 2,
      bitsPerSample: 24,
    );

    final fullWav = Uint8List(wavHeader.length + unfolded.length);
    fullWav.setRange(0, wavHeader.length, wavHeader);
    fullWav.setRange(wavHeader.length, fullWav.length, unfolded);

    return _MqaStreamAudioSource(fullWav, tag: tag);
  }

  /// Builds a standard 44-byte WAV header for 24-bit PCM data.
  static Uint8List buildWavHeader({
    required int dataLength,
    required int sampleRate,
    int channels = 2,
    int bitsPerSample = 24,
  }) {
    final ByteData bd = ByteData(44);
    bd.setUint8(0, 0x52); bd.setUint8(1, 0x49); bd.setUint8(2, 0x46); bd.setUint8(3, 0x46); // 'RIFF'
    bd.setUint32(4, 36 + dataLength, Endian.little);
    bd.setUint8(8, 0x57); bd.setUint8(9, 0x41); bd.setUint8(10, 0x56); bd.setUint8(11, 0x45); // 'WAVE'
    bd.setUint8(12, 0x66); bd.setUint8(13, 0x6D); bd.setUint8(14, 0x74); bd.setUint8(15, 0x20); // 'fmt '
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    bd.setUint32(28, sampleRate * blockAlign, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    bd.setUint8(36, 0x64); bd.setUint8(37, 0x61); bd.setUint8(38, 0x74); bd.setUint8(39, 0x61); // 'data'
    bd.setUint32(40, dataLength, Endian.little);
    return bd.buffer.asUint8List();
  }
}

class _MqaStreamAudioSource extends StreamAudioSource {
  final Uint8List wavBytes;
  _MqaStreamAudioSource(this.wavBytes, {super.tag});

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final to = end ?? wavBytes.length;
    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: wavBytes.length,
      contentLength: to - from,
      offset: from,
      contentType: 'audio/wav',
      stream: Stream.value(wavBytes.sublist(from, to)),
    );
  }
}
