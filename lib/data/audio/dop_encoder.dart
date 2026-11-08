// lib/data/audio/dop_encoder.dart
import 'dart:typed_data';

/// Implements the DoP open standard (DSD over PCM v1.1 specification).
/// Wraps 16 bits of 1-bit DSD audio into 24-bit/32-bit PCM frames with alternating
/// 0x05 / 0xFA marker headers so that standard USB Audio Class 2.0 DACs can detect
/// and natively stream DSD without PCM conversion.
class DopEncoder {
  static const int dopMarkerA = 0x05;
  static const int dopMarkerB = 0xFA;

  /// The PCM carrier rate for a DSD file expressed as a multiple of 44.1 kHz
  /// (DSD64 = 64, DSD128 = 128, DSD256 = 256). DoP packs 16 DSD bits into one
  /// 24-bit PCM sample, so the carrier runs at `dsdRate * 44100 / 16`:
  /// DSD64 (2.8224 MHz) → 176.4 kHz, DSD128 → 352.8 kHz, DSD256 → 705.6 kHz.
  ///
  /// Returns 0 for rates DoP cannot carry (anything above DSD256), so callers
  /// fall back to PCM instead of inventing an unsupported carrier rate.
  static int dopPcmSampleRate(int dsdRate) {
    if (dsdRate <= 0) return 0;
    if (dsdRate <= 64) return 176400;
    if (dsdRate <= 128) return 352800;
    if (dsdRate <= 256) return 705600;
    return 0;
  }

  /// Encodes 1-bit DSD stereo stream (left & right byte channels) into 24-bit packed PCM or 32-bit aligned PCM.
  /// [dsdLeft] and [dsdRight] must have equal length (in bytes).
  /// Every 2 bytes of DSD (16 bits) are combined with an 8-bit alternating marker to form one 24-bit PCM sample per channel.
  static Uint8List encodeToDopPcm24({
    required Uint8List dsdLeft,
    required Uint8List dsdRight,
  }) {
    if (dsdLeft.length != dsdRight.length) {
      throw ArgumentError(
        'DSD channels must have equal length '
        '(left=${dsdLeft.length}, right=${dsdRight.length}). '
        'Refusing to silently truncate.',
      );
    }
    if (dsdLeft.length.isOdd) {
      throw ArgumentError('DSD byte length must be even (16-bit pairs).');
    }
    final int byteCount = dsdLeft.length;
    // Each 2 bytes of DSD yields 1 24-bit PCM sample (3 bytes) per channel (6 bytes per stereo frame).
    final int numSamplesPerChannel = byteCount ~/ 2;
    final Uint8List dopBuffer = Uint8List(numSamplesPerChannel * 6);

    int outOffset = 0;
    for (int i = 0; i < numSamplesPerChannel; i++) {
      final int marker = (i % 2 == 0) ? dopMarkerA : dopMarkerB;
      final int inOffset = i * 2;

      // DoP 1.1: the 24-bit word is [marker | older DSD byte | newer DSD
      // byte] (marker = bits 23..16, oldest DSD bit = MSB). Stored
      // little-endian that is: newer byte, older byte, marker. The previous
      // order (older, newer) swapped the two DSD bytes in every word, which a
      // DoP-capable DAC decodes as noise.
      dopBuffer[outOffset++] = dsdLeft[inOffset + 1];
      dopBuffer[outOffset++] = dsdLeft[inOffset];
      dopBuffer[outOffset++] = marker;

      dopBuffer[outOffset++] = dsdRight[inOffset + 1];
      dopBuffer[outOffset++] = dsdRight[inOffset];
      dopBuffer[outOffset++] = marker;
    }

    return dopBuffer;
  }

