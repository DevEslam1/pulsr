// lib/data/audio/latency_optimizer.dart

/// Direct low-latency buffer frame calculator for local and streaming audio playback.
class LatencyOptimizer {
  /// Local audio files: minimal buffer frames for ultra-low latency (~4ms at 48kHz).
  static const int localFileBufferFrames = 192;

  /// High-Res local files (> 48kHz): balanced buffer frames (~8ms).
  static const int highResLocalBufferFrames = 384;

  /// Network streams: safe buffer frames (~43ms at 48kHz) to absorb network jitter.
  static const int streamBufferFrames = 2048;

  /// Calculates optimal buffer frames based on storage locality, sample rate, and bit depth.
  static int getOptimalBufferFrames({
    required bool isLocalFile,
    required int sampleRate,
    bool isHighRes = false,
  }) {
    if (isLocalFile) {
      final highRes = isHighRes || sampleRate > 48000;
      return highRes ? highResLocalBufferFrames : localFileBufferFrames;
    }
    return streamBufferFrames;
  }

  /// Calculates buffer duration equivalent in milliseconds based on sample rate and buffer frames.
  static double getBufferDurationMs({
    required int bufferFrames,
    required int sampleRate,
  }) {
    final rate = sampleRate <= 0 ? 48000 : sampleRate;
    return (bufferFrames / rate) * 1000.0;
  }
}
