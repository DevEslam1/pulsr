// lib/data/audio/dop_encoder.dart
import 'dart:typed_data';

/// Implements the DoP open standard (DSD over PCM v1.1 specification).
/// Wraps 16 bits of 1-bit DSD audio into 24-bit/32-bit PCM frames with alternating
/// 0x05 / 0xFA marker headers so that standard USB Audio Class 2.0 DACs can detect
/// and natively stream DSD without PCM conversion.
class DopEncoder {
  static const int dopMarkerA = 0x05;
  static const int dopMarkerB = 0xFA;

  /// Encodes 1-bit DSD stereo stream (left & right byte channels) into 24-bit packed PCM or 32-bit aligned PCM.
  /// [dsdLeft] and [dsdRight] must have equal length (in bytes).
  /// Every 2 bytes of DSD (16 bits) are combined with an 8-bit alternating marker to form one 24-bit PCM sample per channel.
  static Uint8List encodeToDopPcm24({
    required Uint8List dsdLeft,
    required Uint8List dsdRight,
  }) {
    final int byteCount =
        dsdLeft.length < dsdRight.length ? dsdLeft.length : dsdRight.length;
    // Each 2 bytes of DSD yields 1 24-bit PCM sample (3 bytes) per channel (6 bytes per stereo frame).
    final int numSamplesPerChannel = byteCount ~/ 2;
    final Uint8List dopBuffer = Uint8List(numSamplesPerChannel * 6);

    int outOffset = 0;
    for (int i = 0; i < numSamplesPerChannel; i++) {
      final int marker = (i % 2 == 0) ? dopMarkerA : dopMarkerB;
      final int inOffset = i * 2;

      // Left channel sample (3 bytes, Little-Endian: DSD0, DSD1, Marker)
      dopBuffer[outOffset++] = dsdLeft[inOffset];
      dopBuffer[outOffset++] = dsdLeft[inOffset + 1];
      dopBuffer[outOffset++] = marker;

      // Right channel sample (3 bytes, Little-Endian: DSD0, DSD1, Marker)
      dopBuffer[outOffset++] = dsdRight[inOffset];
      dopBuffer[outOffset++] = dsdRight[inOffset + 1];
      dopBuffer[outOffset++] = marker;
    }

    return dopBuffer;
  }

  /// Encodes into 32-bit PCM containers (LSB 0 padded, [0x00, DSD0, DSD1, Marker])
  static Uint8List encodeToDopPcm32({
    required Uint8List dsdLeft,
    required Uint8List dsdRight,
  }) {
    final int byteCount =
        dsdLeft.length < dsdRight.length ? dsdLeft.length : dsdRight.length;
    final int numSamplesPerChannel = byteCount ~/ 2;
    final Uint8List dopBuffer = Uint8List(numSamplesPerChannel * 8);

    int outOffset = 0;
    for (int i = 0; i < numSamplesPerChannel; i++) {
      final int marker = (i % 2 == 0) ? dopMarkerA : dopMarkerB;
      final int inOffset = i * 2;

      // Left channel 32-bit (Pad, DSD0, DSD1, Marker)
      dopBuffer[outOffset++] = 0x00;
      dopBuffer[outOffset++] = dsdLeft[inOffset];
      dopBuffer[outOffset++] = dsdLeft[inOffset + 1];
      dopBuffer[outOffset++] = marker;

      // Right channel 32-bit (Pad, DSD0, DSD1, Marker)
      dopBuffer[outOffset++] = 0x00;
      dopBuffer[outOffset++] = dsdRight[inOffset];
      dopBuffer[outOffset++] = dsdRight[inOffset + 1];
      dopBuffer[outOffset++] = marker;
    }

    return dopBuffer;
  }
}
