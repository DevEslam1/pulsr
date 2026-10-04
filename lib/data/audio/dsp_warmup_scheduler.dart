// lib/data/audio/dsp_warmup_scheduler.dart
import 'dart:async';
import 'dart:typed_data';
import '../../core/utils/error_logger.dart';
import 'audio_effects_channel.dart';

/// Schedules and runs silent buffer warmup for heavy DSP stages (e.g., Convolver,
/// ViPER-DDC, Room Correction FIR filters) before unmuting or activating output,
/// completely eliminating filter initial state transient pops/clicks.
class DspWarmupScheduler {
  final AudioEffectsChannel _channel;

  DspWarmupScheduler({AudioEffectsChannel? channel})
      : _channel = channel ?? AudioEffectsChannel();

  /// Runs a 100ms silent buffer through the DSP pipeline before executing [action]
  /// and returning the result.
  Future<T> runWithWarmup<T>(
    Future<T> Function() action, {
    Duration warmupDuration = const Duration(milliseconds: 100),
  }) async {
    try {
      await _channel.sendWarmupBuffer(
          durationMs: warmupDuration.inMilliseconds);
    } catch (e, st) {
      ErrorLogger.log('DspWarmupScheduler silent buffer preload error',
          error: e, stackTrace: st, category: 'DspWarmupScheduler');
    }
    return await action();
  }

  /// Fire-and-forget or awaited standalone warmup execution.
  Future<void> warmup(
      {Duration duration = const Duration(milliseconds: 100)}) async {
    try {
      await _channel.sendWarmupBuffer(durationMs: duration.inMilliseconds);
    } catch (e, st) {
      ErrorLogger.log('DspWarmupScheduler standalone warmup error',
          error: e, stackTrace: st, category: 'DspWarmupScheduler');
    }
  }

  /// Generates a silent float PCM buffer for DSP stage warmup testing.
  Float32List createSilentWarmupBuffer({
    int sampleRate = 48000,
    int channels = 2,
    int durationMs = 100,
  }) {
    // Integer math: the old double multiply could land on x.999… and truncate
    // to an odd sample count, i.e. a torn final stereo frame.
    if (sampleRate <= 0 || channels <= 0 || durationMs <= 0) {
      return Float32List(0);
    }
    final frames = sampleRate * durationMs ~/ 1000;
    return Float32List(frames * channels);
  }
}
