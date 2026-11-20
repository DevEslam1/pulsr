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

  factory DspBatteryEstimate.fromMap(Map<dynamic, dynamic> map) {
    final breakdown = <String, double>{};
    final breakdownRaw = map['stageBreakdown'];
    if (breakdownRaw is Map) {
      breakdownRaw.forEach((k, v) {
        if (v is num) breakdown[k.toString()] = v.toDouble();
      });
    } else if (breakdownRaw is List) {
      for (final item in breakdownRaw) {
        if (item is Map) {
          final key = (item['stageId'] ?? item['stage'] ?? item['name'])?.toString();
          final val = item['mahPerHour'] ?? item['cost'];
          if (key != null && val is num) {
            breakdown[key] = val.toDouble();
          }
        }
      }
    }

    final breakdownListRaw = map['stageBreakdownList'];
    if (breakdown.isEmpty && breakdownListRaw is List) {
      for (final item in breakdownListRaw) {
        if (item is Map) {
          final key = (item['stageId'] ?? item['stage'] ?? item['name'])?.toString();
          final val = item['mahPerHour'] ?? item['cost'];
          if (key != null && val is num) {
            breakdown[key] = val.toDouble();
          }
        }
      }
    }

    final specsRaw = map['stagePowerSpecs'] as Map?;
    final specs = <String, double>{};
    if (specsRaw != null) {
      specsRaw.forEach((k, v) {
        if (v is num) specs[k.toString()] = v.toDouble();
      });
    }

    final rawCount = map['activeStageCount'] ?? map['activeStagesCount'];

    return DspBatteryEstimate(
      estimatedMahPerHour:
          (map['estimatedMahPerHour'] as num?)?.toDouble() ?? 0.0,
      lowPowerBypassActive: map['lowPowerBypassActive'] as bool? ?? false,
      activeStageCount:
          (rawCount as num?)?.toInt() ?? breakdown.length,
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
