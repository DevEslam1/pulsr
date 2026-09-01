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
    // Extractor & Backend Settings
    @Default(ExtractorEngine.auto) ExtractorEngine extractorEngine,
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
  }) = _SettingsState;

  Color get customAccentColor => Color(customAccentColorValue);

  /// True when the accent should track album artwork. Kept for call sites that
  /// only care about the per-song artwork behavior (e.g. Now Playing).
  bool get dynamicThemingEnabled =>
      themeColorSource == ThemeColorSource.artwork;

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
