// lib/features/player/cubit/player_state.dart
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../core/utils/list_content_diff.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/audio_effects_config.dart';
import '../../../domain/models/chapter_info.dart';
import '../../../domain/models/eq_preset.dart';
import '../../../domain/models/headphone_profile.dart';
import '../../../domain/models/lyrics_line.dart';
import '../../../domain/models/quran_mode_profile.dart';

part 'player_state.freezed.dart';

enum PlayerRepeatMode { off, all, one }

/// Focused slice owning playback transport, track identities, positions, and options.
@freezed
abstract class PlaybackSlice with _$PlaybackSlice {
  const PlaybackSlice._();

  const factory PlaybackSlice({
    SongsTableData? currentSong,
    @Default(false) bool isPlaying,
    @Default(Duration.zero) Duration position,
    @Default(Duration.zero) Duration duration,
    @Default(false) bool isShuffle,
    @Default(PlayerRepeatMode.off) PlayerRepeatMode repeatMode,
    @Default(1.0) double playbackSpeed,
    @Default(1.0) double playbackPitch,
    int? audioSessionId,
    String? errorMessage,
    @Default(false) bool isExpanded,
    Color? dominantColor,
    Duration? sleepTimerRemaining,
    int? sleepTimerRemainingTracks,
    @Default(false) bool abLoopEnabled,
    Duration? abPointA,
    Duration? abPointB,
    @Default(0) int trackDelayMs,
    Duration? bookmarkPosition,
    @Default(0) int silenceSkipSensitivity,
    @Default(0) int currentSongRating,
    String? currentSongEqOverride,
    @Default(0.0) double currentSongVolumeOverrideDb,
  }) = _PlaybackSlice;

  /// True when every field other than [position] is equal to [other]'s.
  bool differsBeyondPosition(PlaybackSlice other) {
    return currentSong != other.currentSong ||
        isPlaying != other.isPlaying ||
        duration != other.duration ||
        isShuffle != other.isShuffle ||
        repeatMode != other.repeatMode ||
        playbackSpeed != other.playbackSpeed ||
        playbackPitch != other.playbackPitch ||
        audioSessionId != other.audioSessionId ||
        errorMessage != other.errorMessage ||
        isExpanded != other.isExpanded ||
        dominantColor != other.dominantColor ||
        ((sleepTimerRemaining == null) != (other.sleepTimerRemaining == null) ||
            (sleepTimerRemaining != null &&
                other.sleepTimerRemaining != null &&
                sleepTimerRemaining!.inSeconds !=
                    other.sleepTimerRemaining!.inSeconds)) ||
        sleepTimerRemainingTracks != other.sleepTimerRemainingTracks ||
        abLoopEnabled != other.abLoopEnabled ||
        abPointA != other.abPointA ||
        abPointB != other.abPointB ||
        trackDelayMs != other.trackDelayMs ||
        bookmarkPosition != other.bookmarkPosition ||
        silenceSkipSensitivity != other.silenceSkipSensitivity ||
        currentSongRating != other.currentSongRating ||
        currentSongEqOverride != other.currentSongEqOverride ||
        currentSongVolumeOverrideDb != other.currentSongVolumeOverrideDb;
  }
}

/// Focused slice owning active playback queue, slots, and CUE chapters.
@freezed
abstract class QueueSlice with _$QueueSlice {
  const QueueSlice._();

  const factory QueueSlice({
    @Default([]) List<SongsTableData> queue,
    @Default(0) int currentIndex,
    @Default(0) int activeQueueSlot,
    @Default([]) List<ChapterInfo> cueChapters,
    @Default(0) int currentCueIndex,
  }) = _QueueSlice;

  bool differs(QueueSlice other) {
    return currentIndex != other.currentIndex ||
        activeQueueSlot != other.activeQueueSlot ||
        currentCueIndex != other.currentCueIndex ||
        listContentDiffers(queue, other.queue) ||
        listContentDiffers(cueChapters, other.cueChapters);
  }
}

