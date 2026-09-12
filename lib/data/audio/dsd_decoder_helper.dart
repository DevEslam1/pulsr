// lib/data/audio/dsd_decoder_helper.dart
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../db/app_database.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/platform_capabilities.dart';
import '../../domain/models/audio_quality_info.dart';
import 'audio_effects_channel.dart';
import 'dop_encoder.dart';

/// Thrown when a DSD (DSF/DFF) file is played on a platform/build with no
/// native DSD decoder — most notably iOS, where the `decodeDsd` channel method
/// returns null. Callers must catch this and fail the track gracefully instead
/// of letting a raw [UnsupportedError] escape.
class DsdUnsupportedException implements Exception {
  final String message;

  const DsdUnsupportedException([
    this.message = 'DSD playback is not supported on this platform',
  ]);

  @override
  String toString() => 'DsdUnsupportedException: $message';
}

typedef DsdDecodeFunction = Future<List<double>?> Function(
  List<int> dsdL,
  List<int> dsdR, {
  int dsdRate,
  int targetSampleRate,
  int bitOrder,
});

/// What the output device can accept for DSD playback, probed natively.
///
/// [dop] is the single gate for framing DSD as DSD-over-PCM. Android exposes no
/// true "supports native DSD" flag, so the native side reports [dop] only when a
/// USB DAC is physically connected (UAC2 devices may accept DoP); otherwise
/// every flag is false and playback stays on the PCM path.
class DsdDacCapabilities {
  final bool dsd64;
  final bool dsd128;
  final bool dsd256;
  final bool dop;
  final bool nativeDac;

  const DsdDacCapabilities({
    required this.dsd64,
    required this.dsd128,
    required this.dsd256,
    required this.dop,
    required this.nativeDac,
  });

  static const DsdDacCapabilities none = DsdDacCapabilities(
    dsd64: false,
    dsd128: false,
    dsd256: false,
    dop: false,
    nativeDac: false,
  );

  /// True when DoP is possible on this output path: a USB DAC is present and it
  /// advertises at least one carrier rate DoP can use. A DAC that exposes none
  /// of the carrier rates cannot carry DoP, so the UI must not enable it.
  bool get canUseDop => dop && (dsd64 || dsd128 || dsd256);

  /// Whether this device advertises the DoP carrier rate for [dsdRate]
  /// (the DSD multiple of 44.1 kHz: 64, 128 or 256). Rates above DSD256 have no
  /// standard DoP carrier and always report false.
  bool supportsRate(int dsdRate) {
    if (dsdRate <= 0) return false;
    if (dsdRate <= 64) return dsd64;
    if (dsdRate <= 128) return dsd128;
    if (dsdRate <= 256) return dsd256;
    return false;
  }

  @override
  String toString() =>
      'DsdDacCapabilities(dsd64: $dsd64, dsd128: $dsd128, dsd256: $dsd256, '
      'dop: $dop, nativeDac: $nativeDac)';
}

/// Streams in-memory WAV data produced by decoding DSD (DSF/DFF) files.
class DsdPcmStreamAudioSource extends StreamAudioSource {
  final Uint8List wavBytes;

  DsdPcmStreamAudioSource(this.wavBytes, {super.tag});

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

/// Helper for parsing Sony DSF and Philips/EA DFF audio files and feeding
/// them into the native DSD-to-PCM decoder.
class DsdDecoderHelper {
  /// Injected decoder for tests when running outside of the Android runtime.
  static DsdDecodeFunction? testDecoder;

  static const MethodChannel _hiresChannel = MethodChannel(PulsrChannels.hiresDac);

  /// Probes the native output path for DSD-over-PCM capability.
  ///
  /// Calls the `HiResDacPlugin.getDopCapabilities` channel method directly (the
  /// facade lives here so `HiResAudioService` stays untouched). Any error — no
  /// plugin, non-Android platform, timeout — reports [DsdDacCapabilities.none],
  /// so DoP can never be claimed when the probe is unavailable.
  static Future<DsdDacCapabilities> probeDopCapabilities() async {
    if (!PlatformCapabilities.isAndroid) return DsdDacCapabilities.none;
    try {
      final map = await _hiresChannel
          .invokeMapMethod<String, dynamic>('getDopCapabilities')
          .timeout(const Duration(seconds: 2));
      if (map == null) return DsdDacCapabilities.none;
      return DsdDacCapabilities(
        dsd64: map['dsd64'] == true,
        dsd128: map['dsd128'] == true,
        dsd256: map['dsd256'] == true,
        dop: map['dop'] == true,
        nativeDac: map['nativeDac'] == true,
      );
    } catch (_) {
      return DsdDacCapabilities.none;
    }
  }