  /// Encodes into 32-bit PCM containers (LSB 0 padded). Input DSD bytes must be
  /// MSB-first (oldest bit in bit 7); reverse DSF (LSB-first) data beforehand.
  static Uint8List encodeToDopPcm32({
    required Uint8List dsdLeft,
    required Uint8List dsdRight,
  }) {
    if (dsdLeft.length != dsdRight.length) {
      throw ArgumentError(
        'DSD channels must have equal length '
        '(left=${dsdLeft.length}, right=${dsdRight.length}).',
      );
    }
    if (dsdLeft.length.isOdd) {
      throw ArgumentError('DSD byte length must be even (16-bit pairs).');
    }
    final int byteCount = dsdLeft.length;
    final int numSamplesPerChannel = byteCount ~/ 2;
    final Uint8List dopBuffer = Uint8List(numSamplesPerChannel * 8);

    int outOffset = 0;
    for (int i = 0; i < numSamplesPerChannel; i++) {
      final int marker = (i % 2 == 0) ? dopMarkerA : dopMarkerB;
      final int inOffset = i * 2;

      // 32-bit container, little-endian: pad, newer, older, marker (same
      // byte significance as the 24-bit form, see encodeToDopPcm24).
      dopBuffer[outOffset++] = 0x00;
      dopBuffer[outOffset++] = dsdLeft[inOffset + 1];
      dopBuffer[outOffset++] = dsdLeft[inOffset];
      dopBuffer[outOffset++] = marker;

      dopBuffer[outOffset++] = 0x00;
      dopBuffer[outOffset++] = dsdRight[inOffset + 1];
      dopBuffer[outOffset++] = dsdRight[inOffset];
      dopBuffer[outOffset++] = marker;
    }

    return dopBuffer;
  }
}

/// Implements raw Native DSD bitstream packing (Direct DSD / DSD-Raw).
/// Streams 1-bit DSD audio samples directly to capable USB DAC endpoints
/// without DoP marker overhead, supporting high-rate DSD up to DSD512 (22.5792 MHz).
class DsdRawEncoder {
  const DsdRawEncoder._();

  /// Returns the native 1-bit DSD bitstream sample rate for a given DSD multiple
  /// (DSD64 = 64, DSD128 = 128, DSD256 = 256, DSD512 = 512).
  static int nativeDsdSampleRate(int dsdRate) {
    if (dsdRate <= 0) return 0;
    return dsdRate * 44100;
  }

  /// Encodes 1-bit DSD stereo stream into raw byte-interleaved channel frames
  /// (Left byte, Right byte) matching standard ALSA SNDRV_PCM_FORMAT_DSD_U8 layout.
  static Uint8List encodeToDsdRawInterleaved({
    required Uint8List dsdLeft,
    required Uint8List dsdRight,
  }) {
    if (dsdLeft.length != dsdRight.length) {
      throw ArgumentError(
        'DSD channels must have equal length '
        '(left=${dsdLeft.length}, right=${dsdRight.length}).',
      );
    }
    final int byteCount = dsdLeft.length;
    final Uint8List rawBuffer = Uint8List(byteCount * 2);

    int outOffset = 0;
    for (int i = 0; i < byteCount; i++) {
      rawBuffer[outOffset++] = dsdLeft[i];
      rawBuffer[outOffset++] = dsdRight[i];
    }
    return rawBuffer;
  }

  /// Encodes 1-bit DSD stereo stream into 32-bit native DSD words (DSD_U32_LE)
  /// matching the Linux USB Audio / ALSA Native DSD specification for DACs
  /// requiring 32-bit word alignment.
  static Uint8List encodeToDsdRawU32Le({
    required Uint8List dsdLeft,
    required Uint8List dsdRight,
  }) {
    if (dsdLeft.length != dsdRight.length) {
      throw ArgumentError(
        'DSD channels must have equal length '
        '(left=${dsdLeft.length}, right=${dsdRight.length}).',
      );
    }
    final int alignedLen = (dsdLeft.length ~/ 4) * 4;
    final Uint8List rawBuffer = Uint8List(alignedLen * 2);

    int outOffset = 0;
    for (int i = 0; i < alignedLen; i += 4) {
      // 4 bytes of Left channel (32 bits)
      rawBuffer[outOffset++] = dsdLeft[i + 0];
      rawBuffer[outOffset++] = dsdLeft[i + 1];
      rawBuffer[outOffset++] = dsdLeft[i + 2];
      rawBuffer[outOffset++] = dsdLeft[i + 3];

      // 4 bytes of Right channel (32 bits)
      rawBuffer[outOffset++] = dsdRight[i + 0];
      rawBuffer[outOffset++] = dsdRight[i + 1];
      rawBuffer[outOffset++] = dsdRight[i + 2];
      rawBuffer[outOffset++] = dsdRight[i + 3];
    }
    return rawBuffer;
  }
}
