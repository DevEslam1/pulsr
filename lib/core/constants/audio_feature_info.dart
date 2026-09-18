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

  static const followTrackSampleRate = AudioFeatureInfo(
    id: 'followTrackSampleRate',
    title: 'Follow Track Sample Rate',
    subtitle: 'Reconfigure the output to each track\'s native rate',
    description:
        'On every track change, requests the track\'s own sample rate from the output device so no software resampling is needed. De-duplicated so tracks that share a rate do not trigger redundant native reconfiguration. Skipped on Bluetooth, where the AVRCP/codec link owns the rate. The device may still cap the rate; the negotiated format is shown in Output Path Diagnostics.',
  );

  static const strictBitPerfect = AudioFeatureInfo(
    id: 'strictBitPerfect',
    title: 'Strict Bit-Perfect (No Resample)',
    subtitle: 'Exact source bits, no resampler — DSP stages off',
    description:
        'Forces Bit-Perfect output and the DSP bypass, then follows each track\'s native sample rate so the DAC receives the exact source samples without resampling. Because it is strict, EQ, ReplayGain, Virtualizer/Dynamics and Crossfade cannot run: they would alter the bitstream. Requires a path that reports exclusive bit-perfect support (USB DAC on Android 14+); otherwise the toggle is disabled with the platform reason.',
    conflictsWith: 'EQ / ReplayGain / Effects / Crossfade',
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
    subtitle: '8 rooms (RT60 0.35–5 s), cross-channel crosstalk, or custom IR',
    description:
        'Partitioned convolution (512-frame blocks) against a synthesized room impulse or custom impulse response you load. Features adjustable cross-channel crosstalk for authentic binaural IRS stereo spatialization. Zero heap allocations in audio loop. Needs the native DSP path; disabled during Bit-Perfect.',
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
    subtitle: '32 phases × 32 taps (polyphase engine)',
    description:
        'Polyphase sinc interpolation engine. The in-stream playback path keeps the source frame count, so track→device rate conversion is performed by the platform output (AudioTrack); the polyphase engine is applied internally by the convolution reverb wet path above 48 kHz. Disabled during Bit-Perfect (direct 1:1 stream).',
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
    title: 'DSD (PCM Decode / DoP Output)',
    subtitle: 'PCM by default — DoP only with a compatible USB DAC',
    description:
        'DSD files (DSF/DFF) decode to PCM through the native DSD decoder by default and follow the normal DSP pipeline. When the user selects DoP output and a USB DAC that can carry it is connected, the raw DSD bitstream is framed as DSD over PCM (alternating 0x05/0xFA markers) at DSD rate / 16 (DSD64 → 176.4 kHz, DSD128 → 352.8 kHz, DSD256 → 705.6 kHz) so the DAC streams native DSD, in 24-bit or zero-padded 32-bit containers (selectable for DACs that require 32-bit USB frames). DoP is never enabled automatically and stays unavailable when no compatible USB DAC is detected. Direct native-DSD streaming that bypasses DoP is not implemented in this build, so native-DSD capability is never claimed beyond the detected USB DAC.',
  );

  static const mqa = AudioFeatureInfo(
    id: 'mqa',
    title: 'MQA (Master Quality Authenticated)',
    subtitle: 'Detected — core unfold only, no authenticated rendering',
    description:
        'MQA-encoded files are detected from their signature and labeled "MQA" in the quality sheet. Core unfold is handled by the in-app decoder; full authenticated/native MQA rendering is not available in this build, so MQA status is never silently reported as plain lossless and authenticated MQA output is never claimed.',
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
    subtitle: 'Track / album gain tags in native pre-gain',
    description:
        'Bit-transparent native pre-gain driven by Track/Album Gain tags (20 ms smoothing, 0.5 dB inter-sample headroom, clipping-safe). The Dart mixer then carries only user volume so the gain is never applied twice; DoP and non-Android fall back to Dart math. Conflicts with Bit-Perfect bypass (any gain would alter bits). Set to Off for true exclusive.',
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
    subtitle: 'Tape, Vacuum Tube (2nd harmonic), or Analog Class-A with 4× sinc oversampling',
    description:
        'Generates rich analog warmth and harmonic density. Offers 3 selectable color profiles: Tape (smooth odd-order saturation), Vacuum Tube (asymmetric 6J1 triode with warm even 2nd harmonics), and Analog Class-A (full vintage transformer response). Features 4× polyphase sinc anti-aliasing and DC blocking. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const stereoWidth = AudioFeatureInfo(
    id: 'stereoWidth',
    title: '3-Band Stereo Imager & Bass Mono',
    subtitle: 'Multiband width + sub-bass mono phase protection',
    description:
        'Mid/Side multiband stereo imager utilizing phase-linear Linkwitz-Riley crossovers. Features dedicated low (<160 Hz), mid (160 Hz–2.5 kHz), and high (>2.5 kHz) width controls. Sub-bass mono isolation eliminates stereo low-end phase cancellation and comb filtering. Disabled during Bit-Perfect.',
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
    subtitle: '60–150 Hz Linkwitz-Riley, Bass Mono + Anti-Pop limiting',
    description:
        'Bass redirection for stereo rigs: a 4th-order Linkwitz-Riley low-pass mono sum is mixed into both channels. Features Bass Mono side-channel subtraction to keep sub-bass punchy and mono-centered, plus tanh anti-pop soft-limiting to eliminate clicks. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const dynamicEq = AudioFeatureInfo(
    id: 'dynamicEq',
    title: 'Dynamic EQ (Cut & Boost)',
    subtitle: 'Multi-mode dynamic filters (Peaking, Low-Shelf, High-Shelf)',
    description:
        'Per-band dynamic equalization supporting both Cut (resonance taming) and Boost (transient expansion) modes. Selectable between Peaking biquad, Low-Shelf, and High-Shelf dynamic responses with smooth soft-knee detection. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const multibandCompressor = AudioFeatureInfo(
    id: 'multibandCompressor',
    title: 'Native 4-Band Multiband Compressor',
    subtitle: 'Phase-aligned Linkwitz-Riley 4th order crossovers, zero-latency C++',
    description:
        'Professional 4-band studio mastering compressor built directly into the C++ native DSP engine. Uses Linkwitz-Riley 4th order (LR4) crossovers for exact flat magnitude summation with zero phase distortion. Features independent threshold, ratio, attack, release, soft-knee, and makeup gain per band. Replaces fragile HAL compressor paths. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const dynamicBass = AudioFeatureInfo(
    id: 'dynamicBass',
    title: 'Dynamic Bass (Dynamic System)',
    subtitle: 'Envelope-adaptive sub-bass punch & headphone virtualization',
    description:
        'Modeled on ViPER4Android’s famous Dynamic System. Restores physical weight and tactile punch for headphones by dynamically expanding quiet bass passages and soft-saturating loud peaks. Features Mid-Side sub-bass extraction, psychoacoustic harmonic synthesis, and 9 classic headphone device calibration presets. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const viperDdc = AudioFeatureInfo(
    id: 'viperDdc',
    title: 'ViPER-DDC (Digital Dynamic Correction)',
    subtitle: 'Hardware headphone timbre & frequency linearization',
    description:
        'Loads authentic ViPER-DDC (.vdc) correction profiles. Implements high-order Second-Order Sections (SOS) Direct Form II stereo filtering with real-time sample rate adaptation (44.1 kHz / 48 kHz). Precisely neutralizes earphone-specific resonances. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const arbitraryEq = AudioFeatureInfo(
    id: 'arbitraryEq',
    title: 'Arbitrary Response EQ (GraphicEq)',
    subtitle: 'EqualizerAPO graphic response curve parser & 512-tap FIR filter',
    description:
        'Parses standard EqualizerAPO "GraphicEq: <freq> <gain>; ..." curve specifications. Computes log-frequency interpolated frequency response and synthesizes a 512-tap windowed FIR impulse response for exact acoustic matching. Minimum-phase by default (zero extra delay); enable Linear-phase FIR for constant group delay and exact phase at the cost of pre-ringing. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );

  static const liveProg = AudioFeatureInfo(
    id: 'liveProg',
    title: 'Live Programmable DSP (EEL Scripting)',
    subtitle: 'Real-time custom audio DSP bytecode VM',
    description:
        'Write custom audio DSP algorithms in Jesusonic / EEL scripting syntax right on your phone. Code compiles directly to safe, zero-latency bytecode executed per-sample inside the high-priority native audio thread. Supports @init, @sample, sliders 1..8, and comprehensive transcendental math functions. Disabled during Bit-Perfect.',
    conflictsWith: 'Bit-Perfect bypass',
  );
}

