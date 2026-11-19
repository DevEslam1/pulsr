// lib/features/audio_profiles/audio_profile_keys.dart
//
// The allow-list of SharedPreferences keys an audio profile may read or write.
// Scoping the profile to sound-shaping settings keeps it portable and stops a
// shared file from carrying library paths, account state or credentials.

import '../../core/constants/prefs_keys.dart';

/// Every preference key a profile is allowed to capture or apply.
///
/// The list is intentionally explicit instead of pattern-matched at runtime: a
/// new setting joins a profile only by being added here, and the codec's 200-key
/// ceiling leaves room for roughly twice today's size.
abstract final class AudioProfileKeys {
  /// SharedPreferences keys owned by the audio profile format.
  static const List<String> whitelist = <String>[
    // Equalizer.
    PrefsKeys.eqEnabled,
    PrefsKeys.eqPresetName,
    PrefsKeys.eqGains,
    PrefsKeys.eqBassBoost,
    PrefsKeys.eqPreamp,
    PrefsKeys.eqVolumeBoost,
    PrefsKeys.eqVirtualizerEnabled,
    PrefsKeys.eqVirtualizerStrength,
    PrefsKeys.eqDynamicsPreset,
    PrefsKeys.eqDynamicsEnabled,
    PrefsKeys.eqDynamicsBypassed,
    PrefsKeys.eqSpatializerEnabled,
    PrefsKeys.eqHeadphoneProfileId,
    PrefsKeys.eqCustomFrequencies,
    PrefsKeys.eq32BandMode,
    PrefsKeys.eqBandCount,
    PrefsKeys.eqCustom32Frequencies,
    PrefsKeys.eqCustom64Frequencies,
    // Crossfeed.
    PrefsKeys.crossfeedEnabled,
    PrefsKeys.crossfeedDelayUs,
    PrefsKeys.crossfeedFeedDb,
    PrefsKeys.crossfeedFcut,
    PrefsKeys.crossfeedMode,
    // Saturation.
    PrefsKeys.saturationEnabled,
    PrefsKeys.saturationDrive,
    PrefsKeys.saturationMix,
    PrefsKeys.saturationTilt,
    PrefsKeys.saturationMode,
    PrefsKeys.saturationMultiband,
    // Stereo width.
    PrefsKeys.stereoWidthEnabled,
    PrefsKeys.stereoWidth,
    PrefsKeys.stereoWidthMultiband,
    PrefsKeys.stereoWidthLow,
    PrefsKeys.stereoWidthMid,
    PrefsKeys.stereoWidthHigh,
    PrefsKeys.stereoWidthLowCrossoverHz,
    PrefsKeys.stereoWidthHighCrossoverHz,
    // Dynamic bass.
    PrefsKeys.dynamicBassEnabled,
    PrefsKeys.dynamicBassStrength,
    PrefsKeys.dynamicBassXLow,
    PrefsKeys.dynamicBassXHigh,
    PrefsKeys.dynamicBassYLow,
    PrefsKeys.dynamicBassYHigh,
    PrefsKeys.dynamicBassSideGainLow,
    PrefsKeys.dynamicBassSideGainHigh,
    PrefsKeys.dynamicBassPreset,
    // Multiband compressor.
    PrefsKeys.multibandCompressorEnabled,
    PrefsKeys.multibandCompressorBands,
    PrefsKeys.multibandCompressorF0,
    PrefsKeys.multibandCompressorF1,
    PrefsKeys.multibandCompressorF2,
    // Convolution reverb.
    PrefsKeys.convolutionReverbEnabled,
    PrefsKeys.convolutionReverbPreset,
    PrefsKeys.convolutionReverbWetDry,
    PrefsKeys.convolutionReverbPredelayMs,
    PrefsKeys.convolutionReverbDamping,
    // Limiter.
    PrefsKeys.lookaheadLimiterEnabled,
    PrefsKeys.lookaheadLimiterThresholdDb,
    PrefsKeys.lookaheadLimiterReleaseMs,
    PrefsKeys.lookaheadLimiterLookaheadMs,
    // Dither.
    PrefsKeys.ditherEnabled,
    PrefsKeys.ditherTargetBitDepth,
    // ReplayGain.
    PrefsKeys.replayGainMode,
    PrefsKeys.replayGainPreampWithRg,
    PrefsKeys.replayGainPreampWithoutRg,
    // DSD transport.
    PrefsKeys.dsdOutputMode,
    PrefsKeys.dopContainerBits,
    // Output path.
    PrefsKeys.bitPerfectOutput,
    PrefsKeys.followTrackSampleRate,
    PrefsKeys.strictBitPerfect,
    PrefsKeys.aaudioOutputEnabled,
    PrefsKeys.aaudioPreferExclusive,
    PrefsKeys.aaudioTargetBufferMs,
    PrefsKeys.sincResamplerEnabled,
    PrefsKeys.sincResamplerQuality,
    PrefsKeys.tapSrcQuality,
    PrefsKeys.usbHardwareVolumeEnabled,
    PrefsKeys.dvcEnabled,
    PrefsKeys.bluetoothHiResEnabled,
    // DAC voicing.
    PrefsKeys.dacVoicingEnabled,
    PrefsKeys.dacVoicingCharacter,
    PrefsKeys.dacVoicingAmount,
  ];

  static final Set<String> _lookup = whitelist.toSet();

  /// Whether [key] may be captured into, or applied from, a profile.
  static bool isWhitelisted(String key) => _lookup.contains(key);
}
