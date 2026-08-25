// lib/features/settings/cubit/settings_state.dart
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../core/network/proxy_config.dart';
import '../../player/presentation/widgets/audio_visualizer.dart';

part 'settings_state.freezed.dart';

enum AppThemeMode { dark, light, amoled, system }

/// Where the app's accent color comes from.
/// - [system]: OS wallpaper palette (Material You / Monet, Android 12+),
///   falling back to album artwork when the OS provides no dynamic colors.
/// - [artwork]: extracted from the current track's album art (per-song).
/// - [custom]: the user-picked [customAccentColor].
enum ThemeColorSource { system, artwork, custom }

enum PlayerThemeMode { classic, card, circle, minimal }

enum MiniPlayerSwipeAction { next, prev, volume, none }

enum NowPlayingDoubleTapAction { toggleFavorite, toggleLyrics, none }

enum NowPlayingArtworkSwipeAction { nextPrev, none }

enum ReplayGainMode { off, track, album }

enum YtmAudioQuality { low, medium, high }

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
    @Default(0xFF9B9EF5) int customAccentColorValue,
    @Default(PlayerThemeMode.classic) PlayerThemeMode playerThemeMode,
    @Default(VisualizerStyle.bar) VisualizerStyle visualizerStyle,
    @Default(MiniPlayerSwipeAction.next) MiniPlayerSwipeAction miniPlayerSwipeLeft,
    @Default(MiniPlayerSwipeAction.prev) MiniPlayerSwipeAction miniPlayerSwipeRight,
    @Default(NowPlayingDoubleTapAction.toggleFavorite) NowPlayingDoubleTapAction nowPlayingDoubleTap,
    @Default(NowPlayingArtworkSwipeAction.nextPrev) NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
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
    @Default('') String proxyPassword,
    @Default('localhost, 127.0.0.1') String proxyBypassHosts,
    int? scanResultCount,
    String? errorMessage,
  }) = _SettingsState;

  Color get customAccentColor => Color(customAccentColorValue);

  /// True when the accent should track album artwork. Kept for call sites that
  /// only care about the per-song artwork behavior (e.g. Now Playing).
  bool get dynamicThemingEnabled => themeColorSource == ThemeColorSource.artwork;

  ProxyConfig get proxyConfig => ProxyConfig(
        enabled: proxyEnabled,
        type: proxyType,
        host: proxyHost,
        port: proxyPort,
        username: proxyUsername,
        password: proxyPassword,
        bypassHosts: proxyBypassHosts,
      );
}
