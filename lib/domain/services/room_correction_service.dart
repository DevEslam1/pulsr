// lib/core/services/room_correction_service.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

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
    final gains = <double>[];
    for (final center in centers) {
      final logC = math.log(center);
      var bestIdx = 0;
      var bestDist = double.infinity;
      var windowSum = 0.0;
      var windowCount = 0;
      for (var i = 0; i < tones.length && i < responseDb.length; i++) {
        final logT = math.log(tones[i]);
        final dist = (logT - logC).abs();
        if (dist < bestDist) {
          bestDist = dist;
          bestIdx = i;
        }
        // One-octave window around the center frequency.
        if ((logT - logC).abs() <= math.ln2 / 2) {
          windowSum += responseDb[i];
          windowCount++;
        }
      }
      final dev = windowCount > 0 ? windowSum / windowCount : responseDb[bestIdx];
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

  // --- capture plumbing ---

  StreamSubscription<dynamic>? _captureSub;
  final BytesBuilder _pcmBuffer = BytesBuilder(copy: true);
  bool _capturing = false;

  bool get isCapturing => _capturing;

  /// Starts mic capture; PCM blocks accumulate until [stopCapture].
  Future<bool> startCapture({int sampleRate = captureSampleRate}) async {
    try {
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
