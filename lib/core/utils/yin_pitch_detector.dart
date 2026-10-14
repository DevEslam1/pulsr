// lib/core/utils/yin_pitch_detector.dart
import 'dart:math' as math;

/// Result of fundamental pitch detection via YIN algorithm.
class PitchResult {
  final double frequencyHz;
  final double midiNote;
  final String noteName;
  final double probability;
  final bool isVoiced;

  const PitchResult({
    required this.frequencyHz,
    required this.midiNote,
    required this.noteName,
    required this.probability,
    required this.isVoiced,
  });

  static const PitchResult unvoiced = PitchResult(
    frequencyHz: 0.0,
    midiNote: 0.0,
    noteName: '--',
    probability: 0.0,
    isVoiced: false,
  );

  double get pitch => frequencyHz;

  @override
  String toString() =>
      'PitchResult($noteName, ${frequencyHz.toStringAsFixed(1)}Hz, prob: ${(probability * 100).toStringAsFixed(0)}%)';
}

/// Robust fundamental pitch detection using the YIN algorithm (de Cheveigné & Kawahara).
///
/// Converts microphone PCM audio buffers into real-time fundamental frequencies,
/// MIDI note numbers, and note names for vocal pitch guidance in Karaoke mode.
class YinPitchDetector {
  final double sampleRate;
  final double threshold;

  const YinPitchDetector({
    this.sampleRate = 44100.0,
    this.threshold = 0.15,
  });

  /// Instance method wrapper for real-time streaming buffers.
  PitchResult? getPitch(List<double> buffer) {
    final res =
        detectPitch(buffer, sampleRate: sampleRate, threshold: threshold);
    return res.isVoiced ? res : null;
  }

  static const List<String> _noteNames = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B'
  ];

  /// Detects the fundamental frequency of the given audio [buffer].
  ///
  /// [sampleRate] defaults to 44100 Hz.
  /// [threshold] is the dip tolerance for the cumulative mean normalized difference (standard 0.10–0.15).
  static PitchResult detectPitch(
    List<double> buffer, {
    double sampleRate = 44100.0,
    double threshold = 0.15,
  }) {
    final int halfSize = buffer.length ~/ 2;
    if (halfSize < 32) return PitchResult.unvoiced;

    // Check minimum RMS energy to avoid detecting background noise
    double sumSq = 0.0;
    for (int i = 0; i < buffer.length; i++) {
      sumSq += buffer[i] * buffer[i];
    }
    final double rms = math.sqrt(sumSq / buffer.length);
    if (rms < 0.01) return PitchResult.unvoiced;

    // Step 1: Difference Function
    final yinBuffer = List<double>.filled(halfSize, 0.0);
    for (int tau = 0; tau < halfSize; tau++) {
      for (int i = 0; i < halfSize; i++) {
        final delta = buffer[i] - buffer[i + tau];
        yinBuffer[tau] += delta * delta;
      }
    }

    // Step 2: Cumulative Mean Normalized Difference Function
    yinBuffer[0] = 1.0;
    double runningSum = 0.0;
    for (int tau = 1; tau < halfSize; tau++) {
      runningSum += yinBuffer[tau];
      if (runningSum > 0.0) {
        yinBuffer[tau] = (yinBuffer[tau] * tau) / runningSum;
      } else {
        yinBuffer[tau] = 1.0;
      }
    }

    // Step 3: Absolute Threshold
    int tauEstimate = -1;
    for (int tau = 2; tau < halfSize; tau++) {
      if (yinBuffer[tau] < threshold) {
        while (tau + 1 < halfSize && yinBuffer[tau + 1] < yinBuffer[tau]) {
          tau++;
        }
        tauEstimate = tau;
        break;
      }
    }

    if (tauEstimate == -1) {
      // Find global minimum if threshold was not crossed
      double minVal = 1000.0;
      for (int tau = 2; tau < halfSize; tau++) {
        if (yinBuffer[tau] < minVal) {
          minVal = yinBuffer[tau];
          tauEstimate = tau;
        }
      }
      if (minVal > 0.40) return PitchResult.unvoiced;
    }

    // Step 4: Parabolic Interpolation for sub-sample precision
    double refinedTau = tauEstimate.toDouble();
    if (tauEstimate > 0 && tauEstimate < halfSize - 1) {
      final s0 = yinBuffer[tauEstimate - 1];
      final s1 = yinBuffer[tauEstimate];
      final s2 = yinBuffer[tauEstimate + 1];
      final denom = 2.0 * (2.0 * s1 - s2 - s0);
      if (denom.abs() > 1e-6) {
        final adjustment = (s2 - s0) / denom;
        refinedTau += adjustment;
      }
    }

    if (refinedTau <= 0.0) return PitchResult.unvoiced;

    final freq = sampleRate / refinedTau;
    // Human vocal range typically 70 Hz to 1100 Hz
    if (freq < 65.0 || freq > 1200.0) return PitchResult.unvoiced;

    final prob = (1.0 - yinBuffer[tauEstimate].clamp(0.0, 1.0));
    final midi = 69.0 + 12.0 * (math.log(freq / 440.0) / math.ln2);
    final noteIndex = (midi.round() % 12 + 12) % 12;
    final octave = (midi.round() ~/ 12) - 1;
    final noteStr = '${_noteNames[noteIndex]}$octave';

    return PitchResult(
      frequencyHz: freq,
      midiNote: midi,
      noteName: noteStr,
      probability: prob,
      isVoiced: prob > 0.5,
    );
  }
}

