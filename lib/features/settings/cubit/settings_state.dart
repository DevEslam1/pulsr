// lib/features/settings/cubit/settings_state.dart
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../player/presentation/widgets/audio_visualizer.dart';

part 'settings_state.freezed.dart';

enum AppThemeMode { dark, light, amoled, system }

enum PlayerThemeMode { classic, card, circle, minimal }

enum MiniPlayerSwipeAction { next, prev, volume, none }

enum NowPlayingDoubleTapAction { toggleFavorite, toggleLyrics, none }

enum NowPlayingArtworkSwipeAction { nextPrev, none }

enum ReplayGainMode { off, track, album }

@freezed
abstract class SettingsState with _$SettingsState {
  const SettingsState._();

  const factory SettingsState({
    @Default(true) bool gaplessPlayback,
    @Default(0.0) double crossfadeSeconds,
    @Default(30) int minDurationSec,
    @Default(true) bool autoHideSystemMedia,
    @Default(true) bool dynamicThemingEnabled,
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
    @Default(false) bool isScanning,
    int? scanResultCount,
    String? errorMessage,
  }) = _SettingsState;

  Color get customAccentColor => Color(customAccentColorValue);
}