  /// Parses a DSF or DFF file, decodes DSD frames via the native C++ decoder or
  /// wraps the raw bitstream into DoP (DSD over PCM) frames, and packages the
  /// resulting audio into an [AudioSource].
  ///
  /// [forceDop] is set by the router only when the user selected DoP output and
  /// the native probe confirmed a compatible USB DAC. Even then it is honored
  /// only when the file's DSD rate has a standard DoP carrier and
  /// [dopCapabilities] (when supplied) advertises it; otherwise playback falls
  /// back to the PCM decode path and [AudioQualityInfo.dsdDopActive] stays false.
  static Future<AudioSource> decodeDsdFile(
    SongsTableData song,
    MediaItem tag, {
    bool forceDop = false,
    DsdDacCapabilities? dopCapabilities,
  }) async {
    final file = File(song.path);
    if (!await file.exists()) {
      throw FileSystemException('DSD file not found', song.path);
    }
    final bytes = await file.readAsBytes();
    final ext = song.path.split('.').last.toLowerCase();

    final Uint8List dsdL;
    final Uint8List dsdR;
    final int dsdRate;
    final int bitOrder;

    if (ext == 'dsf') {
      final parsed = parseDsfBytes(bytes);
      dsdL = parsed.dsdL;
      dsdR = parsed.dsdR;
      dsdRate = parsed.dsdRate;
      bitOrder = 0; // MSB first (Sony DSF)
    } else {
      final parsed = parseDffBytes(bytes);
      dsdL = parsed.dsdL;
      dsdR = parsed.dsdR;
      dsdRate = parsed.dsdRate;
      bitOrder = 1; // LSB first (DFF)
    }

    final int dopSampleRate = DopEncoder.dopPcmSampleRate(dsdRate);
    final bool useDop = forceDop &&
        dopSampleRate > 0 &&
        (dopCapabilities == null || dopCapabilities.supportsRate(dsdRate));
    AudioQualityInfo.dsdDopActive = useDop;
    if (useDop) {
      // DoP framing (DSD over PCM v1.1): pack 16-bit DSD chunks with alternating 0x05/0xFA markers
      var left = dsdL;
      var right = dsdR;
      if (left.length != right.length) {
        final minLen = math.min(left.length, right.length);
        left = Uint8List.sublistView(left, 0, minLen);
        right = Uint8List.sublistView(right, 0, minLen);
      }
      if (left.length.isOdd) {
        left = Uint8List.fromList([...left, 0]);
        right = Uint8List.fromList([...right, 0]);
      }

      final dopBytes = DopEncoder.encodeToDopPcm24(dsdLeft: left, dsdRight: right);

      final wavBytes = buildDopWavContainer(
        dopPcmBytes: dopBytes,
        sampleRate: dopSampleRate,
        channels: 2,
        bitsPerSample: 24,
      );

      return DsdPcmStreamAudioSource(wavBytes, tag: tag);
    }

    final targetSampleRate = switch (dsdRate) {
      >= 256 || >= 11289600 => 705600, // DSD256
      >= 128 || >= 5644800 => 352800,  // DSD128
      _ => 176400,                     // DSD64
    };

    final decoder = testDecoder ?? AudioEffectsChannel().decodeDsd;
    final pcmFloats = await decoder(
      dsdL,
      dsdR,
      dsdRate: dsdRate,
      targetSampleRate: targetSampleRate,
      bitOrder: bitOrder,
    );

    if (pcmFloats == null || pcmFloats.isEmpty) {
      // Non-Android has no native decoder at all (the channel returns null);
      // Android can still fail when libpulsr_dsp is absent. Both are handled,
      // user-visible failures — never a raw UnsupportedError.
      throw DsdUnsupportedException(
        PlatformCapabilities.isAndroid
            ? 'The native DSD decoder is unavailable or returned an empty PCM stream.'
            : 'DSD playback is not supported on this platform.',
      );
    }

    final wavBytes = buildWavContainer(
      pcmFloatSamples: pcmFloats,
      sampleRate: targetSampleRate,
      channels: 2,
    );

    return DsdPcmStreamAudioSource(wavBytes, tag: tag);
  }

