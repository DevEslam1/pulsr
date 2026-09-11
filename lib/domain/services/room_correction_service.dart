// lib/core/services/room_correction_service.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/models/eq_preset.dart';
import '../../core/constants/channels.dart';
import '../../core/utils/error_logger.dart';

/// Phase 5: room-correction wizard engine (stepped-sine method).
///
/// Measurement: a log-spaced tone sweep plays through the speakers while the
/// microphone records. Per-tone RMS magnitudes give the room+speaker response
/// (normalized so absolute mic gain cancels), and a correction EQ preset is
/// fitted against a flat target, clamped to the app's +/-15 dB EQ range with
/// adjacent-band smoothing so the result stays musical.
///
/// All math is static and pure so it can be unit-tested deterministically;
/// this instance only owns the platform capture plumbing.
@lazySingleton
class RoomCorrectionService {
  static const MethodChannel _method =
      MethodChannel(PulsrChannels.roomCorrection);
  static const EventChannel _events =
      EventChannel(PulsrChannels.roomCorrectionPcm);

  /// Default sweep tone count and range. 24 tones x 350 ms is ~8.4 s of
  /// sweep: long enough for stable RMS per tone, short enough to record
  /// comfortably in one take.
  static const int defaultToneCount = 24;
  static const double defaultMinHz = 20.0;
  static const double defaultMaxHz = 16000.0;
  static const int captureSampleRate = 48000;

  /// Log-spaced measurement tones, ascending, within [minHz, maxHz].
  static List<double> tonePlan({
    int count = defaultToneCount,
    double minHz = defaultMinHz,
    double maxHz = defaultMaxHz,
  }) {
    if (count < 2) return [minHz, maxHz];
    final ratio = maxHz / minHz;
    return List<double>.generate(count, (i) {
      final f = minHz * math.pow(ratio, i / (count - 1)).toDouble();
      return (f * 10).roundToDouble() / 10;
    });
  }

  /// Synthesizes the measurement sweep as a mono 16-bit WAV file
  /// (44-byte RIFF header + PCM), with short linear fades per tone to
  /// avoid clicks.
  static Uint8List synthSweepWav(
    List<double> tones, {
    int sampleRate = captureSampleRate,
    int toneMs = 350,
    int fadeMs = 12,
    double amp = 0.35,
  }) {
    final framesPerTone = sampleRate * toneMs ~/ 1000;
    final fadeFrames = math.max(1, sampleRate * fadeMs ~/ 1000);
    final totalFrames = framesPerTone * tones.length;
    final dataLength = totalFrames * 2;
    final out = Uint8List(44 + dataLength);
    final b = ByteData.sublistView(out);

    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        out[offset + i] = s.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    b.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, sampleRate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    b.setUint32(40, dataLength, Endian.little);

    var w = 44;
    for (final tone in tones) {
      for (var i = 0; i < framesPerTone; i++) {
        final t = i / sampleRate;
        var env = 1.0;
        if (i < fadeFrames) env = i / fadeFrames;
        if (i > framesPerTone - fadeFrames) {
          env = (framesPerTone - i) / fadeFrames;
        }
        final s = math.sin(2 * math.pi * tone * t) * amp * env;
        b.setInt16(w, (s * 32767).round().clamp(-32768, 32767), Endian.little);
        w += 2;
      }
    }
    return out;
  }

  /// Per-tone RMS magnitude response in dB, normalized so the median tone
  /// sits at 0 dB (absolute mic gain and playback level cancel out).
  /// [pcm] is mono 16-bit; the tone plan timing must match the sweep used.
  static List<double> analyzeResponse(
    Int16List pcm,
    int sampleRate,
    List<double> tones, {
    int toneMs = 350,
    int leadMs = 60,
    int tailMs = 40,
  }) {
    final framesPerTone = sampleRate * toneMs ~/ 1000;
    final lead = sampleRate * leadMs ~/ 1000;
    final tail = sampleRate * tailMs ~/ 1000;
    final usableTones =
        math.min(tones.length, pcm.length ~/ framesPerTone);
    final raw = List<double>.filled(usableTones, 0.0);
    for (var i = 0; i < usableTones; i++) {
      final start = i * framesPerTone + lead;
      final end = (i + 1) * framesPerTone - tail;
      double sum = 0.0;
      var n = 0;
      for (var j = start; j < end && j < pcm.length; j++) {
        final v = pcm[j] / 32768.0;
        sum += v * v;
        n++;
      }
      final rms = n > 0 ? math.sqrt(sum / n) : 0.0;
      raw[i] = 20 * math.log(math.max(rms, 1e-9)) / math.ln10;
    }
    if (raw.isEmpty) return raw;
    final sorted = List<double>.from(raw)..sort();
    final median = sorted[sorted.length ~/ 2];
    return [for (final v in raw) v - median];
  }

