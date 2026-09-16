// lib/features/settings/cubit/settings_state.dart
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../core/network/proxy_config.dart';
import '../../../domain/models/audio_output_info.dart';
import '../../../domain/models/ytm_audio_quality.dart';
import '../../player/presentation/widgets/audio_visualizer.dart';

export '../../../domain/models/ytm_audio_quality.dart';

part 'settings_state.freezed.dart';

enum AppThemeMode { dark, light, amoled, system }

/// Where the app's accent color comes from.
/// - [system]: OS wallpaper palette (Material You / Monet, Android 12+),
///   falling back to album artwork when the OS provides no dynamic colors.
/// - [artwork]: extracted from the current track's album art (per-song).
/// - [custom]: the user-picked [customAccentColor].
enum ThemeColorSource { system, artwork, custom }

enum PlayerThemeMode {
  classic,
  card,
  circle,
  minimal,
  vinyl,
  cassette,
  waveform,
  lyricsFocus
}

enum MiniPlayerSwipeAction { next, prev, volume, none }

enum NowPlayingDoubleTapAction { toggleFavorite, toggleLyrics, none }

enum NowPlayingArtworkSwipeAction { nextPrev, none }

enum ReplayGainMode { off, track, album, auto }

enum ExtractorEngine { auto, remoteYtdlp, onDevice }

/// How DSD (DSF/DFF) files are handed to the output device.
/// - [pcm]: decode DSD to PCM (default, always available).
/// - [dop]: frame DSD as DSD-over-PCM for a compatible USB DAC. Never enabled
///   automatically; requires an explicit choice plus a detected USB DAC.
enum DsdOutputMode { pcm, dop }

/// The app's overall complexity level.
///
/// - [normal] (default): a curated, smart experience. Advanced DSP/output
///   controls are hidden; Smart Audio and sensible defaults run automatically so
///   a non-technical user gets the full benefit without any tuning.
/// - [professional]: the complete control surface, unchanged from before.
enum ExperienceMode {
  normal,
  professional;

  static ExperienceMode fromName(String? name) => ExperienceMode.values
      .firstWhere((m) => m.name == name, orElse: () => ExperienceMode.normal);
}

@freezed
abstract class SettingsState with _$SettingsState {
  const SettingsState._();

