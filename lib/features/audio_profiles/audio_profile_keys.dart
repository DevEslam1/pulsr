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
/// Expected SharedPreferences storage type for an [AudioProfileKeys] entry.
enum AudioProfileValueType {
  boolean,
  integer,
  floating,
  string,
  stringOrStringList,
}

/// Canonical whitelist of settings captured into and restored from an audio
/// profile.
abstract final class AudioProfileKeys {
  /// Per-key typed schema for every setting allowed in an audio profile.
  static const Map<String, AudioProfileValueType> schema =
      <String, AudioProfileValueType>{
    // Equalizer.
    PrefsKeys.eqEnabled: AudioProfileValueType.boolean,
    PrefsKeys.eqPresetName: AudioProfileValueType.string,
    PrefsKeys.eqGains: AudioProfileValueType.stringOrStringList,
    PrefsKeys.eqBassBoost: AudioProfileValueType.floating,
    PrefsKeys.eqPreamp: AudioProfileValueType.floating,
    PrefsKeys.eqVolumeBoost: AudioProfileValueType.floating,
    PrefsKeys.eqVirtualizerEnabled: AudioProfileValueType.boolean,
    PrefsKeys.eqVirtualizerStrength: AudioProfileValueType.floating,
    PrefsKeys.eqDynamicsPreset: AudioProfileValueType.string,
    PrefsKeys.eqDynamicsEnabled: AudioProfileValueType.boolean,
    PrefsKeys.eqDynamicsBypassed: AudioProfileValueType.boolean,
    PrefsKeys.eqSpatializerEnabled: AudioProfileValueType.boolean,
    PrefsKeys.eqHeadphoneProfileId: AudioProfileValueType.string,
    PrefsKeys.eqCustomFrequencies: AudioProfileValueType.string,
    PrefsKeys.eq32BandMode: AudioProfileValueType.boolean,
    PrefsKeys.eqBandCount: AudioProfileValueType.integer,
    PrefsKeys.eqCustom32Frequencies: AudioProfileValueType.string,
    PrefsKeys.eqCustom64Frequencies: AudioProfileValueType.string,
    // HRTF Binaural.
    PrefsKeys.hrtfBinauralEnabled: AudioProfileValueType.boolean,
    PrefsKeys.hrtfAzimuth: AudioProfileValueType.floating,
    PrefsKeys.hrtfElevation: AudioProfileValueType.floating,
    PrefsKeys.hrtfSofaPath: AudioProfileValueType.string,
    // Crossfeed.
    PrefsKeys.crossfeedEnabled: AudioProfileValueType.boolean,
    PrefsKeys.crossfeedDelayUs: AudioProfileValueType.floating,
    PrefsKeys.crossfeedFeedDb: AudioProfileValueType.floating,
    PrefsKeys.crossfeedFcut: AudioProfileValueType.floating,
    PrefsKeys.crossfeedMode: AudioProfileValueType.integer,
    // Saturation.
    PrefsKeys.saturationEnabled: AudioProfileValueType.boolean,
    PrefsKeys.saturationDrive: AudioProfileValueType.floating,
    PrefsKeys.saturationMix: AudioProfileValueType.floating,
    PrefsKeys.saturationTilt: AudioProfileValueType.floating,
    PrefsKeys.saturationMode: AudioProfileValueType.integer,
    PrefsKeys.saturationMultiband: AudioProfileValueType.boolean,
    // Stereo width.
    PrefsKeys.stereoWidthEnabled: AudioProfileValueType.boolean,
    PrefsKeys.stereoWidth: AudioProfileValueType.floating,
    PrefsKeys.stereoWidthMultiband: AudioProfileValueType.boolean,
    PrefsKeys.stereoWidthLow: AudioProfileValueType.floating,
    PrefsKeys.stereoWidthMid: AudioProfileValueType.floating,
    PrefsKeys.stereoWidthHigh: AudioProfileValueType.floating,
    PrefsKeys.stereoWidthLowCrossoverHz: AudioProfileValueType.floating,
    PrefsKeys.stereoWidthHighCrossoverHz: AudioProfileValueType.floating,
    // Dynamic bass.
    PrefsKeys.dynamicBassEnabled: AudioProfileValueType.boolean,
    PrefsKeys.dynamicBassStrength: AudioProfileValueType.floating,
    PrefsKeys.dynamicBassXLow: AudioProfileValueType.integer,
    PrefsKeys.dynamicBassXHigh: AudioProfileValueType.integer,
    PrefsKeys.dynamicBassYLow: AudioProfileValueType.integer,
    PrefsKeys.dynamicBassYHigh: AudioProfileValueType.integer,
    PrefsKeys.dynamicBassSideGainLow: AudioProfileValueType.floating,
    PrefsKeys.dynamicBassSideGainHigh: AudioProfileValueType.floating,
    PrefsKeys.dynamicBassPreset: AudioProfileValueType.integer,
    // Multiband compressor.
    PrefsKeys.multibandCompressorEnabled: AudioProfileValueType.boolean,
    PrefsKeys.multibandCompressorBands: AudioProfileValueType.string,
    PrefsKeys.multibandCompressorF0: AudioProfileValueType.floating,
    PrefsKeys.multibandCompressorF1: AudioProfileValueType.floating,
    PrefsKeys.multibandCompressorF2: AudioProfileValueType.floating,
    // Convolution reverb.
    PrefsKeys.convolutionReverbEnabled: AudioProfileValueType.boolean,
    PrefsKeys.convolutionReverbPreset: AudioProfileValueType.integer,
    PrefsKeys.convolutionReverbWetDry: AudioProfileValueType.floating,
    PrefsKeys.convolutionReverbPredelayMs: AudioProfileValueType.floating,
    PrefsKeys.convolutionReverbDamping: AudioProfileValueType.floating,
    // Limiter.
    PrefsKeys.lookaheadLimiterEnabled: AudioProfileValueType.boolean,
    PrefsKeys.lookaheadLimiterThresholdDb: AudioProfileValueType.floating,
    PrefsKeys.lookaheadLimiterReleaseMs: AudioProfileValueType.floating,
    PrefsKeys.lookaheadLimiterLookaheadMs: AudioProfileValueType.floating,
    // Dither.
    PrefsKeys.ditherEnabled: AudioProfileValueType.boolean,
    PrefsKeys.ditherTargetBitDepth: AudioProfileValueType.integer,
    // ReplayGain.
    PrefsKeys.replayGainMode: AudioProfileValueType.string,
    PrefsKeys.replayGainPreampWithRg: AudioProfileValueType.floating,
    PrefsKeys.replayGainPreampWithoutRg: AudioProfileValueType.floating,
    // DSD transport.
    PrefsKeys.dsdOutputMode: AudioProfileValueType.string,
    PrefsKeys.dopContainerBits: AudioProfileValueType.integer,
    // Output path.
    PrefsKeys.bitPerfectOutput: AudioProfileValueType.boolean,
    PrefsKeys.followTrackSampleRate: AudioProfileValueType.boolean,
    PrefsKeys.strictBitPerfect: AudioProfileValueType.boolean,
    PrefsKeys.aaudioOutputEnabled: AudioProfileValueType.boolean,
    PrefsKeys.aaudioPreferExclusive: AudioProfileValueType.boolean,
    PrefsKeys.aaudioTargetBufferMs: AudioProfileValueType.integer,
    PrefsKeys.sincResamplerEnabled: AudioProfileValueType.boolean,
    PrefsKeys.sincResamplerQuality: AudioProfileValueType.integer,
    PrefsKeys.tapSrcQuality: AudioProfileValueType.integer,
    PrefsKeys.usbHardwareVolumeEnabled: AudioProfileValueType.boolean,
    PrefsKeys.dvcEnabled: AudioProfileValueType.boolean,
    PrefsKeys.bluetoothHiResEnabled: AudioProfileValueType.boolean,
    // DAC voicing.
    PrefsKeys.dacVoicingEnabled: AudioProfileValueType.boolean,
    PrefsKeys.dacVoicingCharacter: AudioProfileValueType.integer,
    PrefsKeys.dacVoicingAmount: AudioProfileValueType.floating,
    // Loudness contour.
    PrefsKeys.loudnessContourEnabled: AudioProfileValueType.boolean,
    PrefsKeys.loudnessContourIntensity: AudioProfileValueType.floating,
    // Subwoofer crossover.
    PrefsKeys.subCrossoverEnabled: AudioProfileValueType.boolean,
    PrefsKeys.subCrossoverCornerHz: AudioProfileValueType.floating,
    PrefsKeys.subCrossoverSlopeDbPerOct: AudioProfileValueType.floating,
    PrefsKeys.subCrossoverGain: AudioProfileValueType.floating,
    PrefsKeys.subCrossoverBassMono: AudioProfileValueType.boolean,
    PrefsKeys.subCrossoverAntiPop: AudioProfileValueType.boolean,
    // Channel Manager.
    PrefsKeys.channelManagerEnabled: AudioProfileValueType.boolean,
    PrefsKeys.channelManagerChannelCount: AudioProfileValueType.integer,
    PrefsKeys.channelManagerTrims: AudioProfileValueType.string,
    PrefsKeys.channelManagerDelays: AudioProfileValueType.string,
    // LFE Crossover.
    PrefsKeys.lfeCrossoverEnabled: AudioProfileValueType.boolean,
    PrefsKeys.lfeCrossoverHz: AudioProfileValueType.floating,
    PrefsKeys.lfeLowPassHz: AudioProfileValueType.floating,
    PrefsKeys.lfeSlopeDbPerOct: AudioProfileValueType.floating,
    PrefsKeys.lfeGainDb: AudioProfileValueType.floating,
    PrefsKeys.lfeChannelIndex: AudioProfileValueType.integer,
    PrefsKeys.lfeRedirectBass: AudioProfileValueType.boolean,
    // Dynamic EQ.
    PrefsKeys.dynamicEqEnabled: AudioProfileValueType.boolean,
    PrefsKeys.dynamicEqBands: AudioProfileValueType.string,
    // ViPER-DDC.
    PrefsKeys.viperDdcEnabled: AudioProfileValueType.boolean,
    PrefsKeys.viperDdcProfileName: AudioProfileValueType.string,
    PrefsKeys.viperDdcContent: AudioProfileValueType.string,
    // Arbitrary response EQ.
    PrefsKeys.arbitraryEqEnabled: AudioProfileValueType.boolean,
    PrefsKeys.arbitraryEqString: AudioProfileValueType.string,
    PrefsKeys.arbitraryEqLinearPhase: AudioProfileValueType.boolean,
    // Live programmable DSP.
    PrefsKeys.liveProgEnabled: AudioProfileValueType.boolean,
    PrefsKeys.liveProgCode: AudioProfileValueType.string,
    PrefsKeys.liveProgSliders: AudioProfileValueType.string,
    // Balance and mix.
    PrefsKeys.stereoBalance: AudioProfileValueType.floating,
    PrefsKeys.monoMix: AudioProfileValueType.boolean,
  };