/// Real-time Exponential Moving Average (EMA) pitch smoother for vocal tracking.
///
/// Smooths instantaneous raw YIN pitch detections to eliminate flutter,
/// octave jumps, and jitter during live singing.
class EmaPitchSmoother {
  final double alpha;
  double? _smoothedFreq;
  double? _smoothedMidi;
  int _unvoicedFrames = 0;
  static const int maxHoldFrames = 4;

  EmaPitchSmoother({this.alpha = 0.28});

  double? get smoothedFrequencyHz => _smoothedFreq;
  double? get smoothedMidiNote => _smoothedMidi;

  PitchResult smooth(PitchResult raw) {
    if (!raw.isVoiced) {
      _unvoicedFrames++;
      if (_unvoicedFrames > maxHoldFrames) {
        _smoothedFreq = null;
        _smoothedMidi = null;
        return PitchResult.unvoiced;
      }
      // Hold last pitch briefly across unvoiced gaps
      if (_smoothedFreq != null && _smoothedMidi != null) {
        return PitchResult(
          frequencyHz: _smoothedFreq!,
          midiNote: _smoothedMidi!,
          noteName: raw.noteName,
          probability: raw.probability * 0.5,
          isVoiced: true,
        );
      }
      return PitchResult.unvoiced;
    }

    _unvoicedFrames = 0;
    if (_smoothedFreq == null || _smoothedMidi == null) {
      _smoothedFreq = raw.frequencyHz;
      _smoothedMidi = raw.midiNote;
    } else {
      // Octave jump damping: if sudden 2x or 0.5x jump, dampen transition
      final ratio = raw.frequencyHz / _smoothedFreq!;
      final isOctaveJump =
          (ratio > 1.85 && ratio < 2.15) || (ratio > 0.45 && ratio < 0.55);
      final effectiveAlpha = isOctaveJump ? (alpha * 0.3) : alpha;

      _smoothedFreq =
          _smoothedFreq! + effectiveAlpha * (raw.frequencyHz - _smoothedFreq!);
      _smoothedMidi =
          _smoothedMidi! + effectiveAlpha * (raw.midiNote - _smoothedMidi!);
    }

    final noteIndex = (_smoothedMidi!.round() % 12 + 12) % 12;
    final octave = (_smoothedMidi!.round() ~/ 12) - 1;
    final noteStr = '${YinPitchDetector._noteNames[noteIndex]}$octave';

    return PitchResult(
      frequencyHz: _smoothedFreq!,
      midiNote: _smoothedMidi!,
      noteName: noteStr,
      probability: raw.probability,
      isVoiced: true,
    );
  }

  void reset() {
    _smoothedFreq = null;
    _smoothedMidi = null;
    _unvoicedFrames = 0;
  }
}