  /// Parses DSF header and demuxes planar channel data blocks.
  static ({Uint8List dsdL, Uint8List dsdR, int dsdRate}) parseDsfBytes(
      Uint8List bytes) {
    if (bytes.length < 52) {
      throw const FormatException('DSF file too small to contain valid headers');
    }
    final byteData = ByteData.sublistView(bytes);

    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic != 'DSD ') {
      throw FormatException('Not a valid DSF file: magic is $magic');
    }

    int pos = 28;
    int dsdRate = 64;
    int channels = 2;
    int blockSize = 4096;
    int samplingFrequency = 2822400;
    int dataOffset = -1;
    int dataSize = -1;

    while (pos + 12 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final chunkSize = byteData.getUint64(pos + 4, Endian.little);

      if (chunkId == 'fmt ') {
        channels = byteData.getUint32(pos + 24, Endian.little);
        samplingFrequency = byteData.getUint32(pos + 28, Endian.little);
        blockSize = byteData.getUint32(pos + 44, Endian.little);
        dsdRate = samplingFrequency ~/ 44100;
      } else if (chunkId == 'data') {
        dataOffset = pos + 12;
        dataSize = chunkSize - 12;
        break;
      }

      pos += chunkSize;
      if (chunkSize <= 0) break;
    }

    if (dataOffset == -1 || dataOffset + dataSize > bytes.length) {
      dataOffset = pos + 12;
      dataSize = bytes.length - dataOffset;
    }

    if (dataSize <= 0 || dataOffset >= bytes.length) {
      throw const FormatException('DSF file contains no audio data');
    }

    final payload = bytes.sublist(
        dataOffset, (dataOffset + dataSize).clamp(0, bytes.length));
    final List<int> leftBytes = [];
    final List<int> rightBytes = [];

    if (blockSize <= 0) {
      blockSize = 4096;
    }
    final stride = blockSize * (channels > 0 ? channels : 2);
    if (stride <= 0) {
      throw const FormatException('Invalid DSF stride/block size');
    }
    for (int offset = 0; offset < payload.length; offset += stride) {
      final leftEnd = (offset + blockSize).clamp(0, payload.length);
      if (offset < leftEnd) {
        leftBytes.addAll(payload.sublist(offset, leftEnd));
      }
      final rightStart = offset + blockSize;
      final rightEnd = (rightStart + blockSize).clamp(0, payload.length);
      if (rightStart < rightEnd) {
        rightBytes.addAll(payload.sublist(rightStart, rightEnd));
      }
    }

    return (
      dsdL: Uint8List.fromList(leftBytes),
      dsdR: Uint8List.fromList(rightBytes),
      dsdRate: dsdRate > 0 ? dsdRate : 64,
    );
  }

  /// Parses DFF header and demuxes interleaved audio bytes.
  static ({Uint8List dsdL, Uint8List dsdR, int dsdRate}) parseDffBytes(
      Uint8List bytes) {
    if (bytes.length < 32) {
      throw const FormatException('DFF file too small to contain valid headers');
    }
    final byteData = ByteData.sublistView(bytes);

    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic != 'FRM8') {
      throw FormatException('Not a valid DFF file: magic is $magic');
    }

    int pos = 12;
    int dsdRate = 64;
    int dataOffset = -1;
    int dataSize = -1;

    while (pos + 12 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final chunkSize = byteData.getUint64(pos + 4, Endian.big);

      if (chunkId == 'FS  ') {
        final sampleRate = byteData.getUint32(pos + 12, Endian.big);
        dsdRate = sampleRate ~/ 44100;
      } else if (chunkId == 'DSD ') {
        dataOffset = pos + 12;
        dataSize = chunkSize.clamp(0, bytes.length - dataOffset);
        break;
      }

      pos += (12 + chunkSize);
      if (chunkSize <= 0) break;
    }

    if (dataOffset == -1 || dataOffset >= bytes.length) {
      throw const FormatException('DFF file contains no DSD audio chunk');
    }

    final payload = bytes.sublist(
        dataOffset, (dataOffset + dataSize).clamp(0, bytes.length));
    final List<int> leftBytes = [];
    final List<int> rightBytes = [];

    // Interleaved 1 byte L, 1 byte R
    for (int i = 0; i + 1 < payload.length; i += 2) {
      leftBytes.add(payload[i]);
      rightBytes.add(payload[i + 1]);
    }

