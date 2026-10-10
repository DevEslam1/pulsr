// lib/data/audio/ir_file_parser.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Decoded impulse response plus the metadata needed to reconcile it with the
/// engine's active sample rate before convolution.
///
/// [sampleRate] is the WAV's own rate (previously parsed and then discarded).
/// The convolution engine assumes the taps it receives are already at its
/// active output rate, so a caller holding an IR at a different rate must
/// resample it (see [IrFileParser.resample]) or the frequency response and
/// RT60 will be wrong (e.g. a 44.1 kHz IR played out at 48/96/192 kHz).
class IrWavData {
  final List<double> samples;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  const IrWavData({
    required this.samples,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  });
}

/// Parses standard WAV files containing room impulse responses (IR) into
/// normalized float arrays suitable for DSP convolution reverb.
class IrFileParser {
  static const int maxSampleRate = 192000;
  static const int maxSamples = 480000; // 10 seconds at 48 kHz

  // WAVE format tags (wFormatTag / SubFormat GUID leading word).
  static const int _wavePcm = 1;
  static const int _waveIeeeFloat = 3;
  static const int _waveExtensible = 0xFFFE;

  /// Reads [file] and parses audio data into normalized [-1.0, 1.0] float
  /// samples. Backward-compatible: existing callers that only need the mono
  /// taps keep working unchanged.
  static Future<List<double>> parseWavFile(File file) async =>
      (await parseWavFileWithInfo(file)).samples;