/// Focused slice owning lyrics lines, sources, and visibility.
@freezed
abstract class LyricsSlice with _$LyricsSlice {
  const factory LyricsSlice({
    @Default([]) List<LyricsLine> lyrics,
    @Default(LyricsSource.none) LyricsSource lyricsSource,
    @Default(false) bool isLoadingLyrics,
    @Default(false) bool isLyricsVisible,
    @Default(false) bool isQueueVisible,
  }) = _LyricsSlice;
}

/// Focused slice owning all audio DSP effects, equalizer presets, and audio processing configurations.
@freezed
abstract class DspSlice with _$DspSlice {
  const DspSlice._();

  const factory DspSlice({
    @Default(EqPreset(name: 'Flat', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
    EqPreset eqPreset,
    @Default(false) bool isEqEnabled,
    @Default(false) bool isVirtualizerEnabled,
    @Default(0.0) double virtualizerStrength,
    @Default(false) bool isVirtualizerSupported,
    @Default(false) bool isDynamicsEnabled,
    @Default(false) bool isDynamicsSupported,
    @Default(DynamicsPreset.off) DynamicsPreset dynamicsPreset,
    HeadphoneProfile? selectedHeadphoneProfile,
    @Default(false) bool isSpatializerSupported,
    @Default(false) bool isSpatializerEnabled,
    @Default(0.0) double volumeBoost,
    @Default(false) bool isVolumeBoostSupported,
    @Default(false) bool isBassBoostSupported,
    @Default(false) bool isCrossfeedEnabled,
    @Default(350.0) double crossfeedDelayUs,
    @Default(-9.0) double crossfeedFeedDb,
    @Default(0) int crossfeedMode,
    @Default(false) bool isLimiterEnabled,
    @Default(-0.2) double limiterThresholdDb,
    @Default(50.0) double limiterReleaseMs,
    @Default(false) bool isReverbEnabled,
    @Default(0) int reverbPreset,
    @Default(0.20) double reverbWetDry,
    @Default(0.0) double stereoBalance,
    @Default(false) bool monoMix,
    @Default(true) bool isSincResamplerEnabled,
    @Default(false) bool isDitherEnabled,
    @Default(16) int ditherTargetBitDepth,
    @Default(false) bool isSaturationEnabled,
    @Default(0.3) double saturationDrive,
    @Default(0.5) double saturationMix,
    @Default(0.3) double saturationTilt,
    @Default(false) bool saturationMultiband,
    @Default(false) bool isStereoWidthEnabled,
    @Default(1.0) double stereoWidth,
    @Default(false) bool isLoudnessContourEnabled,
    @Default(0.0) double loudnessContourIntensity,
    @Default(false) bool isSubCrossoverEnabled,
    @Default(80.0) double subCrossoverCornerHz,
    @Default(24.0) double subCrossoverSlopeDbPerOct,
    @Default(0.8) double subCrossoverGain,
    @Default(false) bool subCrossoverBassMono,
    @Default(true) bool subCrossoverAntiPop,
    @Default(false) bool stereoWidthMultiband,
    @Default(1.0) double stereoWidthLow,
    @Default(1.0) double stereoWidthMid,
    @Default(1.0) double stereoWidthHigh,
    @Default(160.0) double stereoWidthLowCrossoverHz,
    @Default(2500.0) double stereoWidthHighCrossoverHz,
    @Default(160.0) double multibandCompressorF0,
    @Default(1000.0) double multibandCompressorF1,
    @Default(5000.0) double multibandCompressorF2,
    @Default(false) bool isDynamicEqEnabled,
    @Default([]) List<DynamicEqBandConfig> dynamicEqBands,
    @Default(false) bool isViperDdcEnabled,
    @Default('') String viperDdcProfileName,
    @Default(false) bool isArbitraryEqEnabled,
    @Default('') String arbitraryEqString,
    @Default(false) bool isLiveProgEnabled,
    @Default('') String liveProgCode,
    @Default('') String liveProgStatus,
    @Default(false) bool isDynamicBassEnabled,
    @Default(1.0) double dynamicBassStrength,
    @Default(0) int dynamicBassPreset,
    @Default(false) bool hasOemAudio,
    @Default([]) List<String> detectedOemEngines,
    @Default(false) bool isQuranModeEnabled,
    @Default(QuranReciterStyle.murattal) QuranReciterStyle quranReciterStyle,
  }) = _DspSlice;

  bool get isDspActive =>
      isEqEnabled ||
      selectedHeadphoneProfile != null ||
      isVirtualizerEnabled ||
      isDynamicsEnabled ||
      isSpatializerEnabled ||
      isCrossfeedEnabled ||
      isLimiterEnabled ||
      isReverbEnabled ||
      isSaturationEnabled ||
      isStereoWidthEnabled ||
      isLoudnessContourEnabled ||
      isSubCrossoverEnabled ||
      isDynamicEqEnabled ||
      isViperDdcEnabled ||
      isArbitraryEqEnabled ||
      isLiveProgEnabled ||
      isDynamicBassEnabled ||
      volumeBoost > 0.01;

  bool get isDspEffectsActive =>
      isVirtualizerEnabled ||
      isDynamicsEnabled ||
      isSpatializerEnabled ||
      isCrossfeedEnabled ||
      isLimiterEnabled ||
      isReverbEnabled ||
      isSaturationEnabled ||
      isStereoWidthEnabled ||
      isLoudnessContourEnabled ||
      isSubCrossoverEnabled ||
      isDynamicEqEnabled ||
      isViperDdcEnabled ||
      isArbitraryEqEnabled ||
      isLiveProgEnabled ||
      isDynamicBassEnabled ||
      volumeBoost > 0.01;

  int get activeDspStagesCount {
    int count = 0;
    if (isEqEnabled) count++;
    if (selectedHeadphoneProfile != null) count++;
    if (isVirtualizerEnabled) count++;
    if (isDynamicsEnabled) count++;
    if (isSpatializerEnabled) count++;
    if (isCrossfeedEnabled) count++;
    if (isLimiterEnabled) count++;
    if (isReverbEnabled) count++;
    if (isSaturationEnabled) count++;
    if (isStereoWidthEnabled) count++;
    if (isLoudnessContourEnabled) count++;
    if (isSubCrossoverEnabled) count++;
    if (isDynamicEqEnabled) count++;
    if (isViperDdcEnabled) count++;
    if (isArbitraryEqEnabled) count++;
    if (isLiveProgEnabled) count++;
    if (isDynamicBassEnabled) count++;
    if (volumeBoost > 0.01) count++;
    return count;
  }

  int get activeDspEffectStagesCount =>
      activeDspStagesCount -
      (isEqEnabled ? 1 : 0) -
      (selectedHeadphoneProfile != null ? 1 : 0);
}

/// Lightweight composite PlayerState holding the 4 focused state slices.
@freezed
abstract class PlayerState with _$PlayerState {
  const PlayerState._();

  const factory PlayerState({
    @Default(PlaybackSlice()) PlaybackSlice playback,
    @Default(QueueSlice()) QueueSlice queueSlice,
    @Default(DspSlice()) DspSlice dsp,
    @Default(LyricsSlice()) LyricsSlice lyricsSlice,
  }) = _PlayerState;

  // ──────────────────────────────────────────────
  // Forwarded Playback Getters
  // ──────────────────────────────────────────────
  SongsTableData? get currentSong => playback.currentSong;
  bool get isPlaying => playback.isPlaying;
  Duration get position => playback.position;
  Duration get duration => playback.duration;
  bool get isShuffle => playback.isShuffle;
  PlayerRepeatMode get repeatMode => playback.repeatMode;
  double get playbackSpeed => playback.playbackSpeed;
  double get playbackPitch => playback.playbackPitch;
  int? get audioSessionId => playback.audioSessionId;
  String? get errorMessage => playback.errorMessage;
  bool get isExpanded => playback.isExpanded;
  Color? get dominantColor => playback.dominantColor;
  Duration? get sleepTimerRemaining => playback.sleepTimerRemaining;
  int? get sleepTimerRemainingTracks => playback.sleepTimerRemainingTracks;
  bool get abLoopEnabled => playback.abLoopEnabled;
  Duration? get abPointA => playback.abPointA;
  Duration? get abPointB => playback.abPointB;
  int get trackDelayMs => playback.trackDelayMs;
  Duration? get bookmarkPosition => playback.bookmarkPosition;
  int get silenceSkipSensitivity => playback.silenceSkipSensitivity;
  int get currentSongRating => playback.currentSongRating;
  String? get currentSongEqOverride => playback.currentSongEqOverride;
  double get currentSongVolumeOverrideDb => playback.currentSongVolumeOverrideDb;

  // ──────────────────────────────────────────────
  // Forwarded Queue Getters
  // ──────────────────────────────────────────────
  List<SongsTableData> get queue => queueSlice.queue;
  int get currentIndex => queueSlice.currentIndex;
  int get activeQueueSlot => queueSlice.activeQueueSlot;
  List<ChapterInfo> get cueChapters => queueSlice.cueChapters;
  int get currentCueIndex => queueSlice.currentCueIndex;

  // ──────────────────────────────────────────────
  // Forwarded Lyrics Getters
  // ──────────────────────────────────────────────
  List<LyricsLine> get lyrics => lyricsSlice.lyrics;
  LyricsSource get lyricsSource => lyricsSlice.lyricsSource;
  bool get isLoadingLyrics => lyricsSlice.isLoadingLyrics;
  bool get isLyricsVisible => lyricsSlice.isLyricsVisible;
  bool get isQueueVisible => lyricsSlice.isQueueVisible;

  // ──────────────────────────────────────────────
  // Forwarded DSP Getters
  // ──────────────────────────────────────────────
  EqPreset get eqPreset => dsp.eqPreset;
  bool get isEqEnabled => dsp.isEqEnabled;
  bool get isVirtualizerEnabled => dsp.isVirtualizerEnabled;
  double get virtualizerStrength => dsp.virtualizerStrength;
  bool get isVirtualizerSupported => dsp.isVirtualizerSupported;
  bool get isDynamicsEnabled => dsp.isDynamicsEnabled;
  bool get isDynamicsSupported => dsp.isDynamicsSupported;
  DynamicsPreset get dynamicsPreset => dsp.dynamicsPreset;
  HeadphoneProfile? get selectedHeadphoneProfile => dsp.selectedHeadphoneProfile;
  bool get isSpatializerSupported => dsp.isSpatializerSupported;
  bool get isSpatializerEnabled => dsp.isSpatializerEnabled;
  double get volumeBoost => dsp.volumeBoost;
  bool get isVolumeBoostSupported => dsp.isVolumeBoostSupported;
  bool get isBassBoostSupported => dsp.isBassBoostSupported;
  bool get isCrossfeedEnabled => dsp.isCrossfeedEnabled;
  double get crossfeedDelayUs => dsp.crossfeedDelayUs;
  double get crossfeedFeedDb => dsp.crossfeedFeedDb;
  int get crossfeedMode => dsp.crossfeedMode;
  bool get isLimiterEnabled => dsp.isLimiterEnabled;
  double get limiterThresholdDb => dsp.limiterThresholdDb;
  double get limiterReleaseMs => dsp.limiterReleaseMs;
  bool get isReverbEnabled => dsp.isReverbEnabled;
  int get reverbPreset => dsp.reverbPreset;
  double get reverbWetDry => dsp.reverbWetDry;
  double get stereoBalance => dsp.stereoBalance;
  bool get monoMix => dsp.monoMix;
  bool get isSincResamplerEnabled => dsp.isSincResamplerEnabled;
  bool get isDitherEnabled => dsp.isDitherEnabled;
  int get ditherTargetBitDepth => dsp.ditherTargetBitDepth;
  bool get isSaturationEnabled => dsp.isSaturationEnabled;
  double get saturationDrive => dsp.saturationDrive;
  double get saturationMix => dsp.saturationMix;
  double get saturationTilt => dsp.saturationTilt;
  bool get saturationMultiband => dsp.saturationMultiband;
  bool get isStereoWidthEnabled => dsp.isStereoWidthEnabled;
  double get stereoWidth => dsp.stereoWidth;
  bool get isLoudnessContourEnabled => dsp.isLoudnessContourEnabled;
  double get loudnessContourIntensity => dsp.loudnessContourIntensity;
  bool get isSubCrossoverEnabled => dsp.isSubCrossoverEnabled;
  double get subCrossoverCornerHz => dsp.subCrossoverCornerHz;
  double get subCrossoverSlopeDbPerOct => dsp.subCrossoverSlopeDbPerOct;
  double get subCrossoverGain => dsp.subCrossoverGain;
  bool get subCrossoverBassMono => dsp.subCrossoverBassMono;
  bool get subCrossoverAntiPop => dsp.subCrossoverAntiPop;
  bool get stereoWidthMultiband => dsp.stereoWidthMultiband;
  double get stereoWidthLow => dsp.stereoWidthLow;
  double get stereoWidthMid => dsp.stereoWidthMid;
  double get stereoWidthHigh => dsp.stereoWidthHigh;
  double get stereoWidthLowCrossoverHz => dsp.stereoWidthLowCrossoverHz;
  double get stereoWidthHighCrossoverHz => dsp.stereoWidthHighCrossoverHz;
  double get multibandCompressorF0 => dsp.multibandCompressorF0;
  double get multibandCompressorF1 => dsp.multibandCompressorF1;
  double get multibandCompressorF2 => dsp.multibandCompressorF2;
  bool get isDynamicEqEnabled => dsp.isDynamicEqEnabled;
  List<DynamicEqBandConfig> get dynamicEqBands => dsp.dynamicEqBands;
  bool get isViperDdcEnabled => dsp.isViperDdcEnabled;
  String get viperDdcProfileName => dsp.viperDdcProfileName;
  bool get isArbitraryEqEnabled => dsp.isArbitraryEqEnabled;
  String get arbitraryEqString => dsp.arbitraryEqString;
  String get liveProgCode => dsp.liveProgCode;
  bool get isLiveProgEnabled => dsp.isLiveProgEnabled;
  String get liveProgStatus => dsp.liveProgStatus;
  bool get isDynamicBassEnabled => dsp.isDynamicBassEnabled;
  double get dynamicBassStrength => dsp.dynamicBassStrength;
  int get dynamicBassPreset => dsp.dynamicBassPreset;
  bool get hasOemAudio => dsp.hasOemAudio;
  List<String> get detectedOemEngines => dsp.detectedOemEngines;
  bool get isQuranModeEnabled => dsp.isQuranModeEnabled;
  QuranReciterStyle get quranReciterStyle => dsp.quranReciterStyle;

  bool get isDspActive => dsp.isDspActive;
  bool get isDspEffectsActive => dsp.isDspEffectsActive;
  int get activeDspStagesCount => dsp.activeDspStagesCount;
  int get activeDspEffectStagesCount => dsp.activeDspEffectStagesCount;

  /// High-performance diff: skips high-frequency position ticks while reacting
  /// to playback, queue, and lyrics/overlay view changes, plus user-visible
  /// DSP active status toggles (EQ, Quran mode, active DSP stages).
  bool differsFromBeyondPosition(PlayerState other) {
    return playback.differsBeyondPosition(other.playback) ||
        queueSlice.differs(other.queueSlice) ||
        lyricsSlice != other.lyricsSlice ||
        isEqEnabled != other.isEqEnabled ||
        isQuranModeEnabled != other.isQuranModeEnabled ||
        isDspActive != other.isDspActive;
  }

  bool get hasPreviousNeighbour => _hasQueueNeighbour(forward: false);
  bool get hasNextNeighbour => _hasQueueNeighbour(forward: true);

  bool _hasQueueNeighbour({required bool forward}) {
    final length =
        queue.isNotEmpty ? queue.length : (currentSong != null ? 1 : 0);
    if (length <= 1) return false;
    if (isShuffle) return true;
    if (repeatMode == PlayerRepeatMode.all) return true;
    return forward ? currentIndex + 1 < length : currentIndex > 0;
  }
}