    return (
      dsdL: Uint8List.fromList(leftBytes),
      dsdR: Uint8List.fromList(rightBytes),
      dsdRate: dsdRate > 0 ? dsdRate : 64,
    );
  }

  /// Builds a standard 44-byte WAV header containing 16-bit stereo PCM audio.
  static Uint8List buildWavContainer({
    required List<double> pcmFloatSamples,
    required int sampleRate,
    int channels = 2,
  }) {
    final int numFrames = pcmFloatSamples.length ~/ channels;
    final int byteCount = numFrames * channels * 2; // 16-bit PCM = 2 bytes per sample
    final ByteData byteData = ByteData(44 + byteCount);

    // RIFF header
    byteData.setUint8(0, 0x52); // 'R'
    byteData.setUint8(1, 0x49); // 'I'
    byteData.setUint8(2, 0x46); // 'F'
    byteData.setUint8(3, 0x46); // 'F'
    byteData.setUint32(4, 36 + byteCount, Endian.little);
    byteData.setUint8(8, 0x57); // 'W'
    byteData.setUint8(9, 0x41); // 'A'
    byteData.setUint8(10, 0x56); // 'V'
    byteData.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    byteData.setUint8(12, 0x66); // 'f'
    byteData.setUint8(13, 0x6D); // 'm'
    byteData.setUint8(14, 0x74); // 't'
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size
    byteData.setUint16(20, 1, Endian.little); // AudioFormat 1 = PCM
    byteData.setUint16(22, channels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    final int byteRate = sampleRate * channels * 2;
    byteData.setUint32(28, byteRate, Endian.little);
    final int blockAlign = channels * 2;
    byteData.setUint16(32, blockAlign, Endian.little);
    byteData.setUint16(34, 16, Endian.little); // BitsPerSample 16

    // data subchunk
    byteData.setUint8(36, 0x64); // 'd'
    byteData.setUint8(37, 0x61); // 'a'
    byteData.setUint8(38, 0x74); // 't'
    byteData.setUint8(39, 0x61); // 'a'
    byteData.setUint32(40, byteCount, Endian.little);

    int offset = 44;
    for (int i = 0; i < pcmFloatSamples.length; i++) {
      final double sample = pcmFloatSamples[i].clamp(-1.0, 1.0);
      final int pcm16 = (sample * 32767.0).round().clamp(-32768, 32767);
      byteData.setInt16(offset, pcm16, Endian.little);
      offset += 2;
    }

    return byteData.buffer.asUint8List();
  }

  /// Builds a 44-byte WAV header containing 24-bit stereo packed DoP PCM frames.
  static Uint8List buildDopWavContainer({
    required Uint8List dopPcmBytes,
    required int sampleRate,
    int channels = 2,
    int bitsPerSample = 24,
  }) {
    final int byteCount = dopPcmBytes.length;
    final ByteData byteData = ByteData(44 + byteCount);

    // RIFF header
    byteData.setUint8(0, 0x52); // 'R'
    byteData.setUint8(1, 0x49); // 'I'
    byteData.setUint8(2, 0x46); // 'F'
    byteData.setUint8(3, 0x46); // 'F'
    byteData.setUint32(4, 36 + byteCount, Endian.little);
    byteData.setUint8(8, 0x57); // 'W'
    byteData.setUint8(9, 0x41); // 'A'
    byteData.setUint8(10, 0x56); // 'V'
    byteData.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    byteData.setUint8(12, 0x66); // 'f'
    byteData.setUint8(13, 0x6D); // 'm'
    byteData.setUint8(14, 0x74); // 't'
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size
    byteData.setUint16(20, 1, Endian.little); // AudioFormat 1 = PCM
    byteData.setUint16(22, channels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    final int bytesPerSample = bitsPerSample ~/ 8;
    final int blockAlign = channels * bytesPerSample;
    final int byteRate = sampleRate * blockAlign;
    byteData.setUint32(28, byteRate, Endian.little);
    byteData.setUint16(32, blockAlign, Endian.little);
    byteData.setUint16(34, bitsPerSample, Endian.little);

    // data subchunk
    byteData.setUint8(36, 0x64); // 'd'
    byteData.setUint8(37, 0x61); // 'a'
    byteData.setUint8(38, 0x74); // 't'
    byteData.setUint8(39, 0x61); // 'a'
    byteData.setUint32(40, byteCount, Endian.little);

    final Uint8List outBytes = byteData.buffer.asUint8List();
    outBytes.setRange(44, 44 + byteCount, dopPcmBytes);
    return outBytes;
  }
}