  /// SharedPreferences keys owned by the audio profile format.
  static final List<String> whitelist =
      List<String>.unmodifiable(schema.keys);

  /// Whether [key] may be captured into, or applied from, a profile.
  static bool isWhitelisted(String key) => schema.containsKey(key);

  /// Expected value type for [key], or null if [key] is not whitelisted.
  static AudioProfileValueType? typeOf(String key) => schema[key];

  /// Validates and normalizes [value] for [key], returning `null` if [key] is
  /// unknown or [value] does not conform to [schema].
  ///
  /// Whole-number integers encoded as JSON numbers (`0`, `1`) are promoted to
  /// `double` for [AudioProfileValueType.floating] keys; non-finite doubles
  /// (`NaN`, `Infinity`) and non-string list elements are rejected.
  static ({bool valid, Object? normalized}) validate(
      String key, Object? value) {
    final expected = schema[key];
    if (expected == null) return (valid: false, normalized: null);
    switch (expected) {
      case AudioProfileValueType.boolean:
        return value is bool
            ? (valid: true, normalized: value)
            : const (valid: false, normalized: null);
      case AudioProfileValueType.integer:
        return value is int
            ? (valid: true, normalized: value)
            : const (valid: false, normalized: null);
      case AudioProfileValueType.floating:
        if (value is double) {
          return value.isFinite
              ? (valid: true, normalized: value)
              : const (valid: false, normalized: null);
        }
        if (value is int) {
          return (valid: true, normalized: value.toDouble());
        }
        return const (valid: false, normalized: null);
      case AudioProfileValueType.string:
        return value is String
            ? (valid: true, normalized: value)
            : const (valid: false, normalized: null);
      case AudioProfileValueType.stringOrStringList:
        if (value is String) return (valid: true, normalized: value);
        if (value is List) {
          final strings = <String>[];
          for (final item in value) {
            if (item is! String) return const (valid: false, normalized: null);
            strings.add(item);
          }
          return (valid: true, normalized: List<String>.unmodifiable(strings));
        }
        return const (valid: false, normalized: null);
    }
  }
}
