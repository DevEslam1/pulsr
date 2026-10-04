// lib/core/constants/audio_feature_info.dart
// Central registry: every audio feature exposes user-facing info + conflict rules.
// Single source of truth for “show the user info on every feature and prevent him to select 2 thing cannot work together”.

import '../../domain/models/audio_output_info.dart';
import '../../l10n/generated/app_localizations.dart';
import '../utils/l10n_holder.dart';

/// {@category DesignSystem}
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

  AudioFeatureInfo localized(AppLocalizations l) => AudioFeatureInfo(
        id: id,
        title: _title(l),
        subtitle: _subtitle(l),
        description: _description(l),
        conflictsWith: _conflictsWith(l),
        whyDisabledReason: whyDisabledReason,
      );

  String _title(AppLocalizations l) {
    switch (id) {
      case 'bitPerfect':
        return l.featureInfoBitPerfectTitle;
      case 'bypassDsp':
        return l.featureInfoBypassDspTitle;
      case 'followTrackSampleRate':
        return l.featureInfoFollowTrackSampleRateTitle;
      case 'strictBitPerfect':
        return l.featureInfoStrictBitPerfectTitle;
      case 'equalizer':
        return l.featureInfoEqualizerTitle;
      case 'bassBoost':
        return l.featureInfoBassBoostTitle;
      case 'crossfeed':
        return l.featureInfoCrossfeedTitle;
      case 'limiter':
        return l.featureInfoLimiterTitle;
      case 'reverb':
        return l.featureInfoReverbTitle;
      case 'panner':
        return l.featureInfoPannerTitle;
      case 'resampler':
        return l.featureInfoResamplerTitle;
      case 'virtualizer':
        return l.featureInfoVirtualizerTitle;
      case 'spatializer':
        return l.featureInfoSpatializerTitle;
      case 'dynamics':
        return l.featureInfoDynamicsTitle;
      case 'roomCorrection':
        return l.featureInfoRoomCorrectionTitle;
      case 'dsdNative':
        return l.featureInfoDsdNativeTitle;
      case 'mqa':
        return l.featureInfoMqaTitle;
      case 'gapless':
        return l.featureInfoGaplessTitle;
      case 'crossfade':
        return l.featureInfoCrossfadeTitle;
      case 'replayGain':
        return l.featureInfoReplayGainTitle;
      case 'oem':
        return l.featureInfoOemTitle;
      case 'volumeBoost':
        return l.featureInfoVolumeBoostTitle;
      case 'saturation':
        return l.featureInfoSaturationTitle;
      case 'stereoWidth':
        return l.featureInfoStereoWidthTitle;
      case 'loudnessContour':
        return l.featureInfoLoudnessContourTitle;
      case 'subCrossover':
        return l.featureInfoSubCrossoverTitle;
      case 'dynamicEq':
        return l.featureInfoDynamicEqTitle;
      case 'multibandCompressor':
        return l.featureInfoMultibandCompressorTitle;
      case 'dynamicBass':
        return l.featureInfoDynamicBassTitle;
      case 'viperDdc':
        return l.featureInfoViperDdcTitle;
      case 'arbitraryEq':
        return l.featureInfoArbitraryEqTitle;
      case 'liveProg':
        return l.featureInfoLiveProgTitle;
      default:
        return title;
    }
  }

  String _subtitle(AppLocalizations l) {
    switch (id) {
      case 'bitPerfect':
        return l.featureInfoBitPerfectSubtitle;
      case 'bypassDsp':
        return l.featureInfoBypassDspSubtitle;
      case 'followTrackSampleRate':
        return l.featureInfoFollowTrackSampleRateSubtitle;
      case 'strictBitPerfect':
        return l.featureInfoStrictBitPerfectSubtitle;
      case 'equalizer':
        return l.featureInfoEqualizerSubtitle;
      case 'bassBoost':
        return l.featureInfoBassBoostSubtitle;
      case 'crossfeed':
        return l.featureInfoCrossfeedSubtitle;
      case 'limiter':
        return l.featureInfoLimiterSubtitle;
      case 'reverb':
        return l.featureInfoReverbSubtitle;
      case 'panner':
        return l.featureInfoPannerSubtitle;
      case 'resampler':
        return l.featureInfoResamplerSubtitle;
      case 'virtualizer':
        return l.featureInfoVirtualizerSubtitle;
      case 'spatializer':
        return l.featureInfoSpatializerSubtitle;
      case 'dynamics':
        return l.featureInfoDynamicsSubtitle;
      case 'roomCorrection':
        return l.featureInfoRoomCorrectionSubtitle;
      case 'dsdNative':
        return l.featureInfoDsdNativeSubtitle;
      case 'mqa':
        return l.featureInfoMqaSubtitle;
      case 'gapless':
        return l.featureInfoGaplessSubtitle;
      case 'crossfade':
        return l.featureInfoCrossfadeSubtitle;
      case 'replayGain':
        return l.featureInfoReplayGainSubtitle;
      case 'oem':
        return l.featureInfoOemSubtitle;
      case 'volumeBoost':
        return l.featureInfoVolumeBoostSubtitle;
      case 'saturation':
        return l.featureInfoSaturationSubtitle;
      case 'stereoWidth':
        return l.featureInfoStereoWidthSubtitle;
      case 'loudnessContour':
        return l.featureInfoLoudnessContourSubtitle;
      case 'subCrossover':
        return l.featureInfoSubCrossoverSubtitle;
      case 'dynamicEq':
        return l.featureInfoDynamicEqSubtitle;
      case 'multibandCompressor':
        return l.featureInfoMultibandCompressorSubtitle;
      case 'dynamicBass':
        return l.featureInfoDynamicBassSubtitle;
      case 'viperDdc':
        return l.featureInfoViperDdcSubtitle;
      case 'arbitraryEq':
        return l.featureInfoArbitraryEqSubtitle;
      case 'liveProg':
        return l.featureInfoLiveProgSubtitle;
      default:
        return subtitle;
    }
  }

  String _description(AppLocalizations l) {
    switch (id) {
      case 'bitPerfect':
        return l.featureInfoBitPerfectDescription;
      case 'bypassDsp':
        return l.featureInfoBypassDspDescription;
      case 'followTrackSampleRate':
        return l.featureInfoFollowTrackSampleRateDescription;
      case 'strictBitPerfect':
        return l.featureInfoStrictBitPerfectDescription;
      case 'equalizer':
        return l.featureInfoEqualizerDescription;
      case 'bassBoost':
        return l.featureInfoBassBoostDescription;
      case 'crossfeed':
        return l.featureInfoCrossfeedDescription;
      case 'limiter':
        return l.featureInfoLimiterDescription;
      case 'reverb':
        return l.featureInfoReverbDescription;
      case 'panner':
        return l.featureInfoPannerDescription;
      case 'resampler':
        return l.featureInfoResamplerDescription;
      case 'virtualizer':
        return l.featureInfoVirtualizerDescription;
      case 'spatializer':
        return l.featureInfoSpatializerDescription;
      case 'dynamics':
        return l.featureInfoDynamicsDescription;
      case 'roomCorrection':
        return l.featureInfoRoomCorrectionDescription;
      case 'dsdNative':
        return l.featureInfoDsdNativeDescription;
      case 'mqa':
        return l.featureInfoMqaDescription;
      case 'gapless':
        return l.featureInfoGaplessDescription;
      case 'crossfade':
        return l.featureInfoCrossfadeDescription;
      case 'replayGain':
        return l.featureInfoReplayGainDescription;
      case 'oem':
        return l.featureInfoOemDescription;
      case 'volumeBoost':
        return l.featureInfoVolumeBoostDescription;
      case 'saturation':
        return l.featureInfoSaturationDescription;
      case 'stereoWidth':
        return l.featureInfoStereoWidthDescription;
      case 'loudnessContour':
        return l.featureInfoLoudnessContourDescription;
      case 'subCrossover':
        return l.featureInfoSubCrossoverDescription;
      case 'dynamicEq':
        return l.featureInfoDynamicEqDescription;
      case 'multibandCompressor':
        return l.featureInfoMultibandCompressorDescription;
      case 'dynamicBass':
        return l.featureInfoDynamicBassDescription;
      case 'viperDdc':
        return l.featureInfoViperDdcDescription;
      case 'arbitraryEq':
        return l.featureInfoArbitraryEqDescription;
      case 'liveProg':
        return l.featureInfoLiveProgDescription;
      default:
        return description;
    }
  }

  String? _conflictsWith(AppLocalizations l) {
    switch (conflictsWith) {
      case 'All DSP when “Bypass DSP” is ON':
        return l.conflictWithAllDspBypassDsp;
      case 'Bit-Perfect bypass':
        return l.conflictWithBitPerfect;
      case 'EQ / ReplayGain / Effects / Crossfade':
        return l.conflictWithEqReplayGainEffectsCrossfade;
      case 'Bit-Perfect bypass / Direct':
        return l.conflictWithResampler;
      case 'Bit-Perfect bypass, Hardware Spatializer':
        return l.conflictWithVirtualizer;
      case 'Crossfade (>0 s)':
        return l.conflictWithCrossfade;
      case 'Gapless':
        return l.conflictWithGapless;
      default:
        return conflictsWith;
    }
  }
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
    subtitle:
        'Tape, Vacuum Tube (2nd harmonic), or Analog Class-A with 4× sinc oversampling',
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
    subtitle:
        'Phase-aligned Linkwitz-Riley 4th order crossovers, zero-latency C++',
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
  /// True when the native DSP bypass is active: Bit-Perfect output + its DSP
  /// bypass are both enabled on a non-Bluetooth route.
  ///
  /// Deliberately does NOT require `device.isBitPerfectActive`: the native
  /// bypass is pushed the moment Bit-Perfect turns on, so gating on the live
  /// mixer confirmation (false while paused/armed or before the stream matches)
  /// let users edit DSP stages that the engine was already muting. Bluetooth is
  /// excluded because bit-perfect can never be active on a transcoded link.
  static bool dspBypassActive({
    required bool bitPerfectOutput,
    required bool bypassDspOnBitPerfect,
    required AudioOutputInfo? device,
  }) =>
      bitPerfectOutput && bypassDspOnBitPerfect && device?.isBluetooth != true;

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
      return L10nHolder.current?.conflictAaudioDirect ??
          'Disabled: AAudio Direct is ON — it bypasses the ExoPlayer DSP chain (EQ, speed/pitch, silence skip, crossfade). Turn it off to re-enable DSP.';
    }
    if (dsdDopActive) {
      return L10nHolder.current?.conflictDsdDop ??
          'Disabled: DSD over PCM (DoP) is playing — any DSP or gain would corrupt the DoP carrier. Switch DSD output to PCM to re-enable DSP.';
    }
    if (!dspBypassActive(
      bitPerfectOutput: bitPerfectOutput,
      bypassDspOnBitPerfect: bypassDspOnBitPerfect,
      device: device,
    )) {
      return null;
    }
    return L10nHolder.current?.conflictDspBitPerfectBypass ??
        'Disabled: Bit-Perfect bypass is ON — this DSP would alter the exclusive bitstream. Turn off Bit-Perfect or disable “Bypass DSP” to enable.';
  }

  /// Playback speed (and pitch) is applied by ExoPlayer's Sonic processor in the
  /// same sink chain as the native DSP, so any rate other than 1.0× resamples
  /// the exact bitstream while the bypass is active.
  static String? speedBlockedByBitPerfect({
    required bool bitPerfectOutput,
    required bool bypassDspOnBitPerfect,
    required AudioOutputInfo? device,
  }) {
    if (!dspBypassActive(
      bitPerfectOutput: bitPerfectOutput,
      bypassDspOnBitPerfect: bypassDspOnBitPerfect,
      device: device,
    )) {
      return null;
    }
    return L10nHolder.current?.conflictSpeedBitPerfectBypass ??
        'Disabled: Bit-Perfect bypass is ON — changing playback speed or pitch resamples the audio and would alter the exclusive bitstream. Set speed/pitch back to 1.0×, or turn off Bit-Perfect (or its DSP bypass).';
  }

  /// Silence skipping edits the sample stream (removes frames), which no longer
  /// matches the source bitstream.
  static String? silenceSkipBlockedByBitPerfect({
    required bool bitPerfectOutput,
    required bool bypassDspOnBitPerfect,
    required AudioOutputInfo? device,
  }) {
    if (!dspBypassActive(
      bitPerfectOutput: bitPerfectOutput,
      bypassDspOnBitPerfect: bypassDspOnBitPerfect,
      device: device,
    )) {
      return null;
    }
    return L10nHolder.current?.conflictSilenceSkipBitPerfectBypass ??
        'Disabled: Bit-Perfect bypass is ON — silence skipping edits the sample stream. Turn off Bit-Perfect (or its DSP bypass) to use it.';
  }

  /// Only a route that provably cannot carry bit-perfect is a hard block:
  /// Bluetooth transcodes, or no USB DAC at all. Every other native failure
  /// stays attemptable — the direct UAC2 fallback may still work, and a failed
  /// attempt surfaces the concrete reason. In particular
  /// `no_supported_mixer_attributes` is NOT a hard block: it is exactly the
  /// case the direct USB sink exists for.
  static const Set<String> _hardBitPerfectFailures = {
    'exclusive_requires_usb_dac',
    'usb_not_supported',
  };

  static String? bitPerfectBlockedReason(AudioOutputInfo? device) {
    if (device == null) return null;
    if (device.isBluetooth) {
      return L10nHolder.current?.conflictBtBitPerfectUnsupported ??
          'Cannot enable: Bluetooth transcodes (SBC/AAC/LDAC/LC3) — bit-perfect only on a USB DAC.';
    }
    final reason = device.bitPerfectFailureReason;
    if (reason == null || !_hardBitPerfectFailures.contains(reason)) {
      return null;
    }
    return bitPerfectReasonMessage(reason);
  }

  /// Maps a native bit-perfect rejection reason code to a user message.
  static String? bitPerfectReasonMessage(String? reason) {
    switch (reason) {
      case 'requires_android_14_for_usb':
      case 'requires_android_14':
        return L10nHolder.current?.conflictRequiresAndroid14 ??
            'Requires Android 14+ for USB bit-perfect output.';
      case 'usb_not_supported':
        return L10nHolder.current?.conflictNoMixerAttributes ??
            'Android does not advertise an exclusive bit-perfect mixer configuration for this USB DAC.';
      case 'exclusive_requires_usb_dac':
        return L10nHolder.current?.conflictExclusiveRequiresUsbDac ??
            'Cannot enable: Android exposes exclusive output only for USB DACs. Wired hi-res still plays direct when the device supports it.';
      case 'bluetooth_transcoded':
        return L10nHolder.current?.conflictBtBitPerfectUnsupported ??
            'Cannot enable: Bluetooth transcodes (SBC/AAC/LDAC/LC3) — bit-perfect only on a USB DAC.';
      case 'no_supported_mixer_attributes':
        return L10nHolder.current?.conflictNoMixerAttributes ??
            'This USB DAC does not advertise an exclusive mixer configuration.';
      case 'target_format_unavailable':
        return 'This USB DAC does not offer the selected sample rate / bit depth in exclusive mode.';
      case 'set_mixer_attributes_failed':
        return 'Android refused exclusive mode for this USB DAC (another app may be using it).';
      case 'reflection_method_not_found':
      case 'audio_mixer_class_not_found':
        return 'Exclusive output API is not available on this device.';
      default:
        return null;
    }
  }

  static String? gaplessBlockedByCrossfade(double crossfadeSeconds) {
    if (crossfadeSeconds > 0.01) {
      return L10nHolder.current?.conflictGaplessNeedsZeroCrossfade(
              crossfadeSeconds.toStringAsFixed(1)) ??
          'Disabled: Crossfade is ${crossfadeSeconds.toStringAsFixed(1)} s — gapless requires 0 s. Set Crossfade to 0 to enable gapless.';
    }
    return null;
  }

  static String? crossfadeBlockedByGapless(bool gaplessEnabled) {
    if (gaplessEnabled) {
      return L10nHolder.current?.conflictCrossfadeNeedsGaplessOff ??
          'Disabled: Gapless is ON — crossfade needs gapless OFF. Disable Gapless to enable crossfade.';
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
      return L10nHolder.current?.conflictNoDeviceDetected ??
          'Cannot enable: no output device detected yet. Connect a USB DAC and retry.';
    }
    // Attemptable: the cubit tries the platform mixer path first and then the
    // direct USB sink, reverting with the concrete reason if both fail.
    return null;
  }

  /// Reason shown while strict bit-perfect is active (or armed with the DSP
  /// bypass): the stages below are intentionally muted.
  static String? strictBitPerfectActiveReason({
    required bool bitPerfectOutput,
    required bool bypassDspOnBitPerfect,
    required AudioOutputInfo? device,
  }) {
    if (!dspBypassActive(
      bitPerfectOutput: bitPerfectOutput,
      bypassDspOnBitPerfect: bypassDspOnBitPerfect,
      device: device,
    )) {
      return null;
    }
    return L10nHolder.current?.conflictStrictBitPerfectActive ??
        'Strict bit-perfect is ON: EQ, ReplayGain, Virtualizer/Dynamics and Crossfade are muted so the exact source samples reach the DAC. Turn Strict bit-perfect off to re-enable them.';
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
      return L10nHolder.current?.conflictAaudioDirectCrossfade ??
          'Disabled: AAudio Direct is ON — crossfade is applied in the ExoPlayer DSP chain it bypasses. Turn AAudio Direct off to use crossfade.';
    }
    if (!dspBypassActive(
      bitPerfectOutput: bitPerfectOutput,
      bypassDspOnBitPerfect: bypassDspOnBitPerfect,
      device: device,
    )) {
      return null;
    }
    return L10nHolder.current?.conflictCrossfadeBitPerfectBypass ??
        'Disabled: Bit-Perfect bypass is ON — crossfade overlaps two tracks and would alter the bitstream. Turn off Bit-Perfect (or its DSP bypass) to use crossfade.';
  }

  /// AAudio direct bypasses the ExoPlayer DSP chain (EQ/speed/pitch/silence
  /// skip) by design — same class of conflict as bit-perfect bypass.
  static String? dspBlockedByAaudioDirect({required bool aaudioEnabled}) {
    if (!aaudioEnabled) return null;
    return L10nHolder.current?.conflictAaudioDirect ??
        'Disabled: AAudio Direct is ON — it bypasses the ExoPlayer DSP chain (EQ, speed/pitch, silence skip, crossfade). Turn it off to re-enable DSP.';
  }

  static String? oemDoubleProcessingWarning(
      {required bool hasOemAudio, required bool anyDspEnabled}) {
    if (hasOemAudio && anyDspEnabled) {
      return L10nHolder.current?.conflictOemDoubleProcessing ??
          'Warning: System Dolby/Dirac is active — running Pulsr DSP on top causes double-processing. Prefer DSP Preference = Native and disable system effects.';
    }
    return null;
  }

  static String? volumeBoostClippingWarning(
      double volumeBoost, double preampDb) {
    final total = preampDb + volumeBoost * 10.0;
    if (total > 6.0) {
      return L10nHolder.current?.conflictVolumeBoostClipping(
              preampDb.toStringAsFixed(1),
              (volumeBoost * 10).toStringAsFixed(1),
              total.toStringAsFixed(1)) ??
          'Clipping risk: EQ preamp (${preampDb.toStringAsFixed(1)} dB) + boost (+${(volumeBoost * 10).toStringAsFixed(1)} dB) = +${total.toStringAsFixed(1)} dB > 6 dB headroom.';
    }
    if (volumeBoost > 0.6) {
      return L10nHolder.current?.conflictHighBoostDistortion ??
          'High boost may cause distortion or hearing fatigue.';
    }
    return null;
  }
}