  /// Fits a correction gain (dB) for each [centers] band from the measured
  /// [responseDb] at [tones]. Correction inverts the deviation (a dip gets
  /// positive gain), clamped to the EQ range, with adjacent-band smoothing
  /// so a noisy measurement cannot produce wild jumps.
  static List<double> fitCorrection(
    List<double> responseDb,
    List<double> tones, {
    List<double> centers = EqPreset.centerFrequencies,
    double maxGainDb = 15.0,
    double maxAdjacentDeltaDb = 8.0,
  }) {
    if (responseDb.isEmpty || tones.isEmpty || centers.isEmpty) return [];
    if (!maxGainDb.isFinite || maxGainDb <= 0) return List.filled(centers.length, 0.0);
    if (!maxAdjacentDeltaDb.isFinite || maxAdjacentDeltaDb < 0) {
      maxAdjacentDeltaDb = 8.0;
    }
    // Sanitize inputs: non-finite tones/measurements carry no information.
    final cleanTones = tones.where((t) => t.isFinite && t > 0).toList();
    final cleanResponse = <double>[];
    for (var i = 0; i < responseDb.length && i < tones.length; i++) {
      if (tones[i].isFinite && tones[i] > 0 && responseDb[i].isFinite) {
        cleanResponse.add(responseDb[i]);
      }
    }
    // Align lengths after sanitizing.
    final n = cleanTones.length < cleanResponse.length
        ? cleanTones.length
        : cleanResponse.length;
    if (n == 0) return List.filled(centers.length, 0.0);
    final tonesA = cleanTones.sublist(0, n);
    final respA = cleanResponse.sublist(0, n);
    final gains = <double>[];
    for (final center in centers) {
      if (!center.isFinite || center <= 0) {
        gains.add(0.0);
        continue;
      }
      final logC = math.log(center);
      var bestIdx = 0;
      var bestDist = double.infinity;
      var windowSum = 0.0;
      var windowCount = 0;
      for (var i = 0; i < tonesA.length; i++) {
        final logT = math.log(tonesA[i]);
        final dist = (logT - logC).abs();
        if (dist < bestDist) {
          bestDist = dist;
          bestIdx = i;
        }
        // One-octave window around the center frequency.
        if ((logT - logC).abs() <= math.ln2 / 2) {
          windowSum += respA[i];
          windowCount++;
        }
      }
      final dev = windowCount > 0 ? windowSum / windowCount : respA[bestIdx];
      final correction = -dev;
      final clamped = correction.clamp(-maxGainDb, maxGainDb).toDouble();
      gains.add(clamped);
    }
    // Adjacent-band smoothing (causal clamp toward the previous band).
    for (var i = 1; i < gains.length; i++) {
      final prev = gains[i - 1];
      gains[i] =
          gains[i].clamp(prev - maxAdjacentDeltaDb, prev + maxAdjacentDeltaDb);
    }
    return gains;
  }

  /// Builds the EQ preset the wizard applies. [gains] must match
  /// [EqPreset.centerFrequencies].
  static EqPreset buildPreset(List<double> gains) {
    return EqPreset(
      name: 'Room Correction',
      gains: List<double>.from(gains),
      bassBoost: 0.0,
    );
  }

  /// Merges a room-correction curve with a headphone AutoEQ curve band-wise.
  /// Both [roomGains] and [headphoneGains] must share [centers] length;
  /// shorter inputs are zero-padded, result clamped to +/- [maxGainDb].
  /// This is the "Studio in Your Pocket" stack: headphone compensation +
  /// room compensation in one preset instead of two conflicting EQs.
  static List<double> mergeWithHeadphoneCurve(
    List<double> roomGains,
    List<double> headphoneGains, {
    double maxGainDb = 15.0,
  }) {
    final n = math.max(roomGains.length, headphoneGains.length);
    if (n == 0) return [];
    return List<double>.generate(n, (i) {
      final r = i < roomGains.length ? roomGains[i] : 0.0;
      final h = i < headphoneGains.length ? headphoneGains[i] : 0.0;
      final rC = r.isFinite ? r : 0.0;
      final hC = h.isFinite ? h : 0.0;
      return (rC + hC).clamp(-maxGainDb, maxGainDb).toDouble();
    });
  }

