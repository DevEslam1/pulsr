// lib/features/player/cubit/player_state.dart
import 'package:flutter/material.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/eq_preset.dart';
import '../../../domain/models/lyrics_line.dart';

enum PlayerRepeatMode { off, all, one }

class PlayerState {
  final SongsTableData? currentSong;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool isShuffle;
  final PlayerRepeatMode repeatMode;
  final List<SongsTableData> queue;
  final int currentIndex;
  final bool isExpanded;
  final Color? dominantColor;
  final Duration? sleepTimerRemaining;
  final List<LyricsLine> lyrics;
  final bool isLoadingLyrics;
  final bool isLyricsVisible;
  final bool isQueueVisible;
  final EqPreset eqPreset;
  final bool isEqEnabled;
  final int activeQueueSlot; // 0, 1, or 2

  const PlayerState({
    this.currentSong,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isShuffle = false,
    this.repeatMode = PlayerRepeatMode.off,
    this.queue = const [],
    this.currentIndex = 0,
    this.isExpanded = false,
    this.dominantColor,
    this.sleepTimerRemaining,
    this.lyrics = const [],
    this.isLoadingLyrics = false,
    this.isLyricsVisible = false,
    this.isQueueVisible = false,
    this.eqPreset = const EqPreset(name: 'Flat', gains: [0, 0, 0, 0, 0]),
    this.isEqEnabled = false,
    this.activeQueueSlot = 0,
  });

  PlayerState copyWith({
    SongsTableData? currentSong,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool? isShuffle,
    PlayerRepeatMode? repeatMode,
    List<SongsTableData>? queue,
    int? currentIndex,
    bool? isExpanded,
    Color? dominantColor,
    Duration? sleepTimerRemaining,
    bool clearSleepTimer = false,
    List<LyricsLine>? lyrics,
    bool? isLoadingLyrics,
    bool? isLyricsVisible,
    bool? isQueueVisible,
    EqPreset? eqPreset,
    bool? isEqEnabled,
    int? activeQueueSlot,
  }) {
    return PlayerState(
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isExpanded: isExpanded ?? this.isExpanded,
      dominantColor: dominantColor ?? this.dominantColor,
      sleepTimerRemaining: clearSleepTimer ? null : (sleepTimerRemaining ?? this.sleepTimerRemaining),
      lyrics: lyrics ?? this.lyrics,
      isLoadingLyrics: isLoadingLyrics ?? this.isLoadingLyrics,
      isLyricsVisible: isLyricsVisible ?? this.isLyricsVisible,
      isQueueVisible: isQueueVisible ?? this.isQueueVisible,
      eqPreset: eqPreset ?? this.eqPreset,
      isEqEnabled: isEqEnabled ?? this.isEqEnabled,
      activeQueueSlot: activeQueueSlot ?? this.activeQueueSlot,
    );
  }
}
