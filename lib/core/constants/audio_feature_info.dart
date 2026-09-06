// lib/core/constants/audio_feature_info.dart
// Central registry: every audio feature exposes user-facing info + conflict rules.
// Single source of truth for “show the user info on every feature and prevent him to select 2 thing cannot work together”.

import '../../domain/models/audio_output_info.dart';

/// Human-readable info for one toggle/slider/card.
class AudioFeatureInfo {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String? conflictsWith; // e.g. "Bit-Perfect bypass", "Gapless"
  final String? whyDisabledReason; // shown when disabled due to conflict

  const AudioFeatureInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    this.conflictsWith,
    this.whyDisabledReason,
  });
}

/// All audio features in the app. Used by UI to render an Ⓘ button next to each control.
class AudioFeatureRegistry {
  static const bitPerfect = AudioFeatureInfo(
    id: 'bitPerfect',
    title: 'Bit-Perfect USB Pass-Through',
    subtitle: 'Direct hardware streaming to USB / wired DAC',
    description:
        'Bypasses Android AudioFlinger resampler and sends the file\'s exact samples (e.g. 96 kHz / 24-bit) straight to the DAC via AudioMixerAttributes (API 34) for USB, or via direct/offload for wired. No software volume or DSP is applied. Requires Android 14+ for USB, or a wired device that advertises FLOAT/24-bit & hi-res rates. Bluetooth is NEVER bit-perfect (SBC/AAC/LDAC transcode).',
    conflictsWith: 'All DSP when “Bypass DSP” is ON',
  );

  static const bypassDsp = AudioFeatureInfo(
    id: 'bypassDsp',
    title: 'Bypass DSP in Bit-Perfect Mode',
    subtitle: 'Uncolored, pure bitstream to DAC',
    description:
        'When ON, entering Bit-Perfect immediately disables EQ, Virtualizer, Dynamics, Crossfeed, Limiter, Reverb, Stereo Panner and Sinc Resampler (native mask = 0). Volume is locked to hardware DAC. Turn OFF if you want EQ + bit-perfect (not true bit-perfect, but some DACs tolerate it).',
  );