  /// Like [parseWavFile] but also returns the WAV's native sample rate so the
  /// caller can resample to the engine's active rate before convolution.
  static Future<IrWavData> parseWavFileWithInfo(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('IR WAV file not found', file.path);
    }
    final bytes = await file.readAsBytes();
    return parseWavBytesWithInfo(bytes);
  }

  /// Parses in-memory WAV byte buffer, returning only the mono taps.
  /// Backward-compatible with every existing caller.
  static List<double> parseWavBytes(Uint8List bytes) =>
      parseWavBytesWithInfo(bytes).samples;

  /// Parses in-memory WAV byte buffer, returning taps plus the native rate.
  static IrWavData parseWavBytesWithInfo(Uint8List bytes) {
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
    int audioFormat = _wavePcm; // 1 = PCM, 3 = IEEE Float, 0xFFFE = EXTENSIBLE
    int numChannels = 1;
    int sampleRate = 48000;
    int bitsPerSample = 16;
    // For WAVE_FORMAT_EXTENSIBLE the true sample format is carried by the
    // SubFormat GUID, not wFormatTag. null until a valid fmt chunk is read.
    int? extensibleSubFormat;
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
        // Decode the EXTENSIBLE SubFormat GUID. The fmt chunk is laid out as
        // 16 base bytes + cbSize(2) + validBits(2) + channelMask(4) +
        // SubFormat GUID(16); the GUID's first 2 bytes are the real tag
        // (1 = PCM, 3 = IEEE float). This is the bug fix for float IRs that
        // were being decoded as signed PCM (and badly mis-scaled).
        if (audioFormat == _waveExtensible && chunkSize >= 40) {
          final subOffset = pos + 8 + 24;
          if (subOffset + 2 <= bytes.length &&
              subOffset + 2 <= pos + 8 + chunkSize) {
            extensibleSubFormat = byteData.getUint16(subOffset, Endian.little);
          }
        }
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

    // Resolve the effective sample format: EXTENSIBLE defers to its SubFormat
    // GUID (defaulting to PCM when the GUID is absent/truncated).
    final int effectiveFormat = audioFormat == _waveExtensible
        ? (extensibleSubFormat ?? _wavePcm)
        : audioFormat;

    final List<double> samples = [];
    final int bytesPerSample = bitsPerSample ~/ 8;
    if (bytesPerSample <= 0 || numChannels <= 0) {
      throw FormatException(
          'Unsupported WAV format (bits=$bitsPerSample, channels=$numChannels)');
    }
    final int frameSize = numChannels * bytesPerSample;
    final int numFrames = dataLength ~/ frameSize;
    final int framesToRead = numFrames.clamp(0, maxSamples);

    for (int i = 0; i < framesToRead; i++) {
      final frameOffset = dataOffset + (i * frameSize);
      double frameVal = 0.0;

      for (int ch = 0; ch < numChannels; ch++) {
        final sampleOffset = frameOffset + (ch * bytesPerSample);
        double chVal = 0.0;

        if (effectiveFormat == _waveIeeeFloat && bitsPerSample == 32) {
          // 32-bit IEEE Float
          chVal = byteData.getFloat32(sampleOffset, Endian.little);
        } else if (effectiveFormat == _waveIeeeFloat && bitsPerSample == 64) {
          // 64-bit IEEE Float (rare, but valid under EXTENSIBLE)
          chVal = byteData.getFloat64(sampleOffset, Endian.little);
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
            // Dart ints are 64-bit, so `|= 0xFF000000` would yield a large
            // positive value; subtract 2^24 to recover the signed sample.
            val24 -= 0x1000000;
          }
          chVal = val24 / 8388608.0;
        } else if (bitsPerSample == 32) {
          // 32-bit signed PCM
          final int raw32 = byteData.getInt32(sampleOffset, Endian.little);
          chVal = raw32 / 2147483648.0;
        }
        frameVal += chVal;
      }

      // Mix channels to mono without destructive early clamping
      final monoVal = frameVal / numChannels;
      samples.add(monoVal);
    }

    _peakNormalize(samples);

    return IrWavData(
      samples: samples,
      sampleRate: sampleRate,
      channels: numChannels,
      bitsPerSample: bitsPerSample,
    );
  }

  /// True peak-normalizes [samples] in place when any peak exceeds 1.0 (e.g. an
  /// un-normalized float IR); otherwise just clamps stray values into range.
  static void _peakNormalize(List<double> samples) {
    double maxPeak = 0.0;
    for (int i = 0; i < samples.length; i++) {
      final absVal = samples[i].abs();
      if (absVal > maxPeak) maxPeak = absVal;
    }
    if (maxPeak > 1.0) {
      final factor = 1.0 / maxPeak;
      for (int i = 0; i < samples.length; i++) {
        samples[i] *= factor;
      }
    } else {
      for (int i = 0; i < samples.length; i++) {
        samples[i] = samples[i].clamp(-1.0, 1.0);
      }
    }
  }

  /// Resamples [input] from [fromRate] to [toRate] using a Blackman-windowed
  /// sinc interpolation kernel (high quality). On downsampling the kernel's
  /// cutoff is lowered to the output Nyquist to suppress aliasing; the
  /// per-output weight normalization preserves the IR's overall level.
  ///
  /// This is the documented high-quality path. A plain linear interpolation
  /// ([resampleLinear]) is kept as a cheap, well-understood floor for callers
  /// that need it. Returns [input] unchanged when the rates match or inputs are
  /// degenerate. The result is capped at [maxSamples] frames.
  static List<double> resample(List<double> input, int fromRate, int toRate) {
    if (input.length < 2 || fromRate <= 0 || toRate <= 0 || fromRate == toRate) {
      return input;
    }
    final double ratio = toRate / fromRate;
    final int outLength =
        math.min((input.length * ratio).floor(), maxSamples);
    if (outLength <= 0) return <double>[];

    // Half-width of the sinc kernel in INPUT samples. On downsampling the
    // kernel widens (divided by ratio) so the anti-alias low-pass still spans
    // enough input taps.
    const int baseHalf = 16;
    final double cutoff = ratio < 1.0 ? ratio : 1.0;
    final int halfWindow =
        ratio < 1.0 ? (baseHalf / ratio).ceil().clamp(baseHalf, 256) : baseHalf;
    final double step = fromRate / toRate; // input samples per output sample
    final int n = input.length;

    final out = List<double>.filled(outLength, 0.0);
    for (int i = 0; i < outLength; i++) {
      final double center = i * step;
      final int centerFloor = center.floor();
      final int left = centerFloor - halfWindow + 1;
      final int right = centerFloor + halfWindow;
      double acc = 0.0;
      double norm = 0.0;
      for (int k = left; k <= right; k++) {
        if (k < 0 || k >= n) continue;
        final double w = _kernel(center - k, cutoff, halfWindow);
        acc += input[k] * w;
        norm += w;
      }
      out[i] = norm != 0.0 ? acc / norm : 0.0;
    }
    return out;
  }

  /// Cheap linear-interpolation resampler — the documented floor. Prefer
  /// [resample] (windowed-sinc) for correctness; this exists for callers that
  /// explicitly trade quality for cost.
  static List<double> resampleLinear(
      List<double> input, int fromRate, int toRate) {
    if (input.length < 2 || fromRate <= 0 || toRate <= 0 || fromRate == toRate) {
      return input;
    }
    final double ratio = toRate / fromRate;
    final int outLength =
        math.min((input.length * ratio).floor(), maxSamples);
    if (outLength <= 0) return <double>[];
    final double step = fromRate / toRate;
    final int n = input.length;
    final out = List<double>.filled(outLength, 0.0);
    for (int i = 0; i < outLength; i++) {
      final double src = i * step;
      final int i0 = src.floor();
      final int i1 = math.min(i0 + 1, n - 1);
      final double frac = src - i0;
      out[i] = input[i0] * (1.0 - frac) + input[i1] * frac;
    }
    return out;
  }

  /// Windowed-sinc kernel: `sinc(cutoff * t)` under a Blackman window spanning
  /// [-halfWindow, halfWindow] (in input samples).
  static double _kernel(double t, double cutoff, int halfWindow) {
    if (t.abs() > halfWindow) return 0.0;
    return _sinc(cutoff * t) * _blackman(t, halfWindow);
  }

  static double _sinc(double x) {
    if (x == 0.0) return 1.0;
    final double px = math.pi * x;
    return math.sin(px) / px;
  }

  static double _blackman(double t, int halfWindow) {
    // Normalized position in [0, 1] across the window.
    final double x = (t + halfWindow) / (2 * halfWindow);
    if (x < 0.0 || x > 1.0) return 0.0;
    return 0.42 -
        0.5 * math.cos(2 * math.pi * x) +
        0.08 * math.cos(4 * math.pi * x);
  }
}