/// Pure-logic conflict checker. Returns null if allowed, otherwise a human reason why the action must be blocked.
class AudioConflicts {
  /// Bit-perfect bypass disables all native DSP, virtualizer and software gain.
  ///
  /// AAudio Direct bypasses the same DSP chain, and a live DSD-over-PCM carrier
  /// would be corrupted by any sample processing, so both are reported here too
  /// — the caller does not have to chain three checks.
  static String? dspBlockedByBitPerfect({
    required bool bitPerfectOutput,
    required bool bypassDspOnBitPerfect,
    required AudioOutputInfo? device,
    bool aaudioEnabled = false,
    bool dsdDopActive = false,
  }) {
    if (aaudioEnabled) {
      return 'Disabled: AAudio Direct is ON — it bypasses the ExoPlayer DSP chain (EQ, speed/pitch, silence skip, crossfade). Turn it off to re-enable DSP.';
    }
    if (dsdDopActive) {
      return 'Disabled: DSD over PCM (DoP) is playing — any DSP or gain would corrupt the DoP carrier. Switch DSD output to PCM to re-enable DSP.';
    }
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
    bool aaudioEnabled = false,
    bool dsdDopActive = false,
  }) =>
      dspBlockedByBitPerfect(
          bitPerfectOutput: bitPerfectOutput,
          bypassDspOnBitPerfect: bypassDspOnBitPerfect,
          device: device,
          aaudioEnabled: aaudioEnabled,
          dsdDopActive: dsdDopActive);

  /// Strict bit-perfect can only be enabled on a path that actually exposes
  /// exclusive bit-perfect output. Reuses [bitPerfectBlockedReason] for the
  /// transport/OS blockers and adds the "no exclusive mixer attributes" case.
  static String? strictBitPerfectBlockedReason(AudioOutputInfo? device) {
    final base = bitPerfectBlockedReason(device);
    if (base != null) return base;
    if (device == null) {
      return 'Cannot enable: no output device detected yet. Connect a USB DAC and retry.';
    }
    if (!device.isBitPerfectSupported) {
      return 'Cannot enable: this output path does not expose exclusive bit-perfect mixer attributes.';
    }
    return null;
  }

  /// Reason shown while strict bit-perfect is active (or armed with the DSP
  /// bypass): the stages below are intentionally muted.
  static String? strictBitPerfectActiveReason({
    required bool bitPerfectOutput,
    required bool bypassDspOnBitPerfect,
    required AudioOutputInfo? device,
  }) {
    if (!bitPerfectOutput || !bypassDspOnBitPerfect) return null;
    if (device?.isBluetooth == true) return null;
    return 'Strict bit-perfect is ON: EQ, ReplayGain, Virtualizer/Dynamics and Crossfade are muted so the exact source samples reach the DAC. Turn Strict bit-perfect off to re-enable them.';
  }

  /// Crossfade is software overlap and cannot run while the DSP bypass is
  /// keeping the bitstream bit-exact.
  static String? crossfadeBlockedByBitPerfect({
    required bool bitPerfectOutput,
    required bool bypassDspOnBitPerfect,
    required AudioOutputInfo? device,
    bool aaudioEnabled = false,
  }) {
    if (aaudioEnabled) {
      return 'Disabled: AAudio Direct is ON — crossfade is applied in the ExoPlayer DSP chain it bypasses. Turn AAudio Direct off to use crossfade.';
    }
    if (!bitPerfectOutput || !bypassDspOnBitPerfect) return null;
    if (device?.isBluetooth == true) return null;
    return 'Disabled: Bit-Perfect bypass is ON — crossfade overlaps two tracks and would alter the bitstream. Turn off Bit-Perfect (or its DSP bypass) to use crossfade.';
  }

  /// AAudio direct bypasses the ExoPlayer DSP chain (EQ/speed/pitch/silence
  /// skip) by design — same class of conflict as bit-perfect bypass.
  static String? dspBlockedByAaudioDirect({required bool aaudioEnabled}) {
    if (!aaudioEnabled) return null;
    return 'Disabled: AAudio Direct is ON — it bypasses the ExoPlayer DSP chain (EQ, speed/pitch, silence skip, crossfade). Turn it off to re-enable DSP.';
  }

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