  static const equalizer = AudioFeatureInfo(
    id: 'equalizer',
    title: '10 / 32-Band Parametric EQ',
    subtitle: '±15 dB per band, Q=1.414, flat by default',
    description:
        'Native C++ biquad cascade (32 bands max, 8 channels). Uses single bulk JNI hop (≈1 ms) with zero-cost bypass when disabled. Interpolates AutoEQ profiles log-frequency wise. Cannot be active with Bit-Perfect bypass (would re-sample and alter bits).',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const bassBoost = AudioFeatureInfo(
    id: 'bassBoost',
    title: 'Bass Enhancer',
    subtitle: 'Shelving low-end gain (part of EQ engine)',
    description:
        'Adds a low-shelf lift below ~150 Hz via the native EQ biquad chain. Shares the same processing stage as the graphic EQ, so it is disabled while Bit-Perfect bypass is active. Keep moderate to avoid masking detail.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const crossfeed = AudioFeatureInfo(
    id: 'crossfeed',
    title: 'Headphone Crossfeed',
    subtitle: '200–700 µs delay, –15 to –6 dB bleed',
    description:
        'Chu Moy / Linkwitz blend that makes headphones sound like speakers (reduces hard L/R separation). Adds ~0.05 ms latency. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const limiter = AudioFeatureInfo(
    id: 'limiter',
    title: 'Lookahead Brickwall Limiter',
    subtitle: 'True-peak, 0.5–20 ms lookahead',
    description:
        'Adaptive true-peak limiter with 4× oversample. Protects against clipping when EQ boosts. Adds ~5 ms latency. Final stage before DAC. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const reverb = AudioFeatureInfo(
    id: 'reverb',
    title: 'Convolution Reverb',
    subtitle: '8 rooms (RT60 0.35–5 s) or custom IR',
    description:
        'Partitioned convolution (512-frame blocks) against a synthesized room impulse — Studio, Room, Chamber, Hall, Concert Hall, Cathedral, Plate, Spring — or an impulse response you load. Largest latency (~10 ms). IR synthesis runs off the main thread. Needs the native DSP path; disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const panner = AudioFeatureInfo(
    id: 'panner',
    title: 'Stereo Balance & Mono Mix',
    subtitle: '–1.0 Left … +1.0 Right, mono collapse',
    description:
        'Constant-power panner + mono downmix (L+R / 2). Useful for hearing asymmetry. Collapses soundstage when mono ON. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const resampler = AudioFeatureInfo(
    id: 'resampler',
    title: 'Polyphase Sinc Resampler',
    subtitle: '32 phases × 32 taps, auto 44.1→48 kHz',
    description:
        'High-quality sinc interpolation when track rate ≠ device rate. Auto-bypasses when rates match (zero CPU). Disabled during Bit-Perfect (direct 1:1 stream).',
    conflictsWith: 'Bit-Perfect bypass / Direct',
  );

  static const virtualizer = AudioFeatureInfo(
    id: 'virtualizer',
    title: 'Soundstage Widening (Virtualizer)',
    subtitle: 'Android Virtualizer stereo expansion',
    description:
        'Expands stereo field via AudioEffect Virtualizer (0–1000 mB). On devices with Hardware Spatializer, Spatializer takes precedence and Virtualizer is bypassed. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass, Hardware Spatializer',
  );

  static const spatializer = AudioFeatureInfo(
    id: 'spatializer',
    title: 'Hardware Spatializer',
    subtitle: 'Android Spatializer API + head tracking',
    description:
        'Uses AudioManager.spatializer when available (Android 12L+). Provides true spatial audio if device supports it; otherwise emulates via Virtualizer. Mutually managed with Virtualizer.',
  );

  static const dynamics = AudioFeatureInfo(
    id: 'dynamics',
    title: 'Studio Dynamics & MBC',
    subtitle: '3-band MBC + limiter presets',
    description:
        'DynamicsProcessing multiband compressor (Studio Punch / Warm Analog / Vocal Focus / Night Leveller / Bass Tightener). Controls transients and loudness. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const roomCorrection = AudioFeatureInfo(
    id: 'roomCorrection',
    title: 'Room Correction Wizard',
    subtitle: 'Stepped-sine measurement + EQ fit',
    description:
        'Plays a short tone sweep through your speakers, records it with the microphone and fits a Room Correction EQ preset that flattens the measured response (clamped to the +/-15 dB EQ range with adjacent-band smoothing). Applied through the normal EQ pipeline, so it participates in Bit-Perfect bypass like any EQ preset. Not a replacement for acoustic treatment.',
  );

  static const dsdNative = AudioFeatureInfo(
    id: 'dsdNative',
    title: 'DSD (Native / DoP)',
    subtitle: 'Detection-only in this build',
    description:
        'DSD files (DSF/DFF) decode to PCM through the native DSD decoder and then follow the normal DSP pipeline. DoP framing exists as a future transport; raw native-DSD USB streaming is not implemented, so this feature reports DAC class diagnostics (UAC1/UAC2/UAC3) without claiming native-DSD capability.',
  );

  static const gapless = AudioFeatureInfo(
    id: 'gapless',
    title: 'Gapless Playback',
    subtitle: 'ConcatenatingAudioSource, zero gap',
    description:
        'Joins consecutive tracks sample-accurate with no silence. Ideal for live albums. Mutually exclusive with Crossfade — enabling one forces the other OFF.',
    conflictsWith: 'Crossfade (>0 s)',
  );

  static const crossfade = AudioFeatureInfo(
    id: 'crossfade',
    title: 'Crossfade',
    subtitle: '0–12 s overlapping dual-player fade',
    description:
        'Fades out current track while fading in next via dual ExoPlayer. Requires disabling Gapless (cannot be gapless and crossfading simultaneously).',
    conflictsWith: 'Gapless',
  );

  static const replayGain = AudioFeatureInfo(
    id: 'replayGain',
    title: 'ReplayGain Normalization',
    subtitle: 'EBU R128 track/album/auto',
    description:
        'Software volume leveling based on Track/Album Gain tags. Applies multiplier with 0.5 dB inter-sample headroom. Conflicts with Bit-Perfect bypass (software gain would alter bits). Set to Off for true exclusive.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const oem = AudioFeatureInfo(
    id: 'oem',
    title: 'OEM Audio Warning',
    subtitle: 'Dolby / Dirac / SoundAlive double-processing',
    description:
        'System-level effects (Dolby Atmos, Xiaomi Sound, Dirac) run outside the app. Running Pulsr DSP on top causes double-EQ and clipping. Use DSP Preference = Native or disable system effects for cleanest sound.',
  );

  static const volumeBoost = AudioFeatureInfo(
    id: 'volumeBoost',
    title: 'Volume Boost',
    subtitle: 'LoudnessEnhancer +10 dB',
    description:
        'Hardware LoudnessEnhancer gain (0–1000 mB). Capped at +6 dB combined with headphone preamp to avoid clipping. Disabled during Bit-Perfect bypass (hardware DAC volume only).',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const saturation = AudioFeatureInfo(
    id: 'saturation',
    title: 'Harmonic Saturation / Exciter',
    subtitle: 'Tube/tape tanh waveshaping, drive · mix · tilt',
    description:
        'Generates harmonics via tanh waveshaping with a tape-style HF tilt emphasis and wet/dry mix. Zero latency. Adds density and warmth; excessive drive increases THD. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const stereoWidth = AudioFeatureInfo(
    id: 'stereoWidth',
    title: 'Stereo Width (Mid/Side)',
    subtitle: '0 = mono · 1 = normal · 2 = widest',
    description:
        'Mid/Side matrix that scales the side signal (L−R). Independent from Crossfeed and the Virtualizer: width 0 collapses to mono, values above 1 widen the field. Zero latency. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const loudnessContour = AudioFeatureInfo(
    id: 'loudnessContour',
    title: 'Loudness Contour (Fletcher–Munson)',
    subtitle: 'Volume-linked bass & treble compensation',
    description:
        'Equal-loudness approximation: as playback volume decreases, a gentle low-shelf (~100 Hz) and smaller high-shelf (~8 kHz) lift is applied, vanishing at full volume. Gain-domain but complementary to ReplayGain — ReplayGain levels tracks to a common target, while this contour adapts tone to the listening level; both can be ON together. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const subCrossover = AudioFeatureInfo(
    id: 'subCrossover',
    title: 'Subwoofer Crossover (Bass Redirection)',
    subtitle: '60–150 Hz low-pass, 12/24 dB/oct, summed mono tap',
    description:
        'Bass redirection for stereo rigs: a Linkwitz-Riley-style low-passed mono sum is mixed back into both channels at user gain. Mains keep full range — this is not true multichannel LFE routing. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const dynamicEq = AudioFeatureInfo(
    id: 'dynamicEq',
    title: 'Dynamic EQ',
    subtitle: 'Frequency bands that cut only when energy exceeds threshold',
    description:
        'Per-band dynamic cut: engages only while signal energy inside the band exceeds its threshold (threshold/ratio/attack/release per band, capped max cut). Tames resonances without static EQ coloration. Note: it interacts with the OEM DynamicsProcessing compressor — using both may double-compress the same band. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );
}

/// Pure-logic conflict checker. Returns null if allowed, otherwise a human reason why the action must be blocked.
class AudioConflicts {
  /// Bit-perfect bypass disables all native DSP, virtualizer and software gain.
  static String? dspBlockedByBitPerfect({
    required bool bitPerfectOutput,
    required bool bypassDspOnBitPerfect,
    required AudioOutputInfo? device,
  }) {
    if (!bitPerfectOutput || !bypassDspOnBitPerfect) return null;
    if (device?.isBluetooth == true) return null;
    if (device?.isBitPerfectActive != true) return null;
    return 'Disabled: Bit-Perfect bypass is ON — this DSP would alter the exclusive bitstream. Turn off Bit-Perfect or disable “Bypass DSP” to enable.';
  }

  static String? bitPerfectBlockedReason(AudioOutputInfo? device) {
    if (device == null) return null;
    if (device.isBluetooth) {
      return 'Cannot enable: Bluetooth transcodes (SBC/AAC/LDAC/LC3) — bit-perfect only on a USB DAC.';
    }
    if (device.bitPerfectFailureReason == 'requires_android_14_for_usb' ||
        device.bitPerfectFailureReason == 'requires_android_14') {
      return 'Requires Android 14+ for USB bit-perfect output.';
    }
    if (device.bitPerfectFailureReason == 'exclusive_requires_usb_dac') {
      return 'Cannot enable: Android exposes exclusive output only for USB DACs. Wired hi-res still plays direct when the device supports it.';
    }
    if (device.bitPerfectFailureReason == 'no_supported_mixer_attributes') {
      return 'This USB DAC does not advertise an exclusive mixer configuration.';
    }
    return null;
  }

  static String? gaplessBlockedByCrossfade(double crossfadeSeconds) {
    if (crossfadeSeconds > 0.01) {
      return 'Disabled: Crossfade is ${crossfadeSeconds.toStringAsFixed(1)} s — gapless requires 0 s. Set Crossfade to 0 to enable gapless.';
    }
    return null;
  }

  static String? crossfadeBlockedByGapless(bool gaplessEnabled) {
    if (gaplessEnabled) {
      return 'Disabled: Gapless is ON — crossfade needs gapless OFF. Disable Gapless to enable crossfade.';
    }
    return null;
  }

  static String? replayGainBlockedByBitPerfect({
    required bool bitPerfectOutput,
    required bool bypassDspOnBitPerfect,
    required AudioOutputInfo? device,
  }) =>
      dspBlockedByBitPerfect(
          bitPerfectOutput: bitPerfectOutput,
          bypassDspOnBitPerfect: bypassDspOnBitPerfect,
          device: device);

  static String? oemDoubleProcessingWarning(
      {required bool hasOemAudio, required bool anyDspEnabled}) {
    if (hasOemAudio && anyDspEnabled) {
      return 'Warning: System Dolby/Dirac is active — running Pulsr DSP on top causes double-processing. Prefer DSP Preference = Native and disable system effects.';
    }
    return null;
  }

  static String? volumeBoostClippingWarning(
      double volumeBoost, double preampDb) {
    final total = preampDb + volumeBoost * 10.0;
    if (total > 6.0) {
      return 'Clipping risk: EQ preamp (${preampDb.toStringAsFixed(1)} dB) + boost (+${(volumeBoost * 10).toStringAsFixed(1)} dB) = +${total.toStringAsFixed(1)} dB > 6 dB headroom.';
    }
    if (volumeBoost > 0.6) {
      return 'High boost may cause distortion or hearing fatigue.';
    }
    return null;
  }
}
