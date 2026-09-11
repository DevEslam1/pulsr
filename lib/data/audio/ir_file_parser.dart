// lib/data/audio/ir_file_parser.dart
import 'dart:io';
import 'dart:typed_data';

/// Parses standard WAV files containing room impulse responses (IR) into
/// normalized float arrays suitable for DSP convolution reverb.
class IrFileParser {
  static const int maxSampleRate = 192000;
  static const int maxSamples = 480000; // 10 seconds at 48 kHz

  /// Reads [file] and parses audio data into normalized [-1.0, 1.0] float samples.
  static Future<List<double>> parseWavFile(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('IR WAV file not found', file.path);
    }
    final bytes = await file.readAsBytes();
    return parseWavBytes(bytes);
  }

  /// Parses in-memory WAV byte buffer.
  static List<double> parseWavBytes(Uint8List bytes) {
    if (bytes.length < 44) {
      throw const FormatException('File too small to contain valid WAV header');
    }

    final byteData = ByteData.sublistView(bytes);

    // RIFF check
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    if (riff != 'RIFF') {
      throw FormatException('Not a valid RIFF file: $riff');
    }
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (wave != 'WAVE') {
      throw FormatException('Not a valid WAVE file: $wave');
    }

    int pos = 12;
    int audioFormat = 1; // 1 = PCM, 3 = IEEE Float
    int numChannels = 1;
    int sampleRate = 48000;
    int bitsPerSample = 16;
    int dataOffset = -1;
    int dataLength = -1;

    while (pos + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final chunkSize = byteData.getUint32(pos + 4, Endian.little);

      if (chunkId == 'fmt ') {
        audioFormat = byteData.getUint16(pos + 8, Endian.little);
        numChannels = byteData.getUint16(pos + 10, Endian.little);
        sampleRate = byteData.getUint32(pos + 12, Endian.little);
        bitsPerSample = byteData.getUint16(pos + 22, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = pos + 8;
        dataLength = chunkSize.clamp(0, bytes.length - dataOffset);
        break;
      }

      pos += 8 + chunkSize;
      if (chunkSize.isOdd) pos += 1;
    }

    if (sampleRate <= 0) {
      throw FormatException('Invalid sample rate in WAV header: $sampleRate');
    }

    if (dataOffset == -1 || dataLength <= 0) {
      throw const FormatException('WAV file contains no data subchunk');
    }

    final List<double> samples = [];
    final int bytesPerSample = bitsPerSample ~/ 8;
    final int frameSize = numChannels * bytesPerSample;
    final int numFrames = dataLength ~/ frameSize;
    final int framesToRead = numFrames.clamp(0, maxSamples);

    for (int i = 0; i < framesToRead; i++) {
      final frameOffset = dataOffset + (i * frameSize);
      double frameVal = 0.0;

      for (int ch = 0; ch < numChannels; ch++) {
        final sampleOffset = frameOffset + (ch * bytesPerSample);
        double chVal = 0.0;

        if (audioFormat == 3 && bitsPerSample == 32) {
          // 32-bit IEEE Float
          chVal = byteData.getFloat32(sampleOffset, Endian.little);
        } else if (bitsPerSample == 16) {
          // 16-bit signed PCM
          final int raw16 = byteData.getInt16(sampleOffset, Endian.little);
          chVal = raw16 / 32768.0;
        } else if (bitsPerSample == 24) {
          // 24-bit signed PCM
          final b0 = bytes[sampleOffset];
          final b1 = bytes[sampleOffset + 1];
          final b2 = bytes[sampleOffset + 2];
          int val24 = (b2 << 16) | (b1 << 8) | b0;
          if ((val24 & 0x800000) != 0) {
            val24 |= 0xFF000000;
          }
          chVal = val24 / 8388608.0;
        } else if (bitsPerSample == 32) {
          // 32-bit signed PCM
          final int raw32 = byteData.getInt32(sampleOffset, Endian.little);
          chVal = raw32 / 2147483648.0;
        }
        frameVal += chVal;
      }

      // Mix channels to mono
      final monoVal = (frameVal / numChannels).clamp(-1.0, 1.0);
      samples.add(monoVal);
    }

    return samples;
  }
}
