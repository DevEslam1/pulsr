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

// FIX-A04: Architecture roadmap: Split PlayerState into focused slices: PlaybackState
// (playback, position, timing), QueueState (queue, slots, indices), LyricsState
// (lyrics, sync, sources), and DspEffectState (equalizer, spatializer, bit-perfect, crossfade)
// to reduce state object churn and minimize rebuild pressure on player subtrees.
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
    @Default(0) int activeQueueSlot,
    @Default(1.0) double playbackSpeed,
    @Default(1.0) double playbackPitch,
    int? audioSessionId,
    String? errorMessage,
    // F1: AB loop
    @Default(false) bool abLoopEnabled,
    Duration? abPointA,
    Duration? abPointB,
    // F2: per-track delay (ms) for current track
    @Default(0) int trackDelayMs,
    // F11: bookmark resume offer for current track
    Duration? bookmarkPosition,
    // F10: silence-skip sensitivity mirror
    @Default(0) int silenceSkipSensitivity,
    // PowerAmp Parity: per-song rating (1-5), EQ override, Volume offset (dB)
    @Default(0) int currentSongRating,
    String? currentSongEqOverride,
    @Default(0.0) double currentSongVolumeOverrideDb,
    // T10: chapters of the CUE image backing the current song, if any.
    @Default([]) List<ChapterInfo> cueChapters,
    @Default(0) int currentCueIndex,
    // Quran Mode: vocal-optimized recitation profile.
    @Default(false) bool isQuranModeEnabled,
    @Default(QuranReciterStyle.murattal) QuranReciterStyle quranReciterStyle,
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
  /// // AUTO-GENERATED — do not edit (B-31 schema parity verified across all 101 fields)
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
        ((sleepTimerRemaining == null) != (other.sleepTimerRemaining == null) ||
            (sleepTimerRemaining != null &&
                other.sleepTimerRemaining != null &&
                sleepTimerRemaining!.inSeconds !=
                    other.sleepTimerRemaining!.inSeconds)) ||
        listContentDiffers(lyrics, other.lyrics) ||
        lyricsSource != other.lyricsSource ||
        isLoadingLyrics != other.isLoadingLyrics ||
        isLyricsVisible != other.isLyricsVisible ||
        isQueueVisible != other.isQueueVisible ||
        eqPreset != other.eqPreset ||
        isEqEnabled != other.isEqEnabled ||
        isVirtualizerEnabled != other.isVirtualizerEnabled ||
        virtualizerStrength != other.virtualizerStrength ||
        isVirtualizerSupported != other.isVirtualizerSupported ||
        isDynamicsEnabled != other.isDynamicsEnabled ||
        isDynamicsSupported != other.isDynamicsSupported ||
        dynamicsPreset != other.dynamicsPreset ||
        selectedHeadphoneProfile != other.selectedHeadphoneProfile ||
        isSpatializerSupported != other.isSpatializerSupported ||
        isSpatializerEnabled != other.isSpatializerEnabled ||
        volumeBoost != other.volumeBoost ||
        isVolumeBoostSupported != other.isVolumeBoostSupported ||
        isBassBoostSupported != other.isBassBoostSupported ||
        isCrossfeedEnabled != other.isCrossfeedEnabled ||
        crossfeedDelayUs != other.crossfeedDelayUs ||
        crossfeedFeedDb != other.crossfeedFeedDb ||
        crossfeedMode != other.crossfeedMode ||
        isLimiterEnabled != other.isLimiterEnabled ||
        limiterThresholdDb != other.limiterThresholdDb ||
        limiterReleaseMs != other.limiterReleaseMs ||
        isReverbEnabled != other.isReverbEnabled ||
        reverbPreset != other.reverbPreset ||
        reverbWetDry != other.reverbWetDry ||
        stereoBalance != other.stereoBalance ||
        monoMix != other.monoMix ||
        isSincResamplerEnabled != other.isSincResamplerEnabled ||
        isDitherEnabled != other.isDitherEnabled ||
        ditherTargetBitDepth != other.ditherTargetBitDepth ||
        isSaturationEnabled != other.isSaturationEnabled ||
        saturationDrive != other.saturationDrive ||
        saturationMix != other.saturationMix ||
        saturationTilt != other.saturationTilt ||
        saturationMultiband != other.saturationMultiband ||
        isStereoWidthEnabled != other.isStereoWidthEnabled ||
        stereoWidth != other.stereoWidth ||
        isLoudnessContourEnabled != other.isLoudnessContourEnabled ||
        loudnessContourIntensity != other.loudnessContourIntensity ||
        isSubCrossoverEnabled != other.isSubCrossoverEnabled ||
        subCrossoverCornerHz != other.subCrossoverCornerHz ||
        subCrossoverSlopeDbPerOct != other.subCrossoverSlopeDbPerOct ||
        subCrossoverGain != other.subCrossoverGain ||
        subCrossoverBassMono != other.subCrossoverBassMono ||
        subCrossoverAntiPop != other.subCrossoverAntiPop ||
        stereoWidthMultiband != other.stereoWidthMultiband ||
        stereoWidthLow != other.stereoWidthLow ||
        stereoWidthMid != other.stereoWidthMid ||
        stereoWidthHigh != other.stereoWidthHigh ||
        stereoWidthLowCrossoverHz != other.stereoWidthLowCrossoverHz ||
        stereoWidthHighCrossoverHz != other.stereoWidthHighCrossoverHz ||
        multibandCompressorF0 != other.multibandCompressorF0 ||
        multibandCompressorF1 != other.multibandCompressorF1 ||
        multibandCompressorF2 != other.multibandCompressorF2 ||
        isDynamicEqEnabled != other.isDynamicEqEnabled ||
        listContentDiffers(dynamicEqBands, other.dynamicEqBands) ||
        isViperDdcEnabled != other.isViperDdcEnabled ||
        viperDdcProfileName != other.viperDdcProfileName ||
        isArbitraryEqEnabled != other.isArbitraryEqEnabled ||
        arbitraryEqString != other.arbitraryEqString ||
        isLiveProgEnabled != other.isLiveProgEnabled ||
        liveProgCode != other.liveProgCode ||
        liveProgStatus != other.liveProgStatus ||
        isDynamicBassEnabled != other.isDynamicBassEnabled ||
        dynamicBassStrength != other.dynamicBassStrength ||
        dynamicBassPreset != other.dynamicBassPreset ||
        hasOemAudio != other.hasOemAudio ||
        listContentDiffers(detectedOemEngines, other.detectedOemEngines) ||
        activeQueueSlot != other.activeQueueSlot ||
        playbackSpeed != other.playbackSpeed ||
        audioSessionId != other.audioSessionId ||
        errorMessage != other.errorMessage ||
        abLoopEnabled != other.abLoopEnabled ||
        abPointA != other.abPointA ||
        abPointB != other.abPointB ||
        trackDelayMs != other.trackDelayMs ||
        bookmarkPosition != other.bookmarkPosition ||
        silenceSkipSensitivity != other.silenceSkipSensitivity ||
        // FIX-L4: Ensure playbackPitch is compared
        playbackPitch != other.playbackPitch ||
        currentSongRating != other.currentSongRating ||
        currentSongEqOverride != other.currentSongEqOverride ||
        currentSongVolumeOverrideDb != other.currentSongVolumeOverrideDb ||
        listContentDiffers(cueChapters, other.cueChapters) ||
        currentCueIndex != other.currentCueIndex ||
        isQuranModeEnabled != other.isQuranModeEnabled ||
        quranReciterStyle != other.quranReciterStyle;
  }

  /// Whether a neighbouring queue entry exists to skip to, mirroring the
  /// handler's notification-control decision (`_hasQueueNeighbour`). A lone
  /// stream or a single-entry queue has no neighbour in either direction.
  bool get hasPreviousNeighbour => _hasQueueNeighbour(forward: false);

  /// See [hasPreviousNeighbour].
  bool get hasNextNeighbour => _hasQueueNeighbour(forward: true);

  bool _hasQueueNeighbour({required bool forward}) {
    final length =
        queue.isNotEmpty ? queue.length : (currentSong != null ? 1 : 0);
    if (length <= 1) return false;
    if (isShuffle) return true;
    if (repeatMode == PlayerRepeatMode.all) return true;
    return forward ? currentIndex + 1 < length : currentIndex > 0;
  }

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

  /// True when any non-EQ DSP stage is engaged. Deliberately excludes
  /// [isEqEnabled] and the AutoEQ headphone profile: the Equalizer master
  /// switch owns those, while the "DSP & Spatial Effects" master switch in the
  /// equalizer sheet must toggle independently instead of mirroring EQ.
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

  /// Non-EQ DSP stages only, matching [isDspEffectsActive] for the sheet label.
  int get activeDspEffectStagesCount =>
      activeDspStagesCount -
      (isEqEnabled ? 1 : 0) -
      (selectedHeadphoneProfile != null ? 1 : 0);
}
