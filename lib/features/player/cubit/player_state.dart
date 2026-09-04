// lib/features/player/cubit/player_state.dart
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
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
}