  /// Exports a correction curve as a linear-phase FIR impulse response for
  /// the native convolution stage (`nativeLoadImpulseResponse`) or WAV export.
  ///
  /// Frequency-sampling design: desired magnitude per FFT bin comes from
  /// log-interpolated [gains] at [centers]; linear phase; Hamming-windowed
  /// inverse DFT. Returns mono taps of length [taps] (odd, default 127).
  /// Magnitude-only correction — phase of the room is left untouched.
  static Float32List exportCorrectionImpulseResponse(
    List<double> gains, {
    List<double> centers = EqPreset.centerFrequencies,
    int sampleRate = captureSampleRate,
    int taps = 127,
  }) {
    final n = taps.isOdd ? taps : taps + 1;
    if (gains.isEmpty || centers.isEmpty || gains.length != centers.length) {
      final ir = Float32List(n);
      ir[n ~/ 2] = 1.0;
      return ir;
    }
    double magAt(double freq) {
      final f = freq.clamp(centers.first, centers.last).toDouble();
      final logF = math.log(f);
      for (var i = 0; i < centers.length - 1; i++) {
        final l0 = math.log(centers[i]);
        final l1 = math.log(centers[i + 1]);
        if (logF >= l0 && logF <= l1) {
          final t = (l1 - l0) < 1e-9 ? 0.0 : (logF - l0) / (l1 - l0);
          final gDb = gains[i] * (1 - t) + gains[i + 1] * t;
          return math.pow(10.0, gDb / 20.0).toDouble();
        }
      }
      return math.pow(10.0, gains.last / 20.0).toDouble();
    }

    // Even-length FFT for symmetric bins; design half spectrum then mirror.
    final fftSize = 512;
    final half = fftSize ~/ 2;
    final real = List<double>.filled(fftSize, 0.0);
    final imag = List<double>.filled(fftSize, 0.0);
    for (var k = 0; k <= half; k++) {
      final freq = k * sampleRate / fftSize;
      final mag = k == 0 ? 1.0 : magAt(freq.clamp(20.0, sampleRate / 2 - 1));
      // Linear phase: delay = (n-1)/2 samples.
      final delay = (n - 1) / 2;
      final phase = -2 * math.pi * k * delay / fftSize;
      real[k] = mag * math.cos(phase);
      imag[k] = mag * math.sin(phase);
      if (k > 0 && k < half) {
        real[fftSize - k] = real[k];
        imag[fftSize - k] = -imag[k];
      }
    }
    // Naive inverse DFT (512 pts — trivial cost, runs once per wizard finish).
    final time = List<double>.filled(fftSize, 0.0);
    for (var m = 0; m < fftSize; m++) {
      var sum = 0.0;
      for (var k = 0; k < fftSize; k++) {
        final ang = 2 * math.pi * k * m / fftSize;
        sum += real[k] * math.cos(ang) - imag[k] * math.sin(ang);
      }
      time[m] = sum / fftSize;
    }
    // Crop center (n-1)/2 delay to n taps + Hamming window.
    final start = fftSize ~/ 2 - n ~/ 2;
    final ir = Float32List(n);
    for (var i = 0; i < n; i++) {
      final w = 0.54 - 0.46 * math.cos(2 * math.pi * i / (n - 1));
      ir[i] = (time[start + i] * w).toDouble();
    }
    // Unity-DC normalize so bypass transparency holds when curve is flat.
    var dcSum = 0.0;
    for (final v in ir) {
      dcSum += v;
    }
    if (dcSum.abs() > 1e-9) {
      for (var i = 0; i < ir.length; i++) {
        ir[i] = ir[i] / dcSum;
      }
    }
    return ir;
  }

  // --- capture plumbing ---

  StreamSubscription<dynamic>? _captureSub;
  final BytesBuilder _pcmBuffer = BytesBuilder(copy: true);
  bool _capturing = false;

  bool get isCapturing => _capturing;

  /// Starts mic capture; PCM blocks accumulate until [stopCapture].
  /// Returns false with a log when microphone permission is denied.
  Future<bool> startCapture({int sampleRate = captureSampleRate}) async {
    try {
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final requested = await Permission.microphone.request();
        if (!requested.isGranted) {
          ErrorLogger.log(
              'Room-correction capture blocked: microphone permission denied',
              category: 'RoomCorrection');
          return false;
        }
      }
      _pcmBuffer.clear();
      _captureSub = _events.receiveBroadcastStream().listen((data) {
        if (data is Map && data['pcm'] is Uint8List) {
          _pcmBuffer.add(data['pcm'] as Uint8List);
        }
      }, onError: (Object e) {
        ErrorLogger.log('Room-correction capture stream error',
            error: e, category: 'RoomCorrection');
      });
      final ok = await _method.invokeMethod<bool>('startCapture',
          {'sampleRate': sampleRate});
      _capturing = ok ?? false;
      return _capturing;
    } catch (e, st) {
      ErrorLogger.log('Failed to start room-correction capture',
          error: e, stackTrace: st, category: 'RoomCorrection');
      await _captureSub?.cancel();
      _captureSub = null;
      return false;
    }
  }

  /// Stops capture and returns the accumulated mono 16-bit samples.
  Future<Int16List> stopCapture() async {
    try {
      await _method.invokeMethod<bool>('stopCapture');
    } catch (e) {
      ErrorLogger.log('Failed to stop room-correction capture',
          error: e, category: 'RoomCorrection');
    }
    await _captureSub?.cancel();
    _captureSub = null;
    _capturing = false;
    final bytes = _pcmBuffer.takeBytes();
    // Align to whole samples (16-bit).
    final sampleBytes = bytes.length - (bytes.length % 2);
    return Int16List.view(
        bytes.buffer, bytes.offsetInBytes, sampleBytes ~/ 2);
  }
}