  const factory SettingsState({
    @Default(true) bool gaplessPlayback,
    @Default(0.0) double crossfadeSeconds,
    @Default(30) int minDurationSec,
    @Default(true) bool autoHideSystemMedia,
    @Default(ThemeColorSource.artwork) ThemeColorSource themeColorSource,
    @Default(true) bool resumeAfterInterruption,
    @Default(true) bool waveformSeekBarEnabled,
    @Default(AppThemeMode.dark) AppThemeMode themeMode,
    @Default(false) bool autoThemeByTime,
    @Default(false) bool highContrast,
    // Accessibility: when true the app forces reduced motion app-wide (all
    // animations snap to their end state). When false the OS "Reduce motion" /
    // "Remove animations" setting is still honoured — this toggle only ever
    // adds reduction, never removes it.
    @Default(false) bool reduceMotion,
    @Default(0.80) double liquidGlassTint,
    @Default('system') String languageCode,
    @Default(0xFF9B9EF5) int customAccentColorValue,
    @Default(PlayerThemeMode.classic) PlayerThemeMode playerThemeMode,
    @Default(VisualizerStyle.bar) VisualizerStyle visualizerStyle,
    @Default(MiniPlayerSwipeAction.next)
    MiniPlayerSwipeAction miniPlayerSwipeLeft,
    @Default(MiniPlayerSwipeAction.prev)
    MiniPlayerSwipeAction miniPlayerSwipeRight,
    @Default(NowPlayingDoubleTapAction.toggleFavorite)
    NowPlayingDoubleTapAction nowPlayingDoubleTap,
    @Default(NowPlayingArtworkSwipeAction.nextPrev)
    NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
    @Default(ReplayGainMode.track) ReplayGainMode replayGainMode,
    @Default(0.0) double replayGainPreampWithRg,
    @Default(-3.0) double replayGainPreampWithoutRg,
    @Default(YtmAudioQuality.high) YtmAudioQuality streamingQuality,
    @Default(YtmAudioQuality.high) YtmAudioQuality downloadQuality,
    @Default(false) bool wifiOnlyMode,
    @Default(false) bool offlineOnlyMode,
    @Default(false) bool isScanning,
    // Proxy Settings
    @Default(false) bool proxyEnabled,
    @Default(AppProxyType.http) AppProxyType proxyType,
    @Default('') String proxyHost,
    @Default(8080) int proxyPort,
    @Default('') String proxyUsername,
    @Default(false) bool hasProxyPassword,
    @Default('localhost, 127.0.0.1') String proxyBypassHosts,
    @Default([]) List<ProxyEntry> proxyList,
    @Default(false) bool isTestingAllProxies,
    // Extractor & Backend Settings (remote yt-dlp backend decommissioned)
    @Default(ExtractorEngine.onDevice) ExtractorEngine extractorEngine,
    @Default(false) bool ytdlpBackendEnabled,
    @Default('https://xdm-backend-10763667121.europe-west1.run.app')
    String ytdlpBackendUrl,
    @Default('') String ytdlpBackendToken,
    @Default(false) bool syncCookiesToBackend,
    @Default(false) bool isTestingYtdlpBackend,
    String? ytdlpBackendStatusMessage,
    String? ytdlpBackendVersion,
    int? ytdlpBackendProxyCount,
    String? ytdlpBackendCircuitState,
    // Audiophile & Hi-Res Output
    @Default(false) bool bitPerfectOutput,
    @Default(true) bool bypassDspOnBitPerfect,
    // T2: reconfigure the output to each track's native sample rate.
    @Default(true) bool followTrackSampleRate,
    // T3: strict bit-perfect (no resample). Forces Bit-Perfect + DSP bypass and
    // surfaces the EQ/ReplayGain/effects/crossfade conflict card.
    @Default(false) bool strictBitPerfect,
    // T4: DSD output transport (default PCM; DoP only with a detected USB DAC).
    @Default(DsdOutputMode.pcm) DsdOutputMode dsdOutputMode,
    // Overall complexity level. Defaults to Normal so first-time users get the
    // curated, smart experience; advanced controls are revealed in Professional.
    @Default(ExperienceMode.normal) ExperienceMode experienceMode,
    // Result of the native DoP capability probe: true only when a USB DAC is
    // connected and advertises a carrier rate DoP can use. Drives the UI.
    @Default(false) bool dsdDopSupported,
    AudioOutputInfo? currentOutputDevice,
    int? scanResultCount,
    String? errorMessage,
    // DSP & Sound Quality
    @Default(false) bool crossfeedEnabled,
    @Default(350.0) double crossfeedDelayUs,
    @Default(-9.0) double crossfeedFeedDb,
    @Default(false) bool limiterEnabled,
    @Default(3.0) double limiterLookaheadMs,
    @Default(-0.2) double limiterThresholdDb,
    @Default(50.0) double limiterReleaseMs,
    @Default(false) bool reverbEnabled,
    @Default(0) int reverbPreset,
    @Default(0.20) double reverbWetDry,
    @Default(0.0) double stereoBalance,
    @Default(false) bool monoMix,
    @Default(true) bool sincResamplerEnabled,
    @Default('native') String dspPreference,
    // System audio effects (Dolby Atmos / vendor)
    @Default('auto') String systemEffectsPolicy,
    @Default('unknown') String systemEffectsStatus,
    @Default(<String>[]) List<String> systemEffectsBundles,
    // Bluetooth quality & sync
    @Default(150) int bluetoothLatencyOffsetMs,
    // F3/F4/F7/F8/F9/F10
    @Default(true) bool hedgedResolutionEnabled,
    @Default(true) bool adaptiveQualityEnabled,
    @Default('duck') String duckingMode,
    @Default(0.3) double duckingLevel,
    @Default('systemDefault') String multiOutputMode,
    @Default(true) bool dspSnapshotEnabled,
    @Default(0) int silenceSkipSensitivity,
    // Per-session audio telemetry (route/codec/negotiated format/dropouts).
    @Default(true) bool sessionLogEnabled,
    // Per-track output-format negotiation (default ON: always request the
    // track's native rate/depth so hi-res output is automatic).
    @Default(true) bool outputFormatNegotiationEnabled,
    // 24/32-bit float DSP path (default ON: hi-res sources are no longer
    // truncated to 16-bit. 16-bit sources are unaffected because Media3 only
    // takes the float branch for >16-bit PCM; unsupported devices fall back).
    @Default(true) bool floatOutputEnabled,
    // Opt-in AAudio Direct output (bit-perfect; DSP chain bypassed).
    @Default(false) bool aaudioOutputEnabled,
    // Opt-in Direct Volume Control: pins the Android media stream to maximum
    // and applies the composed gain in the native float DSP path.
    @Default(false) bool dvcEnabled,
    // Opt-in USB DAC hardware volume control (UAC Feature Unit).
    @Default(false) bool usbHardwareVolumeEnabled,
    @Default(true) bool aaudioPreferExclusive,
    @Default(150) int aaudioTargetBufferMs,
    // Resampler quality (0=Fast/linear .. 3=Ultra/64-tap).
    @Default(3) int sincResamplerQuality,
    // BPM-synced crossfade (needs a known BPM for the incoming track).
    @Default(false) bool bpmSyncCrossfadeEnabled,
  }) = _SettingsState;

  Color get customAccentColor => Color(customAccentColorValue);

  /// True when the full professional control surface should be shown.
  bool get isProfessional => experienceMode == ExperienceMode.professional;

  /// True when the accent should track album artwork. Kept for call sites that
  /// only care about the per-song artwork behavior (e.g. Now Playing).
  bool get dynamicThemingEnabled =>
      themeColorSource == ThemeColorSource.artwork;

  /// How far the audible signal trails the position the player reports.
  ///
  /// Every Bluetooth sink (A2DP or LE Audio) buffers audio downstream, so the
  /// listener hears a moment that was decoded [bluetoothLatencyOffsetMs] ago.
  /// Anything syncing visuals to sound (lyrics, karaoke) must follow the
  /// audible position; wired and speaker output have no comparable lag. The
  /// amount is user-calibrated because Android exposes no sink-latency API.
  Duration get audibleLatencyOffset => currentOutputDevice?.isBluetooth == true
      ? Duration(milliseconds: bluetoothLatencyOffsetMs)
      : Duration.zero;

  ProxyConfig get proxyConfig => ProxyConfig(
        enabled: proxyEnabled,
        type: proxyType,
        host: proxyHost,
        port: proxyPort,
        username: proxyUsername,
        password: '',
        bypassHosts: proxyBypassHosts,
      );
}
