// lib/data/audio/autoeq_fir_generator.dart
import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/models/headphone_profile.dart';

/// High-fidelity AutoEQ FIR impulse response synthesizer.
///
/// Converts AutoEQ parametric biquad filter cascades into minimum-phase or
/// linear-phase FIR impulse responses (e.g. 1024, 2048, or 4096 taps).
///
/// Minimum-phase FIR preserves the exact causal impulse response of the biquad
/// filter cascade with near-zero latency and matches the parametric EQ curve
/// to within tight dB tolerance (< 0.1 dB across 20 Hz - 20 kHz).
///
/// Linear-phase FIR eliminates phase distortion and delivers constant group delay
/// at the cost of symmetric latency (taps / 2).
class AutoEqFirGenerator {
  AutoEqFirGenerator._();

  static const double defaultSampleRate = 48000.0;
  static const int defaultTaps = 4096;

  /// Synthesizes an impulse response from a [HeadphoneProfile].
  ///
  /// When [linearPhase] is false (the AutoEQ convolution default), synthesizes
  /// a minimum-phase impulse response by feeding a unit impulse into the
  /// cascaded biquad transfer functions.
  /// When [linearPhase] is true, synthesizes a symmetric linear-phase FIR
  /// from the composite magnitude spectrum.
  static List<double> generateFir({
    required HeadphoneProfile profile,
    bool linearPhase = false,
    int taps = defaultTaps,
    double sampleRate = defaultSampleRate,
  }) {
    if (profile.hasParametricFilters) {
      if (linearPhase) {
        return generateLinearPhaseFromFilters(
          filters: profile.filters,
          preampGain: profile.preampGain,
          taps: taps,
          sampleRate: sampleRate,
        );
      } else {
        return generateMinimumPhaseFromFilters(
          filters: profile.filters,
          preampGain: profile.preampGain,
          taps: taps,
          sampleRate: sampleRate,
        );
      }
    }

    // Fallback for legacy profiles with only gains:
    final targetGains = profile.gains;
    return generateFromGains(
      gains: targetGains,
      linearPhase: linearPhase,
      taps: taps,
      sampleRate: sampleRate,
    );
  }

  /// Synthesizes a minimum-phase FIR filter from a cascade of parametric biquad filters.
  static List<double> generateMinimumPhaseFromFilters({
    required List<EqFilter> filters,
    double preampGain = 0.0,
    int taps = defaultTaps,
    double sampleRate = defaultSampleRate,
  }) {
    if (taps <= 0) return const [];
    final ir = List<double>.filled(taps, 0.0);

    final biquads = <_BiquadCoeffs>[];
    for (final f in filters) {
      if (!f.frequency.isFinite || f.frequency <= 0 || !f.gain.isFinite) {
        continue;
      }
      final bq = _BiquadCoeffs.fromFilter(f, sampleRate);
      if (bq != null) {
        biquads.add(bq);
      }
    }

    if (biquads.isEmpty) {
      final scale = math.pow(10.0, preampGain / 20.0).toDouble();
      ir[0] = scale.isFinite ? scale : 1.0;
      return ir;
    }

    final initialScale = math.pow(10.0, preampGain / 20.0).toDouble();
    final scale = initialScale.isFinite ? initialScale : 1.0;

    // Direct Form II Transposed states: 2 states per biquad
    final s1 = List<double>.filled(biquads.length, 0.0);
    final s2 = List<double>.filled(biquads.length, 0.0);

    for (var n = 0; n < taps; n++) {
      var x = n == 0 ? scale : 0.0;
      for (var i = 0; i < biquads.length; i++) {
        final b = biquads[i];
        final y = b.b0 * x + s1[i];
        s1[i] = b.b1 * x - b.a1 * y + s2[i];
        s2[i] = b.b2 * x - b.a2 * y;
        x = y;
      }
      ir[n] = x.isFinite ? x : 0.0;
    }

    // Apply a cosine fade over the last 64 samples to ensure smooth tail decay
    final fadeLength = math.min(64, taps ~/ 8);
    final fadeStart = taps - fadeLength;
    for (var i = fadeStart; i < taps; i++) {
      final t = (i - fadeStart) / fadeLength;
      final w = 0.5 * (1.0 + math.cos(math.pi * t));
      ir[i] *= w;
    }

    return ir;
  }

