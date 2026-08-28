// lib/data/audio/optimized_dsp_pipeline.dart

/// Supported stages in the DSP audio processing chain.
enum DspStage {
  parametricEq('Parametric EQ', 0.1),
  crossfeed('Crossfeed', 0.05),
  convolutionReverb('Convolution Reverb', 0.3),
  stereoPanner('Stereo Balance / Mono Mix', 0.02),
  lookaheadLimiter('Lookahead Limiter', 0.08),
  volume('Volume & ReplayGain', 0.01);

  final String label;
  final double estimatedLatencyMs;
  const DspStage(this.label, this.estimatedLatencyMs);
}

/// DSP pipeline coordinator for optimal stage ordering and zero-cost stage skipping.
class OptimizedDspPipeline {
  bool eqEnabled = false;
  bool crossfeedEnabled = false;
  bool reverbEnabled = false;
  double balance = 0.0;
  bool monoMix = false;
  bool limiterEnabled = false;
  bool isBitPerfectBypass = false;

  /// Last measured native pipeline latency in frames (from AudioDspEngine.getPipelineLatencyFrames).
  int _nativeLatencyFrames = 0;
  double _nativeSampleRate = 48000.0;

  /// Pipeline execution order optimized for minimal latency and acoustic correctness:
  /// 1. Parametric EQ (10-32 bands)
  /// 2. Crossfeed (headphone acoustic cross-coupling)
  /// 3. Convolution Reverb (spatial room impulse response)
  /// 4. Stereo Balance / Mono Mix
  /// 5. Lookahead Limiter (brickwall peak protection)
  /// 6. Volume (ReplayGain + user master volume)
  static const List<DspStage> pipelineOrder = [
    DspStage.parametricEq,
    DspStage.crossfeed,
    DspStage.convolutionReverb,
    DspStage.stereoPanner,
    DspStage.lookaheadLimiter,
    DspStage.volume,
  ];

  /// Returns the active DSP stages, skipping disabled stages entirely with zero wasted CPU cycles.
  List<DspStage> getActiveStages() {
    return pipelineOrder.where((stage) {
      switch (stage) {
        case DspStage.parametricEq:
          return eqEnabled;
        case DspStage.crossfeed:
          return crossfeedEnabled;
        case DspStage.convolutionReverb:
          return reverbEnabled;
        case DspStage.stereoPanner:
          return balance.abs() > 0.001 || monoMix;
        case DspStage.lookaheadLimiter:
          return limiterEnabled;
        case DspStage.volume:
          return true; // Always applied at the output stage
      }
    }).toList();
  }

  /// Calculates total estimated DSP processing latency in milliseconds.
  /// When bit-perfect bypass is active, latency is zero (direct passthrough).
  /// Otherwise uses measured native latency if available, falling back to static estimates.
  double calculateTotalEstimatedLatencyMs() {
    if (isBitPerfectBypass) return 0.0;
    if (_nativeLatencyFrames > 0) {
      return (_nativeLatencyFrames / _nativeSampleRate) * 1000.0;
    }
    return getActiveStages().fold<double>(
      0.0,
      (sum, stage) => sum + stage.estimatedLatencyMs,
    );
  }

  /// Updates measured native latency from C++ engine (call after each setActiveStages).
  void updateNativeLatency({required int frames, double sampleRate = 48000.0}) {
    _nativeLatencyFrames = frames;
    _nativeSampleRate = sampleRate > 0 ? sampleRate : 48000.0;
  }

  /// Returns compensated position for lyrics/seek sync.
  Duration getCompensatedPosition(Duration rawPosition) {
    if (isBitPerfectBypass || _nativeLatencyFrames <= 0) return rawPosition;
    final latencyMs = (_nativeLatencyFrames / _nativeSampleRate) * 1000.0;
    final latency = Duration(microseconds: (latencyMs * 1000).round());
    if (rawPosition <= latency) return Duration.zero;
    return rawPosition - latency;
  }

  /// Updates pipeline state from active settings.
  void updateState({
    bool? isEqEnabled,
    bool? isCrossfeedEnabled,
    bool? isReverbEnabled,
    double? stereoBalance,
    bool? isMonoMix,
    bool? isLimiterEnabled,
    bool? bitPerfectBypass,
  }) {
    if (isEqEnabled != null) eqEnabled = isEqEnabled;
    if (isCrossfeedEnabled != null) crossfeedEnabled = isCrossfeedEnabled;
    if (isReverbEnabled != null) reverbEnabled = isReverbEnabled;
    if (stereoBalance != null) balance = stereoBalance;
    if (isMonoMix != null) monoMix = isMonoMix;
    if (isLimiterEnabled != null) limiterEnabled = isLimiterEnabled;
    if (bitPerfectBypass != null) isBitPerfectBypass = bitPerfectBypass;
  }
}
