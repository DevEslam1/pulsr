// lib/data/audio/dop_encoder.dart
import 'dart:typed_data';

import 'dop_native_framer_stub.dart'
    if (dart.library.ffi) 'dop_native_framer_io.dart' as native_framer;

/// Implements the DoP open standard (DSD over PCM v1.1 specification).
/// Wraps 16 bits of 1-bit DSD audio into 24-bit/32-bit PCM frames with alternating
/// 0x05 / 0xFA marker headers so that standard USB Audio Class 2.0 DACs can detect
/// and natively stream DSD without PCM conversion.
///
/// On Android this delegates to the authoritative native C++ `DopFramer` in
/// `libpulsr_dsp.so` via FFI, falling back to the identical pure-Dart path in
/// host tests or platforms without the native library.
class DopEncoder {
  static const int dopMarkerA = 0x05;
  static const int dopMarkerB = 0xFA;

  static bool forceDartFallbackForTesting = false;

  static void setNativeLibraryPathForTesting(String? path) =>
      native_framer.setDopNativeLibraryPathForTesting(path);

  static final Uint8List _bitReverseLut = () {
    final table = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      int v = i;
      int r = 0;
      for (int b = 0; b < 8; b++) {
        r = (r << 1) | (v & 1);
        v >>= 1;
      }
      table[i] = r;
    }
    return table;
  }();

  static void _validateInputs(
    Uint8List dsdLeft,
    Uint8List dsdRight,
    int firstMarker,
  ) {
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
    if (firstMarker != dopMarkerA && firstMarker != dopMarkerB) {
      throw ArgumentError.value(
        firstMarker,
        'firstMarker',
        'DoP marker must be 0x05 or 0xFA.',
      );
    }
  }

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

  /// Encodes 1-bit DSD stereo stream (left & right byte channels) into 24-bit packed PCM.
  /// [dsdLeft] and [dsdRight] must have equal even length (in bytes).
  /// Set [reverseBits] when the input bytes are LSB-first (Sony DSF) so bit
  /// reversal happens inline without extra intermediate copies.
  static Uint8List encodeToDopPcm24({
    required Uint8List dsdLeft,
    required Uint8List dsdRight,
    bool reverseBits = false,
    int firstMarker = dopMarkerA,
  }) {
    _validateInputs(dsdLeft, dsdRight, firstMarker);
    if (!forceDartFallbackForTesting) {
      final nativeResult = native_framer.encodeDopPlanarNative(
        dsdLeft: dsdLeft,
        dsdRight: dsdRight,
        containerBits: 24,
        reverseBits: reverseBits,
        firstMarker: firstMarker,
      );
      if (nativeResult != null) return nativeResult;
    }

    final int byteCount = dsdLeft.length;
    // Each 2 bytes of DSD yields 1 24-bit PCM sample (3 bytes) per channel (6 bytes per stereo frame).
    final int numSamplesPerChannel = byteCount ~/ 2;
    final Uint8List dopBuffer = Uint8List(numSamplesPerChannel * 6);
    final int markerFlip =
        (firstMarker == dopMarkerA) ? dopMarkerB : dopMarkerA;

    int outOffset = 0;
    for (int i = 0; i < numSamplesPerChannel; i++) {
      final int marker = (i % 2 == 0) ? firstMarker : markerFlip;
      final int inOffset = i * 2;

      int l0 = dsdLeft[inOffset];
      int l1 = dsdLeft[inOffset + 1];
      int r0 = dsdRight[inOffset];
      int r1 = dsdRight[inOffset + 1];
      if (reverseBits) {
        l0 = _bitReverseLut[l0];
        l1 = _bitReverseLut[l1];
        r0 = _bitReverseLut[r0];
        r1 = _bitReverseLut[r1];
      }

      // DoP 1.1: the 24-bit word is [marker | older DSD byte | newer DSD
      // byte] (marker = bits 23..16, oldest DSD bit = MSB). Stored
      // little-endian that is: newer byte, older byte, marker.
      dopBuffer[outOffset++] = l1;
      dopBuffer[outOffset++] = l0;
      dopBuffer[outOffset++] = marker;

      dopBuffer[outOffset++] = r1;
      dopBuffer[outOffset++] = r0;
      dopBuffer[outOffset++] = marker;
    }

    return dopBuffer;
  }

  /// Encodes into 32-bit PCM containers (LSB 0 padded). Set [reverseBits]
  /// when the input bytes are LSB-first (Sony DSF).
  static Uint8List encodeToDopPcm32({
    required Uint8List dsdLeft,
    required Uint8List dsdRight,
    bool reverseBits = false,
    int firstMarker = dopMarkerA,
  }) {
    _validateInputs(dsdLeft, dsdRight, firstMarker);
    if (!forceDartFallbackForTesting) {
      final nativeResult = native_framer.encodeDopPlanarNative(
        dsdLeft: dsdLeft,
        dsdRight: dsdRight,
        containerBits: 32,
        reverseBits: reverseBits,
        firstMarker: firstMarker,
      );
      if (nativeResult != null) return nativeResult;
    }

    final int byteCount = dsdLeft.length;
    final int numSamplesPerChannel = byteCount ~/ 2;
    final Uint8List dopBuffer = Uint8List(numSamplesPerChannel * 8);
    final int markerFlip =
        (firstMarker == dopMarkerA) ? dopMarkerB : dopMarkerA;

    int outOffset = 0;
    for (int i = 0; i < numSamplesPerChannel; i++) {
      final int marker = (i % 2 == 0) ? firstMarker : markerFlip;
      final int inOffset = i * 2;

      int l0 = dsdLeft[inOffset];
      int l1 = dsdLeft[inOffset + 1];
      int r0 = dsdRight[inOffset];
      int r1 = dsdRight[inOffset + 1];
      if (reverseBits) {
        l0 = _bitReverseLut[l0];
        l1 = _bitReverseLut[l1];
        r0 = _bitReverseLut[r0];
        r1 = _bitReverseLut[r1];
      }

      // 32-bit container, little-endian: pad, newer, older, marker (same
      // byte significance as the 24-bit form, see encodeToDopPcm24).
      dopBuffer[outOffset++] = 0x00;
      dopBuffer[outOffset++] = l1;
      dopBuffer[outOffset++] = l0;
      dopBuffer[outOffset++] = marker;

      dopBuffer[outOffset++] = 0x00;
      dopBuffer[outOffset++] = r1;
      dopBuffer[outOffset++] = r0;
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
