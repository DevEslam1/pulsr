// lib/features/player/cubit/player_state.dart
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../core/utils/list_content_diff.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/audio_effects_config.dart';
import '../../../domain/models/eq_preset.dart';
import '../../../domain/models/headphone_profile.dart';
import '../../../domain/models/lyrics_line.dart';

part 'player_state.freezed.dart';

enum PlayerRepeatMode { off, all, one }

@freezed
abstract class PlayerState with _$PlayerState {
  const PlayerState._();

  const factory PlayerState({
    SongsTableData? currentSong,
    @Default(false) bool isPlaying,
    @Default(Duration.zero) Duration position,
    @Default(Duration.zero) Duration duration,
    @Default(false) bool isShuffle,
    @Default(PlayerRepeatMode.off) PlayerRepeatMode repeatMode,
    @Default([]) List<SongsTableData> queue,
    @Default(0) int currentIndex,
    @Default(false) bool isExpanded,
    Color? dominantColor,
    Duration? sleepTimerRemaining,
    @Default([]) List<LyricsLine> lyrics,
    @Default(LyricsSource.none) LyricsSource lyricsSource,
    @Default(false) bool isLoadingLyrics,
    @Default(false) bool isLyricsVisible,
    @Default(false) bool isQueueVisible,
    @Default(EqPreset(name: 'Flat', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
    EqPreset eqPreset,
    @Default(false) bool isEqEnabled,
    @Default(false) bool isVirtualizerEnabled,
    @Default(0.0) double virtualizerStrength,
    @Default(false) bool isDynamicsEnabled,
    @Default(DynamicsPreset.off) DynamicsPreset dynamicsPreset,
    HeadphoneProfile? selectedHeadphoneProfile,
    @Default(false) bool isSpatializerSupported,
    @Default(false) bool isSpatializerEnabled,
    @Default(0.0) double volumeBoost,
    @Default(false) bool isCrossfeedEnabled,
    @Default(350.0) double crossfeedDelayUs,
    @Default(-9.0) double crossfeedFeedDb,
    @Default(false) bool isLimiterEnabled,
    @Default(-0.2) double limiterThresholdDb,
    @Default(50.0) double limiterReleaseMs,
    @Default(false) bool isReverbEnabled,
    @Default(0) int reverbPreset,
    @Default(0.20) double reverbWetDry,
    @Default(0.0) double stereoBalance,
    @Default(false) bool monoMix,
    @Default(true) bool isSincResamplerEnabled,
    @Default(false) bool hasOemAudio,
    @Default([]) List<String> detectedOemEngines,
    @Default(0) int activeQueueSlot,
    @Default(1.0) double playbackSpeed,
    int? audioSessionId,
    String? errorMessage,
  }) = _PlayerState;

  /// True when every field other than [position] is equal to [other]'s, i.e.
  /// the two states differ only by the ~200 ms playback position tick.
  ///
  /// Collections (`queue`, `lyrics`, `detectedOemEngines`) are compared with
  /// O(1) [listContentDiffers] (length + first/last): freezed `copyWith` does NOT
  /// preserve list reference identity (even a no-arg copyWith yields new list
  /// instances), so identity checks would false-positive on every tick. This
  /// keeps the check O(1) — unlike the generated [==], which deep-compares
  /// those lists (O(queue size)) on every call.
  bool differsFromBeyondPosition(PlayerState other) {
    return currentSong != other.currentSong ||
        isPlaying != other.isPlaying ||
        duration != other.duration ||
        isShuffle != other.isShuffle ||
        repeatMode != other.repeatMode ||
        listContentDiffers(queue, other.queue) ||
        currentIndex != other.currentIndex ||
        isExpanded != other.isExpanded ||
        dominantColor != other.dominantColor ||
        sleepTimerRemaining != other.sleepTimerRemaining ||
        listContentDiffers(lyrics, other.lyrics) ||
        lyricsSource != other.lyricsSource ||
        isLoadingLyrics != other.isLoadingLyrics ||
        isLyricsVisible != other.isLyricsVisible ||
        isQueueVisible != other.isQueueVisible ||
        eqPreset != other.eqPreset ||
        isEqEnabled != other.isEqEnabled ||
        isVirtualizerEnabled != other.isVirtualizerEnabled ||
        virtualizerStrength != other.virtualizerStrength ||
        isDynamicsEnabled != other.isDynamicsEnabled ||
        dynamicsPreset != other.dynamicsPreset ||
        selectedHeadphoneProfile != other.selectedHeadphoneProfile ||
        isSpatializerSupported != other.isSpatializerSupported ||
        isSpatializerEnabled != other.isSpatializerEnabled ||
        volumeBoost != other.volumeBoost ||
        isCrossfeedEnabled != other.isCrossfeedEnabled ||
        crossfeedDelayUs != other.crossfeedDelayUs ||
        crossfeedFeedDb != other.crossfeedFeedDb ||
        isLimiterEnabled != other.isLimiterEnabled ||
        limiterThresholdDb != other.limiterThresholdDb ||
        limiterReleaseMs != other.limiterReleaseMs ||
        isReverbEnabled != other.isReverbEnabled ||
        reverbPreset != other.reverbPreset ||
        reverbWetDry != other.reverbWetDry ||
        stereoBalance != other.stereoBalance ||
        monoMix != other.monoMix ||
        isSincResamplerEnabled != other.isSincResamplerEnabled ||
        hasOemAudio != other.hasOemAudio ||
        listContentDiffers(detectedOemEngines, other.detectedOemEngines) ||
        activeQueueSlot != other.activeQueueSlot ||
        playbackSpeed != other.playbackSpeed ||
        audioSessionId != other.audioSessionId ||
        errorMessage != other.errorMessage;
  }

  bool get isDspActive =>
      isVirtualizerEnabled ||
      isDynamicsEnabled ||
      isSpatializerEnabled ||
      isCrossfeedEnabled ||
      isLimiterEnabled ||
      isReverbEnabled ||
      volumeBoost > 0.01;

  int get activeDspStagesCount {
    int count = 0;
    if (isVirtualizerEnabled) count++;
    if (isDynamicsEnabled) count++;
    if (isSpatializerEnabled) count++;
    if (isCrossfeedEnabled) count++;
    if (isLimiterEnabled) count++;
    if (isReverbEnabled) count++;
    if (volumeBoost > 0.01) count++;
    return count;
  }
}