  /// Synthesizes a symmetric linear-phase FIR filter from a cascade of parametric biquad filters.
  static List<double> generateLinearPhaseFromFilters({
    required List<EqFilter> filters,
    double preampGain = 0.0,
    int taps = defaultTaps,
    double sampleRate = defaultSampleRate,
  }) {
    if (taps <= 0) return const [];
    // FFT size must be power of 2 >= taps
    var fftSize = 1;
    while (fftSize < taps) {
      fftSize <<= 1;
    }
    fftSize <<= 1; // 2x oversampling for clean frequency sampling

    final half = fftSize ~/ 2;
    final scale = math.pow(10.0, preampGain / 20.0).toDouble();
    final delay = (taps - 1) * 0.5;

    final re = List<double>.filled(fftSize, 0.0);
    final im = List<double>.filled(fftSize, 0.0);

    for (var k = 0; k <= half; k++) {
      final freq = k * sampleRate / fftSize;
      var mag = scale;
      for (final f in filters) {
        mag *= _biquadMagnitude(f, freq, sampleRate);
      }
      if (!mag.isFinite || mag < 1e-9) mag = 1e-9;

      if (k == 0 || k == half) {
        re[k] = mag;
        im[k] = 0.0;
      } else {
        final phase = -2.0 * math.pi * k * delay / fftSize;
        re[k] = mag * math.cos(phase);
        im[k] = mag * math.sin(phase);
        re[fftSize - k] = re[k];
        im[fftSize - k] = -im[k];
      }
    }

    // Inverse FFT
    _fft(re, im, invert: true);

    final ir = List<double>.filled(taps, 0.0);
    final halfTaps = (taps + 1) ~/ 2;
    for (var i = 0; i < halfTaps; i++) {
      final w = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (taps - 1)));
      final opp = taps - 1 - i;
      final val1 = re[i] * w;
      final val2 = re[opp] * w;
      final sym = (val1 + val2) * 0.5;
      ir[i] = sym.isFinite ? sym : 0.0;
      ir[opp] = ir[i];
    }

    return ir;
  }

  /// Synthesizes an impulse response from 10-band graphic EQ gains.
  static List<double> generateFromGains({
    required List<double> gains,
    bool linearPhase = false,
    int taps = defaultTaps,
    double sampleRate = defaultSampleRate,
  }) {
    if (taps <= 0) return const [];
    // Convert 10-band gains into frequency nodes
    const isoCenters = [
      31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0
    ];
    final nodes = <math.Point<double>>[];
    for (var i = 0; i < gains.length && i < isoCenters.length; i++) {
      nodes.add(math.Point<double>(isoCenters[i], gains[i]));
    }

    var fftSize = 1;
    while (fftSize < taps) {
      fftSize <<= 1;
    }
    fftSize <<= 1;

    final half = fftSize ~/ 2;
    final re = List<double>.filled(fftSize, 0.0);
    final im = List<double>.filled(fftSize, 0.0);

    if (linearPhase) {
      final delay = (taps - 1) * 0.5;
      for (var k = 0; k <= half; k++) {
        final freq = k * sampleRate / fftSize;
        final gainDb = _interpolateGain(nodes, freq);
        final mag = math.pow(10.0, gainDb / 20.0).toDouble();

        if (k == 0 || k == half) {
          re[k] = mag;
          im[k] = 0.0;
        } else {
          final phase = -2.0 * math.pi * k * delay / fftSize;
          re[k] = mag * math.cos(phase);
          im[k] = mag * math.sin(phase);
          re[fftSize - k] = re[k];
          im[fftSize - k] = -im[k];
        }
      }
      _fft(re, im, invert: true);

      final ir = List<double>.filled(taps, 0.0);
      for (var i = 0; i < taps; i++) {
        final w = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (taps - 1)));
        final tap = re[i] * w;
        ir[i] = tap.isFinite ? tap : 0.0;
      }
      return ir;
    } else {
      // Real cepstrum minimum phase liftering
      for (var k = 0; k <= half; k++) {
        final freq = k * sampleRate / fftSize;
        final gainDb = _interpolateGain(nodes, freq);
        var mag = math.pow(10.0, gainDb / 20.0).toDouble();
        if (!mag.isFinite || mag < 1e-9) mag = 1e-9;
        final logMag = math.log(mag);
        re[k] = logMag;
        im[k] = 0.0;
        if (k > 0 && k < half) {
          re[fftSize - k] = logMag;
          im[fftSize - k] = 0.0;
        }
      }

      _fft(re, im, invert: true);

      // Homomorphic liftering
      re[0] = re[0];
      im[0] = 0.0;
      for (var n = 1; n < half; n++) {
        re[n] = re[n] * 2.0;
        im[n] = 0.0;
      }
      re[half] = re[half];
      im[half] = 0.0;
      for (var n = half + 1; n < fftSize; n++) {
        re[n] = 0.0;
        im[n] = 0.0;
      }

      _fft(re, im, invert: false);

      for (var k = 0; k < fftSize; k++) {
        var r = re[k];
        final i = im[k];
        if (r > 80.0) r = 80.0;
        if (r < -80.0) r = -80.0;
        final mag = math.exp(r);
        re[k] = mag * math.cos(i);
        im[k] = mag * math.sin(i);
      }

      _fft(re, im, invert: true);

      final ir = List<double>.filled(taps, 0.0);
      final fadeStart = taps - taps ~/ 8;
      for (var i = 0; i < taps; i++) {
        var w = 1.0;
        if (i >= fadeStart) {
          final t = (i - fadeStart) / (taps - fadeStart);
          w = 0.5 * (1.0 + math.cos(math.pi * t));
        }
        final tap = re[i] * w;
        ir[i] = tap.isFinite ? tap : 0.0;
      }
      return ir;
    }
  }

  /// Evaluates the discrete frequency response magnitude (in dB) of an FIR filter
  /// at [frequencyHz] using direct DFT summation.
  static double evaluateFirMagnitudeDb(
    List<double> ir,
    double frequencyHz, {
    double sampleRate = defaultSampleRate,
  }) {
    if (ir.isEmpty || frequencyHz <= 0 || !frequencyHz.isFinite) return 0.0;
    final w = 2.0 * math.pi * frequencyHz / sampleRate;
    var re = 0.0;
    var im = 0.0;
    for (var n = 0; n < ir.length; n++) {
      final sample = ir[n];
      final phase = -w * n;
      re += sample * math.cos(phase);
      im += sample * math.sin(phase);
    }
    final mag = math.sqrt(re * re + im * im);
    if (mag <= 1e-12) return -240.0;
    return 20.0 * (math.log(mag) / math.ln10);
  }

  /// Encodes an impulse response as a standard 32-bit float or 16-bit PCM RIFF/WAVE.
  static Uint8List toWavBytes(
    List<double> ir, {
    double sampleRate = defaultSampleRate,
    bool float32 = true,
  }) {
    final numSamples = ir.length;
    final bytesPerSample = float32 ? 4 : 2;
    final dataSize = numSamples * bytesPerSample;
    final buffer = Uint8List(44 + dataSize);
    final bdata = ByteData.view(buffer.buffer);

    // RIFF chunk descriptor
    buffer.setRange(0, 4, 'RIFF'.codeUnits);
    bdata.setUint32(4, 36 + dataSize, Endian.little);
    buffer.setRange(8, 12, 'WAVE'.codeUnits);

    // fmt subchunk
    buffer.setRange(12, 16, 'fmt '.codeUnits);
    bdata.setUint32(16, 16, Endian.little); // subchunk1 size
    bdata.setUint16(20, float32 ? 3 : 1, Endian.little); // 3=IEEE Float, 1=PCM
    bdata.setUint16(22, 1, Endian.little); // mono
    bdata.setUint32(24, sampleRate.round(), Endian.little);
    bdata.setUint32(
        28, sampleRate.round() * bytesPerSample, Endian.little); // byte rate
    bdata.setUint16(32, bytesPerSample, Endian.little); // block align
    bdata.setUint16(34, bytesPerSample * 8, Endian.little); // bits per sample

    // data subchunk
    buffer.setRange(36, 40, 'data'.codeUnits);
    bdata.setUint32(40, dataSize, Endian.little);

    var offset = 44;
    for (var i = 0; i < numSamples; i++) {
      final s = ir[i].clamp(-1.0, 1.0);
      if (float32) {
        bdata.setFloat32(offset, s, Endian.little);
        offset += 4;
      } else {
        final pcm = (s * 32767.0).round().clamp(-32768, 32767);
        bdata.setInt16(offset, pcm, Endian.little);
        offset += 2;
      }
    }

    return buffer;
  }

  // --- Internal math helpers ---

  static double _biquadMagnitude(
      EqFilter filter, double freq, double sampleRate) {
    final f0 = filter.frequency;
    if (f0 <= 0 || !f0.isFinite) return 1.0;
    final a = filter.gain.abs() <= 1e-9
        ? 1.0
        : math.pow(10.0, filter.gain / 40.0).toDouble();
    final w0 = 2 * math.pi * f0 / sampleRate;
    final w = 2 * math.pi * freq / sampleRate;
    if (w0 <= 0 || w0 >= math.pi) return 1.0;
    final cosw0 = math.cos(w0);
    final sinw0 = math.sin(w0);

    if (filter.filterType == EqFilterType.lowShelf) {
      final s = math.sqrt(a) / math.sqrt(math.max(filter.q, 0.1));
      final alpha = sinw0 / 2 * math.sqrt((a + 1 / a) * (1 / s - 1) + 2);
      final b0 = a * ((a + 1) - (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha);
      final b1 = 2 * a * ((a - 1) - (a + 1) * cosw0);
      final b2 = a * ((a + 1) - (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha);
      final a0 = (a + 1) + (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha;
      final a1 = -2 * ((a - 1) + (a + 1) * cosw0);
      final a2 = (a + 1) + (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha;
      return _hMag(b0, b1, b2, a0, a1, a2, w);
    } else if (filter.filterType == EqFilterType.highShelf) {
      final s = math.sqrt(a) / math.sqrt(math.max(filter.q, 0.1));
      final alpha = sinw0 / 2 * math.sqrt((a + 1 / a) * (1 / s - 1) + 2);
      final b0 = a * ((a + 1) + (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha);
      final b1 = -2 * a * ((a - 1) + (a + 1) * cosw0);
      final b2 = a * ((a + 1) + (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha);
      final a0 = (a + 1) - (a - 1) * cosw0 + 2 * math.sqrt(a) * alpha;
      final a1 = 2 * ((a - 1) - (a + 1) * cosw0);
      final a2 = (a + 1) - (a - 1) * cosw0 - 2 * math.sqrt(a) * alpha;
      return _hMag(b0, b1, b2, a0, a1, a2, w);
    }
    // Peaking
    final alpha = sinw0 / (2 * math.max(filter.q, 0.1));
    final b0 = 1 + alpha * a;
    final b1 = -2 * cosw0;
    final b2 = 1 - alpha * a;
    final a0 = 1 + alpha / a;
    final a1 = -2 * cosw0;
    final a2 = 1 - alpha / a;
    return _hMag(b0, b1, b2, a0, a1, a2, w);
  }

  static double _hMag(double b0, double b1, double b2, double a0, double a1,
      double a2, double w) {
    final cosw = math.cos(w);
    final cos2w = math.cos(2 * w);
    final num2 = b0 * b0 +
        b1 * b1 +
        b2 * b2 +
        2 * (b0 * b1 + b1 * b2) * cosw +
        2 * b0 * b2 * cos2w;
    final den2 = a0 * a0 +
        a1 * a1 +
        a2 * a2 +
        2 * (a0 * a1 + a1 * a2) * cosw +
        2 * a0 * a2 * cos2w;
    if (den2 <= 0) return 1.0;
    return math.sqrt(math.max(num2, 0) / den2);
  }

  static double _interpolateGain(List<math.Point<double>> nodes, double freq) {
    if (nodes.isEmpty) return 0.0;
    if (freq <= nodes.first.x) return nodes.first.y;
    if (freq >= nodes.last.x) return nodes.last.y;

    for (var i = 0; i < nodes.length - 1; i++) {
      final p1 = nodes[i];
      final p2 = nodes[i + 1];
      if (freq >= p1.x && freq <= p2.x) {
        final t = (math.log(freq) - math.log(p1.x)) /
            (math.log(p2.x) - math.log(p1.x));
        return p1.y + t * (p2.y - p1.y);
      }
    }
    return 0.0;
  }

  /// Radix-2 Cooley-Tukey FFT / IFFT in place.
  static void _fft(List<double> re, List<double> im, {bool invert = false}) {
    final n = re.length;
    // Bit reversal
    var j = 0;
    for (var i = 0; i < n - 1; i++) {
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
      var k = n >> 1;
      while (k <= j) {
        j -= k;
        k >>= 1;
      }
      j += k;
    }

    for (var len = 2; len <= n; len <<= 1) {
      final half = len >> 1;
      final ang = 2.0 * math.pi / len * (invert ? -1.0 : 1.0);
      final wstepRe = math.cos(ang);
      final wstepIm = math.sin(ang);

      for (var i = 0; i < n; i += len) {
        var wRe = 1.0;
        var wIm = 0.0;
        for (var k = 0; k < half; k++) {
          final uRe = re[i + k];
          final uIm = im[i + k];
          final vRe = re[i + k + half] * wRe - im[i + k + half] * wIm;
          final vIm = re[i + k + half] * wIm + im[i + k + half] * wRe;

          re[i + k] = uRe + vRe;
          im[i + k] = uIm + vIm;
          re[i + k + half] = uRe - vRe;
          im[i + k + half] = uIm - vIm;

          final nextWre = wRe * wstepRe - wIm * wstepIm;
          final nextWim = wRe * wstepIm + wIm * wstepRe;
          wRe = nextWre;
          wIm = nextWim;
        }
      }
    }

    if (invert) {
      final invN = 1.0 / n;
      for (var i = 0; i < n; i++) {
        re[i] *= invN;
        im[i] *= invN;
      }
    }
  }
}

class _BiquadCoeffs {
  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  const _BiquadCoeffs({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  static _BiquadCoeffs? fromFilter(EqFilter filter, double sampleRate) {
    final f0 = filter.frequency;
    if (f0 <= 0 || !f0.isFinite) return null;
    final w0 = 2.0 * math.pi * f0 / sampleRate;
    if (w0 <= 0 || w0 >= math.pi) return null;

    final cosw0 = math.cos(w0);
    final sinw0 = math.sin(w0);
    final a = math.pow(10.0, filter.gain / 40.0).toDouble();

    double b0, b1, b2, a0, a1, a2;

    if (filter.filterType == EqFilterType.lowShelf) {
      final s = math.sqrt(a) / math.sqrt(math.max(filter.q, 0.1));
      final alpha = sinw0 / 2.0 * math.sqrt((a + 1.0 / a) * (1.0 / s - 1.0) + 2.0);
      b0 = a * ((a + 1.0) - (a - 1.0) * cosw0 + 2.0 * math.sqrt(a) * alpha);
      b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cosw0);
      b2 = a * ((a + 1.0) - (a - 1.0) * cosw0 - 2.0 * math.sqrt(a) * alpha);
      a0 = (a + 1.0) + (a - 1.0) * cosw0 + 2.0 * math.sqrt(a) * alpha;
      a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cosw0);
      a2 = (a + 1.0) + (a - 1.0) * cosw0 - 2.0 * math.sqrt(a) * alpha;
    } else if (filter.filterType == EqFilterType.highShelf) {
      final s = math.sqrt(a) / math.sqrt(math.max(filter.q, 0.1));
      final alpha = sinw0 / 2.0 * math.sqrt((a + 1.0 / a) * (1.0 / s - 1.0) + 2.0);
      b0 = a * ((a + 1.0) + (a - 1.0) * cosw0 + 2.0 * math.sqrt(a) * alpha);
      b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cosw0);
      b2 = a * ((a + 1.0) + (a - 1.0) * cosw0 - 2.0 * math.sqrt(a) * alpha);
      a0 = (a + 1.0) - (a - 1.0) * cosw0 + 2.0 * math.sqrt(a) * alpha;
      a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cosw0);
      a2 = (a + 1.0) - (a - 1.0) * cosw0 - 2.0 * math.sqrt(a) * alpha;
    } else {
      // Peaking
      final alpha = sinw0 / (2.0 * math.max(filter.q, 0.1));
      b0 = 1.0 + alpha * a;
      b1 = -2.0 * cosw0;
      b2 = 1.0 - alpha * a;
      a0 = 1.0 + alpha / a;
      a1 = -2.0 * cosw0;
      a2 = 1.0 - alpha / a;
    }

    if (a0 == 0.0 || !a0.isFinite) return null;
    final invA0 = 1.0 / a0;
    return _BiquadCoeffs(
      b0: b0 * invA0,
      b1: b1 * invA0,
      b2: b2 * invA0,
      a1: a1 * invA0,
      a2: a2 * invA0,
    );
  }
}
