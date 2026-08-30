// lib/data/audio/optimized_dsp_pipeline.dart

/// Supported stages in the DSP audio processing chain.
enum DspStage {
  parametricEq('Parametric EQ', 0.1),
  dynamicEq('Dynamic EQ', 0.0),
  crossfeed('Crossfeed', 0.05),
  convolutionReverb('Convolution Reverb', 0.3),
  stereoPanner('Stereo Balance / Mono Mix', 0.02),
  harmonicSaturation('Harmonic Saturation', 0.0),
  stereoWidth('Stereo Width', 0.0),
  subCrossover('Sub Crossover (Bass Redirection)', 0.0),
  lookaheadLimiter('Lookahead Limiter', 0.08),
  loudnessContour('Loudness Contour', 0.0),
  volume('Volume & ReplayGain', 0.01);

  final String label;
  final double estimatedLatencyMs;
  const DspStage(this.label, this.estimatedLatencyMs);
}

/// DSP pipeline coordinator for optimal stage ordering and zero-cost stage skipping.
class OptimizedDspPipeline {
  bool eqEnabled = false;
  bool dynamicEqEnabled = false;
  bool crossfeedEnabled = false;
  bool reverbEnabled = false;
  double balance = 0.0;
  bool monoMix = false;
  bool saturationEnabled = false;
  bool stereoWidthEnabled = false;
  bool subCrossoverEnabled = false;
  bool loudnessContourEnabled = false;
  bool limiterEnabled = false;
  bool isBitPerfectBypass = false;

  /// Last measured native pipeline latency in frames (from AudioDspEngine.getPipelineLatencyFrames).
  int _nativeLatencyFrames = 0;
  double _nativeSampleRate = 48000.0;

  /// Pipeline execution order optimized for minimal latency and acoustic correctness:
  /// 1. Parametric EQ (10-32 bands)
  /// 2. Dynamic EQ (energy-dependent cuts, adjacent to the static EQ)
  /// 3. Crossfeed (headphone acoustic cross-coupling)
  /// 4. Convolution Reverb (spatial room impulse response)
  /// 5. Stereo Balance / Mono Mix
  /// 6. Harmonic Saturation (after tonal/spatial shaping, before peak control)
  /// 7. Stereo Width (M/S, after crossfeed/reverb, before the limiter)
  /// 8. Sub Crossover (bass redirection sum, after width, before the limiter)
  /// 9. Lookahead Limiter (brickwall peak protection)
  /// 10. Loudness Contour (computed against the current volume-stage value)
  /// 11. Volume (ReplayGain + user master volume)
  static const List<DspStage> pipelineOrder = [
    DspStage.parametricEq,
    DspStage.dynamicEq,
    DspStage.crossfeed,
    DspStage.convolutionReverb,
    DspStage.stereoPanner,
    DspStage.harmonicSaturation,
    DspStage.stereoWidth,
    DspStage.subCrossover,
    DspStage.lookaheadLimiter,
    DspStage.loudnessContour,
    DspStage.volume,
  ];

  /// Returns the active DSP stages, skipping disabled stages entirely with zero wasted CPU cycles.
  List<DspStage> getActiveStages() {
    return pipelineOrder.where((stage) {
      switch (stage) {
        case DspStage.parametricEq:
          return eqEnabled;
        case DspStage.dynamicEq:
          return dynamicEqEnabled;
        case DspStage.crossfeed:
          return crossfeedEnabled;
        case DspStage.convolutionReverb:
          return reverbEnabled;
        case DspStage.stereoPanner:
          return balance.abs() > 0.001 || monoMix;
        case DspStage.harmonicSaturation:
          return saturationEnabled;
        case DspStage.stereoWidth:
          return stereoWidthEnabled;
        case DspStage.subCrossover:
          return subCrossoverEnabled;
        case DspStage.lookaheadLimiter:
          return limiterEnabled;
        case DspStage.loudnessContour:
          return loudnessContourEnabled;
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
    bool? isDynamicEqEnabled,
    bool? isCrossfeedEnabled,
    bool? isReverbEnabled,
    double? stereoBalance,
    bool? isMonoMix,
    bool? isSaturationEnabled,
    bool? isStereoWidthEnabled,
    bool? isSubCrossoverEnabled,
    bool? isLoudnessContourEnabled,
    bool? isLimiterEnabled,
    bool? bitPerfectBypass,
  }) {
    if (isEqEnabled != null) eqEnabled = isEqEnabled;
    if (isDynamicEqEnabled != null) dynamicEqEnabled = isDynamicEqEnabled;
    if (isCrossfeedEnabled != null) crossfeedEnabled = isCrossfeedEnabled;
    if (isReverbEnabled != null) reverbEnabled = isReverbEnabled;
    if (stereoBalance != null) balance = stereoBalance;
    if (isMonoMix != null) monoMix = isMonoMix;
    if (isSaturationEnabled != null) saturationEnabled = isSaturationEnabled;
    if (isStereoWidthEnabled != null) stereoWidthEnabled = isStereoWidthEnabled;
    if (isSubCrossoverEnabled != null) subCrossoverEnabled = isSubCrossoverEnabled;
    if (isLoudnessContourEnabled != null) {
      loudnessContourEnabled = isLoudnessContourEnabled;
    }
    if (isLimiterEnabled != null) limiterEnabled = isLimiterEnabled;
    if (bitPerfectBypass != null) isBitPerfectBypass = bitPerfectBypass;
  }
}
