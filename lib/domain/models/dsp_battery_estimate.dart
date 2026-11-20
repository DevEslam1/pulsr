// lib/domain/models/dsp_battery_estimate.dart

class DspBatteryEstimate {
  final double estimatedMahPerHour;
  final bool lowPowerBypassActive;
  final int activeStageCount;
  final Map<String, double> stageBreakdown;
  final Map<String, double> stagePowerSpecs;

  const DspBatteryEstimate({
    this.estimatedMahPerHour = 0.0,
    this.lowPowerBypassActive = false,
    this.activeStageCount = 0,
    this.stageBreakdown = const {},
    this.stagePowerSpecs = const {},
  });

  factory DspBatteryEstimate.fromMap(Map<String, dynamic> map) {
    final breakdownRaw = map['stageBreakdown'] as Map?;
    final breakdown = <String, double>{};
    if (breakdownRaw != null) {
      breakdownRaw.forEach((k, v) {
        if (v is num) breakdown[k.toString()] = v.toDouble();
      });
    }
    final specsRaw = map['stagePowerSpecs'] as Map?;
    final specs = <String, double>{};
    if (specsRaw != null) {
      specsRaw.forEach((k, v) {
        if (v is num) specs[k.toString()] = v.toDouble();
      });
    }
    return DspBatteryEstimate(
      estimatedMahPerHour:
          (map['estimatedMahPerHour'] as num?)?.toDouble() ?? 0.0,
      lowPowerBypassActive: map['lowPowerBypassActive'] as bool? ?? false,
      activeStageCount:
          (map['activeStageCount'] as num?)?.toInt() ?? breakdown.length,
      stageBreakdown: breakdown,
      stagePowerSpecs: specs,
    );
  }

  static String stageDisplayName(String stageKey) {
    switch (stageKey) {
      case 'reverb':
        return 'Convolution Reverb';
      case 'saturation':
        return 'Harmonic Saturation';
      case 'dynamicBass':
        return 'Dynamic Bass';
      case 'liveProg':
        return 'Live Programmable DSP';
      case 'subCrossover':
        return 'Subwoofer Crossover';
      case 'lfeCrossover':
        return 'LFE Bass Management';
      case 'channelManager':
        return 'Channel Manager';
      case 'limiter':
        return 'True Peak Limiter';
      case 'multiband':
        return 'Multiband Dynamics';
      case 'dynamicEq':
        return 'Dynamic EQ';
      case 'stereoWidth':
        return 'Stereo Width';
      case 'crossfeed':
        return 'Crossfeed';
      case 'sincResampler':
        return 'Sinc Resampler';
      case 'loudnessContour':
        return 'Loudness Contour';
      case 'dither':
        return 'TPDF Dither';
      case 'autoEq':
        return 'AutoEQ Filter';
      case 'tubeWarmth':
        return 'Tube Warmth';
      case 'compressor':
        return 'Compressor';
      case 'bassBoost':
        return 'Bass Boost';
      case 'equalizer':
        return 'Equalizer';
      default:
        return stageKey;
    }
  }
}
