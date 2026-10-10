// Unit tests for the IR sample-rate reconciliation + WAVE_FORMAT_EXTENSIBLE
// float decode (fix #3). Pure logic: no files, no platform channels.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/ir_file_parser.dart';

/// Builds a minimal RIFF/WAVE byte buffer with a single fmt + data chunk.
/// [formatTag] 1 = PCM, 3 = IEEE float, 0xFFFE = EXTENSIBLE (then
/// [extensibleSubFormat] carries the real tag in the SubFormat GUID).
Uint8List buildWav({
  required int formatTag,
  required int sampleRate,
  required int bitsPerSample,
  required int channels,
  required Uint8List data,
  int? extensibleSubFormat,
}) {
  const le = Endian.little;
  final fmtSize = formatTag == 0xFFFE ? 40 : 16;
  final bytesPerSample = bitsPerSample ~/ 8;

  final b = BytesBuilder();
  b.add(Uint8List.fromList('RIFF'.codeUnits));
  final fileLen = 4 + (8 + fmtSize) + (8 + data.length);
  b.add((ByteData(4)..setUint32(0, fileLen, le)).buffer.asUint8List());
  b.add(Uint8List.fromList('WAVE'.codeUnits));

  b.add(Uint8List.fromList('fmt '.codeUnits));
  b.add((ByteData(4)..setUint32(0, fmtSize, le)).buffer.asUint8List());
  final fmt = ByteData(fmtSize)
    ..setUint16(0, formatTag, le)
    ..setUint16(2, channels, le)
    ..setUint32(4, sampleRate, le)
    ..setUint32(8, sampleRate * channels * bytesPerSample, le)
    ..setUint16(12, channels * bytesPerSample, le)
    ..setUint16(14, bitsPerSample, le);
  if (fmtSize == 40) {
    fmt
      ..setUint16(16, 22, le) // cbSize
      ..setUint16(18, bitsPerSample, le) // valid bits
      ..setUint32(20, 0, le) // channel mask
      ..setUint16(24, extensibleSubFormat ?? 1, le); // SubFormat leading word
  }
  b.add(fmt.buffer.asUint8List());

  b.add(Uint8List.fromList('data'.codeUnits));
  b.add((ByteData(4)..setUint32(0, data.length, le)).buffer.asUint8List());
  b.add(data);
  return b.toBytes();
}

Uint8List float32Data(List<double> samples) {
  final bd = ByteData(samples.length * 4);
  for (var i = 0; i < samples.length; i++) {
    bd.setFloat32(i * 4, samples[i], Endian.little);
  }
  return bd.buffer.asUint8List();
}

Uint8List pcm16Data(List<int> samples) {
  final bd = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    bd.setInt16(i * 2, samples[i], Endian.little);
  }
  return bd.buffer.asUint8List();
}

void main() {
  group('IR sample-rate exposure', () {
    test('parseWavBytesWithInfo exposes the native WAV sample rate', () {
      final wav = buildWav(
        formatTag: 1,
        sampleRate: 44100,
        bitsPerSample: 16,
        channels: 1,
        data: pcm16Data(List<int>.filled(100, 8000)),
      );
      final info = IrFileParser.parseWavBytesWithInfo(wav);
      expect(info.sampleRate, 44100);
      expect(info.channels, 1);
      expect(info.bitsPerSample, 16);
      expect(info.samples.length, 100);
      // Backward-compatible accessor still returns just the taps.
      expect(IrFileParser.parseWavBytes(wav).length, info.samples.length);
    });
  });

  group('WAVE_FORMAT_EXTENSIBLE float decode', () {
    test('EXTENSIBLE float IR decodes via the SubFormat GUID, not as PCM', () {
      final values = [0.8, -0.6, 0.3];
      final wav = buildWav(
        formatTag: 0xFFFE,
        sampleRate: 48000,
        bitsPerSample: 32,
        channels: 1,
        data: float32Data(values),
        extensibleSubFormat: 3, // IEEE float
      );
      final parsed = IrFileParser.parseWavBytes(wav);
      expect(parsed.length, 3);
      // Correct float decode preserves the values; a PCM mis-read of these
      // float bit-patterns would land near ~0.49 / -0.51 / ~0.19 instead.
      expect(parsed[0], closeTo(0.8, 1e-4));
      expect(parsed[1], closeTo(-0.6, 1e-4));
      expect(parsed[2], closeTo(0.3, 1e-4));
    });

    test('plain IEEE-float (tag 3) still decodes as float', () {
      final wav = buildWav(
        formatTag: 3,
        sampleRate: 48000,
        bitsPerSample: 32,
        channels: 1,
        data: float32Data([0.5, -0.25]),
      );
      final parsed = IrFileParser.parseWavBytes(wav);
      expect(parsed[0], closeTo(0.5, 1e-4));
      expect(parsed[1], closeTo(-0.25, 1e-4));
    });
  });

  group('IR resampling', () {
    test('matching rates return the input unchanged', () {
      final input = [0.1, 0.2, 0.3, 0.4];
      expect(identical(IrFileParser.resample(input, 48000, 48000), input),
          isTrue);
    });

    test('tiny inputs are returned unchanged', () {
      expect(IrFileParser.resample(const [0.5], 44100, 48000), const [0.5]);
    });

    test('upsampling 44.1k -> 48k grows length and preserves a DC level', () {
      final input = List<double>.filled(200, 0.5);
      final out = IrFileParser.resample(input, 44100, 48000);
      expect(out.length, (200 * 48000 / 44100).floor());
      for (final v in out) {
        expect(v, closeTo(0.5, 1e-6));
      }
    });

    test('downsampling 48k -> 24k halves length and preserves a DC level', () {
      final input = List<double>.filled(200, -0.4);
      final out = IrFileParser.resample(input, 48000, 24000);
      expect(out.length, 100);
      for (final v in out) {
        expect(v, closeTo(-0.4, 1e-6));
      }
    });

    test('windowed-sinc output stays finite and bounded', () {
      final input = List<double>.generate(
          256, (i) => (i == 0) ? 1.0 : 0.0); // unit impulse
      final out = IrFileParser.resample(input, 44100, 96000);
      expect(out.isNotEmpty, isTrue);
      for (final v in out) {
        expect(v.isFinite, isTrue);
        expect(v.abs() <= 2.0, isTrue);
      }
    });

    test('linear floor interpolates between samples', () {
      final out = IrFileParser.resampleLinear([0.0, 1.0], 1, 2);
      expect(out, [0.0, 0.5, 1.0, 1.0]);
    });
  });
}
